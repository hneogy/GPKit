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
swift run -c release --package-path tools/bit-record gpkit-bit-record > conformance/bit-records/$(swift run -c release --package-path tools/bit-record gpkit-bit-record --platform).txt
```

When the check fails:
1. Read what moved: the count and the largest difference, in units in the last place and in km or km/s.
2. Say it in the changelog: which platform, which toolchain or system, how many numbers, how far.
3. Record the platform again with the second command, and commit the record with the changelog line.

A record is only made from a release build (`-c release`); the tool refuses to run from a debug build, which can
differ from a release build in the last place.
