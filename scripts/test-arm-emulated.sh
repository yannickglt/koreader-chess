#!/bin/sh
# Rejoue la suite de tests dans un conteneur Linux ARMv7 émulé, avec le LuaJIT, les
# déclarations POSIX et ffi/util (fork par runInSubProcess) du paquet officiel KOReader kobov5
# et le Stockfish ARM du plugin. « transport: OK (koreader) » confirme que le chemin KOReader
# a bien été exercé.
# Ce n'est pas une mesure sur la Tolino : vitesse réelle, mémoire et batterie restent à relever
# sur l'appareil (docs/VALIDATION.md).
set -eu
cd "$(dirname "$0")/.."
: "${KOREADER_PACKAGE:?Chemin absolu vers le dossier koreader extrait de koreader-kobov5-v2026.07.1.zip}"
test -x "$KOREADER_PACKAGE/luajit"
test -f "$KOREADER_PACKAGE/ffi/posix_h.lua"
docker run --rm --platform linux/arm/v7 \
    -v "$PWD:/repo:ro" -v "$KOREADER_PACKAGE:/koreader:ro" \
    debian:bookworm-slim sh -c '
        set -e
        cd /repo
        export LUA_PATH="/koreader/?.lua;;" LUA_CPATH="/koreader/?.so;;"
        /koreader/luajit -v
        echo "--- stockfish bench 8 1 6 default depth (émulation, pas la Tolino) ---"
        LD_LIBRARY_PATH=/repo/chess.koplugin/bin /repo/chess.koplugin/bin/stockfish bench 8 1 6 default depth 2>&1 | tail -4
        echo "--- tests ---"
        LUAJIT=/koreader/luajit STOCKFISH=/repo/chess.koplugin/bin/stockfish ./scripts/test.sh'
