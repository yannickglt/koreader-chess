#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${LUAJIT:?Indiquer le chemin absolu vers luajit}"
"$LUAJIT" tests/test_board.lua
"$LUAJIT" tests/test_game.lua
"$LUAJIT" tests/test_engine.lua
"$LUAJIT" tests/test_transport.lua
"$LUAJIT" tests/test_ui.lua
if [ -n "${STOCKFISH:-}" ]; then
    "$LUAJIT" tests/test_integration.lua
    "$LUAJIT" tests/test_rules.lua
    "$LUAJIT" tests/test_shutdown.lua
fi
