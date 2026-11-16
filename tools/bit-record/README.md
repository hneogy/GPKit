# The bit record

What GPKit's release build gives from `Propagator.state`, held at the bit on one platform. It is not a promise that
every platform gives the same bits: GPKit makes none (the 2.0.0 changelog, "Known platform difference"). It makes a
change that moves the last place, from a compiler, a toolchain or a system library such as the one that supplies
`__sincos_stret` on Apple's systems, visible in CI the day it happens.

- **The sets:** 39, made from a rule in `Sources/gpkit-bit-record/main.swift`: three angle choices in each of
  thirteen regimes. No provider's data and none of Vallado's verification sets.
- **The times:** a day before the epoch, then every 720.5 minutes to ten days after: 22.
- **The record:** `conformance/bit-records/PLATFORM.txt`, one line per set and time, the six numbers as the hex of
  their bit patterns, or `fail KIND` where SGP4 stops.

```sh
sh tools/bit-record/check.sh                                     # this platform against its record; 1 if any moved
sh tools/bit-record/check.sh --build-system native               # the same on Windows, as CI builds there
swift run -c release --package-path tools/bit-record gpkit-bit-record > conformance/bit-records/$(swift run -c release --package-path tools/bit-record gpkit-bit-record --platform).txt
```

`check.sh` also checks the tool before it trusts a record:
- **The ULP arithmetic** (`--self-test`): fixed pairs of doubles, both ways round.
- **The counts:** the 39 sets and 22 times above are the ones the tool makes.
- **A planted change:** the record with one hex digit of one number changed must fail the check, reported as one
  number moved.
- **The same run:** the record made twice in one run must be the same, but for its `# made` line.
Then it compares this build with every other platform's record (`--compare`), for information only: the platforms
are not promised to agree, and the comparison never fails a run.

A record's `#` lines aren't compared, except `# platform`. `# swift` and `# made` say which toolchain made it and when,
so a toolchain update that leaves the bits alone doesn't fail, and one that moves them says what made the old ones.
Records are read with any line ending, and `.gitattributes` keeps git from converting them.

**A platform with no record** (the first run in CI): the step fails, and the record it made is left as
`tools/bit-record/.build/bit-record-new-PLATFORM.txt`, which CI uploads as an artifact named
`bit-record-PLATFORM`. Read it, look at how it compares with the other platforms, and commit it as
`conformance/bit-records/PLATFORM.txt`. A large difference from another platform is a finding to report, not a reason
to hold the record back.

When the check fails:
1. Read what moved: the count and the largest difference, in units in the last place and in km or km/s.
2. Say it in the changelog: which platform, which toolchain or system, how many numbers, how far.
3. Record the platform again with the second command, and commit the record with the changelog line.

A record is only made from a release build (`-c release`); the tool refuses to run from a debug build, which can
differ from a release build in the last place.
