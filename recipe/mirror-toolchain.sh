#!/usr/bin/env bash
# mirror-toolchain.sh — copie l'image de la chaîne d'outils de BtbN vers ghcr.io/mjinina-prog, à l'octet près :
# `skopeo copy --preserve-digests` recopie le manifeste tel quel, si bien que le miroir sert le MÊME digest.
# Variables : GHCR_USER, GHCR_TOKEN (GITHUB_TOKEN du workflow, droit packages: write).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
source "$here/pins.env"

command -v skopeo >/dev/null || { sudo apt-get update -q && sudo apt-get install -y -q skopeo; }
skopeo --version

src="docker://${TOOLCHAIN_UPSTREAM}@${TOOLCHAIN_DIGEST}"
dst="docker://${TOOLCHAIN_MIRROR}:${TOOLCHAIN_MIRROR_TAG}"
skopeo copy --retry-times 3 --preserve-digests --dest-creds "${GHCR_USER}:${GHCR_TOKEN}" "$src" "$dst"

# Contrôle : le miroir, lu par digest, rend un manifeste dont l'empreinte est ce digest.
got="sha256:$(skopeo inspect --raw --creds "${GHCR_USER}:${GHCR_TOKEN}" \
    "docker://${TOOLCHAIN_MIRROR}@${TOOLCHAIN_DIGEST}" | sha256sum | cut -d' ' -f1)"
echo "digest épinglé : $TOOLCHAIN_DIGEST"
echo "digest miroir  : $got"
test "$got" = "$TOOLCHAIN_DIGEST"
skopeo inspect --creds "${GHCR_USER}:${GHCR_TOKEN}" "docker://${TOOLCHAIN_MIRROR}@${TOOLCHAIN_DIGEST}" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print("créée :", d.get("Created")); print("couches :", len(d.get("Layers", [])))'
