#!/usr/bin/env python3
"""build_pyav.py — compile PyAV au commit épinglé, avec MSVC, contre les DLL FFmpeg de sme-media-build.

Usage (runner Windows, outils de pyav/requirements-build.txt installés) :
    python pyav/build_pyav.py --sources <archives> --ffmpeg <build-dev/ffmpeg> --out <sortie>

Étapes :
  1. extraction de l'archive PyAV (fetch-sources.sh) ;
  2. version locale écrite dans av/about.py (ancre exacte, sinon arrêt) ;
  3. bibliothèques d'import MSVC régénérées par lib.exe depuis les .def de FFmpeg ;
  4. setup.py bdist_wheel --ffmpeg-dir (vcvars64, DISTUTILS_USE_SDK, /Brepro pour cl et link) ;
  5. delvewheel repair --no-mangle-all : les DLL FFmpeg entrent dans av.libs SOUS LEUR NOM (avcodec-62.dll…),
     le même que celui qu'importe libmpv-2.dll (lettre L1, voie (b)) ;
  6. re-zip déterministe (ordre des entrées, dates = SOURCE_DATE_EPOCH) ;
  7. contrôles : DLL de av.libs identiques octet pour octet à celles de la construction, .pyd important les noms nus.
"""
from __future__ import annotations

import argparse
import glob
import hashlib
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tarfile
import time
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
FFMPEG_LIBS = ("avformat", "avcodec", "avdevice", "avutil", "avfilter", "swscale", "swresample")


def pins() -> dict:
    out = {}
    for ln in (ROOT / "pins.env").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^([A-Z0-9_]+)=(.*)$", ln)
        if m:
            out[m.group(1)] = m.group(2).strip('"')
    return out


