#!/bin/sh
# Fifth diagnostic, the owner's one cheap try (2026-11-10): do -file-compilation-dir or the prefix-map flags make two
# folders' builds byte-identical? Each variant is built here and in a copy at another path; then the variant with every
# flag is built again here after an empty commit and after a commit that changes a file no target compiles.
set -eu
SDK=swift-6.4.2-RELEASE_wasm
build() {  # build DIR NAME FLAGS...
    dir=$1; name=$2; shift 2
    rm -rf "$dir/playground/.build"
    swift build --package-path "$dir/playground" --product GPKitPlayground --swift-sdk $SDK -c release "$@" > "out/$name.log" 2>&1 || { tail -20 "out/$name.log"; return 1; }
    bin=$(swift build --package-path "$dir/playground" --product GPKitPlayground --swift-sdk $SDK -c release "$@" --show-bin-path)
    cp "$(find "$bin" -maxdepth 1 -type f \( -name GPKitPlayground.wasm -o -name GPKitPlayground \) | head -1)" "out/$name.wasm"
}
flags() {  # flags VARIANT DIR: the swift build arguments for a variant, with DIR mapped to /src
    case $1 in
        none) ;;
        fcd) echo "-Xswiftc -file-compilation-dir -Xswiftc /src" ;;
        dpm) echo "-Xswiftc -debug-prefix-map -Xswiftc $2=/src -Xcc -fdebug-prefix-map=$2=/src" ;;
        fpm) echo "-Xswiftc -file-prefix-map -Xswiftc $2=/src -Xcc -ffile-prefix-map=$2=/src" ;;
        all) echo "-Xswiftc -file-compilation-dir -Xswiftc /src -Xswiftc -debug-prefix-map -Xswiftc $2=/src -Xswiftc -file-prefix-map -Xswiftc $2=/src -Xcc -ffile-prefix-map=$2=/src" ;;
    esac
}
mkdir -p out
here=$PWD; there=/tmp/elsewhere-longer-path
rm -rf "$there"; cp -a . "$there"
for v in none fcd dpm fpm all; do
    build "$here" "$v-here" $(flags $v "$here") || echo "$v: the build failed here"
    build "$there" "$v-there" $(flags $v "$there") || echo "$v: the build failed there"
    if [ -f "out/$v-here.wasm" ] && [ -f "out/$v-there.wasm" ]; then
        if cmp -s "out/$v-here.wasm" "out/$v-there.wasm"; then echo "RESULT $v: two folders byte-identical"
        else echo "RESULT $v: two folders differ"; python3 playground/repro/find.py "out/$v-here.wasm" "out/$v-there.wasm" playground/.build | sed -n '1,3p'; fi
    fi
done
git config user.email repro@localhost; git config user.name repro
git commit -q --allow-empty -m "empty"
build "$here" all-empty-commit $(flags all "$here")
echo x > playground/repro/unused.txt; git add playground/repro/unused.txt; git commit -q -m "a file no target compiles"
build "$here" all-file-commit $(flags all "$here")
for x in all-empty-commit all-file-commit; do
    if cmp -s out/all-here.wasm "out/$x.wasm"; then echo "RESULT $x: byte-identical to all-here"; else echo "RESULT $x: differs from all-here"; fi
done
sha256sum out/*.wasm
