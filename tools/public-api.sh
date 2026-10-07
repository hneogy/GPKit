#!/bin/sh
# Writes docs/public-api.swift: GPKit's public interface as the compiler states it, declarations only.
# Run from the package's root after a change to anything public, and commit the result with the change.
set -eu
out=$(mktemp -d)
swiftc -module-name GPKit -swift-version 6 -enable-library-evolution -emit-module -emit-module-path "$out/GPKit.swiftmodule" \
    -emit-module-interface-path "$out/GPKit.swiftinterface" Sources/GPKit/*.swift
python3 - "$out/GPKit.swiftinterface" > docs/public-api.swift <<'PY'
import re
import sys

print("// GPKit's public interface, as the compiler states it: tools/public-api.sh writes this file; do not edit it.")
print("// Left out: module prefixes, and what the compiler synthesises for Hashable, CaseIterable and RawRepresentable.")
print("// Each declaration's documentation is in Sources/GPKit.")
print()
lines = [l.rstrip("\n") for l in open(sys.argv[1])]
skip = 0
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
    print(line)
PY
rm -rf "$out"
echo "docs/public-api.swift: $(grep -c . docs/public-api.swift) lines"
