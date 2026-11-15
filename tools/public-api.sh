#!/bin/sh
# Writes docs/public-api.swift and docs/public-api-sources.swift: the public interfaces of GPKit and of GPKitSources as
# the compiler states them, declarations only. Run from the package's root after a change to anything public, and
# commit the result with the change.
#
# tools/public-api.sh --check [BASE] changes nothing and stops on an unannounced change to a public interface:
#   - an interface differs from its file (the file was not written again with the change);
#   - with BASE (a commit, as CI gives the one before a push or a pull request's base): either file changed since
#     BASE and CHANGELOG.md did not;
#   - within a major version: GPKit's interface breaks code written against the latest tag of that major (SwiftPM's
#     API digester); for a new major's first release, a break against the previous major that CHANGELOG.md's
#     "Breaking changes" does not name. GPKitSources is held to it too from the first tag that holds it (1.1.0).
set -eu
check=no
base=
if [ "${1:-}" = "--check" ]; then
    check=yes
    base=${2:-}
fi
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
# interface MODULE SOURCES... : MODULE's interface, written to $out/MODULE.api.swift
interface() {
    module=$1
    shift
    swiftc -module-name "$module" -swift-version 6 -enable-library-evolution -I "$out" -emit-module -emit-module-path "$out/$module.swiftmodule" \
        -emit-module-interface-path "$out/$module.swiftinterface" "$@" 2> "$out/swiftc.log" || { cat "$out/swiftc.log" >&2; exit 1; }
    python3 - "$out/$module.swiftinterface" "$module" > "$out/$module.api.swift" <<'PY'
import re
import sys

module = sys.argv[2]
print(f"// {module}'s public interface, as the compiler states it: tools/public-api.sh writes this file; do not edit it.")
print("// Left out: module prefixes, and what the compiler synthesises for Hashable, CaseIterable and RawRepresentable.")
print(f"// Each declaration's documentation is in Sources/{module}.")
print()
# where Foundation is swift-corelibs-foundation (Linux, Windows), Date is declared in FoundationEssentials
# and URLSession's types in FoundationNetworking
lines = [l.rstrip("\n").replace("FoundationEssentials::", "Foundation::").replace("FoundationNetworking::", "Foundation::") for l in open(sys.argv[1])]
# and where there is Objective-C (Apple's systems) a class of NSObject's is marked @objc and NSObject is
# ObjectiveC's: the same interface, stated the same everywhere. A deinit is no part of what a caller writes.
lines = [l.replace("@objc ", "").replace("ObjectiveC::NSObject", "Foundation::NSObject") for l in lines if l.strip() not in ("deinit", "@objc deinit")]
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
    line = re.sub(r"\b(Swift|GPKitSources|GPKit)::", "", line).replace("@frozen ", "")
    # a read-only property on one line
    if s.endswith("{") and i + 2 < len(lines) and lines[i + 1].strip() == "get" and lines[i + 2].strip() == "}":
        line = line + " get }"
        skip = 2
    out.append(line)
# the interface is stated with the conditions already decided: say which extension is there only with Foundation
for i, line in enumerate(out):
    if line.startswith("extension "):
        end = next(j for j in range(i, len(out)) if out[j] == "}")
        if module == "GPKit" and any("Foundation::" in l for l in out[i:end]):
            print("// only where Foundation can be imported (Sources/GPKit/Date.swift)")
    print(line.replace("Foundation::", "Foundation."))
PY
}
interface GPKit Sources/GPKit/*.swift
interface GPKitSources Sources/GPKitSources/*.swift
if [ $check = no ]; then
    cp "$out/GPKit.api.swift" docs/public-api.swift
    cp "$out/GPKitSources.api.swift" docs/public-api-sources.swift
    echo "docs/public-api.swift: $(command grep -c . docs/public-api.swift) lines; docs/public-api-sources.swift: $(command grep -c . docs/public-api-sources.swift) lines"
    exit 0
fi

for pair in GPKit:docs/public-api.swift GPKitSources:docs/public-api-sources.swift; do
    module=${pair%%:*} file=${pair#*:}
    if ! diff -u "$file" "$out/$module.api.swift"; then
        echo "$module's public interface is not the one $file states: run tools/public-api.sh, commit the file, and say the change in CHANGELOG.md" >&2
        exit 1
    fi
    echo "$file states $module's public interface"
done

# a push that replaced commits (a force push) names as its base a commit this clone may not hold: then the
# comparison is from where the branch left origin/main, said so, and never skipped
if [ -n "$base" ] && ! git cat-file -e "$base^{commit}" 2>/dev/null; then
    fallback=$(git merge-base HEAD origin/main 2>/dev/null) || { echo "$base is not in this clone, and there is no origin/main to compare with" >&2; exit 1; }
    echo "$base is not in this clone (commits replaced by a force push): comparing with $fallback, where the branch left origin/main"
    base=$fallback
fi
if [ -n "$base" ]; then
    changed=$(git diff --name-only "$base" HEAD -- docs/public-api.swift docs/public-api-sources.swift CHANGELOG.md)
    if echo "$changed" | command grep -qE '^docs/public-api(-sources)?\.swift$' && ! echo "$changed" | command grep -qx 'CHANGELOG.md'; then
        echo "a public interface changed since $base and CHANGELOG.md did not: say the change there" >&2
        exit 1
    fi
    echo "since $base: $(echo "$changed" | command grep -qE '^docs/public-api(-sources)?\.swift$' && echo 'an interface changed, and CHANGELOG.md says so' || echo 'the interfaces did not change')"
fi

# A major release stays source-compatible: nothing public is removed or changed in a way that breaks code written
# against an earlier release of the same major version. The major is the one CHANGELOG.md's first release heading
# states (`## 2.0.0 (...)`). Once a tag of that major exists, its latest is the base and nothing may break. Before
# it (the first release of a new major, made once), the base is the previous major's latest tag, and each break the
# digester finds must be named, as `Name`, in that first section's "Breaking changes" list; any other fails.
major=$(sed -n 's/^## \([0-9][0-9]*\)\.[0-9][0-9]*\.[0-9][0-9]*.*/\1/p' CHANGELOG.md | head -1)
if [ -z "$major" ]; then
    echo "CHANGELOG.md has no release heading (## X.Y.Z)" >&2
    exit 1
