# Streaming batch propagation: design (2.0)

For the owner's review (2026-11-10), on branch `v2-streaming`. It answers the design issue the owner recorded in the
2.0 plan: `Propagator.states(of:from:every:count:)` keeps every state of a run. A day at one-minute steps of 40,000
sets held 3.4 GB (`conformance/benchmark-2026-11-10.txt`). Batch propagation should stream its results instead, with
a memory bound a phone can keep.

## The design

```swift
extension Propagator {
    static let defaultStreamBudget: Int                     // 8 MiB
    static var bytesPerStreamedState: Int { get }           // 56 bytes on 64-bit systems
    static func streamBlockLength(satellites: Int, budget: Int = defaultStreamBudget) -> Int
    static func streamStates(of: [Propagator], from: Epoch, every: Double, count: Int,
                             budget: Int = defaultStreamBudget, chunk: Int = 512,
                             isolation: isolated (any Actor)? = #isolation,
                             _ body: (StateBlock) async throws -> Void) async rethrows
}
struct StateBlock: Sendable { firstStep, steps, satellites; subscript(step:satellite:) }
```

- **A block** is `streamBlockLength` consecutive instants of every satellite, at most `budget` bytes, never fewer
  than one instant. The run is made block by block, and the next block only after `body` returns. So the stream
  holds one block, plus that block's parts while it is made: at most twice the budget, plus the task group's own
  small use.
- **Within a block**, the satellites are cut into runs of `chunk`. Each run is a child task that fills one array of
  its own, then the block is laid out by instant. An earlier version gave each satellite an array of its own, one
  allocation a satellite and a block, and was 79 ns a state at 40,000 sets against 62 for this one (load about 5).
- **The same states as the batch**, to the bit. The instants are worked out as the batch works them out
  (`start.advanced(by: i × step)`), and each state is `state(at:)`'s.
- **The caller's isolation.** `body` runs where the call was made (the main actor in an app), so it can draw or
  store what it gets without a hop. A body that throws stops the stream.
- **The batch stays.** `states(of:from:every:count:)` is not changed (1.x promise). Its documentation already says
  it keeps every state. 2.0 could point it at the stream.

## The bound for phones, proposed

**With the default budget, a streamed run adds at most 24 MB to what the propagators hold, at any count** (three
times the 8 MiB budget, for the block, its parts and the task group). Measured on a Mac (the M5, macOS 27.2.1,
release build):

| sets | propagators made | after a streamed day | the stream added | the batch's day (same tool) |
|---|---|---|---|---|
| 10,000 | 54 MB | 66 MB | 12 MB | 857 MB |
| 20,000 | 103 MB | 114 MB | 11 MB | 1,752 MB |
| 40,000 | 174 MB | 189 MB | 15 MB | 3,386 MB |

Each figure is the process's resident peak, each run in a process of its own. On a phone, the same code should take
the same bytes a state **[inferred: not run on a device; the Android emulator and iOS simulators run the tests, not
this benchmark]**.

## What the bound does not cover

- **The propagators themselves.** In this tool, 40,000 sets hold 174 MB once read and made. That figure includes the
  CSV text and the read sets the tool keeps; how it splits has not been measured apart. For a phone with a whole
  catalogue, that is the next design issue. Neither part is changed here.
- **What `body` keeps.** A program that copies every block keeps the run again.

## Speed

At the same load, streaming a day of 40,000 sets runs at the batch's speed: 55 against 56 ns a state (load about 10).
Budgets measured at 40,000 sets:

| budget | instants a block | ns a state | most memory held |
|---|---|---|---|
| 2 MiB | 1 | 69 | 179 MB |
| 8 MiB | 3 | 55 | 189 MB |
| 32 MiB | 14 | 51 | 232 MB |

## How it is proved

- `Tests/GPKitTests/StreamTests.swift`, three tests:
  - the stream gathered back equals the batch, at block lengths 1, 2, 7, 25 and 40 over a 25-instant run;
  - the blocks come in time order, every instant once;
  - every block is within its budget, with one instant the least a block holds;
  - failures are carried as in the batch, and a thrown error stops the stream after that block;
  - an empty or non-finite run gives no block.
- Six planted faults each fail them: a run's layout transposed, runs out of order, the budget ignored, an instant
  skipped, an error swallowed, times counted from the block.
- The benchmark's `--stream` mode checks the stream against one propagator at a time, to the bit, before timing. A
  planted fault there stops it, exit 1.
