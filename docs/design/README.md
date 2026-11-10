# What is written about GPKit's future, and where

An index, as of 2026-11-10 (GPKit 1.3.0, `main` 1f5405b). Several of these documents live on branches that are not
merged yet, so each row names its branch.

## Documents

| Document | Branch | What it holds |
|---|---|---|
| `ROADMAP.md` | this branch (`docs-future`) | 2.0's items with status, the releases (1.4.0 and 2.0.0), the owner's rulings, and the pointer to GPKit everywhere |
| `docs/design/gpkit-everywhere.md` | this branch | the family beyond 2.0: a Rust core with bindings, Swift held to it by gpconf; layers core, astro, OD and sim; data without fetching from CelesTrak or Space-Track; licences; the competition; the benchmark method; package names; CI cost; relations with maintainers; Phases 0 to 8 |
| `docs/design/release-2.0-plan.md` | `v2-plans` | 1.4.0 now, 2.0.0 with gpconf 0.9.0; the merge order trialled; the breaking-change list (one: `PropagationFailure.Kind.sgp4XP`) |
| `docs/design/data-age-api-2.0.md` | `v2-plans` | the data-age API's shape: options A, B and C. B is the one in 2.0's scope: an open `OrbitClass`, a `Measurement`, a `Codable` `DataAgeTable` with provenance, and a typed `Estimate` |
| `docs/design/sources-2.0.md` | `v2-sources` | `ElementSetStore`, `FolderSource` and `Ledger.nextAsk`, and what is left out (Space-Track) |
| `docs/design/streaming-2.0.md` | `v2-streaming`, `v2-propagator-memory` | streamed batch propagation and its promise (at most 24 MB added at the default budget); the catalogue's memory |
| `docs/design/android-feasibility.md` | `v2-android-note` | what CI shows on Android, and what is untested (arm64 phones, size, 16 KB pages, a Kotlin interface) |
| `conformance/benchmark-2026-11-10.txt`, `benchmark-stream-2026-11-10.txt`, `memory-split-2026-11-10.txt` | `v2-benchmarks`, `v2-streaming`, `v2-propagator-memory` | constellation-scale timings, the streamed run against the batch, and the memory split, made-up and real |

## Branches toward 2.0

| Branch | Status | What |
|---|---|---|
| `v1.3.1-comment` | ready, for 1.4.0 | the Vallado documentation fix and the README's version line; no 1.3.1 on its own |
| `v2-sources` | ready, for 1.4.0 | the data sources' store, folder source and next-ask |
| `v2-benchmarks` | ready, inside `v2-propagator-memory` | `--count` and `--workloads` |
| `v2-streaming` | ready, inside `v2-propagator-memory` | `Propagator.streamStates` |
| `v2-propagator-memory` | ready, for 1.4.0 | the above two, the catalogue-scale article and the `--memory` modes |
| `v2-android-note` | ready, for 1.4.0 | the feasibility note |
| `v2-plans` | ready (documents) | the release plan and the data-age API note |
| `v2-data-age` | in progress, for 2.0.0 | data age; the shape (option B) still to be built |
| `v2-type4-refusal` | ready but for merging main in, for 2.0.0 | the one breaking change; its conflicts with 1.3.0 (a few lines in `Propagator.swift` and the adapter) are resolved in the release plan |
| `v2-epoch-leap-seconds` | merged (released in 1.2.0) | — |
| `macos-signing` | prepared, not pushed | `tools/sign-macos.sh`: Developer ID signing and notarization through a notarytool keychain profile |
| `playground-repro` | a diagnostic, not for release | the playground module's build-to-build difference |

## Not started

- **Badges:** the CI and gpconf badges.
- **macOS CI on a general-release image.**
- **One icon family:** an indigo ring-and-dot mark for GPKit, its site and GP Passes. GP Passes' icon is drawn from
  it already.
- **A "How GPKit compares" page:** built from gpconf's published library rows only.
- **GPKit everywhere, Phases 1 to 8:** after Phase 0.
