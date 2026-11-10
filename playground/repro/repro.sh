#!/bin/sh
# Second diagnostic: what the 432-byte segment at memory 0x111c20 depends on, and which file holds it.
#   A this checkout; F the same, with one file added to playground/ that no target uses; G a copy of this checkout
#   (.git and all) in another folder; H a copy at a path of the same length as this one.
set -eu
SDK=swift-6.4.2-RELEASE_wasm
build() {
    dir=$1; name=$2
    rm -rf "$dir/playground/.build"
    swift build --package-path "$dir/playground" --product GPKitPlayground --swift-sdk $SDK -c release -v > "out/$name.log" 2>&1
    bin=$(swift build --package-path "$dir/playground" --product GPKitPlayground --swift-sdk $SDK -c release --show-bin-path)
    cp "$(find "$bin" -maxdepth 1 -type f \( -name GPKitPlayground.wasm -o -name GPKitPlayground \) | head -1)" "out/$name.wasm"
}
mkdir -p out
build . A
echo "the link line:"; /usr/bin/grep -E "wasm-ld|clang.*-o .*GPKitPlayground" out/A.log | tail -2 | cut -c1-3000
echo "where the segment's bytes are, under the build, the SDK and the toolchain:"
python3 playground/repro/where.py out/A.wasm 1121312 432 "$PWD/playground/.build" "$HOME/.swiftpm" /root/.swiftpm /usr/lib/swift /usr/lib/swift_static /usr/bin
cp -a . /tmp/elsewhere-longer-path
build /tmp/elsewhere-longer-path G
here=$PWD; same=$(echo "$here" | sed 's/./x/g' | sed 's|^x|/|'); mkdir -p "$(dirname "$same")"; cp -a . "$same"
echo "H at $same (length ${#same}, here ${#here})"
build "$same" H
echo "unused" > playground/unused.txt
build . F
rm playground/unused.txt
sha256sum out/*.wasm
for x in F G H; do echo "== A and $x"; python3 playground/repro/find.py out/A.wasm "out/$x.wasm" playground/.build | head -4; done
echo "the segment in each:"
for x in A F G H; do python3 -c "import sys;d=open('out/$x.wasm','rb').read();i=d.find(bytes.fromhex(sys.argv[1]));print('$x', d[i-0:i+48].hex() if i>=0 else 'prefix not found')" 41a0b8c4000bb003; done
