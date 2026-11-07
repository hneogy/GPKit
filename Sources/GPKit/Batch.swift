extension Propagator {

    /// The states of many satellites at one instant of UTC, worked out in parallel: what a map or a screen of a whole
    /// constellation asks for at each frame. Each result is the one `state(at:)` gives for that propagator, in the
    /// same order, to the bit.
    ///
    /// The propagators are cut into runs of `chunk` and each run is a child task, so the work spreads over the
    /// threads Swift's concurrency has, one a core. Ten thousand sets take a millisecond or two on one core of a
    /// recent Mac (`conformance/benchmark-*.txt`), so for a single instant of a small catalog the plain loop is as
    /// good; the batch pays from a few thousand states up.
    public static func states(of propagators: [Propagator], at time: Epoch, chunk: Int = 512) async -> [Result<StateVector, PropagationFailure>] {
        await states(of: propagators, chunk: chunk) { propagator in
            Result { () throws(PropagationFailure) -> StateVector in try propagator.state(at: time) }
        }
    }

    /// The states of many satellites at a run of instants: `count` of them, `step` seconds apart from `start`.
    /// The result is by propagator, then by instant, each the one `state(at:)` gives for that instant, to the bit;
    /// an instant outside the years an `Epoch` can hold is a failure of kind `time`.
    ///
    /// Every state is kept: 10,000 satellites over a day at one-minute steps are 14.4 million states, some 800 MB.
    /// For more, ask for a shorter run at a time.
    public static func states(of propagators: [Propagator], from start: Epoch, every step: Double, count: Int,
                              chunk: Int = 64) async -> [[Result<StateVector, PropagationFailure>]] {
        guard count > 0, step.isFinite else { return propagators.map { _ in [] } }
        let times = (0..<count).map { i in try? start.advanced(by: Double(i) * step) }
        return await states(of: propagators, chunk: chunk) { propagator in
            times.map { time in
                Result { () throws(PropagationFailure) -> StateVector in
                    guard let time else { throw PropagationFailure(kind: .time, minutesFromEpoch: nil) }
                    return try propagator.state(at: time)
                }
            }
        }
    }

    /// `work` on every propagator, in runs of `chunk` run as child tasks, the results in the propagators' order.
    static func states<Each: Sendable>(of propagators: [Propagator], chunk: Int, _ work: @escaping @Sendable (Propagator) -> Each) async -> [Each] {
        let size = max(1, chunk)
        let runs = stride(from: 0, to: propagators.count, by: size).map { $0..<min($0 + size, propagators.count) }
        return await withTaskGroup(of: (Int, [Each]).self) { group in
            for (index, run) in runs.enumerated() {
                group.addTask { (index, propagators[run].map(work)) }
            }
            var done = [[Each]](repeating: [], count: runs.count)
            for await (index, results) in group { done[index] = results }
            return done.flatMap { $0 }
        }
    }
}
