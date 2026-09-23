#!/bin/bash
# Puts the three files the site serves into the site: the disk image for
# people, the ZIP for the updater, and the appcast that names them both.
#
#   ./publish.sh /path/to/download/folder
#
# ./build.sh release ship makes them first (release dmg makes them too, but
# unnotarised — fine for trying, not for anyone else's Mac). The names never
# change, so the site's links never have to.
set -euo pipefail

cd "$(dirname "$0")"
[ $# -eq 1 ] || { echo "usage: ./publish.sh <folder>" >&2; exit 1; }
FOLDER="$1"
FILES=(Satori.dmg Satori.zip appcast.json)

for FILE in "${FILES[@]}"; do
  [ -f "build/$FILE" ] || { echo "build/$FILE is missing — ./build.sh release dmg makes it" >&2; exit 1; }
done
xcrun stapler validate -q "build/Satori.dmg" >/dev/null 2>&1 \
  || echo "note: build/Satori.dmg is not notarised — ./build.sh release ship does that" >&2

mkdir -p "$FOLDER"
for FILE in "${FILES[@]}"; do
  cp "build/$FILE" "$FOLDER/$FILE"
  echo "copied: build/$FILE → $FOLDER/$FILE"
done
