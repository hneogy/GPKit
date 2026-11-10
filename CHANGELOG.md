# Changelog

Every change to GPKit's public interface is said here, in the release that makes it. `docs/public-api.swift` states
the interface, and CI stops a change to it that this file does not say (`tools/public-api.sh --check`). Within 1.x
nothing public is removed or changed in a way that breaks code written against an earlier 1.x release.

## Unreleased (to go out with the next release, not on its own: the owner's ruling of 2026-11-10)

Nothing in the public interface is added, removed or changed; `docs/public-api.swift` is as in 1.3.0.

- `Propagator.EpochReading.vallado`'s documentation said set 23333 agrees with `tcppver.out` "to 7e-9 km". It now
  says what `ValladoEpochTests` measures and names the test: at most 4.9e-9 km and 4.9e-10 km/s over its 15 rows,
  against 4.1e-6 km at the exact epoch. The changelog's 1.3.0 entry already said 4.9e-9 km.
- The README's installation line asks for `from: "1.3.0"`, where 1.3.0 left it at "1.2.0".

Added to GPKitSources' public interface; nothing is removed or changed (`docs/public-api-sources.swift`):

- `ElementSetStore`, the element sets a program holds, by catalog number: the newest of each object and up to `keep`
  sets of it (4 by default), newest first. `merge` takes a file or sets and reports what it did with each: added,
  replaced, unchanged, older (kept in the history while it has room), conflicting (another set at a held epoch; the
  held one is kept), uncatalogued (not held) and refused. `current`, `history`, `catalogNumbers` and `stale(at:olderThan:)`
  read it. `save()` writes every set as an OMM in CelesTrak's JSON form, each number in its own digits, and
  `init(saved:keep:)` reads it back to the same values.
- `FolderSource`, element sets from files already held, with no request: a file's format is its extension's (`.csv`,
  `.json`, `.xml`, `.kvn`, `.tle`, `.txt`); hidden files and other extensions are skipped and named, and a file GPKit
  refuses whole is named with the reason. `load(into:)` merges the folder into a store.
- `Ledger.nextAsk(_:at:)`, when the rules next let an address be asked: nil when it may be asked now, else the end of
  the latest quiet time that holds it, the address's own or its host's.

All of it is tested against recorded fixtures only (`Tests/GPKitSourcesTests/Resources/fixtures`, made up from the
Space Station's 1998 set); no test makes a request, and seven planted faults each fail the tests.

## 1.3.0 (2026-11-10)

Added to the public interface; nothing is removed or changed:

- `Propagator.EpochReading` and `Propagator.init(_:gravity:epochReading:)`: `.exact`, the default and what
  `init(_:gravity:)` keeps doing, or `.vallado`, the epoch as David Vallado's C++ reader makes it from a TLE (its day
  read as a `Double`, his `days2mdhms` and `jday`, the Julian date and fraction summed less 2,433,281.5), up to about
  20 microseconds from the exact epoch. It is for matching his `tcppver.out` to its last digits: on all 33 sets of
  `SGP4-VER.TLE` the epoch is his reader's to the bit, and set 23333 (eccentricity 0.97), 4.1e-6 km from it at the
  exact epoch, comes within 4.9e-9 km and 4.9e-10 km/s, inside gpconf's 2e-7 bar for its `sgp4-ver-positions` case.
  A set not from a TLE is first rounded as a TLE writes its epoch.

Outside the public interface:

- The gpconf adapter declares its propagate op's constants in gpconf's constants declaration, `{"gravity": "wgs72",
  "opsmode": "i", "epoch": "exact"}` beside the refusals declaration, and takes `--epoch vallado` before a command to
  propagate from `.vallado` and declare `"epoch": "vallado"`, for a run recorded beside the default one. The default
  stays the exact epoch, and GPKit's recorded result is made from it. `tools/check_adapter_epoch.py` checks both
  readings (set 23333 inside gpconf's bar with `--epoch vallado` and outside it by default), and CI runs it.

## 1.2.1 (2026-11-10)

Nothing in the public interface is added, removed or changed; `docs/public-api.swift` is as in 1.2.0.

- The gpconf adapter (`gpkit-gpconf vectors`) answers gpconf's `propagate` op: each step's position and velocity, or
  Vallado's error code where SGP4 stops; a set GPKit will not propagate, one for SGP4-XP among them (refused as
  `.notSGP4` in 1.x), is an error for the call. It reads a set with its checksums unchecked, as Vallado's reader does,
  since gpconf holds his verification sets valid input for propagation; `parse` still verifies them.

## 1.2.0 (2026-11-10)

Nothing in the public interface is added, removed or changed; `docs/public-api.swift` is as in 1.1.0.

- The playground's module: GPKit built for WebAssembly as a WASI reactor (`playground/`), for a page that reads a TLE
  or an OMM and works out the look, the point beneath and the next day's passes in the browser, with no request but
  its own files. It is built from GPKit's own sources without `Date.swift`, so no Foundation is linked in, with
  `--strip-all` and then `wasm-opt -Oz --converge`; CI holds it to 1.1 MiB as sent (brotli -q 11) and fails above it.
- Its answers are held to GPKit's native build: under Node's WASI, CI makes 145 calls of the module over the pass-check
  sets, the ISS as OMM and two refused texts, at four places, and each answer matches the native one to within 1e-9:
  its shape, strings, times and integers the same, every other number within 1e-9 (WebAssembly's maths library is not
  the platform's, so sines and arctangents part in the last bits, at most 7.3e-12 measured). A planted difference
  must stop the comparison, in every run.
- A published release attaches the module built from its tag, `gpkit-playground.wasm`, with its SHA-256 and the
  checks' output (`release.yml`, through `playground-module.yml`, which CI also runs on every push).
- An epoch's second 60 is read only at 23:59:60 UTC on the 27 days that ended in a leap second (IERS's
  Leap_Second.dat, the last 2016-12-31; the list is closed, UTC running without leap seconds from 20 May 2027 by CGPM
  2026 Resolution 5). 1.1.0 read a second 60 at 23:59 on any day; such an epoch is now refused as `.notAnEpoch`, with
  the reason. gpconf's `ccsds-epoch-strings` vectors pass with it.

## 1.1.0 (2026-11-09)

Added to the public interface; nothing is removed or changed:

- `CloseApproach.screen(_:from:for:step:within:)`: a rough screen on GP data with SGP4 for candidate close approaches,
  each with its time, miss distance and relative speed; no probability of collision. Not for operational collision
  avoidance, and no approach found does not mean safe, as its documentation, `gpkit approaches` and the README say.
  Tested against closest approaches computed independently: by formula, and by brute force over the same positions.
- `OEM.write(_:from:every:count:originator:created:)`: an ephemeris as a CCSDS Orbit Ephemeris Message (OEM 2.0, KVN),
  SGP4's states in TEME and UTC, positions to the millimetre and velocities to the nanometre a second. `gpkit oem`
  writes one; in CI the `oem` package for Python reads it back, each number as written, and refuses broken copies
  (`tools/check_oem.py`).
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
  change to it that this file does not say. This is GPKitSources' first release: from here on it is held to the same
  promise as GPKit's, and the check holds it to the latest 1.x tag as it does GPKit.

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