fi
latest=$(git tag --list "v$major.*" --sort=-v:refname | head -1)
allow=no
if [ -z "$latest" ]; then
    latest=$(git tag --list "v$((major - 1)).*" --sort=-v:refname | head -1)
    allow=yes
fi
if [ -z "$latest" ]; then
    echo "no v$major.x or v$((major - 1)).x tag is in this checkout (CI fetches tags with the history)" >&2
    exit 1
fi
# the first section of CHANGELOG.md, up to the next release heading: where a new major names its breaking changes
section=$(awk 'NR > 1 && /^## [0-9]/ { n++ } n == 1 && /^## [0-9]/ { p = 1 } n == 2 { exit } p' CHANGELOG.md)
breaking=$(printf '%s\n' "$section" | awk '/^### / { p = ($0 ~ /^### Breaking changes/) ; next } p')

# digest PRODUCT LOG: the digester against $latest; with $allow, its breaks pass when the changelog names each
digest() {
    product=$1 log=$2
    if swift package diagnose-api-breaking-changes "$latest" --products "$product" > "$log" 2>&1; then
        echo "$product: no breaking change against $latest"
        return 0
    fi
    if [ $allow = no ]; then
        command grep -vE '^\[|^Building|^Build complete|^Compiling|^Planning|^Fetching|^Computing' "$log" >&2
        echo "$product's public interface breaks code written against $latest: within $major.x that waits for $((major + 1)).0" >&2
        exit 1
    fi
    # each "API breakage: <kind> <name> ..." line of the digester's summary, by name
    names=$(sed -n 's/.*API breakage: [A-Za-z]* \([^ ]*\) .*/\1/p' "$log" | sort -u)
    if [ -z "$names" ]; then
        command grep -vE '^\[|^Building|^Build complete|^Compiling|^Planning|^Fetching|^Computing' "$log" >&2
        echo "$product: the digester failed against $latest and named no break" >&2
        exit 1
    fi
    for name in $names; do
        if ! printf '%s\n' "$breaking" | command grep -qF "\`$name\`"; then
            echo "$product: \`$name\` breaks code written against $latest, and CHANGELOG.md's $major.0.0 \"Breaking changes\" does not name it" >&2
            exit 1
        fi
        echo "$product: \`$name\` breaks code written against $latest, as CHANGELOG.md's $major.0.0 says"
    done
}
digest GPKit "$out/digester.log"
# GPKitSources is held to the promise from its first release, 1.1.0: from the first tag that holds it
if git cat-file -e "$latest:Sources/GPKitSources" 2>/dev/null; then
    digest GPKitSources "$out/digester-sources.log"
else
    echo "GPKitSources: $latest does not hold it, so its changes are allowed and said in CHANGELOG.md"
fi
