#!/usr/bin/env bash
# fetch-sources.sh <répertoire de sortie>
#
# Récupère chaque composant de pins.env à son commit épinglé (git fetch --depth=1 <commit>),
# vérifie que HEAD est bien ce commit, puis en fait une archive `git archive` (qui applique
# export-subst, p. ex. le .relver de LuaJIT) compressée par xz mono-fil, donc déterministe.
# Les sous-modules de libplacebo sont lus dans l'arbre du commit épinglé (mode 160000) et
# archivés à part, sous le préfixe qui les replace à leur chemin.
# Sortie : une archive par composant, SOURCES.tsv (dépôt, commit, octets, sha256), SHA256SUMS.
# S'exécute sur le runner (git, xz, tar), jamais dans l'image de la chaîne d'outils.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../pins.env
source "$here/pins.env"

out="$(realpath -m "${1:?usage: fetch-sources.sh <sortie>}")"
mkdir -p "$out"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export TZ=UTC LC_ALL=C GIT_TERMINAL_PROMPT=0

name_of() { echo "$1" | tr 'A-Z_' 'a-z-'; }   # SPIRV_TOOLS -> spirv-tools

fetch() {  # fetch <répertoire> <dépôt> <commit>
    local dir="$1" repo="$2" commit="$3" n
    rm -rf "$dir"
    git init -q "$dir"
    git -C "$dir" remote add origin "$repo"
    for n in 1 2 3 4 5; do
        if git -C "$dir" fetch -q --depth=1 origin "$commit"; then
            break
        fi
        if [ "$n" = 5 ]; then
            echo "échec : git fetch $repo $commit" >&2
            exit 1
        fi
        sleep $((n * 15))
    done
    git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
    if [ "$(git -C "$dir" rev-parse HEAD)" != "$commit" ]; then
        echo "échec : $repo, HEAD $(git -C "$dir" rev-parse HEAD) au lieu de $commit" >&2
        exit 1
    fi
}

archive() {  # archive <répertoire git> <préfixe/> <fichier.tar.xz>
    git -C "$1" archive --format=tar --prefix="$2" HEAD | xz -9 -T1 -c > "$3"
}

printf 'composant\tdepot\tcommit\tarchive\toctets\tsha256\n' > "$out/SOURCES.tsv"
record() {  # record <composant> <dépôt> <commit> <fichier>
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$(basename "$4")" \
        "$(stat -c %s "$4")" "$(sha256sum "$4" | cut -d' ' -f1)" >> "$out/SOURCES.tsv"
}

git --version
for c in $COMPONENTS; do
    repo_var="${c}_REPO"
    commit_var="${c}_COMMIT"
    repo="${!repo_var}"
    commit="${!commit_var}"
    n="$(name_of "$c")"
    d="$work/$n"
    echo "::group::$n @ $commit"
    fetch "$d" "$repo" "$commit"
    f="$out/$n-$commit.tar.xz"
    archive "$d" "$n/" "$f"
    record "$n" "$repo" "$commit" "$f"
    if [ "$c" = LIBPLACEBO ]; then
        for sm in $LIBPLACEBO_SUBMODULES; do
            # commit du sous-module tel qu'enregistré dans l'arbre du commit épinglé
            smc="$(git -C "$d" ls-tree HEAD "$sm" | awk '$1 == "160000" { print $3 }')"
            smurl="$(git -C "$d" config -f .gitmodules "submodule.$sm.url")"
            if [ -z "$smc" ] || [ -z "$smurl" ]; then
                echo "échec : sous-module $sm introuvable dans libplacebo@$commit" >&2
                exit 1
            fi
            smn="libplacebo-$(basename "$sm" | tr 'A-Z_' 'a-z-')"
            fetch "$work/sub-$smn" "$smurl" "$smc"
            f="$out/$smn-$smc.tar.xz"
            archive "$work/sub-$smn" "$n/$sm/" "$f"
            record "$smn" "$smurl" "$smc" "$f"
        done
    fi
    rm -rf "$d" "$work"/sub-*
    echo "::endgroup::"
done

(cd "$out" && sha256sum -- *.tar.xz > SHA256SUMS)
cat "$out/SOURCES.tsv"
