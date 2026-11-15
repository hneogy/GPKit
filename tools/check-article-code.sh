#!/bin/sh
# Each article's code is the code its test compiles and runs: the Swift block of the article, and the function in the
# test after "// as the article prints it", less its indent, must be the same text. Exit 1, with the difference, if
# not. The pairs: the catalogue-scale article and CatalogueScaleTests, the migration article and MigrationTests.
set -eu
a=$(mktemp); t=$(mktemp)
trap 'rm -f "$a" "$t"' EXIT
for pair in CatalogueScale:CatalogueScaleTests Migrating:MigrationTests; do
    article=Sources/GPKit/GPKit.docc/Articles/${pair%%:*}.md
    test=Tests/GPKitTests/${pair#*:}.swift
    sed -n '/^```swift/,/^```/p' "$article" | sed '1d;$d' > "$a"
    sed -n '/    \/\/ as the article prints it/,/^    }$/p' "$test" | sed '1d' | sed 's/^    //' > "$t"
    if [ ! -s "$a" ] || [ ! -s "$t" ]; then echo "$article: the article's code or the test's was not found"; exit 1; fi
    if ! diff "$a" "$t"; then echo "$article: the article's code is not the code its test runs"; exit 1; fi
    echo "$article: its code is the code its test runs ($(wc -l < "$a" | tr -d ' ') lines)"
done
