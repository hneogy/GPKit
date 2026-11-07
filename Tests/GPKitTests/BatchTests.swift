import Testing
@testable import GPKit

/// Many satellites at once: the batch gives what one propagator at a time gives, in the same order, to the bit.
@Suite struct BatchTests {

    /// The pass-check sets and the Space Station's first, each many times over, and one that SGP4 refuses part way.
    static func propagators() throws -> [Propagator] {
        var sets = [try TLE.parse(name: Sample.name, line1: Sample.line1, line2: Sample.line2)]
        sets.append(try TLE.parse(line1: "1 20453U 90008B   26263.56914166  .00350177  49935-4  75989-3 0  9996",
                                  line2: "2 20453  35.5934 307.3932 0022512 310.3690  49.5094 15.96788691956793"))
        sets.append(try TLE.parse(line1: "1 08195U 75081A   06176.33215444  .00000099  00000-0  11873-3 0   813",
                                  line2: "2 08195  64.1586 279.0717 6877146 264.7651  20.2257  2.00491383225656"))
        let base = try sets.map { try Propagator($0) }
        return (0..<700).map { base[$0 % base.count] }
    }

    @Test func oneInstantIsWhatEachPropagatorGives() async throws {
        let propagators = try BatchTests.propagators()
        let time = try Epoch(ccsds: "2026-10-01T00:00:00")
        for chunk in [1, 7, 512, 10_000] {
            let batch = await Propagator.states(of: propagators, at: time, chunk: chunk)
            #expect(batch.count == propagators.count)
            for (propagator, result) in zip(propagators, batch) {
                switch (result, Result { () throws(PropagationFailure) -> StateVector in try propagator.state(at: time) }) {
                case (.success(let a), .success(let b)): #expect(a == b)
                case (.failure(let a), .failure(let b)): #expect(a == b)
                default: Issue.record("the batch and the propagator disagree on whether \(propagator.elementSet.catalogNumber ?? -1) can be propagated")
                }
            }
        }
        // at the end of 2026 the rocket body of 1990 has come down, and SGP4 refuses it: the failure is carried too
        let late = try Epoch(ccsds: "2026-12-31T00:00:00")
        let refused = await Propagator.states(of: propagators, at: late).enumerated().filter { if case .failure = $0.element { true } else { false } }
        #expect(!refused.isEmpty && refused.allSatisfy { propagators[$0.offset].elementSet.catalogNumber == 20453 })
        #expect(await Propagator.states(of: [], at: time).isEmpty)
    }

    @Test func aRunOfInstantsIsWhatEachPropagatorGives() async throws {
        let propagators = Array(try BatchTests.propagators().prefix(90))
        let start = try Epoch(ccsds: "1998-11-20T06:50:00")
        let batch = await Propagator.states(of: propagators, from: start, every: 61.5, count: 25, chunk: 4)
        #expect(batch.count == propagators.count && batch.allSatisfy { $0.count == 25 })
        for (propagator, run) in zip(propagators, batch) {
            for (i, result) in run.enumerated() {
                let time = try start.advanced(by: Double(i) * 61.5)
                let one = Result { () throws(PropagationFailure) -> StateVector in try propagator.state(at: time) }
                switch (result, one) {
                case (.success(let a), .success(let b)): #expect(a == b, "\(propagator.elementSet.catalogNumber ?? -1) at \(time)")
                case (.failure(let a), .failure(let b)): #expect(a == b)
                default: Issue.record("disagree at \(time)")
                }
            }
        }
        #expect(await Propagator.states(of: propagators, from: start, every: 60, count: 0).allSatisfy(\.isEmpty))
    }
}
