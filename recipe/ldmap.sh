#!/usr/bin/env bash
# ldmap.sh <pilote> <arguments…>
# Lance l'édition de liens avec <pilote> (p. ex. x86_64-w64-mingw32-gcc). Quand la sortie est une DLL
# ou un EXE, ajoute la carte d'édition de liens (<sortie>.map, exigée par DA-7) et un horodatage PE nul
# (--no-insert-timestamp, reproductibilité). Sert de --ld à FFmpeg.
set -u
drv="$1"
shift
out=""
prev=""
for a in "$@"; do
    if [ "$prev" = "-o" ]; then
        out="$a"
    fi
    case "$a" in
        -o?*) out="${a#-o}" ;;
    esac
    prev="$a"
done
case "$out" in
    *.dll|*.exe) exec "$drv" "$@" "-Wl,-Map=$out.map" -Wl,--no-insert-timestamp ;;
    *) exec "$drv" "$@" ;;
esac
