# GPKit everywhere: a design for an astrodynamics family

A design for the owner's review (2026-11-10). It holds no code, starts no repository and publishes nothing.

**Marks.**
- **[read]**: read for this note on 2026-11-10, from GitHub's API or a package registry's own pages.
- **[recall]**: from memory, not read today. Check it before relying on it, above all the licence of each data
  file.
- **[estimate]**: a judgement, not a measurement.

## 0. Phase 0 comes first (phases 0 to 8 in §10)

Nothing here starts until three things are finished:

1. **GP Passes 1.0**: in App Review now (1.0 (4), from c7a92f0, submitted 2026-11-10).
2. **GPKit 2.0**: the plan in `docs/design/release-2.0-plan.md` (branch `v2-plans`):
   - 1.4.0 with the additive branches;
   - then 2.0.0 with the type-4 refusal, data age, and gpconf 0.9.0's full run.
3. **gpconf 0.9.0**: the propagation tier, the TLE/OMM twins, the type-4 case, and its re-measure fetch.

The reason is that every layer below proves itself the way GPKit does: a public conformance suite run in CI, with
recorded results. That only works if gpconf 0.9.0, the first such suite, is finished and trusted.

## 1. The shape

```
                    ┌───────────────── proof ─────────────────┐
 gpkit-sim    ── Basilisk scenarios (simconf)                  │
 gpkit-od     ── Orekit OD tutorials, published cases (odconf) │
 gpkit-astro  ── Orekit + GMAT reference runs (astroconf)      │
 gpkit-core   ── gpconf                                        │
                    └──────────────────────────────────────────┘
 one Rust core per layer ── bindings: Python (PyO3), JS/WASM (wasm-bindgen), C (cbindgen),
                            C#/.NET (P/Invoke over the C ABI), Java/Kotlin (JNI or the FFM API over the C ABI)
 Swift GPKit: stays pure Swift, no Rust inside; it and the Rust core are held to each other by gpconf, both
              in the same CI run, each answer to the bit where the arithmetic allows and within the bar where not
```

Two implementations on purpose. Swift GPKit stays the dependency-free Swift library that GP Passes and Apple
platforms want. The Rust core serves every other language. When two independent implementations agree on gpconf,
each is a check on the other, which is worth more than one implementation wrapped five times.

**The rule kept from GPKit:** the core makes no network request of its own. Data a layer needs is something the user
gives it, or a versioned data package (section 4). The library never fetches it by itself.

## 2. The layers

### 2.1 gpkit-core (crate `gpkit-core`): GP data and SGP4

**Scope:**
- reading TLE (with Alpha-5) and OMM in KVN, XML, JSON and CSV;
- refusal with reasons, including type 4 (SGP4-XP) refused with its own kind;
- writing TLE;
- epoch readings, exact and Vallado;
- SGP4/SDP4, ported from Vallado's C++, as Swift GPKit's is;
- TEME to ECEF, looks and passes, Doppler;
- data age, with tables measured, not quoted;
- batch propagation and streaming of a whole catalogue.

This is Swift GPKit 2.0's scope, so it is a port with a finished specification and a finished test suite.

