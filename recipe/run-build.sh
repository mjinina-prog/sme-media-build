#!/usr/bin/env bash
# run-build.sh — lance build-all.sh dans l'image de la chaîne d'outils, lue par digest.
# Source de l'image, dans l'ordre :
#   1. une archive `docker save` si IMAGE_ARCHIVE_DIR est posé (parties base-win64.docker.tar.zst.part-* et leur
#      empreinte : c'est la copie de référence, tenue hors ligne ; elle n'est plus publiée avec les releases) ;
#   2. sinon l'image amont de BtbN, par digest (BtbN ne garde que deux versions : le digest peut disparaître).
# Quelle que soit la source, l'identifiant de l'image est comparé à celui de pins.env avant toute construction.
# Entrées : out/sources (archives). Sortie : out/build.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
source "$here/pins.env"
work="${RUNNER_TEMP:-/tmp}/smework"
out="$here/out/build"
rm -rf "$work" "$out"
mkdir -p "$work" "$out"

if [ -n "${IMAGE_ARCHIVE_DIR:-}" ]; then
    # L'empreinte attendue est celle que pins.env épingle ; elle porte sur l'archive entière, qui peut être
    # découpée en parties : on la recompose.
    want="$TOOLCHAIN_ARCHIVE_SHA256"
    if [ -f "$IMAGE_ARCHIVE_DIR/base-win64.docker.tar.zst.sha256" ] \
        && [ "$(cut -d' ' -f1 "$IMAGE_ARCHIVE_DIR/base-win64.docker.tar.zst.sha256")" != "$want" ]; then
        echo "base-win64.docker.tar.zst.sha256 ne porte pas l'empreinte de pins.env ($want)" >&2
        exit 1
    fi
    got="$(cat "$IMAGE_ARCHIVE_DIR"/base-win64.docker.tar.zst.part-* | sha256sum | cut -d' ' -f1)"
    if [ -z "$want" ] || [ "$got" != "$want" ]; then
        echo "archive de l'image : empreinte $got, attendu $want" >&2
        exit 1
    fi
    echo "archive de l'image : empreinte $got conforme"
    cat "$IMAGE_ARCHIVE_DIR"/base-win64.docker.tar.zst.part-* | zstd -d -c | docker load
    image="$(docker image ls --digests --format '{{.ID}}' | head -1)"
    for ref in "$TOOLCHAIN_IMAGE_ID" "${TOOLCHAIN_UPSTREAM}@${TOOLCHAIN_DIGEST}"; do
        if docker image inspect "$ref" >/dev/null 2>&1; then image="$ref"; break; fi
    done
    source_image="archive (IMAGE_ARCHIVE_DIR)"
else
    image=""
    for ref in "${TOOLCHAIN_UPSTREAM}@${TOOLCHAIN_DIGEST}"; do
        if docker pull -q "$ref"; then image="$ref"; break; fi
        echo "image indisponible : $ref" >&2
    done
    if [ -z "$image" ]; then
        echo "aucun registre ne sert le digest $TOOLCHAIN_DIGEST : restaurer la copie hors ligne (IMAGE_ARCHIVE_DIR)" >&2
        exit 1
    fi
    source_image="$image"
fi

# L'image doit être celle qui est épinglée : identifiant = digest de la configuration (magasin classique)
# ou digest du manifeste (magasin containerd).
id="$(docker image inspect --format '{{.Id}}' "$image")"
echo "image : $image"
echo "source de l'image : $source_image"
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
