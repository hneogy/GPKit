extension Propagator {

    /// The memory a streamed run's block of states is held to by default: 8 MiB. At 40,000 satellites that is 3
    /// instants a block; at 1,000, 149.
    public static let defaultStreamBudget = 8 * 1_048_576

    /// The bytes one state takes in a block.
    public static var bytesPerStreamedState: Int { MemoryLayout<Result<StateVector, PropagationFailure>>.stride }

    /// How many instants a block of a streamed run holds for `satellites` within `budget` bytes: never fewer than one,
    /// however large the count, so one instant of every satellite is the least a block holds.
    public static func streamBlockLength(satellites: Int, budget: Int = defaultStreamBudget) -> Int {
        max(1, budget / max(1, satellites * bytesPerStreamedState))
    }

    /// The states of many satellites over a run of instants, handed to `body` a block of instants at a time, in time
    /// order, so that the run is never held whole: `count` instants, `step` seconds apart from `start`. Each state is
    /// the one `states(of:from:every:count:)` and `state(at:)` give for that instant, in the same build, to the bit.
    ///
    /// A block holds `streamBlockLength(satellites:budget:)` instants of every satellite, at most `budget` bytes
    /// unless one instant alone is more. While a block is made, its parts are held beside it, so the stream's states
    /// take at most twice the block. The next block is made only after `body` returns. If `body` throws, no more blocks
    /// are made and the error comes out of the call.
    ///
    /// **The promise:** with the default budget, streaming adds at most 24 MB on top of the propagators, at any
    /// count up to 149,796 satellites (the most of whom one instant fits in 8 MiB; above that, a block is one instant,
    /// 56 bytes a satellite). What `body` keeps of the blocks is its own. Measured on an Apple M5: 12, 11 and 15 MB
    /// added at 10,000, 20,000 and 40,000 satellites over a day at one-minute steps, where the batch kept 857 MB,
    /// 1,752 MB and 3,386 MB (`conformance/benchmark-stream-2026-11-10.txt`).
    ///
    /// **For a memory-tight app**, a smaller budget holds less at some cost in speed. With `budget: 2 * 1_048_576`,
    /// 40,000 satellites stream one instant a block, the stream added 5 MB, and a day took 69 ns a state against
    /// 55 ns with the default (the same Mac and record). A larger budget gains little: 32 MiB gave 51 ns.
    ///
    /// Within a block, the satellites are cut into runs of `chunk` and each run is a child task, as in the batch.
    /// `body` runs in the caller's isolation (the main actor, for a call from it), so it may touch what the caller
    /// owns.
    public static func streamStates(of propagators: [Propagator], from start: Epoch, every step: Double, count: Int,
                                    budget: Int = defaultStreamBudget, chunk: Int = 512,
                                    isolation: isolated (any Actor)? = #isolation,
                                    _ body: (StateBlock) async throws -> Void) async rethrows {
        guard count > 0, step.isFinite, !propagators.isEmpty else { return }
        let length = streamBlockLength(satellites: propagators.count, budget: budget)
        var first = 0
        while first < count {
            let steps = min(length, count - first)
            let times = (first..<(first + steps)).map { i in try? start.advanced(by: Double(i) * step) }
            // each run of `chunk` satellites is a child task that fills one array of its own, by instant then by
            // satellite: one allocation a run and a block, where an array a satellite would be one a satellite
            let size = max(1, chunk)
            let runs = stride(from: 0, to: propagators.count, by: size).map { $0..<min($0 + size, propagators.count) }
            let pieces = await withTaskGroup(of: (Int, [Result<StateVector, PropagationFailure>]).self) { group in
                for (index, run) in runs.enumerated() {
                    group.addTask {
                        let width = run.count
                        var out = [Result<StateVector, PropagationFailure>](
                            repeating: .failure(PropagationFailure(kind: .time, minutesFromEpoch: nil)), count: steps * width)
                        for (k, p) in run.enumerated() {
                            let propagator = propagators[p]
                            for (s, time) in times.enumerated() {
                                out[s * width + k] = Result { () throws(PropagationFailure) -> StateVector in
                                    guard let time else { throw PropagationFailure(kind: .time, minutesFromEpoch: nil) }
                                    return try propagator.state(at: time)
                                }
                            }
                        }
                        return (index, out)
                    }
                }
                var done = [[Result<StateVector, PropagationFailure>]](repeating: [], count: runs.count)
                for await (index, out) in group { done[index] = out }
                return done
            }
            // laid out by instant, then by satellite
            var flat: [Result<StateVector, PropagationFailure>] = []
            flat.reserveCapacity(steps * propagators.count)
            for s in 0..<steps {
                for (index, run) in runs.enumerated() {
                    flat.append(contentsOf: pieces[index][(s * run.count)..<((s + 1) * run.count)])
                }
            }
            try await body(StateBlock(firstStep: first, steps: steps, satellites: propagators.count, states: flat))
            first += steps
        }
    }
}

/// A block of a streamed run (`Propagator.streamStates`): `steps` consecutive instants of the run, from its
/// `firstStep`-th, of every satellite in the order the propagators were given.
public struct StateBlock: Sendable {
    /// The run's index of the block's first instant: the instant `start + step × firstStep`.
    public let firstStep: Int
    /// How many instants the block holds.
    public let steps: Int
    /// How many satellites each instant holds.
    public let satellites: Int
    let states: [Result<StateVector, PropagationFailure>]

    /// The state of the `satellite`-th propagator at the block's `step`-th instant (from 0, within the block).
    public subscript(step: Int, satellite: Int) -> Result<StateVector, PropagationFailure> {
        precondition(step >= 0 && step < steps && satellite >= 0 && satellite < satellites, "outside the block")
        return states[step * satellites + satellite]
    }
}
