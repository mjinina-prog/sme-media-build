#!/usr/bin/env bash
# run-build.sh — lance build-all.sh dans l'image de la chaîne d'outils, lue par digest.
# Source de l'image : le miroir ghcr (défaut), ou une archive `docker save` si IMAGE_ARCHIVE_DIR est posé
# (parties base-win64.docker.tar.zst.part-*, c'est le contrôle de restauration de M7).
# Entrées : out/sources (archives). Sortie : out/build.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
source "$here/pins.env"
work="${RUNNER_TEMP:-/tmp}/smework"
out="$here/out/build"
rm -rf "$work" "$out"
mkdir -p "$work" "$out"

if [ -n "${IMAGE_ARCHIVE_DIR:-}" ]; then
    (cd "$IMAGE_ARCHIVE_DIR" && sha256sum -c base-win64.docker.tar.zst.sha256)
    cat "$IMAGE_ARCHIVE_DIR"/base-win64.docker.tar.zst.part-* | zstd -d -c | docker load
    image="$(docker image ls --digests --format '{{.ID}}' | head -1)"
    for ref in "$TOOLCHAIN_IMAGE_ID" "${TOOLCHAIN_MIRROR}@${TOOLCHAIN_DIGEST}" "${TOOLCHAIN_MIRROR}:${TOOLCHAIN_MIRROR_TAG}"; do
        if docker image inspect "$ref" >/dev/null 2>&1; then image="$ref"; break; fi
    done
else
    image="${TOOLCHAIN_MIRROR}@${TOOLCHAIN_DIGEST}"
    docker pull -q "$image"
fi

# L'image doit être celle qui est épinglée : identifiant = digest de la configuration (magasin classique)
# ou digest du manifeste (magasin containerd).
id="$(docker image inspect --format '{{.Id}}' "$image")"
echo "image : $image"
echo "identifiant : $id"
if [ "$id" != "$TOOLCHAIN_IMAGE_ID" ] && [ "$id" != "$TOOLCHAIN_DIGEST" ]; then
    echo "image inattendue (attendu $TOOLCHAIN_IMAGE_ID ou $TOOLCHAIN_DIGEST)" >&2
    exit 1
fi
docker version --format 'docker {{.Server.Version}}'
docker info --format 'magasin : {{.Driver}}' || true

docker run --rm -u "$(id -u):$(id -g)" \
    -v "$here":/recipe:ro -v "$here/out/sources":/sources:ro -v "$work":/work -v "$out":/out \
    "$image" bash /recipe/recipe/build-all.sh
