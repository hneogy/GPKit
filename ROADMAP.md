# GPKit 2.0: roadmap

A draft for the owner's review (2026-11-05), brought up to date on 2026-11-10 (GPKit 1.4.0); the owner's rulings of 2026-11-05 are in. The milestones and items are the owner's list of
2026-11-01; nothing is promised beyond it. Each item gives what it is, what it depends on, and what proves it done.
Status: **done** (merged), **in progress** (a branch or pull request exists), or blank (not started).

GPKit 1.x stays source-compatible throughout: 2.0's additions arrive as new API, and anything that would break 1.x
code waits for 2.0 itself and is named in the changelog.

## 2.0-a Foundations

| Item | Status | What it is | Depends on | Done when |
|---|---|---|---|---|
| Linux and Windows CI | done (#2, 2026-11-05) | build and test on `ubuntu-latest` and `windows-latest` with a pinned official Swift toolchain | nothing | every job green on `main`, the toolchain pinned to one release |
| The gpconf 0.8.0 result | done (#1, 2026-11-05) | the full run, published with its steps | nothing | `conformance/gpconf-0.8.0-2026-11-05.txt` on `main`: commands, versions, per-case verdicts |
| Vallado agreement, with steps | done (#4, 2026-11-06) | the comparison with Vallado's `SGP4.cpp` published as a result anyone can repeat | nothing (the tests exist) | a record in `conformance/` with the command, the versions and the largest differences |
| README fixes | done (#1, 2026-11-05) | the README says what the tests prove (within a micrometre of the C++) and the actual gpconf result | nothing | merged |
| A stable-API promise and a changelog | done (#3, 2026-11-06) | 1.x stays compatible; `CHANGELOG.md` from 1.0.0 | nothing | the promise in the README, and `tools/public-api.sh` failing CI on an unannounced change to the public API |
| Pin the macOS CI job to Swift 6.4.2 | done (#11, 2026-11-07: the xcode-27 preview image, Xcode 27.2; the job stops if Swift is not 6.4.2) | the `macos-26` job builds with the runner's Xcode, Swift 6.3.3 (main's run 41944427512), while Linux and Windows are pinned to 6.4.2; choose an Xcode with Swift 6.4.2 if the runner offers one (the owner's addition, 2026-11-06) | the runner's installed Xcode versions | `swift --version` in the macOS job says 6.4.2, or the record says the runner offers none |
| Move macOS CI off the preview image | | #11's job runs on GitHub's `xcode-27` image, a public preview; move it to a general-release image once one offers Swift 6.4.2 (the owner's addition, 2026-11-07) | a general-release macOS image with Swift 6.4.2 | the macOS job on a general-release image, still stopping unless Swift is 6.4.2 |
| CI and gpconf badges | | a CI badge, and a gpconf badge that links to the run itself (gpconf's D-378 rule) | gpconf's badge (gpconf 0.9.0-c) | both in the README, each linking to its run |

## 2.0-b Newcomers

| Item | Status | What it is | Depends on | Done when |
|---|---|---|---|---|
| DocC tutorials | done (#5, with #6 for Windows, 2026-11-06) | "Your first ISS pass in 10 lines", "Draw a pass on a sky chart", "Doppler for your radio" | the stable API | each builds in DocC and its code is compiled in a test |
| Example projects | done (#7, 2026-11-06) | a command-line pass predictor, a small SwiftUI sky view, a ham Doppler tool | the tutorials' code | each builds in CI |
| A page for each refusal kind | done (#8, 2026-11-06) | all 19 kinds of `Refusal.Kind`: what happened, how to fix it | nothing | 19 pages, and a test that fails when a kind has no page |
| A concepts guide | done (#9, 2026-11-06) | TLE vs OMM, Alpha-5, what SGP4 is, how accurate it is, from GP Passes' lessons and glossary, whose texts the owner allows into GPKit's MIT documentation (2026-11-05) | GP Passes' 1.0.1 fix F2 (the glossary's Alpha-5 entry) first; no text is copied before it | the guide in DocC; its accuracy figures cite the records in `conformance/` |
| WebAssembly playground | held until the GPKit site has launched (the owner, 2026-11-06); GPKit itself builds and its tests run for WebAssembly (#18, 2026-11-07) | on gpkit.gppasses.com: paste a TLE, see your next passes, computed by GPKit itself | GPKit building for WebAssembly (Swift's Wasm SDK); the site | the playground's passes match GPKit's on the same input, in a test |
| One icon family | GP Passes' icon drafted from it (its PR #38, 2026-11-01); GPKit's own not started | one indigo ring-and-dot mark (#4a50d8 on white, #9099ff in the dark, white on black tinted) for GPKit, its site and GP Passes | nothing | the mark in GPKit's DocC, README and site, and GP Passes' icon from the same drawing |

## 2.0-c Core science

| Item | Status | What it is | Depends on | Done when |
|---|---|---|---|---|
| Match Vallado's `tcppver.out` | partly done: 1.3.0's opt-in `Propagator.EpochReading.vallado` gives every one of the 33 verification epochs Vallado's reader's to the bit, and set 23333 within 4.9e-9 km (the exact epoch, still the default, is 4.1e-6 km out); gpconf 0.9.0's case still to run on a release | the published verification output, line for line within its printed digits | gpconf 0.9.0's propagation tier (Vallado's reference output) | the 0.9.0 propagation cases pass |
| Every gpconf case, 0.9.0's propagation tier included | | all cases of gpconf 0.9.0 | gpconf 0.9.0 | the full run recorded in `conformance/` |
| Native OMM | partly done: the GPKit side (#12, 2026-11-07: 976 OMM/TLE pairs written alike and propagated to the bit); gpconf 0.9.0's cases still to pass | proof that a set's OMM and its TLE propagate alike, and reading any OMM encoding (KVN, XML, JSON) GPKit does not read yet; today it reads all three and CSV, with no gap known (the owner's ruling, 2026-11-05) | gpconf 0.9.0's TLE/OMM equivalence cases | those cases pass, and every OMM encoding gpconf grades is read |
| Ephemeris-type-4 sets refused clearly | in progress: branch `v2-type4-refusal`, `PropagationFailure.Kind.sgp4XP`, the one change of 2.0 that breaks 1.x code (`docs/design/release-2.0-plan.md`, branch `v2-plans`) | `Propagator` already refuses type 4 (SGP4-XP) in 1.0 (`Propagator.swift:95`) | gpconf 0.9.0's type-4 refusal case | that case passes |
| Data age with an error estimate | in progress: branch `v2-data-age` (ESA's orbit classes, Issue 10.0, Table 1.2); its API shape is option B of `docs/design/data-age-api-2.0.md` (branch `v2-plans`), as listed in the owner's 2.0 scope of 2026-11-10; the table waits for gpconf 0.9.0's re-measure fetch, with MEO and GEO sets (the owner's ruling, 2026-11-07); the sets held give 214 LEO satellites at two epochs, 16 a week apart; a private low-orbit pilot may test the tool, and no number from it is published | how old an element set is at a given time, and the position error to expect at that age, **measured, not quoted**: older element sets propagated forward and compared with newer sets for the same satellite, the errors published as percentiles by orbit regime (the owner's ruling, 2026-11-05) | element sets already held, with more than one set per satellite; **no request to CelesTrak or Space-Track** is made for it | the measurement's method, data and script in `conformance/`, repeatable; the percentiles by regime published; GPKit's estimate reads from them |
| Sun and visibility model | done in GPKit (#13, #14, 2026-11-07: GP Passes' USNO and NOAA figures held, a brightness estimate by Mallama 2021); GP Passes moves to GPKit's model once a GPKit release has it | sunlit, observer in darkness, a brightness estimate, moved from GP Passes into GPKit | the app's `Sun.swift` and its tests (the sun's figures read from USNO and NOAA) | GPKit's tests hold the same reference figures; the app uses GPKit's |
| Coordinate frames and maps | done (#15, 2026-11-07: Earth-fixed state and RA/Dec against Skyfield 1.55, ground track, footprint; record in `conformance/`) | TEME → Earth-fixed → latitude and longitude, ground tracks, coverage footprints, RA/Dec | nothing | each conversion checked against a named reference |

## 2.0-d Reach

| Item | Status | What it is | Depends on | Done when |
|---|---|---|---|---|
| A `gpkit` command-line tool | done but for the release (#16, 2026-11-07: release builds for Linux, macOS and Windows run without Swift in CI; `release.yml` attaches them to the next published release); a signed and notarized macOS build is prepared as `tools/sign-macos.sh` (local branch `macos-signing`, 30b1878, not pushed), which signs with the Developer ID and notarizes through a notarytool keychain profile | passes and conversions from the terminal, downloads for Windows, Linux and macOS | Linux and Windows CI | release builds attached to a GitHub release, each run in CI |
| A data sources module | done (#21, 2026-11-07: GPKitSources; CelesTrak from held captures only, Space-Track left out on the owner's ruling) | CelesTrak; Space-Track with the user's own login; SatNOGS; with caching | nothing; each source's usage rules | each source follows its provider's rules, tested against recorded answers; GPKit's core still makes no request of its own (the module is separate) |
| Satellite frequencies | done (#21, 2026-11-07: SatNOGS DB's active transmitters from one recorded request, with GPKit's Doppler) | from the SatNOGS DB API, paired with GPKit's Doppler | the data sources module | a satellite's transmitters read from recorded answers, with SatNOGS's credit |
| Fast propagation at Starlink scale | done (#17, 2026-11-07: the batch, to the bit what one propagator gives; 10,000 sets, a day at one-minute steps in 0.37 s on an Apple M5; `tools/benchmark` and its record) | about 10,000 objects | nothing | published benchmarks, repeatable, on named hardware |
| Streamed batch propagation, a memory bound for phones | in progress (branch `v2-streaming`, 2026-11-10) | **a design issue (the owner, 2026-11-10):** the batch keeps every state of a run, 3.4 GB for a day of 40,000 sets at one-minute steps (`conformance/benchmark-2026-11-10.txt` on `v2-benchmarks`); batch propagation should stream its results instead of holding them all, with a target memory bound for phones. Proposed: `Propagator.streamStates`, a block of instants at a time within a byte budget (8 MiB by default), and the bound "at most 24 MB added to the propagators, at any count" | fast propagation | the bound met in a benchmark at 10,000 to 40,000 sets (measured on `v2-streaming`: 12 to 15 MB added; 189 MB against 3,386 MB at 40,000), the states the batch's to the bit in tests; then the propagators' own memory at catalogue scale, the next issue |
| The propagators' memory at catalogue scale | measured, no design (2026-11-10; branch `v2-propagator-memory`, `conformance/memory-split-2026-11-10.txt`) | **the next 2.0 issue (the owner, 2026-11-10), measured first:** of 145 MB held at 40,000 made-up sets, the propagators with their element sets 79 MB (55 per cent; 1,368 bytes a propagator inline, 896 of them SGP4 state), the input text 14 MB and the file read from it 52 MB. The propagators are the largest part but do not dominate, so no design is proposed (the owner's rule); reading in pieces gives 87 MB at the peak against 174 with no change to GPKit | streamed batch propagation | the owner's word on whether about 3 KB a set (real capture of 11,141 sets; about 2 KB made-up, a lower bound) is to be cut further |
| A smaller propagator (an option, not a goal) | not started, by the owner's ruling (2026-11-10): no shrink now | **an option recorded, not a goal:** below about 3 KB a set (real capture of 11,141 sets; about 2 KB made-up, a lower bound), a propagator would hold its element set apart or not at all (896 bytes of SGP4 state; the element set 472 bytes inline and about 690 of its own, `conformance/memory-split-2026-11-10.txt`), which changes `Propagator.elementSet`, a 2.0 change | the propagators' memory measured | taken up only on the owner's word. The extra kilobyte of real data over made-up is in the element set's own allocations (same record) |
| A "How GPKit compares" page | | GPKit beside other GP libraries, built from gpconf's library-comparison work: only results gpconf has published, each with its run, its corpus version and the library's version | gpconf's published library rows | the page live, every number linked to its gpconf run, and each library's maintainer able to see it before it is published |

## 2.0-e Explore

| Item | Status | What it is | Depends on | Done when |
|---|---|---|---|---|
| Android | done (#18, 2026-11-07: built and tested in an emulator with swift.org's Android SDK for 6.4.2) | through Swift 6.3's official Android SDK; a path to GP Passes on Android | Linux CI | GPKit builds and its tests run for Android in CI |
| A Python package | done but for PyPI (#20, 2026-11-07: pygpkit, wheels for Linux, macOS and Windows tested in CI; nothing published without the owner's word) | `pip install gpkit` | the stable API | the package's results match GPKit's in a test |
| Hamlib rotator output | done (#23, 2026-11-07: Hamlib 4.5.5's dummy rotator follows a pass in CI) | rotator commands from a pass | coordinate frames | a Hamlib rotator simulator follows a recorded pass |
| CCSDS OEM export | done (#24, 2026-11-07: OEM 2.0 KVN in TEME; the oem package for Python reads it in CI) | an ephemeris in CCSDS OEM | coordinate frames | a written OEM read back by a named OEM reader |
| A rough close-approach screen | done (#25, 2026-11-07: candidates only, no probability; held to closest approaches by formula and by brute force) | clearly labelled as limited by SGP4's accuracy | fast propagation | the label in the API's documentation and output; tests on recorded pairs |

## Versions

Each row is checked against `CHANGELOG.md` and the release on GitHub.

| Version | Date | State | What it holds |
|---|---|---|---|
| 1.0.0 | 2026-10-07 | released | the first release: OMM as CSV, JSON, XML or KVN, TLE with Alpha-5, catalog numbers as integers, a TLE writer, SGP4 from Vallado's `SGP4.cpp`, passes with Doppler |
| 1.1.0 | 2026-11-09 | released | the close-approach screen, OEM export, rotator tracks, the sun and visibility, Earth-fixed state, RA/Dec, ground tracks and footprints, batch propagation, GPKitSources (CelesTrak and SatNOGS DB's transmitters), the `gpkit` CLI, pygpkit (not on PyPI), watchOS, Linux, Windows and Android in CI, DocC tutorials, examples, refusal pages and the concepts guide, and the gpconf 0.8.0 and Vallado records |
| 1.2.0 | 2026-11-10 | released | the playground's WebAssembly module, at most 1.1 MiB as sent, its answers held to the native build within 1e-9 |
| 1.2.1 | 2026-11-10 | released | the gpconf adapter answers gpconf's `propagate` op |
| 1.3.0 | 2026-11-10 | released | `Propagator.EpochReading`, with the opt-in `.vallado` epoch that matches `tcppver.out` |
| 1.4.0 | 2026-11-10 | released | streamed batch propagation; GPKitSources' `ElementSetStore`, `FolderSource` and `Ledger.nextAsk`; the catalogue-scale article; the benchmark's workloads, stream and memory modes with their records; the Android note; the documentation fix held from 1.3.0 (there was no 1.3.1) |
| 2.0.0 | with gpconf 0.9.0 | planned | data age with option B (`v2-data-age`), the type-4 refusal, the one change that breaks 1.x code (`v2-type4-refusal`), gpconf 0.9.0's full run and its badge (`docs/design/release-2.0-plan.md`, branch `v2-plans`) |
| gpkit-core 0.1 | later | planned | Phase 1 of GPKit everywhere: the Rust core, SGP4 first, held to Swift GPKit by gpconf, once Phase 0 is done and its gate is met (`docs/design/gpkit-everywhere.md`) |

## After 2.0: GPKit everywhere

A Rust `gpkit-core` with bindings for Python, JS/WASM, C#, Java/Kotlin and C; Swift GPKit stays native and is held
to the Rust core by gpconf. Phases 0 to 8, each gated on users and its own proof suite:
`docs/design/gpkit-everywhere.md`.

## Launch

Swift Forums (Related Projects), iOS Dev Weekly, r/swift, and the AMSAT and SatNOGS communities, once 2.0-b's
playground is live. Every post is the owner's, in the owner's voice.

## Rulings (the owner, 2026-11-05)

1. Native OMM: the equivalence proof, plus any OMM encoding (KVN, XML, JSON) GPKit does not read yet.
2. GP Passes' lesson and glossary texts may be copied into GPKit's MIT documentation, the owner owning both, once F2's Alpha-5 fix is in.
3. The data-age error estimate is measured, not quoted, from data already held; never a request to CelesTrak or Space-Track.

## Rulings (the owner, 2026-11-10)

1. Record the batch's 3.4 GB at 40,000 sets as a 2.0 design issue: batch propagation streams its results instead of holding them all, with a target memory bound for phones; the design proposed on a branch with a benchmark showing the bound (`v2-streaming`).
2. No 1.3.1 for the documentation fix alone: `v1.3.1-comment` goes out with the next real release.
3. Streaming keeps the 8 MiB default; the documented promise is "streaming adds at most 24 MB on top of the propagators", with the budget option documented for memory-tight apps (2 MiB, and its speed cost).
4. The propagators' memory at catalogue scale is the next 2.0 issue, measured first (the 174 MB at 40,000 sets split, each part in its own process); a design only if the propagators dominate.
5. No propagator shrink now: a smaller propagator is recorded as an option, not a goal. The "read in pieces, keep only the propagators" pattern (87 MB against 174 at the peak at 40,000 sets) is documented and is a benchmark mode; the memory split is re-run on the largest real capture held, beside the made-up result.

## Rulings (the owner, 2026-11-07)

1. Data age: the real estimate waits for gpconf 0.9.0's re-measure fetch (MEO and GEO sets included); a private low-orbit pilot may test the tool, with no number from it published.
2. Move macOS CI off the preview xcode-27 image once a general-release image offers Swift 6.4.2.
3. Order: Sun and visibility, coordinate frames and maps, the gpkit CLI, fast propagation, Android, the Python package, WebAssembly. Stop and ask before the data sources module and satellite frequencies; no request to CelesTrak, Space-Track or SatNOGS.
