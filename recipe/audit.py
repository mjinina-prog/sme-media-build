#!/usr/bin/env python3
"""audit.py — balayage bloquant (DA-7) et inventaire lié (M6) de sme-media-build.

Sous-commandes :
  scan       chaînes interdites dans chaque DLL/EXE/PYD (et dans les wheels), configuration embarquée,
             bibliothèques statiques liées d'après les cartes d'édition de liens. Code de sortie 1 = refus.
  inventory  table des bibliothèques réellement liées, tirée des cartes d'édition de liens.

Aucune étiquette ne fait foi : ce qui compte est ce que contient le binaire et ce que l'éditeur de liens a tiré.
Python 3 seul, sans dépendance.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import struct
import sys
import zipfile

# --------------------------------------------------------------------------- chaînes interdites
# (identifiant, motif octets) — toute occurrence est un refus.
FORBIDDEN = [
    ("fftw_codelet_", rb"fftw_codelet_"),
    ("fftw", rb"(?i)fftw"),
    ("chromaprint", rb"(?i)chromaprint"),
    ("zvbi", rb"(?i)zvbi"),
    ("aribb24", rb"(?i)aribb24"),
    ("libgme", rb"(?i)libgme"),
    ("game music emu", rb"(?i)game music emu"),
    ("libx264", rb"(?i)libx264"),
    ("x264_encoder", rb"(?i)x264_encoder"),
    ("bannière encodeur x264", rb"H\.264/MPEG-4 AVC codec - Copy"),
    ("x265", rb"(?i)x265"),
    ("--enable-gpl", rb"--enable-gpl"),
    ("--enable-nonfree", rb"--enable-nonfree"),
    ("--enable-version3", rb"--enable-version3"),
    ("étiquette FFmpeg GPL", rb"(?<!L)GPL version [0-9]"),
    ("-Dgpl=true", rb"-Dgpl=true"),
    ("dvdnav=enabled", rb"dvdnav=enabled"),
    ("rubberband=enabled", rb"rubberband=enabled"),
]
# « x264 » : seules occurrences admises, celles qui servent à DÉCODER des flux produits par d'anciennes versions
# de l'encodeur x264 (contournements de défauts). Chaque chaîne admise est citée entière, avec sa source au
# commit épinglé ; une occurrence n'est admise que si elle se trouve à l'intérieur d'une de ces chaînes.
# Toute autre occurrence est un refus.
X264_ALLOWED_STRINGS = [
    # FFmpeg libavcodec/h2645_sei.c l. 315 et 318 : lecture de la version x264 dans le SEI « user data unregistered ».
    rb"x264 - core %d",
    rb"x264 - core 0000",
    # FFmpeg libavcodec/h264dec.c l. 1095 : option du décodeur H.264 (nom et texte d'aide).
    rb"x264_build",
    rb"Assume this x264 version if no x264 version found in any SEI",
    # mpv video/decode/vd_lavc.c l. 120 : option qui règle « x264_build » du décodeur (l. 835).
    rb"vd-lavc-assume-old-x264",
    # mpv demux/demux_mkv.c l. 2358 : nom d'une fonction statique (table des symboles des DLL non épurées).
    rb"probe_x264_garbage",
    # FFmpeg libavformat/riff.c l. 39-40 : étiquettes FourCC de la table des codecs AVI, entrées
    # { AV_CODEC_ID_H264 (= 27, libavcodec/codec_id.h), MKTAG('X','2','6','4') } et { …, MKTAG('x','2','6','4') } :
    # un fichier AVI étiqueté ainsi se lit comme du H.264. Entier de 4 octets, pas une chaîne.
    struct.pack("<I", 27) + b"X264",
    struct.pack("<I", 27) + b"x264",
]

FFMPEG_LIBS = ("avcodec", "avdevice", "avfilter", "avformat", "avutil", "swresample", "swscale")


def is_ffmpeg_dll(name: str) -> bool:
    return bool(re.fullmatch(r"(%s)-\d+\.dll" % "|".join(FFMPEG_LIBS), name))


def printable_strings(data: bytes, needle: bytes, maxlen: int = 20000) -> list[str]:
    """Chaînes ASCII terminées par NUL qui contiennent needle (configuration embarquée)."""
    out = []
    for m in re.finditer(re.escape(needle), data):
        s = data.rfind(b"\x00", max(0, m.start() - maxlen), m.start()) + 1
        e = data.find(b"\x00", m.end())
        if e == -1:
            e = m.end()
        out.append(data[s:e].decode("latin-1"))
    return sorted(set(out))


# --------------------------------------------------------------------------- en-têtes PE
def pe_info(data: bytes) -> dict | None:
    """Machine, horodatage COFF et DLL importées (table d'import et table d'import différé) d'un binaire PE."""
    try:
        if len(data) < 0x40 or data[:2] != b"MZ":
            return None
        pe = struct.unpack_from("<I", data, 0x3C)[0]
        if data[pe:pe + 4] != b"PE\0\0":
            return None
        machine, nsec, stamp, _, _, optsize, _ = struct.unpack_from("<HHIIIHH", data, pe + 4)
        opt = pe + 24
        magic = struct.unpack_from("<H", data, opt)[0]
        if magic == 0x20B:
            image_base = struct.unpack_from("<Q", data, opt + 24)[0]
            ndirs = struct.unpack_from("<I", data, opt + 108)[0]
            dirs = opt + 112
        elif magic == 0x10B:
            image_base = struct.unpack_from("<I", data, opt + 28)[0]
            ndirs = struct.unpack_from("<I", data, opt + 92)[0]
            dirs = opt + 96
        else:
            return None
        secs = []
        for i in range(nsec):
            vsize, va, rsize, rptr = struct.unpack_from("<IIII", data, opt + optsize + 40 * i + 8)
            secs.append((va, max(vsize, rsize), rptr))

        def off(rva: int):
            for va, size, rptr in secs:
                if va <= rva < va + size:
                    return rva - va + rptr
            return None

        def cstr(rva: int):
            o = off(rva)
            if o is None:
                return None
            return data[o:data.find(b"\0", o)].decode("latin-1")

        def ddir(i: int) -> tuple[int, int]:
            return struct.unpack_from("<II", data, dirs + 8 * i) if i < ndirs else (0, 0)

        imports = []
        o = off(ddir(1)[0]) if ddir(1)[0] else None
        while o is not None and o + 20 <= len(data):
            oft, _, _, name_rva, ft = struct.unpack_from("<IIIII", data, o)
            if not (oft or name_rva or ft):
                break
            n = cstr(name_rva)
            if n:
                imports.append(n)
            o += 20
        delayed = []
        o = off(ddir(13)[0]) if ddir(13)[0] else None
        while o is not None and o + 32 <= len(data):
            attrs, name_ref = struct.unpack_from("<II", data, o)
            if not name_ref:
                break
            if not attrs & 1 and name_ref >= image_base:
                name_ref -= image_base            # ancien format : adresses virtuelles
            n = cstr(name_ref)
            if n:
                delayed.append(n)
            o += 32
        return {"machine": hex(machine), "horodatage_coff": stamp, "imports": imports, "imports_differes": delayed}
    except struct.error:
        return {"erreur": "en-tête PE illisible"}


