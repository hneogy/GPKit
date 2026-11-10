#!/bin/sh
# Fourth diagnostic: what wasm-ld puts at 0x111c20 (the map), and whether file times or SOURCE_DATE_EPOCH move it.
#   A here; T1 every file's time set to 2026-01-01; T1b the same again; T2 set to 2026-06-01; S SOURCE_DATE_EPOCH=0.
set -eu
SDK=swift-6.4.2-RELEASE_wasm
build() {  # build NAME [env prefix...]
    name=$1; shift
    rm -rf playground/.build
    "$@" swift build --package-path playground --product GPKitPlayground --swift-sdk $SDK -c release -Xlinker -Map=$PWD/out/$name.map > "out/$name.log" 2>&1 || { tail -20 "out/$name.log"; exit 1; }
    bin=$("$@" swift build --package-path playground --product GPKitPlayground --swift-sdk $SDK -c release -Xlinker -Map=$PWD/out/$name.map --show-bin-path)
    cp "$(find "$bin" -maxdepth 1 -type f \( -name GPKitPlayground.wasm -o -name GPKitPlayground \) | head -1)" "out/$name.wasm"
}
mkdir -p out
build A env
echo "the map from swift5_tests on:"
n=$(/usr/bin/grep -n " swift5_tests$" out/A.map | head -1 | cut -d: -f1); sed -n "$((n-2)),$((n+40))p" out/A.map | cut -c1-260
find . -path ./out -prune -o -exec touch -h -d 2026-01-01T00:00:00Z {} + ; build T1 env
find . -path ./out -prune -o -exec touch -h -d 2026-01-01T00:00:00Z {} + ; build T1b env
find . -path ./out -prune -o -exec touch -h -d 2026-06-01T00:00:00Z {} + ; build T2 env
build S env SOURCE_DATE_EPOCH=0
sha256sum out/*.wasm
for x in T1 T1b T2 S; do echo "== A and $x"; python3 playground/repro/find.py out/A.wasm "out/$x.wasm" playground/.build | head -3; done
echo "== T1 and T1b"; python3 playground/repro/find.py out/T1.wasm out/T1b.wasm playground/.build | head -3
echo "== T1 and T2"; python3 playground/repro/find.py out/T1.wasm out/T2.wasm playground/.build | head -3
