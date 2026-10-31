#!/bin/sh
# Construit une archive de chess.koplugin prête à être décompressée dans
# .adds/koreader/plugins/ de la liseuse. Ne touche pas à la liseuse.
set -eu
cd "$(dirname "$0")/.."
test -x chess.koplugin/bin/stockfish
file chess.koplugin/bin/stockfish | grep -q "ELF 32-bit LSB executable, ARM" \
    || { echo "chess.koplugin/bin/stockfish n'est pas un ELF ARM 32 bits" >&2; exit 1; }
for lib in libatomic.so.1 libstdc++.so.6 libgcc_s.so.1; do
    test -f "chess.koplugin/bin/$lib" || { echo "bibliothèque absente : $lib" >&2; exit 1; }
done
# Nom de version : le tag courant (release), sinon la date et le commit.
version="$(git describe --tags --exact-match 2>/dev/null || echo "$(date +%Y-%m-%d)-$(git rev-parse --short HEAD)")"
if [ -n "$(git status --porcelain chess.koplugin)" ]; then version="$version-dirty"; fi
mkdir -p dist
archive="dist/chess.koplugin-$version.zip"
rm -f "$archive" "$archive.sha256"
find chess.koplugin -name '.DS_Store' -delete
zip -q -r -X "$archive" chess.koplugin -x '*.DS_Store'
shasum -a 256 "$archive" | tee "$archive.sha256"
unzip -l "$archive" | tail -1
echo "Archive : $archive"
