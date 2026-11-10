#!/bin/sh
# Third diagnostic: what sits at memory 0x111c20 (wasm-ld's map), and whether the environment alone moves it.
#   A here; E here with one more environment variable; M here under a minimal environment; M2 the same again.
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
build E env GPKIT_REPRO_PADDING=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
build M env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root
build M2 env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root
sha256sum out/*.wasm
echo "the map around 0x111c20:"
awk 'NR==1{print} /^ *[0-9a-f]+ / { a=strtonum("0x"$1); if (a >= 0x111a00 && a <= 0x111e00) print }' out/A.map | head -40
/usr/bin/grep -n -i "111c" out/A.map | head -20
for x in E M M2; do echo "== A and $x"; python3 playground/repro/find.py out/A.wasm "out/$x.wasm" playground/.build | head -3; done
echo "== M and M2"; python3 playground/repro/find.py out/M.wasm out/M2.wasm playground/.build | head -3
