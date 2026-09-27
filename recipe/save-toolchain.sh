#!/usr/bin/env bash
# save-toolchain.sh <sortie> — `docker save` de l'image miroir (DA-8), compressé (zstd) et découpé en parties
# de moins de 2 Gio (limite d'un fichier de release). Restauration :
#   cat base-win64.docker.tar.zst.part-* | zstd -d -c | docker load
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
source "$here/pins.env"
out="$(realpath -m "${1:?usage: save-toolchain.sh <sortie>}")"
mkdir -p "$out"
image="${TOOLCHAIN_MIRROR}@${TOOLCHAIN_DIGEST}"
docker pull -q "$image"
docker tag "$image" "${TOOLCHAIN_MIRROR}:${TOOLCHAIN_MIRROR_TAG}"
docker save "${TOOLCHAIN_MIRROR}:${TOOLCHAIN_MIRROR_TAG}" | zstd -T0 -12 -c > "$out/base-win64.docker.tar.zst"
(cd "$out" && sha256sum base-win64.docker.tar.zst > base-win64.docker.tar.zst.sha256)
split -b 1900M -d -a 2 "$out/base-win64.docker.tar.zst" "$out/base-win64.docker.tar.zst.part-"
rm "$out/base-win64.docker.tar.zst"
cat > "$out/TOOLCHAIN.txt" <<EOF
Image de la chaîne d'outils (DA-6, DA-8)
amont    : ${TOOLCHAIN_UPSTREAM}@${TOOLCHAIN_DIGEST}
miroir   : ${TOOLCHAIN_MIRROR}@${TOOLCHAIN_DIGEST} (étiquette ${TOOLCHAIN_MIRROR_TAG})
config   : ${TOOLCHAIN_IMAGE_ID}
archive  : base-win64.docker.tar.zst, découpée en parties ; empreinte de l'archive entière dans base-win64.docker.tar.zst.sha256
restaurer: cat base-win64.docker.tar.zst.part-* | zstd -d -c | docker load
EOF
ls -l "$out"
