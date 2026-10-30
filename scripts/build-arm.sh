#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${STOCKFISH_SOURCE:?Chemin absolu vers la source officielle Stockfish 16 (commit 68e1e9b3811e16cad014b590d7443b9063b3eb52)}"
: "${KOBOV5_TOOLCHAIN:?Chemin absolu vers x-tools/arm-kobov5-linux-gnueabihf}"
test -f "$STOCKFISH_SOURCE/src/nn-5af11540bbfe.nnue"
test -x "$KOBOV5_TOOLCHAIN/bin/arm-kobov5-linux-gnueabihf-g++"
docker run --rm --platform linux/amd64 \
    -v "$STOCKFISH_SOURCE:/stockfish" \
    -v "$KOBOV5_TOOLCHAIN:/toolchain:ro" \
    -w /stockfish/src debian:trixie-slim sh -lc \
    'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq make curl >/dev/null && export PATH=/toolchain/bin:$PATH && make clean ARCH=armv7-neon KERNEL=Linux COMP=gcc COMPCXX=arm-kobov5-linux-gnueabihf-g++ && make -j4 build ARCH=armv7-neon KERNEL=Linux COMP=gcc COMPCXX=arm-kobov5-linux-gnueabihf-g++ STRIP=arm-kobov5-linux-gnueabihf-strip && arm-kobov5-linux-gnueabihf-strip stockfish'
mkdir -p chess.koplugin/bin
cp "$STOCKFISH_SOURCE/src/stockfish" chess.koplugin/bin/stockfish
cp -L "$KOBOV5_TOOLCHAIN/arm-kobov5-linux-gnueabihf/sysroot/lib/libatomic.so.1" chess.koplugin/bin/libatomic.so.1
cp -L "$KOBOV5_TOOLCHAIN/arm-kobov5-linux-gnueabihf/sysroot/lib/libstdc++.so.6" chess.koplugin/bin/libstdc++.so.6
cp -L "$KOBOV5_TOOLCHAIN/arm-kobov5-linux-gnueabihf/sysroot/lib/libgcc_s.so.1" chess.koplugin/bin/libgcc_s.so.1
chmod 755 chess.koplugin/bin/stockfish
file chess.koplugin/bin/stockfish
shasum -a 256 chess.koplugin/bin/stockfish
