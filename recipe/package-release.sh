#!/usr/bin/env bash
# package-release.sh <étiquette> <entrées> <sortie> — assemble les fichiers de la release (DA-8).
# <entrées> contient : sources/, build-bin/, build-dev/, build-maps/, build-meta/, wheel/, audit/, toolchain/.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
source "$here/pins.env"
tag="${1:?étiquette}"
in="$(realpath "${2:?entrées}")"
out="$(realpath -m "${3:?sortie}")"
rm -rf "$out"
mkdir -p "$out"
export TZ=UTC LC_ALL=C
tarz() {  # tarz <archive.tar.xz|.zip> <répertoire> : archive déterministe
    tar --sort=name --mtime="@${SOURCE_DATE_EPOCH}" --owner=0 --group=0 --numeric-owner \
        --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime -cf - -C "$(dirname "$2")" "$(basename "$2")" \
        | xz -9 -T1 -c > "$1"
}
stage="$(mktemp -d)"

# Exécution : les huit DLL, les licences de mpv et de FFmpeg.
mkdir -p "$stage/sme-media-win64/bin"
cp "$in"/build-bin/*.dll "$stage/sme-media-win64/bin/"
cp "$in"/build-dev/libmpv/LICENSE.LGPL "$stage/sme-media-win64/LICENSE.LGPL.mpv"
cp "$in"/build-dev/ffmpeg/COPYING.LGPLv2.1 "$stage/sme-media-win64/COPYING.LGPLv2.1.ffmpeg"
cp "$in"/build-dev/ffmpeg/LICENSE.md "$stage/sme-media-win64/LICENSE.md.ffmpeg"
(cd "$stage/sme-media-win64" && sha256sum bin/*.dll > SHA256SUMS)
tarz "$out/sme-media-$tag-win64-runtime.tar.xz" "$stage/sme-media-win64"

# Développement : en-têtes, bibliothèques d'import, pkg-config.
cp -r "$in/build-dev" "$stage/sme-media-dev"
tarz "$out/sme-media-$tag-win64-dev.tar.xz" "$stage/sme-media-dev"

# Wheel PyAV.
cp "$in"/wheel/*.whl "$out/"

# Preuves : cartes d'édition de liens, inventaire, balayage, configuration embarquée, chaîne d'outils.
cp -r "$in/build-maps" "$stage/sme-media-maps"
tarz "$out/sme-media-$tag-maps.tar.xz" "$stage/sme-media-maps"
cp "$in"/audit/inventory.json "$in"/audit/inventory.md "$in"/audit/scan.json "$out/"
cp -r "$in/build-meta" "$stage/sme-media-meta"
tarz "$out/sme-media-$tag-meta.tar.xz" "$stage/sme-media-meta"

# Source correspondante : archives de chaque composant au commit, liste, recette et workflow (ce dépôt).
mkdir -p "$stage/sme-media-source/components"
cp "$in"/sources/* "$stage/sme-media-source/components/"
git -C "$here" archive --format=tar --prefix=sme-media-build/ HEAD > "$stage/sme-media-source/sme-media-build-recipe.tar"
git -C "$here" rev-parse HEAD > "$stage/sme-media-source/RECIPE_COMMIT"
cp "$in"/toolchain/TOOLCHAIN.txt "$stage/sme-media-source/"
tar --sort=name --mtime="@${SOURCE_DATE_EPOCH}" --owner=0 --group=0 --numeric-owner \
    -cf "$out/sme-media-$tag-source.tar" -C "$stage" sme-media-source

# Image de la chaîne d'outils (docker save, en parties).
cp "$in"/toolchain/base-win64.docker.tar.zst.part-* "$in"/toolchain/base-win64.docker.tar.zst.sha256 "$out/"

(cd "$out" && sha256sum -- * > SHA256SUMS)
rm -rf "$stage"
ls -l "$out"
