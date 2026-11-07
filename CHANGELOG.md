# Changelog

Every change to GPKit's public interface is said here, in the release that makes it. `docs/public-api.swift` states
the interface, and CI stops a change to it that this file does not say (`tools/public-api.sh --check`). Within 1.x
nothing public is removed or changed in a way that breaks code written against an earlier 1.x release.

## Unreleased

Added to the public interface; nothing is removed or changed:

- `Sun`: the sun's direction, right ascension and declination, its height at a place, and whether it shines on a
  point, after the NOAA calculators' formulas, held in the tests to the US Naval Observatory's and NOAA's figures.
- `Sunlight`, from `Propagator.sunlight(from:at:)`: the sky at a place (daylight, twilight or dark), whether the
  satellite is sunlit, the phase angle, and a brightness estimate from a standard magnitude the caller gives.
- `PassVisibility`, from `Propagator.visibility(of:from:)`: when in a pass the satellite is sunlit, and when it can
  be seen with the eye.
- `EquatorialPosition`: a right ascension and declination.

Also:

- GPKit builds and its tests run on Linux and Windows, in CI on every push: Linux on the official Swift 6.4.2
  image, Windows with swift.org's 6.4.2 installer. On Windows the C runtime's math is imported (`ucrt`).
- The full gpconf run under gpconf 0.8.0 is in `conformance/`, and CI's offline gpconf run uses 0.8.0.
- The comparison with Vallado's `SGP4.cpp` is in `conformance/`, with its command, versions and largest differences.
- A test that the catalog fields `A+123` and `A1_23` are refused.
- The README says what the tests against the C++ hold: agreement within a micrometre.
- CI checks the public interface against `docs/public-api.swift`, this file, and the latest 1.x release.
- CI's macOS job runs Swift 6.4.2, as Linux and Windows do: Xcode 27.2 on GitHub's `xcode-27` image.
- DocC documentation, with three tutorials: your first ISS pass, a pass on a sky chart, and Doppler for your
  radio. Their code is compiled and run in the tests, and CI builds the documentation (`tools/check-docs.sh`).
- Three example projects in `Examples/`: a command-line pass predictor, a Doppler tool for radios, and a Mac sky
  view. CI builds them and holds the command-line ones to the tutorials' figures (`tools/check-examples.sh`).
- A page for each of the 19 kinds of `Refusal.Kind`: what happened, how to fix it, and an example whose message a
  test holds to what GPKit says.
- A concepts guide: element sets and their epoch, TLE and OMM, catalog numbers and Alpha-5, SGP4, and how far
  the results can be trusted, citing the records in `conformance/`.
- OMM and TLE shown to be one element set: over 976 pairs of the provider files held, GPKit writes each OMM as the
  provider's TLE lines, character for character, and they propagate to the bit (`tools/equivalence`, the record in
  `conformance/`, and `EquivalenceTests`).

## 1.0.0 (2026-10-07)

The first release: readers for OMM as CSV, JSON, XML or KVN and for TLE with Alpha-5, catalog numbers as plain
integers (six and nine digits included), a TLE writer, SGP4 ported from Vallado's `SGP4.cpp`, and pass prediction
with Doppler. It does not build for watchOS.
