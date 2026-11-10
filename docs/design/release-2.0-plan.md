# GPKit 2.0: a release plan

For the owner's review (2026-11-10), on branch `v2-plans`. This is a plan only: nothing here is merged, tagged or
released. Every merge into main and every tag and release waits for the owner's word, as always: each branch goes in
through a pull request, as a merge commit, once all checks pass. Branches are kept.

## What was checked to write it

The proposed order was merged on a local scratch branch, `merge-check/release-2.0-order`, from main (1.3.0). It is
not pushed.
- **Merging:** each branch merged in turn. Every `## Unreleased` changelog heading collided, and the only conflicts in
  code were `v2-type4-refusal`'s, in `Propagator.swift` and the adapter, each a few lines.
- **The result:** the suite passes (134 + 22 tests), as does the adapter's epoch check.
  `tools/public-api.sh --check` finds exactly one breaking change against v1.3.0, the one below.
- **Without type-4:** everything else together passes too (128 + 22), with no breaking change.

## Recommended: two releases, 1.4.0 now and 2.0.0 with gpconf 0.9.0

Only one branch breaks 1.x code. Everything else is additive, so it can reach users now as 1.4.0 instead of waiting
for gpconf 0.9.0.

### 1.4.0: additive, ready now

In this order, each a PR into main:

1. `v1.3.1-comment`: the Vallado documentation fix and the README's `from: "1.3.0"`. Merges cleanly.
2. `v2-sources`: `ElementSetStore`, `FolderSource` and `Ledger.nextAsk` (GPKitSources). The changelog needs joining.
3. `v2-propagator-memory`: carries `v2-benchmarks` and `v2-streaming` inside it.
   - Contents: `Propagator.streamStates` with its 24 MB promise, the catalogue-scale article and its checks, and the
     benchmark's `--workloads`, `--stream` and `--memory` modes with three records.
   - The changelog needs joining.
   - `v2-streaming` and `v2-benchmarks` then need no merge of their own. Merging `v2-propagator-memory` into
     `v2-streaming` gives the same tree (checked, 2026-11-10).
4. `v2-android-note`: the feasibility note. Merges cleanly.

Then date the changelog (one `## 1.4.0` heading whose intro line says what was added), tag v1.4.0, publish through
`release.yml`, and verify the files and the module's hash as for 1.3.0.

### 2.0.0: when gpconf 0.9.0 is released

In this order:

5. `v2-data-age`, after the owner rules on its shape (`docs/design/data-age-api-2.0.md`; option B recommended).
   - It is additive, but it goes in 2.0 so that its shape is settled before any table is published. Its table waits
     for gpconf 0.9.0's re-measure fetch anyway (ruling of 2026-11-07).
   - Its base is older than 1.3.0, so main is merged into it first (a merge, never a rebase: it is pushed). The
     changelog needs joining.
6. `v2-type4-refusal`: the breaking change. Main is merged in first, and the conflicts are resolved as in the trial:
   - `Propagator.init(_:gravity:epochReading:)` keeps 1.3.0's signature, with type-4's two guards (SGP4-XP first, then
     not SGP4) inside it;
   - the adapter keeps 1.3.0's `epochReading` line.
7. The gpconf 0.9.0 full run, recorded in `conformance/` with its steps, and the gpconf badge that links to it
   (roadmap 2.0-a, 2.0-c). This is the "done when" of the 0.9.0 items.
8. `tools/public-api.sh`: at 2.0.0 its check compares against the latest 2.x tag. This needs a small change on its own
   branch, so the one listed break is allowed exactly once, by the 2.0.0 changelog.

Then date, tag v2.0.0, release, and verify as before.

### If the owner prefers one release

Steps 1 to 8 in order as 2.0.0, with nothing released before gpconf 0.9.0. That costs users the additive work in the
meantime, for one fewer release to make.

## The breaking changes in 2.0

1. **`PropagationFailure.Kind.sgp4XP`** (`v2-type4-refusal`). An element set for SGP4-XP, whose ephemeris type is 4 or
   whose `MEAN_ELEMENT_THEORY` is `SGP4-XP`, is refused with this new kind.
   - A `switch` over every kind without a `default` stops compiling.
   - Code that checks for `.notSGP4` to catch type-4 sets must check `.sgp4XP` too. `.notSGP4` now means a theory
     other than SGP4 or SGP4-XP.
   - This is the only break the API digester finds across all branches combined.

Considered and not proposed:
- **Removing `Propagator.states(of:from:every:count:)`:** it stays. Its documentation already says it keeps every
  state, and a pointer to `streamStates` can be added without a break.
- **A smaller `Propagator`:** an option, not a goal, by the owner's ruling. It would change `Propagator.elementSet`.
- **`OrbitRegime`'s rename or reshape:** unreleased, so not a break, whichever option is ruled.

## What waits, beyond 2.0

- The data-age table itself: it waits for gpconf 0.9.0's re-measure fetch, then is published with its method.
- `DataAgeStudy` (option C of the data-age note): only if the re-measure fetch's size calls for it.
- A smaller propagator: an option, not a goal.
- The WebAssembly playground on the site: held until the site has launched.
- Android: an arm64 CI job and the Kotlin interface wait for the owner's answers in the feasibility note.
- macOS CI off the preview `xcode-27` image: when a general-release image offers Swift 6.4.2.
- pygpkit on PyPI: on the owner's word.
- Space-Track in GPKitSources: left out by the 1.1.0 ruling.

## Branches that need no merge

- `v2-epoch-leap-seconds`: already in main (released in 1.2.0).
- `v2-streaming` and `v2-benchmarks`: contained in `v2-propagator-memory`.
- `v1.3-vallado-epoch` and the `release-*` branches: merged.
- `playground-repro`: a diagnostic branch, not for release.
- `v2-plans`: these notes. It can merge with 1.4.0, or stay as a branch.

## Questions for the owner

1. Two releases (1.4.0 now, 2.0.0 with gpconf 0.9.0), or one?
2. The data-age shape (A, B or C; B recommended), before step 5.
3. Should `v2-plans`' two notes go into main with 1.4.0?
