#!/bin/sh
set -eu
: "${STOCKFISH:?Indiquer le chemin du binaire Stockfish à mesurer}"
"$STOCKFISH" bench 8 1 6 default depth
