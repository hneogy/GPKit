#!/bin/sh
# Writes docs/public-api.swift: GPKit's public interface as the compiler states it, declarations only.
# Run from the package's root after a change to anything public, and commit the result with the change.
#
# tools/public-api.sh --check [BASE] changes nothing and stops on an unannounced change to the public interface:
#   - the interface differs from docs/public-api.swift (the file was not written again with the change);
#   - with BASE (a commit, as CI gives the one before a push or a pull request's base): docs/public-api.swift
#     changed since BASE and CHANGELOG.md did not;
#   - within 1.x: the interface breaks code written against the latest 1.x tag (SwiftPM's API digester).
set -eu
check=no
base=
if [ "${1:-}" = "--check" ]; then
    check=yes
    base=${2:-}
fi
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
swiftc -module-name GPKit -swift-version 6 -enable-library-evolution -emit-module -emit-module-path "$out/GPKit.swiftmodule" \
    -emit-module-interface-path "$out/GPKit.swiftinterface" Sources/GPKit/*.swift 2> "$out/swiftc.log" || { cat "$out/swiftc.log" >&2; exit 1; }
python3 - "$out/GPKit.swiftinterface" > "$out/public-api.swift" <<'PY'
import re
import sys

print("// GPKit's public interface, as the compiler states it: tools/public-api.sh writes this file; do not edit it.")
print("// Left out: module prefixes, and what the compiler synthesises for Hashable, CaseIterable and RawRepresentable.")
print("// Each declaration's documentation is in Sources/GPKit.")
print()
# where Foundation is swift-corelibs-foundation (Linux, Windows), Date is declared in FoundationEssentials
lines = [l.rstrip("\n").replace("FoundationEssentials::", "Foundation::") for l in open(sys.argv[1])]
skip = 0
out = []
for i, line in enumerate(lines):
    if skip:
        skip -= 1
        continue
    s = line.strip()
    if s.startswith(("// swift-", "import ", "#if ", "#endif", "#else", "public typealias AllCases", "public typealias RawValue",
                     "public static func == (", "public func hash(into", "public init?(rawValue:")) or (s.startswith("extension ") and s.endswith("{}")):
        continue
    if s.startswith(("public var hashValue", "nonisolated public static var allCases", "public var rawValue")):
        skip = 2  # the accessor block that follows
        continue
    line = re.sub(r"\b(Swift|GPKit)::", "", line).replace("@frozen ", "")
    # a read-only property on one line
    if s.endswith("{") and i + 2 < len(lines) and lines[i + 1].strip() == "get" and lines[i + 2].strip() == "}":
        line = line + " get }"
        skip = 2
    out.append(line)
# the interface is stated with the conditions already decided: say which extension is there only with Foundation
for i, line in enumerate(out):
    if line.startswith("extension "):
        end = next(j for j in range(i, len(out)) if out[j] == "}")
        if any("Foundation::" in l for l in out[i:end]):
            print("// only where Foundation can be imported (Sources/GPKit/Date.swift)")
    print(line.replace("Foundation::", "Foundation."))
PY
if [ $check = no ]; then
    cp "$out/public-api.swift" docs/public-api.swift
    echo "docs/public-api.swift: $(grep -c . docs/public-api.swift) lines"
    exit 0
fi

if ! diff -u docs/public-api.swift "$out/public-api.swift"; then
    echo "the public interface is not the one docs/public-api.swift states: run tools/public-api.sh, commit the file, and say the change in CHANGELOG.md" >&2
    exit 1
fi
echo "docs/public-api.swift states the public interface"

if [ -n "$base" ]; then
    changed=$(git diff --name-only "$base" HEAD -- docs/public-api.swift CHANGELOG.md)
    if echo "$changed" | grep -qx 'docs/public-api.swift' && ! echo "$changed" | grep -qx 'CHANGELOG.md'; then
        echo "the public interface changed since $base and CHANGELOG.md did not: say the change there" >&2
        exit 1
    fi
    echo "since $base: $(echo "$changed" | grep -qx 'docs/public-api.swift' && echo 'the interface changed, and CHANGELOG.md says so' || echo 'the interface did not change')"
fi

# 1.x stays source-compatible: nothing public is removed or changed in a way that breaks code written against 1.x
latest=$(git tag --list 'v1.*' --sort=-v:refname | head -1)
if [ -z "$latest" ]; then
    echo "no v1.x tag is in this checkout (CI fetches tags with the history)" >&2
    exit 1
fi
swift package diagnose-api-breaking-changes "$latest" --products GPKit > "$out/digester.log" 2>&1 || {
    grep -vE '^\[|^Building|^Build complete|^Compiling|^Planning|^Fetching|^Computing' "$out/digester.log" >&2
    echo "the public interface breaks code written against $latest: within 1.x that waits for 2.0" >&2
    exit 1
}
echo "no breaking change against $latest"