def sha256(p: pathlib.Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def vcvars64() -> pathlib.Path:
    vswhere = pathlib.Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / \
        "Microsoft Visual Studio" / "Installer" / "vswhere.exe"
    inst = subprocess.check_output([str(vswhere), "-latest", "-products", "*", "-requires",
                                    "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
                                    "-property", "installationPath"], text=True).strip()
    p = pathlib.Path(inst) / "VC" / "Auxiliary" / "Build" / "vcvars64.bat"
    if not p.is_file():
        sys.exit(f"vcvars64.bat introuvable : {p}")
    return p


def run_cmd(script: pathlib.Path, text: str) -> None:
    script.write_text(text.replace("\n", "\r\n"), encoding="ascii")
    print(f">>> cmd /c {script}\n{text}", flush=True)
    r = subprocess.run(["cmd", "/c", str(script)])
    if r.returncode != 0:
        sys.exit(f"échec (rc={r.returncode}) : {script.name}")


def deterministic_rezip(src: pathlib.Path, dst: pathlib.Path, epoch: int) -> None:
    dt = time.gmtime(max(epoch, 315532800))[:6]
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(dst, "w") as zout:
        for info in sorted(zin.infolist(), key=lambda i: i.filename):
            data = zin.read(info)
            zi = zipfile.ZipInfo(info.filename, date_time=dt)
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = info.external_attr
            zi.create_system = 0
            zout.writestr(zi, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sources", required=True, help="répertoire des archives de fetch-sources.sh")
    ap.add_argument("--ffmpeg", required=True, help="répertoire dev/ffmpeg de la construction (include, lib, bin)")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    pn = pins()
    epoch = int(pn["SOURCE_DATE_EPOCH"])
    os.environ["SOURCE_DATE_EPOCH"] = str(epoch)
    out = pathlib.Path(a.out).resolve()
    work = pathlib.Path(os.environ.get("RUNNER_TEMP", str(out.parent))) / "pyav-work"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    out.mkdir(parents=True, exist_ok=True)
    ffdev = pathlib.Path(a.ffmpeg).resolve()

    # 1. extraction
    arch = glob.glob(str(pathlib.Path(a.sources) / f"pyav-{pn['PYAV_COMMIT']}.tar.xz"))
    if len(arch) != 1:
        sys.exit(f"archive PyAV introuvable : {arch}")
    with tarfile.open(arch[0], "r:xz") as tf:
        tf.extractall(work, filter="data")
    src = work / "pyav"

    # 2. version locale
    about = src / "av" / "about.py"
    anchor = f'__version__ = "{pn["PYAV_VERSION"]}"'
    txt = about.read_text(encoding="utf-8")
    if anchor not in txt:
        sys.exit(f"ancre absente de {about} : {anchor!r}")
    about.write_text(txt.replace(anchor, f'__version__ = "{pn["PYAV_LOCAL_VERSION"]}"', 1), encoding="utf-8")

    # 3. bibliothèques d'import MSVC depuis les .def, dans un arbre --ffmpeg-dir dédié
    ffmsvc = work / "ffmpeg-msvc"
    (ffmsvc / "lib").mkdir(parents=True)
    shutil.copytree(ffdev / "include", ffmsvc / "include")
    lines = []
    for lib in FFMPEG_LIBS:
        defs = sorted((ffdev / "lib").glob(f"{lib}-*.def"))
        if len(defs) != 1:
            sys.exit(f".def introuvable ou ambigu pour {lib} : {defs}")
        dll = defs[0].stem + ".dll"
        if not (ffdev / "bin" / dll).is_file():
            sys.exit(f"DLL absente : {dll}")
        lines.append(f'lib.exe /nologo /machine:x64 /def:"{defs[0]}" /name:{dll} /out:"{ffmsvc / "lib" / (lib + ".lib")}" || exit /b 1')

    # 4. compilation
    dist = work / "dist"
    vc = vcvars64()
    run_cmd(work / "build.cmd", "\n".join([
        "@echo off",
        f'call "{vc}" || exit /b 91',
        *lines,
        "set DISTUTILS_USE_SDK=1",
        "set MSSdk=1",
        "set CL=/Brepro",
        "set LINK=/Brepro",
        f"set SOURCE_DATE_EPOCH={epoch}",
        "cl 2>&1 | findstr /C:\"Version\"",
        f'cd /d "{src}"',
        f'"{sys.executable}" setup.py bdist_wheel --ffmpeg-dir="{ffmsvc}" -d "{dist}" || exit /b 1',
        "exit /b 0",
    ]))
    wheels = sorted(dist.glob("*.whl"))
    if len(wheels) != 1:
        sys.exit(f"un wheel attendu, trouvé {wheels}")

    # 5. delvewheel, sans renommage
    rep = work / "repaired"
    r = subprocess.run([sys.executable, "-m", "delvewheel", "repair", "--no-mangle-all",
                        "--add-path", str(ffdev / "bin"), "-w", str(rep), "-v", str(wheels[0])])
    if r.returncode != 0:
        sys.exit("delvewheel a échoué")
    repaired = sorted(rep.glob("*.whl"))
    if len(repaired) != 1:
        sys.exit(f"un wheel réparé attendu, trouvé {repaired}")

    # 6. re-zip déterministe
    final = out / repaired[0].name
    deterministic_rezip(repaired[0], final, epoch)

    # 7. contrôles
    import pefile  # noqa: E402  (outil épinglé de requirements-build.txt)
    with zipfile.ZipFile(final) as z:
        names = z.namelist()
        libs = sorted(n for n in names if n.startswith("av.libs/") and n.lower().endswith(".dll"))
        expected = sorted(f"av.libs/{p.name}" for p in (ffdev / "bin").glob("*.dll"))
        print("av.libs :", [n.split("/")[-1] for n in libs])
        if libs != expected:
            sys.exit(f"av.libs ≠ DLL de la construction :\n  {libs}\n  {expected}")
        for n in libs:
            if hashlib.sha256(z.read(n)).hexdigest() != sha256(ffdev / "bin" / n.split("/")[-1]):
                sys.exit(f"{n} diffère de la DLL de la construction")
        bare = {p.name.lower() for p in (ffdev / "bin").glob("*.dll")}
        pyds = [n for n in names if n.endswith(".pyd")]
        seen = set()
        for n in pyds:
            pe = pefile.PE(data=z.read(n))
            for imp in getattr(pe, "DIRECTORY_ENTRY_IMPORT", []):
                dll = imp.dll.decode().lower()
                if dll.startswith(("av", "sw")):
                    if dll not in bare:
                        sys.exit(f"{n} importe {dll}, absent des DLL de la construction (renommage ?)")
                    seen.add(dll)
        print(f".pyd : {len(pyds)} ; DLL FFmpeg importées : {sorted(seen)}")
    (out / (final.name + ".sha256")).write_text(f"{sha256(final)}  {final.name}\n", encoding="ascii")
    print(f"wheel : {final.name} {final.stat().st_size} o sha256 {sha256(final)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
