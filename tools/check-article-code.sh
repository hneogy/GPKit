#!/bin/sh
# The catalogue-scale article's code is the code its test compiles and runs: the Swift block of
# Sources/GPKit/GPKit.docc/Articles/CatalogueScale.md, and the function in Tests/GPKitTests/CatalogueScaleTests.swift
# after "// as the article prints it", less its indent, must be the same text. Exit 1, with the difference, if not.
set -eu
article=Sources/GPKit/GPKit.docc/Articles/CatalogueScale.md
test=Tests/GPKitTests/CatalogueScaleTests.swift
a=$(mktemp); t=$(mktemp)
trap 'rm -f "$a" "$t"' EXIT
sed -n '/^```swift/,/^```/p' "$article" | sed '1d;$d' > "$a"
sed -n '/    \/\/ as the article prints it/,/^    }$/p' "$test" | sed '1d' | sed 's/^    //' > "$t"
if [ ! -s "$a" ] || [ ! -s "$t" ]; then echo "the article's code or the test's was not found"; exit 1; fi
if ! diff "$a" "$t"; then echo "the article's code is not the code its test runs"; exit 1; fi
echo "the article's code is the code its test runs ($(wc -l < "$a" | tr -d ' ') lines)"