FFMPEG_DLL = re.compile(r"(%s)-\d+\.dll" % "|".join(FFMPEG_LIBS), re.I)
FFMPEG_LIKE = re.compile(r"(%s)[-_.].*dll" % "|".join(FFMPEG_LIBS), re.I)
# DLL qu'aucun Windows ne fournit : bibliothèques d'exécution de la chaîne (libstdc++-6, libgcc_s_seh-1,
# libwinpthread-1, libssp-0) et bibliothèques tierces partagées. Leur présence dans une table d'import veut dire
# qu'un composant n'a pas été lié comme prévu, ou qu'il faudrait livrer une DLL de plus.
NOT_SHIPPED_DLL = re.compile(r"(lib.*|zlib1|lua5\d.*|vulkan-1|dav1d.*|ass.*|freetype.*|harfbuzz.*|fribidi.*"
                             r"|shaderc.*|spirv-cross.*|placebo.*|glslang.*)\.dll", re.I)
MPV_MUST_IMPORT = ("avcodec", "avfilter", "avformat", "avutil", "swresample", "swscale")


def pe_refusals(name: str, pe: dict) -> list[str]:
    if "erreur" in pe:
        return [pe["erreur"]]
    ref = []
    base = name.rsplit("/", 1)[-1].rsplit("!", 1)[-1]
    in_wheel = "!" in name
    for imp in pe["imports"] + pe["imports_differes"]:
        if FFMPEG_LIKE.fullmatch(imp) and not FFMPEG_DLL.fullmatch(imp):
            ref.append(f"import d'une DLL FFmpeg renommée : {imp}")
        elif NOT_SHIPPED_DLL.fullmatch(imp):
            ref.append(f"import d'une DLL non livrée : {imp}")
    if base.lower().startswith("libmpv"):
        got = {m.group(1).lower() for m in (FFMPEG_DLL.fullmatch(i) for i in pe["imports"]) if m}
        missing = [x for x in MPV_MUST_IMPORT if x not in got]
        if missing:
            ref.append("libmpv n'importe pas " + ", ".join(missing) + " : liaison dynamique à FFmpeg non établie")
    if not in_wheel:
        sde = os.environ.get("SOURCE_DATE_EPOCH")
        ok = {0} | ({int(sde)} if sde and sde.isdigit() else set())
        if pe["horodatage_coff"] not in ok:
            ref.append(f"horodatage PE {pe['horodatage_coff']} (attendu : {sorted(ok)}, DA-6)")
    return ref


