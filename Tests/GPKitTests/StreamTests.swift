import Testing
@testable import GPKit

/// A streamed run: the batch's states, to the bit, a block at a time, in time order, each block within its budget.
@Suite struct StreamTests {

    struct Stop: Error {}

    /// The streamed run gathered back into the batch's shape, by propagator then by instant, with the blocks seen.
    static func gathered(_ propagators: [Propagator], from start: Epoch, every step: Double, count: Int, budget: Int,
                         chunk: Int = 512) async -> (runs: [[Result<StateVector, PropagationFailure>]], blocks: [StateBlock]) {
        var runs = propagators.map { _ in [Result<StateVector, PropagationFailure>]() }
        var blocks: [StateBlock] = []
        await Propagator.streamStates(of: propagators, from: start, every: step, count: count, budget: budget, chunk: chunk) { block in
            blocks.append(block)
            for s in 0..<block.steps {
                for p in 0..<block.satellites { runs[p].append(block[s, p]) }
            }
        }
        return (runs, blocks)
    }

    @Test func theStreamIsTheBatchToTheBitAtEveryBlockLength() async throws {
        let propagators = Array(try BatchTests.propagators().prefix(90))
        let start = try Epoch(ccsds: "1998-11-20T06:50:00")
        let batch = await Propagator.states(of: propagators, from: start, every: 61.5, count: 25, chunk: 4)
        let one = Propagator.bytesPerStreamedState * propagators.count
        // block lengths 1, 2, 7 (25 is not a multiple), 25 and more than the run
        for length in [1, 2, 7, 25, 40] {
            let (runs, blocks) = await Self.gathered(propagators, from: start, every: 61.5, count: 25, budget: one * length, chunk: 7)
            #expect(Propagator.streamBlockLength(satellites: propagators.count, budget: one * length) == length)
            #expect(runs == batch, "block length \(length)")
            // in time order, every instant once
            #expect(blocks.map(\.firstStep) == Array(stride(from: 0, to: 25, by: min(length, 25))))
            #expect(blocks.reduce(0) { $0 + $1.steps } == 25 && blocks.allSatisfy { $0.satellites == 90 && $0.steps <= length })
        }
    }

    @Test func aBlockIsHeldToItsBudgetAndNeverBelowOneInstant() async throws {
        let propagators = try BatchTests.propagators()   // 700
        let start = try Epoch(ccsds: "2026-10-01T00:00:00")
        let budget = 100_000
        let (_, blocks) = await Self.gathered(propagators, from: start, every: 60, count: 30, budget: budget)
        #expect(blocks.allSatisfy { $0.steps * $0.satellites * Propagator.bytesPerStreamedState <= budget })
        #expect(blocks.count == (30 + Propagator.streamBlockLength(satellites: 700, budget: budget) - 1) / Propagator.streamBlockLength(satellites: 700, budget: budget))
        // a budget smaller than one instant still gives one instant a block
        #expect(Propagator.streamBlockLength(satellites: 700, budget: 1) == 1)
        let (_, single) = await Self.gathered(propagators, from: start, every: 60, count: 3, budget: 1)
        #expect(single.map(\.steps) == [1, 1, 1])
        // the default: 8 MiB, at least one instant
        #expect(Propagator.defaultStreamBudget == 8 * 1_048_576)
        let forty = Propagator.streamBlockLength(satellites: 40_000)
        #expect(forty >= 1 && forty * 40_000 * Propagator.bytesPerStreamedState <= Propagator.defaultStreamBudget)
        print("a streamed state takes \(Propagator.bytesPerStreamedState) bytes; by default a block holds \(forty) instants of 40,000 satellites, \(Propagator.streamBlockLength(satellites: 1_000)) of 1,000")
    }

    @Test func failuresAreCarriedAndAThrownErrorStopsTheStream() async throws {
        let propagators = try BatchTests.propagators()
        // at the end of 2026 the rocket body of 1990 has come down: its failures come in the blocks as in the batch
        let late = try Epoch(ccsds: "2026-12-31T00:00:00")
        let (runs, _) = await Self.gathered(propagators, from: late, every: 60, count: 4, budget: 1)
        #expect(runs == (await Propagator.states(of: propagators, from: late, every: 60, count: 4)))
        #expect(runs.contains { $0.contains { if case .failure = $0 { true } else { false } } })
        // the body throws on the second block: no third is made
        var seen = 0
        await #expect(throws: Stop.self) {
            try await Propagator.streamStates(of: propagators, from: late, every: 60, count: 10, budget: 1) { _ in
                seen += 1
                if seen == 2 { throw Stop() }
            }
        }
        #expect(seen == 2)
        // nothing to stream: no block
        var none = 0
        await Propagator.streamStates(of: [], from: late, every: 60, count: 10) { _ in none += 1 }
        await Propagator.streamStates(of: propagators, from: late, every: 60, count: 0) { _ in none += 1 }
        await Propagator.streamStates(of: propagators, from: late, every: .nan, count: 3) { _ in none += 1 }
        #expect(none == 0)
    }
}
