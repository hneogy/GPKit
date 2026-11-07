# Changelog

Every change to GPKit's public interface is said here, in the release that makes it. `docs/public-api.swift` states
the interface, and CI stops a change to it that this file does not say (`tools/public-api.sh --check`). Within 1.x
nothing public is removed or changed in a way that breaks code written against an earlier 1.x release.

## Unreleased

Added to the public interface; nothing is removed or changed:

- `Propagator.rotatorTrack(for:from:every:limits:)`, `RotatorLimits` and `RotatorPoint`: where to point an antenna
  rotator through a pass, within its limits, the azimuth carried on past north where the range allows and flipped over
  the zenith where the elevation runs to 180; `RotatorPoint.hamlibCommand` is Hamlib's set-position command. `gpkit
  rotator` prints them for one pass, to pipe to rotctl, or with `--follow` each at its instant; in CI, Hamlib's dummy
  rotator follows a pass that it gives (`tools/check-rotator.sh`).
- `Sun`: the sun's direction, right ascension and declination, its height at a place, and whether it shines on a
  point, after the NOAA calculators' formulas, held in the tests to the US Naval Observatory's and NOAA's figures.
- `Sunlight`, from `Propagator.sunlight(from:at:)`: the sky at a place (daylight, twilight or dark), whether the
  satellite is sunlit, the phase angle, and a brightness estimate from a standard magnitude the caller gives.
- `PassVisibility`, from `Propagator.visibility(of:from:)`: when in a pass the satellite is sunlit, and when it can
  be seen with the eye.
- `EquatorialPosition`: a right ascension and declination.
- `Propagator.earthFixedState(at:)`: the satellite's position and velocity in the Earth-fixed frame.
- `Propagator.equatorial(from:at:)`: its right ascension and declination from a place, for the true equator and
  equinox of the date.
- `Propagator.groundTrack(from:for:every:)` and `GroundTrack`: the point beneath the satellite at each step.
- `GeodeticPosition.footprint(minimumElevation:points:)`: the ring on the ground from which the satellite stands at
  an elevation.
- These are checked against Skyfield 1.55 (`tools/skyfield_frames_reference.py`) and the record in `conformance/`.
- `Propagator.states(of:at:)` and `Propagator.states(of:from:every:count:)`: many satellites at once, in parallel,
  each result the one `state(at:)` gives in the same build, to the bit. On an Apple M5, 10,000 sets at one instant take 0.5 ms and a
  day at one-minute steps 0.37 s, against 1.7 ms and 2.1 s one at a time (`tools/benchmark`, the record in
  `conformance/`).

Also:

- Where the documentation says results agree "to the bit", it now says for what: the same build mode on the same
  system. An optimised build, or another system's maths library, can round a sine or a cosine differently in the last
  bit (a few nanometres where measured). Dated notes say so in three records in `conformance/`.

- `tools/public-api.sh` checks GPKitSources' interface too, against `docs/public-api-sources.swift`, and stops a
  change to it that this file does not say. GPKitSources has had no release, so until its first its interface may
  change, each change said here; from its first release it is held to the same promise as GPKit's.

- GPKitSources, a library apart from GPKit, which still makes no request of its own: CelesTrak's GP queries and
  SatNOGS DB's active transmitters, each asked at most once in two hours, stopped at any answer that is not a 200
  (and the host left alone for two hours after one), never repeated, with a cache of the last good answer and a ledger
  a program keeps between runs. Transmitters tune with GPKit's Doppler, and an inverting transponder's passband is
  mirrored. Tested against recorded answers only: SatNOGS DB's, from one request made for the tests (CC BY-SA 4.0,
  see NOTICE), and CelesTrak's made up from public data. Space-Track is not among the sources. Its interface is
  stated in `docs/public-api-sources.swift`, and `tools/public-api.sh` checks it.

- watchOS 9 and later: GPKit builds for watchOS (arm64 and arm64_32), in CI on every push.
- pygpkit, a Python package in `python/` (`import pygpkit`): reading, TLE writing, SGP4 states, looks, map positions
  and passes, from GPKit compiled behind a small C interface. Its tests hold every number with `==` to what GPKit's
  own release build gives on the same system; CI builds and tests a wheel on Linux, macOS and Windows. Not on PyPI.
- GPKit builds and its tests run on Android, in an emulator, with swift.org's Android SDK for Swift 6.4.2, and for
  WebAssembly (WASI) with swift.org's Wasm SDK. The math of each system's C library is imported. A day's
  microseconds are counted in `Int64`, since they do not fit where `Int` is 32 bits wide, as on wasm32;
  `tools/check-32-bit.sh` compiles the core for a 32-bit `Int` in CI. The three tests that read the documentation's
  files run where the source tree is: macOS, Linux and Windows.
- `gpkit`, a command-line tool: `read`, `tle`, `passes`, `where` and `track`, built for release on Linux, macOS
  and Windows, each build run where Swift is not installed and held to the tutorials' figures (`tools/check-cli.sh`).
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
  provider's TLE lines, character for character, and they propagate to the bit in the same build (`tools/equivalence`, the record in
  `conformance/`, and `EquivalenceTests`).

## 1.0.0 (2026-10-07)

The first release: readers for OMM as CSV, JSON, XML or KVN and for TLE with Alpha-5, catalog numbers as plain
integers (six and nine digits included), a TLE writer, SGP4 ported from Vallado's `SGP4.cpp`, and pass prediction
with Doppler. It does not build for watchOS.