def context(data: bytes, start: int, end: int, width: int = 40) -> str:
    """Voisinage imprimable d'une occurrence (pour juger une occurrence au journal)."""
    chunk = data[max(0, start - width): end + width]
    return "".join(chr(b) if 0x20 <= b < 0x7f else "." for b in chunk)


def allowed_spans(data: bytes, strings: list[bytes]) -> list[tuple[int, int]]:
    spans = []
    for a in strings:
        i = data.find(a)
        while i != -1:
            spans.append((i, i + len(a)))
            i = data.find(a, i + 1)
    return spans


def scan_bytes(name: str, data: bytes) -> dict:
    res = {"fichier": name, "octets": len(data), "sha256": hashlib.sha256(data).hexdigest(),
           "occurrences": {}, "contextes_interdits": {}, "x264_contextes": [], "refus": []}
    for ident, pat in FORBIDDEN:
        found = list(re.finditer(pat, data))
        res["occurrences"][ident] = len(found)
        if found:
            ctxs = [context(data, m.start(), m.end()) for m in found[:5]]
            res["contextes_interdits"][ident] = ctxs
            res["refus"].append(f"{ident} ×{len(found)} (ex. : {ctxs[0]})")
    spans = allowed_spans(data, X264_ALLOWED_STRINGS)
    for m in re.finditer(rb"(?i)x264", data):
        ok = any(s <= m.start() and m.end() <= e for s, e in spans)
        ctx = context(data, m.start(), m.end())
        res["x264_contextes"].append({"admis": ok, "contexte": ctx})
        if not ok:
            res["refus"].append("x264 hors des chaînes admises : " + ctx)
    pe = pe_info(data)
    if pe is not None:
        res["pe"] = pe
        res["refus"] += pe_refusals(name, pe)
    base = name.rsplit("/", 1)[-1]
    if is_ffmpeg_dll(base):
        confs = printable_strings(data, b"--disable-everything")
        res["configuration_ffmpeg"] = confs
        if not confs:
            res["refus"].append("configuration FFmpeg embarquée introuvable")
        lic = sorted(set(m.group(0).decode() for m in re.finditer(rb"L?GPL version [0-9.]+ or later", data)))
        res["etiquette_licence"] = lic
        if lic != ["LGPL version 2.1 or later"]:
            res["refus"].append(f"étiquette de licence inattendue : {lic}")
    if base.lower().startswith("libmpv"):
        confs = printable_strings(data, b"-Dgpl=")
        res["configuration_mpv"] = confs
        if not any("-Dgpl=false" in c for c in confs):
            res["refus"].append("-Dgpl=false absent de la configuration mpv embarquée")
        feats = printable_strings(data, b"List of enabled features")
        res["fonctions_mpv"] = feats
    return res


