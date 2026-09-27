#!/usr/bin/env bash
# free-disk.sh — libère de la place sur le runner Ubuntu (image de 2 Go compressés, ~6 Go une fois chargée).
set -u
df -h / | tail -1
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /usr/local/.ghcup /opt/hostedtoolcache/CodeQL \
    /usr/local/share/boost /usr/local/share/powershell /usr/share/swift 2>/dev/null || true
sudo docker image prune -af >/dev/null 2>&1 || true
df -h / | tail -1
