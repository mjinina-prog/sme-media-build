#!/usr/bin/env bash
# package-release.sh <étiquette> <entrées> <sortie> — assemble les fichiers de la release (DA-8).
# <entrées> contient : sources/, build-bin/, build-dev/, build-maps/, build-meta/, wheel/, audit/.
# L'image de la chaîne d'outils n'est pas publiée : la release la nomme par digest et par l'empreinte de sa copie
# de référence, tenue hors ligne (TOOLCHAIN.txt).
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

# Preuves : cartes d'édition de liens, inventaire, balayage, configuration embarquée.
cp -r "$in/build-maps" "$stage/sme-media-maps"
tarz "$out/sme-media-$tag-maps.tar.xz" "$stage/sme-media-maps"
cp "$in"/audit/inventory.json "$in"/audit/inventory.md "$in"/audit/scan.json "$out/"
cp -r "$in/build-meta" "$stage/sme-media-meta"
tarz "$out/sme-media-$tag-meta.tar.xz" "$stage/sme-media-meta"

# Source correspondante : archives de chaque composant au commit, liste, recette et workflow (ce dépôt),
# la chaîne d'outils par ses références, et les modifications apportées aux sources.
mkdir -p "$stage/sme-media-source/components"
cp "$in"/sources/* "$stage/sme-media-source/components/"
git -C "$here" archive --format=tar --prefix=sme-media-build/ HEAD > "$stage/sme-media-source/sme-media-build-recipe.tar"
git -C "$here" rev-parse HEAD > "$stage/sme-media-source/RECIPE_COMMIT"
cat > "$stage/sme-media-source/TOOLCHAIN.txt" <<EOF
Image de la chaîne d'outils (DA-6)
amont       : ${TOOLCHAIN_UPSTREAM}@${TOOLCHAIN_DIGEST}
identifiant : ${TOOLCHAIN_IMAGE_ID} (empreinte de sa configuration)
archive     : non publiée ; copie de référence tenue hors ligne (docker save, zstd),
              empreinte ${TOOLCHAIN_ARCHIVE_SHA256}
restaurer   : cat base-win64.docker.tar.zst.part-* | zstd -d -c | docker load
construire  : IMAGE_ARCHIVE_DIR=<répertoire de l'archive> bash recipe/run-build.sh
EOF
cat > "$stage/sme-media-source/MODIFICATIONS.txt" <<EOF
Modifications apportées aux sources des composants par la recette (recipe/build-all.sh), depuis le 2026-09-27.
Les archives de components/ sont celles des commits, sans retouche ; ces modifications se font à la construction.

mpv, commit ${MPV_COMMIT} (LGPL-2.1 ou ultérieure ; mention exigée par la LGPL-2.1, § 2 b)
  Fichier MPV_VERSION (fonction build_mpv) : sa ligne unique, « 0.41.0-UNKNOWN » dans l'archive du commit, devient
  « 0.41.0-dev-g${MPV_COMMIT:0:9} », la forme que produit le CI de mpv sur un clone, pour que libmpv nomme son
  commit (propriété mpv-version). meson exige que ce fichier ne contienne qu'une ligne : la mention de la
  modification ne peut pas y être écrite ; elle l'est ici et dans les notes de la release.

LuaJIT, commit ${LUAJIT_COMMIT} (MIT)
  Fichier etc/luajit.pc (fonction build_luajit) : la ligne « Libs.private: -Wl,-E -lm -ldl » est retirée avant
  l'installation, pour que l'édition de liens de libmpv ne reçoive pas ces options, propres à Unix. C'est un
  fichier pkg-config ; aucun code compilé n'est modifié.

Aucun autre fichier des sources n'est modifié. Les autres retouches de la recette portent sur des fichiers
pkg-config installés dans le préfixe de construction, pas sur les sources.
EOF
tar --sort=name --mtime="@${SOURCE_DATE_EPOCH}" --owner=0 --group=0 --numeric-owner \
    -cf "$out/sme-media-$tag-source.tar" -C "$stage" sme-media-source

(cd "$out" && sha256sum -- * > SHA256SUMS)
rm -rf "$stage"
ls -l "$out"