def iter_targets(paths: list[str]):
    """(nom, octets) de chaque binaire : fichiers .dll/.exe/.pyd, répertoires, et membres de wheels."""
    for p in paths:
        path = pathlib.Path(p)
        files = sorted(path.rglob("*")) if path.is_dir() else [path]
        for f in files:
            if not f.is_file():
                continue
            low = f.name.lower()
            if low.endswith((".dll", ".exe", ".pyd")):
                yield str(f.as_posix()), f.read_bytes()
            elif low.endswith(".whl"):
                with zipfile.ZipFile(f) as z:
                    for info in sorted(z.infolist(), key=lambda i: i.filename):
                        if info.filename.lower().endswith((".dll", ".pyd", ".exe")):
                            yield f"{f.name}!{info.filename}", z.read(info)


# --------------------------------------------------------------------------- cartes d'édition de liens
MAP_SECTION_END = ("Discarded input sections", "Memory Configuration", "Allocating common symbols",
                   "Linker script and memory map")


def parse_map(text: str) -> dict:
    """Archives dont l'éditeur de liens a tiré des membres, et fichiers chargés (LOAD)."""
    members: dict[str, set] = {}
    lines = text.splitlines()
    in_sec = False
    # « archive(membre) » seul sur sa ligne, ou suivi sur la même ligne du fichier qui l'a appelé
    # (ld aligne les chemins courts) ; les chemins des conteneurs ne contiennent pas d'espace.
    rx = re.compile(r"^(\S+?\.(?:a|lib))\(([^)\s]+)\)(?:\s.*)?$")
    for ln in lines:
        if ln.startswith("Archive member included to satisfy reference by file"):
            in_sec = True
            continue
        if in_sec and ln.startswith(MAP_SECTION_END):
            in_sec = False
        if in_sec:
            m = rx.match(ln)
            if m:
                members.setdefault(m.group(1), set()).add(m.group(2))
    loads = [ln.split(None, 1)[1].strip() for ln in lines if ln.startswith("LOAD ")]
    return {"archives": {k: sorted(v) for k, v in sorted(members.items())}, "load": loads}


TOOLCHAIN_ROOT = "/opt/ct-ng/"
PREFIX_LIB = "/work/prefix/lib/"

# Archives du préfixe autorisées, par binaire (DA-3, DA-4). Les bibliothèques d'import FFmpeg sont admises partout.
FFMPEG_IMPORT = re.compile(r"(^|/)lib(%s)\.dll\.a$" % "|".join(FFMPEG_LIBS))
ALLOWED_PREFIX = {
    "avcodec": {"libdav1d.a", "libz.a"},
    "avformat": {"libz.a"},
    "avfilter": set(),
    "avdevice": set(),
    "avutil": set(),
    "swresample": set(),
    "swscale": set(),
    "ffprobe": set(),
    "libmpv": {"libass.a", "libfreetype.a", "libfribidi.a", "libharfbuzz.a", "libplacebo.a",
               "libshaderc_combined.a", "libspirv-cross-c.a", "libspirv-cross-glsl.a",
               "libspirv-cross-hlsl.a", "libspirv-cross-reflect.a", "libspirv-cross-util.a",
               "libspirv-cross-core.a", "libluajit-5.1.a", "libz.a"},
}


