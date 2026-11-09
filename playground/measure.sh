#!/bin/bash
# The playground module's size under each build setting, and what keeps Swift's Unicode name tables in it.
# Run by CI only (the "playground" job), in the swift container with the Wasm SDK installed; never needed locally.
# Writes measure.txt: one line per setting, raw and brotli bytes, then the profile.
set -u
SDK=swift-6.4.2-RELEASE_wasm
out=$PWD/measure.txt
: > "$out"
say() { echo "$*" | tee -a "$out"; }
size() { printf '%-58s raw %9d  brotli -q 11 %9d\n' "$1" "$(wc -c < "$2")" "$(brotli -q 11 -c "$2" | wc -c)" | tee -a "$out"; }

# build NAME OPT GC STRIP: one build of its own, in a scratch folder of its own; leaves the module at NAME.wasm
build() {
    local name=$1 bin wasm
    GPKIT_PLAYGROUND_OPT=$2 GPKIT_PLAYGROUND_GC=$3 GPKIT_PLAYGROUND_STRIP=$4 \
        swift build --package-path playground --scratch-path "build-$name" --swift-sdk $SDK -c release > "build-$name.log" 2>&1 \
        || { say "$name: the build failed"; tail -20 "build-$name.log"; return 1; }
    bin=$(GPKIT_PLAYGROUND_OPT=$2 GPKIT_PLAYGROUND_GC=$3 GPKIT_PLAYGROUND_STRIP=$4 \
        swift build --package-path playground --scratch-path "build-$name" --swift-sdk $SDK -c release --show-bin-path)
    wasm=$(find "$bin" -maxdepth 1 -type f \( -name 'GPKitPlayground.wasm' -o -name 'GPKitPlayground' \) | head -1)
    cp "$wasm" "$name.wasm"
}
features="--enable-bulk-memory --enable-sign-ext --enable-mutable-globals --enable-nontrapping-float-to-int"

say "== sizes, each setting added to the one before"
build plain O 0 0          && size "-O, no --gc-sections, nothing stripped" plain.wasm
build osize Osize 0 0      && size "-Osize" osize.wasm
build gc Osize 1 0         && size "-Osize, --gc-sections (names kept)" gc.wasm
build page Osize 1 1       && size "-Osize, --gc-sections, --strip-all (the page's build)" page.wasm
wasm-opt -Oz $features page.wasm -o page-oz.wasm \
    && size "  then wasm-opt -Oz" page-oz.wasm
wasm-opt -Oz --strip-debug --strip-producers $features page.wasm -o page-oz-strip.wasm \
    && size "  then wasm-opt -Oz --strip-debug --strip-producers" page-oz-strip.wasm
wasm-opt -Oz --strip-debug --strip-producers --converge $features page.wasm -o page-oz-converge.wasm \
    && size "  then the same, --converge" page-oz-converge.wasm

say ""
say "== what keeps the Unicode name tables (profiled on the build with names kept: gc.wasm)"
# the data segment that holds a scalar name, by its index, as twiggy names segments: data[N]
segment=$(python3 - gc.wasm <<'PY'
import sys
b = open(sys.argv[1], 'rb').read()
def leb(i):
    r = s = 0
    while True:
        x = b[i]; i += 1; r |= (x & 0x7f) << s; s += 7
        if x < 0x80: return r, i
i = 8
while i < len(b):
    kind = b[i]; n, j = leb(i + 1)
    if kind == 11:
        count, k = leb(j)
        for index in range(count):
            flags, k = leb(k)
            if flags == 2: _, k = leb(k)
            if flags in (0, 2):
                k += 1                      # the offset's opcode, i32.const
                _, k = leb(k)               # its value
                k += 1                      # end
            size, k = leb(k)
            if b.find(b'LENTICULA', k, k + size) >= 0:
                print(index, size); break
            k += size
    i = j + n
PY
)
say "the segment holding the names: data[${segment% *}], ${segment#* } bytes (all data: see the sections below)"
wasm-objdump -h gc.wasm | tee -a "$out"
say ""
say "-- functions whose names say Unicode scalar names"
wasm-objdump -x -j name gc.wasm 2>/dev/null | grep -iE 'scalarname|getScalarName|nameAlias|_name_' | head -20 | tee -a "$out"
say ""
say "-- callers of the name functions, from the disassembly, four levels up (a direct call; a call through the table is listed as table)"
wasm-objdump -d gc.wasm > gc.dis 2>/dev/null
python3 - gc.dis <<'PY2' | tee -a "$out"
import re, sys, collections
callers = collections.defaultdict(set); names = {}; current = None
for line in open(sys.argv[1], errors='replace'):
    m = re.match(r'^[0-9a-f]+ func\[(\d+)\] <(.*)>:', line)
    if m: current = int(m.group(1)); names[current] = m.group(2); continue
    m = re.search(r'\bcall (\d+) <', line)
    if m and current is not None: callers[int(m.group(1))].add(current)
targets = [i for i, n in names.items() if n in ('_swift_stdlib_getScalarName', '_swift_stdlib_getNameAlias')]
def up(i, depth, seen):
    for c in sorted(callers.get(i, ())):
        print('  ' * depth + f'<- {names.get(c, c)}')
        if depth < 4 and c not in seen: up(c, depth + 1, seen | {c})
for t in targets:
    print(names[t]); up(t, 1, {t})
    if not callers.get(t): print('  no direct caller')
PY2
[ -x /root/.cargo/bin/twiggy ] && PATH="/root/.cargo/bin:$PATH"
if command -v twiggy > /dev/null; then
    say ""
    say "-- twiggy top 30"
    twiggy top -n 30 gc.wasm | tee -a "$out"
    say ""
    say "-- twiggy paths to the segment"
    twiggy paths gc.wasm "data[${segment% *}]" -d 12 -r 40 | tee -a "$out"
    for f in $(wasm-objdump -x -j name gc.wasm 2>/dev/null | grep -oE '<[^>]*(getScalarName|getNameAlias|nameAlias)[^>]*>' | tr -d '<>' | sort -u | head -3); do
        say ""
        say "-- twiggy paths to $f"
        twiggy paths gc.wasm "$f" -d 14 -r 40 | tee -a "$out"
    done
    say ""
    say "-- twiggy dominators, top"
    twiggy dominators gc.wasm -d 4 -r 40 | tee -a "$out"
else
    say "twiggy is not installed: no profile"
fi
exit 0