**API sketch (Rust; the bindings mirror it in each language's idiom):**

```rust
let file = gpkit_core::read(bytes, Format::Csv)?;            // ElementSetFile: sets and refusals, in order
let p = Propagator::new(&file.sets[0], Gravity::Wgs72, EpochReading::Exact)?;
let s = p.state_at(epoch)?;                                    // TEME position (km) and velocity (km/s)
let passes = p.passes(&observer, from, Duration::days(1), 0.0); // with rise, culmination and set
batch::stream(&props, from, step, count, Budget::mib(8), |block| { ... })?;  // bounded memory, as in Swift
```

```python
import gpkit                       # the Python name is open: see section 7
f = gpkit.read(data, "csv")
p = gpkit.Propagator(f.sets[0])
r, v = p.state_at("2026-11-10T00:00:00Z")
```

**Data:** none needed. SGP4 needs only WGS-72's constants, written in the code. Leap seconds matter only for converting
UTC to TAI for users who want it, and come from the core's shipped table (section 4).

**References:**
- Vallado's `SGP4.cpp` and `tcppver.out`, used through gpconf's manifest, as in Swift GPKit;
- python-sgp4, as a second implementation to compare with;
- Swift GPKit itself.

**Proof:**
- gpconf's every case, in each binding;
- Swift and Rust agreeing on the same inputs;
- `tcppver.out` within 2e-7 with Vallado's epoch reading.

**Licences:**
- Vallado's SGP4 (AIAA 2006-6753 code): the Swift port's NOTICE records the terms GPKit follows. The Rust port
  follows the same, citing it.
- WGS-72 constants are facts, not a licensed work.

**Effort, solo [estimate]:**
- 3 to 5 months for the Rust core with Python and WASM to Swift GPKit 2.0's parity, held to gpconf;
- 1 to 2 months more for C, C#/.NET and Java/Kotlin over a C ABI;
- after that, about 20 per cent of the time goes to keeping five languages released together.

**Gate to start:**
- Phase 0 done: gpconf 0.9.0 released and Swift GPKit passing all of it;
- **and** evidence of demand outside Apple platforms: about 100 GitHub stars on GPKit, or 3 people outside the project
  asking for another language, or a contributor offering a binding.

### 2.2 gpkit-astro: time, frames and numerical propagation

**Scope:**
- **time scales:** UTC, TAI, TT, TDB, UT1, GPS;
- **frames:** TEME, GCRF, ITRF with Earth orientation (IAU 2006/2000A, CIO-based), and MOD/TOD for old data;
- **numerical propagation:**
  - gravity harmonics up to degree and order 120 (EGM2008 truncated);
  - atmospheric drag (Harris-Priester first; NRLMSISE-00 next);
  - solar radiation pressure (cannonball, conical shadow);
  - third-body Sun and Moon (analytic first, JPL ephemerides next);
- **events:** eclipse, node, apsis, elevation and access;
- **impulsive and finite maneuvers.**

**API sketch:**

```rust
let eop = astro::Eop::from_package(&data)?;          // never fetched by the library
let frame = astro::Frames::new(eop);
let orbit = astro::Orbit::cartesian(epoch, Frame::Gcrf, r, v);
let mut prop = astro::Numerical::new(orbit)
    .gravity(Gravity::egm2008(20, 20)).drag(Drag::harris_priester(area, cd))
    .srp(Srp::cannonball(area, cr)).third_body([Body::Sun, Body::Moon])
    .integrator(Integrator::dormand_prince_853(tol));
let events = prop.detect([Event::eclipse(), Event::elevation(&station, 5.0)]);
let traj = prop.propagate_to(epoch + days(7))?;
```

**Data**, all through `gpkit-data` (section 4):
- EOP: x and y pole, UT1−UTC, dX/dY, from IERS;
- the leap seconds;
- space weather for drag: F10.7, Ap and Kp;
- JPL DE440 for Sun and Moon;
- a gravity model's coefficients.

**References, as oracles:**
- **Orekit** (Apache-2.0 [read]) and **NASA GMAT** (Apache-2.0 [read]), each run in CI on the same scenarios.
- Vallado's worked examples, used for their published numbers only, never their text.

**Proof, "astroconf":** a scenario corpus in the gpconf style.
- **Each scenario** is an initial state, force models, an interval and the outputs wanted.
- **Reference outputs** come from Orekit and from GMAT. Both must agree with each other within a stated bar before a
  scenario counts.
- **Bars are per scenario**, set from the two references' own disagreement, never tuned to make gpkit-astro pass.
- **The corpus records** each reference's version, and the data files' checksums. The scenarios are written for
  this; no copyrighted text goes in.

**Licences [recall unless said]:**

| Model or data | Source | Terms |
|---|---|---|
| IAU 2006/2000A series | IERS Conventions 2010 | free to use with citation |
| EOP | IERS Earth Orientation Centre / IERS Rapid Service (USNO) | free with citation; the provider's statement copied |
| JPL DE440/DE441 | NASA JPL | free to use; no licence file |
| EGM2008 | NGA | public release |
| NRLMSISE-00 | US Naval Research Laboratory | public domain in the US; the code's own notice kept |
| Harris-Priester | published density table | facts and a formula |
| Space weather | GFZ Potsdam (Kp/ap; CC BY 4.0) and NRC Canada / NOAA (F10.7) | as each states; never CelesTrak's compilation (section 4) |

**Effort, solo [estimate]:**
- 9 to 15 months to a first release that holds astroconf's LEO, MEO and GEO scenarios;
- frames and time are about a third of that, and are where most bugs live.

**Gate to start:**
- gpkit-core released in at least three languages, passing gpconf in each, Swift and Rust agreeing;
- **and** about 250 stars across the family, or 10 public repositories depending on it;
- **and** the astroconf skeleton with 20 scenarios run against Orekit and GMAT **before** any gpkit-astro code: the
  proof comes first, as gpconf came before GPKit.

### 2.3 gpkit-od: orbit determination

**Scope:**
- observations: range, range-rate, angles (RA/Dec, az/el), and GNSS position;
- measurement models with biases;
- batch least squares;
- EKF and UKF, with process noise;
- covariance propagation and its realism checks;
- TLE/OMM fitting: fit a mean element set to a trajectory, for writing GP data from your own tracking.

**API sketch:**

```rust
let mut od = od::BatchLeastSquares::new(initial_guess, numerical_propagator_builder)
    .measurement(Range::new(station, sigma_m)).measurement(AzEl::new(station, sigma_rad));
let solution = od.solve(&observations)?;   // state, covariance, residuals, iterations, convergence reason
```

**Data:** that of gpkit-astro, plus station coordinates, which the user gives.

**References:**
- Orekit's OD tutorials and its test cases (Apache-2.0);
- published OD cases, used for their numbers only (for example the Vallado and Tapley/Schutz/Born textbooks);
- simulated observations from gpkit-astro, made with known truth so that recovery can be checked.

**Proof, "odconf":** a fixed set of observation files with known truth, or with Orekit's solution. The bar is on
the recovered state and the consistency of its covariance, using normalised residuals.

**Licences:** Orekit is Apache-2.0 [read]. Published textbook cases are cited, never copied beyond their numbers.

**Effort, solo [estimate]:** 6 to 12 months after gpkit-astro.

**Gate to start:**
- gpkit-astro holding astroconf;
- about 500 stars, or a named user with tracking data and a need;
- odconf's first 10 cases built and run against Orekit first.

### 2.4 gpkit-sim: attitude, sensors, GN&C, Monte Carlo

**Scope:**
- attitude kinematics and dynamics;
- environment torques;
- sensors (star tracker, gyro, sun sensor, magnetometer, with an IGRF model) and actuators (reaction wheels,
  magnetorquers, thrusters);
- a module and message architecture, and closed-loop GN&C examples;
- Monte Carlo dispersion runs.

This covers the same ground as Basilisk.

**API sketch:** a component graph:

```rust
let mut sim = sim::Simulation::new(dt);
sim.add(Spacecraft::new(mass, inertia));
sim.add(ReactionWheels::new(...));
sim.add(StarTracker::new(...));
sim.add(Controller::mrp_feedback(k, p));
sim.connect(...);
let runs = sim.monte_carlo(1000, dispersions, seed);
```

**Data:** that of gpkit-astro, plus IGRF-14 for the magnetometer and torquer models. IGRF is published by IAGA and
free to use [recall].

**References:** Basilisk (ISC [read]): its scenarios and their outputs, run in CI. Published GN&C examples.

**Proof, "simconf":** Basilisk scenarios re-expressed. The bars are on attitude error histories and Monte Carlo
statistics, the latter with stated confidence.

**Effort, solo [estimate]:** 2 to 4 years to anything covering the ground Basilisk covers. Realistically this layer
needs a collaborator or funding.

**Gate to start:**
- gpkit-od released;
- **and** a collaborator or sponsor named;
- **and** a user who needs simulation in a language Basilisk does not offer. Basilisk is C/C++ with Python, so the
  languages would be WASM, .NET or the JVM.

## 3. The bindings and their parity

- **Build:**
  - one Rust crate per layer, plus a `gpkit-ffi` crate with a C ABI (cbindgen);
  - Python through PyO3 and maturin, with abi3 wheels;
  - JS/WASM through wasm-bindgen, as one npm package with WASM inside;
  - .NET through P/Invoke over the C ABI;
  - Java/Kotlin through the FFM API (Java 22+) over the C ABI, or JNI for older JVMs.
- **Parity rule:** every public call exists in every binding with the same meaning and the same refusals. A parity
  test, generated from one table of calls, runs each binding on the same inputs, and the answers must match.
  Numbers are compared to the bit, or within 1e-12 where the language's maths library differs, as the WASM
  playground already measures against Swift.
- **Swift ↔ Rust:** both answer gpconf's command protocol, and CI runs gpconf against both and compares their
  reports, not only their pass marks.

## 4. Data: shipped and updated without a session ever fetching

**The rule:** no session and no library fetches from celestrak.org or space-track.org, ever. The data a layer needs
comes from the primary sources, by a job the owner approves, and is published as a versioned, checksummed data
package.

- **`gpkit-data`** is a package per registry, versioned by date (for example `2026.11.10`). Each release has:
  - every file it holds, with SHA-256, source URL, retrieval date and licence statement (as gpconf's manifest does);
  - a `PROVENANCE.md` copied from each provider's terms.
- **Sources:**

  | Data | Primary source | Not from |
  |---|---|---|
  | leap seconds | IERS `Leap_Second.dat` (Bulletin C) | |
  | EOP | IERS finals2000A or EOP 20 C04 | CelesTrak's EOP-All |
  | space weather | GFZ Potsdam (Kp/ap), NRC Canada / NOAA (F10.7) | CelesTrak's SW-All |
  | JPL ephemerides | JPL's DE440 file, trimmed to a span | |
  | gravity models | NGA (EGM2008), or ICGEM (GFZ) | |

  Leap seconds will stop changing: CGPM 2026 Resolution 5, as GPKit's changelog records it. The table then becomes
  fixed.
- **Updates:** a scheduled GitHub Actions job on Linux, in a public repository so its minutes are free.
  - It fetches only from those primary sources, at most daily for EOP and space weather, and monthly for the rest.
  - It checks each file's format and ranges, and opens a pull request with the new files and their checksums.
  - **A person merges it.** Nothing publishes itself.
  - The job is the only thing that fetches, under each provider's stated rules, and identifies itself with a
    contact.
- **In the libraries:**
  - a data package is loaded explicitly (`Eop::from_package`);
  - the age of loaded data is visible, and a computation past its data's end refuses or says so, as GPKit's data
    age does for element sets;
  - users may give their own files in the same formats.
- **Before any of this runs:** the owner reads each provider's terms of use, and the job's fetch rules are written
  down as CelesTrak's were for gpconf.

## 5. Other libraries, and how GPKit relates to them

Read today [read]: licence, stars and latest release, from GitHub. Each library is described by what it covers.
No shortcoming of another library is stated here unless it has been reported upstream, with the link. The
corpus has harnesses for several of these libraries, and their results are gpconf's to publish, not this note's.

| Library | Language | Licence | Stars | Latest release | What it covers | How the GPKit family relates to it |
|---|---|---|---|---|---|---|
| python-sgp4 | Python + C++ (Vallado's own) | MIT | 483 | no GitHub release (PyPI) | Vallado's code itself, the reference SGP4; batch through SatrecArray; OMM | covers the same ground in Python; GPKit compares with it as a second implementation |
| satellite.js | JS/TS | MIT | 1,098 | 7.1.0 (2026-07-23) | SGP4 for the web | covers the same ground in JS/WASM |
| SGP.NET | C# | MIT | 48 | v1.6.0 (2026-09-23) | SGP4 for .NET, reading all five TLE/OMM formats | covers the same ground in C# |
| sgp4 (crate) | Rust | MIT/Apache | 120 | 2.4.0 (2026-02-23) | a fast, small SGP4 for Rust | covers the same ground in Rust |
| akhenakh/sgp4 | Go | Apache-2.0 | 6 | v1.0.4 (2026-11-10) | SGP4 and OMM for Go | Go is not among this plan's bindings |
| satkit | Rust + Python | Apache-2.0 | 97 | v0.24.0 (2026-09-26) | frames, JPL ephemerides, numerical propagation | covers the same ground as gpkit-core and gpkit-astro, and is ahead on astro today |
| brahe | Rust + Python | MIT | 105 | v1.8.1 (2026-10-31) | astrodynamics with good documentation, OMM reading, EOP | covers the same ground as gpkit-core and gpkit-astro, and is ahead on astro today |
| Orekit | Java | Apache-2.0 | 307 (GitHub mirror) | 13.1.9 (2026-10-03) | the industry reference: frames, propagation, OD, events | interoperates as a reference oracle for astroconf and odconf; covers far more ground than gpkit-astro and gpkit-od will for years |
| Basilisk | C/C++ + Python | ISC | 419 | v2.12.2 (2026-11-01) | GN&C simulation, Monte Carlo | interoperates as simconf's reference; gpkit-sim would cover the same ground in other languages |
| GMAT | C++ | Apache-2.0 | 146 | R2026a (2026-05-06) | mission design, NASA's own | interoperates as a reference oracle for astroconf |
| nyx | Rust | AGPL-3.0 | 510 | 2.6.0 (2026-09-12) | Rust astrodynamics and OD | covers the same ground in Rust, and is ahead on astro and OD |
| **GPKit** | Swift | MIT | 0 | v1.3.0 (2026-11-10) | GP reading and SGP4 with passes; gpconf 0.8.0: 17 of 18 cases pass exactly, the 18th runs no parser; Vallado's output matched; batch and streaming | |

**What the GPKit family would add:**
- **Correctness made public:** a conformance result published with every release, from a corpus anyone can run.
- **Multi-language parity:** the same answers and refusals in every language, tested.
- **OMM-first:** all four OMM encodings, six- and nine-digit catalog numbers, and refusal with reasons.
- **Batch propagation with bounded memory:** about 30 to 40 ns a state, measured on one Mac. That is GPKit's own
  figure only, until the benchmark below runs each library on its own best path.

**Where GPKit stands today:** no adoption yet (zero stars), trust that takes years, one language, and the astro, OD
and simulation ground that satkit, brahe, nyx and Orekit already cover.

## 6. A fair public benchmark

1. **Same work, each library's own best path:**
   - python-sgp4's `SatrecArray`, not a Python loop;
   - satellite.js's own propagate, in Node at a pinned version;
   - each crate built in release mode.

   Each maintainer is asked, before publication, whether the harness uses their library as they would.
2. **The same inputs:**
   - the tool's made-up constellation, published;
   - a real catalogue the publisher holds but does not redistribute, with its fingerprint published;
   - the same instants and the same output (TEME r, v).
3. **Agreement before speed:** every library's output is compared with python-sgp4's within gpconf's bar before
   anything is timed. A library that disagrees is reported as disagreeing, not timed as faster.
4. **Method:**
   - named hardware;
   - one-thread and all-thread figures apart;
   - parse time apart from propagation;
   - warm-up, then the median of N runs, with spread;
   - memory peak, in its own process.
5. **Published whole:** scripts, versions, lock files, raw numbers and the machine's load, so anyone can re-run it.
   No chart without its table.
6. **No cherry-picking:**
   - every library is run on every workload it supports, and a workload one library lacks is said, not dropped;
   - results where GPKit is slower are published too.

## 7. Package names [read 2026-11-10]

| Registry | `gpkit` | Other names checked |
|---|---|---|
| PyPI | **taken**: the MIT geometric-programming toolkit (convexengineering/gpkit, 1.1.1) | `gpkit-core` **taken** (the same project's fork, beautifulmachines, 0.7.0); free: `gpkit-astro`, `gpkit-od`, `gpkit-sim`, `pygpkit`, `gpkit-sgp4`, `gpkitpy` |
| npm | free | free: `gpkit-core`, `gpkit-wasm`; the scope `@gpkit` is someone else's (`@gpkit/core` 1.0.0, an unrelated utilities package, 2026-09-17) |
| NuGet | free | free: `GPKit.Core`, `GPKit.Astro` |
| crates.io | free | free: `gpkit-core`, `gpkit-astro`, `gpkit-od`, `gpkit-sim` |
| Maven Central | no artifact `gpkit` | no group under `dev.neogy`; the owner's domain would give `dev.neogy.gpkit:gpkit-core` |

**The Python name is the one real problem.** "gpkit" in Python already means geometric programming, a known MIT
project. Options:
- `pygpkit` (free), which the 2.0 roadmap's Python package already considered;
- a family name chosen fresh for all registries.

Nothing is reserved. Registering a name is publishing, so it waits for the owner. Names can be taken in the
meantime.

## 8. CI cost plan: Linux first

- **Public repositories:** GitHub Actions' standard runners are free for public repositories [recall]. The family's
  repositories are public, as GPKit is, so Linux, and even macOS and Windows, cost nothing there. Private
  repositories (GP Passes) are where minutes cost, macOS at about ten times Linux.
- **On every push and pull request:** Linux only:
  - the Rust tests;
  - Python, WASM, .NET and JVM binding tests, all of which run on Linux;
  - gpconf and the other conformance suites;
  - Swift GPKit's Linux job.
- **macOS and Windows:** on release tags, on a weekly schedule, and by hand. The jobs: Swift on Apple platforms,
  macOS and Windows wheels, and the .NET and JVM natives for those systems.
- **Heavy reference runs** (Orekit and GMAT for astroconf): on a schedule, with their outputs cached as versioned
  vectors in the corpus. A pull request compares with the vectors and never re-runs the oracles.
- **Budget guard:** any job on a private repository, or any paid runner, is listed with its expected minutes before
  it is added. The owner's rule stands: tell the owner before Actions spend passes $40 in a month.

## 9. Keeping good relations with maintainers

These are the rules the gpconf work already keeps (the corpus's outreach and public-voice conventions):

- **One finding, one reproduction, one number** in anything filed. No tables, no inventories, no "our tool says".
  The evidence stays in the corpus.
- **Their design is theirs.** A behaviour that is a design consequence of another library is recorded in the corpus
  and not filed again.
- **No nudging.** Replies are the owner's, in the owner's own voice. AI involvement is said plainly if asked, and
  never claimed as by-hand work.
- **Credit and contribution first:** fixes upstream (for example Gpredict's "Read the full mean motion field from TLE
  line 2", https://github.com/csete/gpredict/pull/428, merged 2026-10-08), cited sources, and thanks. GPKit's NOTICE
  names what it ports.
- **Benchmarks shown to them before publication** (section 6), with their corrections taken.
- **Being useful, not headline comparisons.** A comparison page states its method and is updated
  when a maintainer fixes something.

## 10. The phases, 0 to 8

Each phase is gated on users and on its proof suite passing. The proof is built before the code it proves.
Phases 1 to 4 split the core and its bindings as proposed here, SGP4 first. The numbering is the owner's.

| Phase | What | Starts when | Done when |
|---|---|---|---|
| 0 | Finish GP Passes 1.0, GPKit 2.0 and gpconf 0.9.0 | now | GP Passes 1.0 on the store; GPKit 2.0.0 released with gpconf 0.9.0; GPKit passing every gpconf 0.9.0 case |
| 1 | `gpkit-core` in Rust, SGP4 first: TLE/OMM reading with refusals, SGP4/SDP4, the epoch readings | Phase 0, and demand outside Apple platforms (§2.1) | gpconf passing in Rust; Swift and Rust agreeing on every gpconf input |
| 2 | Python (PyO3) and JS/WASM bindings | Phase 1 | gpconf passing in both; the parity test (§3) green |
| 3 | The C ABI, C#/.NET and Java/Kotlin bindings | Phase 2, and a user asking for .NET or the JVM | gpconf and parity in all five languages |
| 4 | The rest of the core in every binding: passes, data age, batch and streaming; the public benchmark (§6) | Phase 3 | parity for the whole core; the benchmark published with the maintainers' review |
| 5 | astroconf: the scenario corpus against Orekit and GMAT | Phase 4, and about 250 stars or 10 dependents | 20 scenarios where Orekit and GMAT agree |
| 6 | `gpkit-astro`: time, frames with EOP, numerical propagation, events, maneuvers | Phase 5 | astroconf held in every binding |
| 7 | odconf, then `gpkit-od` | Phase 6, and about 500 stars or a named user with tracking data | odconf held |
| 8 | `gpkit-sim`, covering the same ground as Basilisk | Phase 7, and a collaborator or sponsor | simconf held |

## Questions for the owner

1. **The Python name:** `pygpkit`, or a new family name for every registry?
2. **Reserving names:** register them early (publishing), or wait until there is code?
3. **Where the Rust core lives:** in the GPKit repository (one place, one CI), or a family repository beside it?
4. **The gates' numbers** (100, 250 and 500 stars): right, or should the gates be users and dependents only?
5. **Licence:** MIT for the whole family, as GPKit is, or Apache-2.0 for the patent grant, given that satkit, Orekit
   and GMAT are Apache?