def owner_of(map_name: str) -> str:
    base = map_name.split("/")[-1]
    for k in ALLOWED_PREFIX:
        if base.startswith(k):
            return k
    return "?"


def check_map(map_name: str, parsed: dict) -> list[str]:
    refus = []
    own = owner_of(map_name)
    allowed = ALLOWED_PREFIX.get(own)
    if allowed is None:
        return [f"carte sans règle d'autorisation : {map_name}"]
    for arch in parsed["archives"]:
        base = arch.split("/")[-1]
        if arch.startswith(TOOLCHAIN_ROOT):
            continue                      # chaîne d'outils : inventoriée, jamais refusée ici
        if FFMPEG_IMPORT.search(arch):
            continue                      # bibliothèques d'import des DLL FFmpeg (liaison dynamique)
        if arch.startswith(PREFIX_LIB) and base in allowed:
            continue
        refus.append(f"{map_name} : bibliothèque statique hors liste liée : {arch}")
    return refus


# --------------------------------------------------------------------------- inventaire
COMPONENT_OF = [
    (r"libdav1d\.a$", "dav1d"), (r"libz\.a$", "zlib"), (r"libass\.a$", "libass"),
    (r"libfreetype\.a$", "freetype"), (r"libfribidi\.a$", "fribidi"), (r"libharfbuzz\.a$", "harfbuzz"),
    (r"libplacebo\.a$", "libplacebo"), (r"libshaderc_combined\.a$", "shaderc+glslang+spirv-tools"),
    (r"libspirv-cross-[a-z]+\.a$", "spirv-cross"), (r"libluajit-5\.1\.a$", "luajit"),
    (FFMPEG_IMPORT.pattern, "ffmpeg (import)"),
    (r"/libgcc(_eh)?\.a$", "toolchain: libgcc"), (r"/libstdc\+\+\.a$", "toolchain: libstdc++"),
    (r"/libssp(_nonshared)?\.a$", "toolchain: libssp"),
    (r"/lib(pthread|winpthread)\.a$", "toolchain: winpthreads"),
    (r"/lib(mingw32|mingwex|moldname|msvcrt[a-z0-9-]*|ucrt[a-z0-9-]*|ucrtbase|api-ms-win-[a-z0-9-]+)\.a$",
     "toolchain: mingw-w64 CRT"),
]


def component(arch: str) -> str:
    for pat, comp in COMPONENT_OF:
        if re.search(pat, arch):
            return comp
    if arch.startswith(TOOLCHAIN_ROOT):
        return "toolchain: bibliothèque d'import Windows (" + arch.split("/")[-1] + ")"
    return "INCONNU"


