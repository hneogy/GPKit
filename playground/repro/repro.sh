#!/bin/sh
# Builds the playground's module four times, as CI's playground job does, and compares them:
#   A this commit; B this commit again from a clean .build; C this commit from another folder; D 708efe5's sources.
# Before wasm-opt and after it. Run in CI (playground-repro.yml); prints where any two part.
set -eu
SDK=swift-6.4.2-RELEASE_wasm
build() {  # build DIR NAME [extra swift build arguments]
    dir=$1; name=$2; shift 2
    rm -rf "$dir/playground/.build"
    swift build --package-path "$dir/playground" --product GPKitPlayground --swift-sdk $SDK -c release "$@" > /dev/null
    bin=$(swift build --package-path "$dir/playground" --product GPKitPlayground --swift-sdk $SDK -c release "$@" --show-bin-path)
    cp "$(find "$bin" -maxdepth 1 -type f \( -name GPKitPlayground.wasm -o -name GPKitPlayground \) | head -1)" "out/$name.wasm"
    wasm-opt -Oz --converge --enable-bulk-memory --enable-sign-ext --enable-mutable-globals --enable-nontrapping-float-to-int "out/$name.wasm" -o "out/$name.opt.wasm"
    rm -rf "out/$name.build"; cp -R "$dir/playground/.build" "out/$name.build"
}
mkdir -p out
build . A
build . B
rm -rf /tmp/elsewhere && mkdir -p /tmp/elsewhere && git archive HEAD | tar -x -C /tmp/elsewhere
build /tmp/elsewhere C
rm -rf /tmp/old && mkdir -p /tmp/old && git archive 708efe5 | tar -x -C /tmp/old
build /tmp/old D
sha256sum out/*.wasm
for pair in "A B" "A C" "A D"; do
    set -- $pair
    for kind in wasm opt.wasm; do
        echo "== $1 and $2, $kind"
        python3 playground/repro/find.py "out/$1.$kind" "out/$2.$kind" "out/$1.build"
    done
done