def cmd_inventory(args) -> int:
    pins = {}
    for ln in pathlib.Path(args.pins).read_text(encoding="utf-8").splitlines():
        m = re.match(r"^([A-Z0-9_]+)=(.*)$", ln)
        if m:
            pins[m.group(1)] = m.group(2).strip('"')
    inv = {"binaires": {}}
    for mp in sorted(pathlib.Path(args.maps).glob("*.map")):
        parsed = parse_map(mp.read_text(encoding="utf-8", errors="replace"))
        rows = []
        for arch, mem in parsed["archives"].items():
            rows.append({"archive": arch, "composant": component(arch), "membres": len(mem)})
        inv["binaires"][mp.name[:-4]] = rows
    inv["commits"] = {k[:-7].lower(): v for k, v in pins.items() if k.endswith("_COMMIT")}
    pathlib.Path(args.json).write_text(json.dumps(inv, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    md = ["# Inventaire lié (tiré des cartes d'édition de liens)", ""]
    for b, rows in inv["binaires"].items():
        md += [f"## {b}", "", "| composant | archive | membres tirés |", "|---|---|---|"]
        for r in sorted(rows, key=lambda r: (r["composant"], r["archive"])):
            md.append(f"| {r['composant']} | `{r['archive']}` | {r['membres']} |")
        md.append("")
    pathlib.Path(args.md).write_text("\n".join(md), encoding="utf-8")
    unknown = [r for rows in inv["binaires"].values() for r in rows if r["composant"] == "INCONNU"]
    print(f"inventaire : {len(inv['binaires'])} binaires, {sum(len(r) for r in inv['binaires'].values())} archives,"
          f" {len(unknown)} inconnue(s)")
    for r in unknown:
        print("  INCONNU :", r["archive"])
    return 0


def cmd_scan(args) -> int:
    report = {"binaires": [], "cartes": [], "refus": []}
    for name, data in iter_targets(args.paths):
        r = scan_bytes(name, data)
        report["binaires"].append(r)
        report["refus"] += [f"{name} : {x}" for x in r["refus"]]
    if args.maps:
        maps = sorted(pathlib.Path(args.maps).glob("*.map"))
        if not maps:
            report["refus"].append(f"aucune carte d'édition de liens dans {args.maps}")
        for mp in maps:
            parsed = parse_map(mp.read_text(encoding="utf-8", errors="replace"))
            ref = check_map(mp.name, parsed)
            report["cartes"].append({"carte": mp.name, "archives": list(parsed["archives"]), "refus": ref})
            report["refus"] += ref
    if args.identical_to:
        ref_dir = pathlib.Path(args.identical_to)
        for b in report["binaires"]:
            if "!" in b["fichier"] and b["fichier"].lower().endswith(".dll"):
                base = b["fichier"].rsplit("/", 1)[-1]
                ref = ref_dir / base
                if not ref.is_file():
                    report["refus"].append(f"{b['fichier']} : aucune DLL de même nom dans {ref_dir}")
                elif hashlib.sha256(ref.read_bytes()).hexdigest() != b["sha256"]:
                    report["refus"].append(f"{b['fichier']} : diffère de {ref}")
    if not report["binaires"]:
        report["refus"].append("aucun binaire balayé")
    pathlib.Path(args.report).write_text(json.dumps(report, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    for b in report["binaires"]:
        nz = {k: v for k, v in b["occurrences"].items() if v}
        print(f"{b['fichier']} : {b['octets']} o, sha256 {b['sha256'][:16]}…, occurrences {nz or 'aucune'}, "
              f"x264 {len(b['x264_contextes'])} (admis {sum(c['admis'] for c in b['x264_contextes'])})")
        pe = b.get("pe")
        if pe and "imports" in pe:
            print(f"    PE {pe['machine']}, horodatage {pe['horodatage_coff']}, imports : {', '.join(pe['imports'])}"
                  + (f" ; différés : {', '.join(pe['imports_differes'])}" if pe["imports_differes"] else ""))
    for c in report["cartes"]:
        print(f"carte {c['carte']} : {len(c['archives'])} archives, refus {len(c['refus'])}")
    if report["refus"]:
        print("REFUS :")
        for x in report["refus"]:
            print("  -", x)
        return 1
    print("balayage : aucun refus")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan")
    s.add_argument("paths", nargs="+")
    s.add_argument("--maps")
    s.add_argument("--identical-to", help="les DLL trouvées dans les wheels doivent être identiques à celles de ce répertoire")
    s.add_argument("--report", required=True)
    i = sub.add_parser("inventory")
    i.add_argument("--maps", required=True)
    i.add_argument("--pins", required=True)
    i.add_argument("--json", required=True)
    i.add_argument("--md", required=True)
    a = ap.parse_args()
    return cmd_scan(a) if a.cmd == "scan" else cmd_inventory(a)


if __name__ == "__main__":
    sys.exit(main())
