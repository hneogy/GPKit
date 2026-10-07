import Foundation
import Testing
@testable import GPKit
import SGP4Oracle

/// One of the verification element sets published with "Revisiting Spacetrack Report #3": two lines, and the times
/// its run is made at.
struct VerificationCase {
    let line1: String
    /// The first 69 characters of the file's line 2.
    let line2: String
    /// Line 2 as the file has it, with the start, the stop and the step after column 69.
    let line2WithTimes: String

    var catalogField: String { String(line1.dropFirst(2).prefix(5)) }

    static func all() throws -> [VerificationCase] {
        let url = try #require(Bundle.module.url(forResource: "SGP4-VER", withExtension: "TLE", subdirectory: "Resources"))
        let lines = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
        var cases: [VerificationCase] = []
        for (i, line) in lines.enumerated() where line.hasPrefix("1 ") && i + 1 < lines.count && lines[i + 1].hasPrefix("2 ") {
            cases.append(VerificationCase(line1: line, line2: String(lines[i + 1].prefix(69)), line2WithTimes: lines[i + 1]))
        }
        return cases
    }

    /// The times of the run, as the C++'s own test driver steps through them, after a first call at the epoch.
    static func times(start: Double, stop: Double, step: Double) -> [Double] {
        var times = [0.0]
        var tsince = start
        if abs(tsince) > 1.0e-8 { tsince -= step }
        while tsince < stop {
            tsince += step
            if tsince > stop { tsince = stop }
            times.append(tsince)
        }
        return times
    }
}

/// The largest difference between two runs, and how often they agreed to the bit.
struct Comparison {
    var steps = 0
    /// Steps at which every double of the position and the velocity has the same bits, and the error code is the same.
    var identical = 0
    var maxPosition = 0.0   // kilometres
    var maxVelocity = 0.0   // kilometres per second
    var errorsDiffer = 0

    mutating func add(_ r: (Double, Double, Double), _ v: (Double, Double, Double), _ error: Int, oracle or: [Double], _ ov: [Double], _ oerror: Int32) {
        steps += 1
        if error != Int(oerror) { errorsDiffer += 1 }
        let mine = [r.0, r.1, r.2, v.0, v.1, v.2], theirs = or + ov
        if error == Int(oerror), zip(mine, theirs).allSatisfy({ $0.bitPattern == $1.bitPattern }) { identical += 1 }
        // a difference that is not a number counts as the largest there is
        func gap(_ a: Double, _ b: Double) -> Double { (a - b).isNaN ? .infinity : abs(a - b) }
        for i in 0..<3 {
            maxPosition = max(maxPosition, gap(mine[i], theirs[i]))
            maxVelocity = max(maxVelocity, gap(mine[i + 3], theirs[i + 3]))
        }
    }

    mutating func merge(_ other: Comparison) {
        steps += other.steps
        identical += other.identical
        maxPosition = max(maxPosition, other.maxPosition)
        maxVelocity = max(maxVelocity, other.maxVelocity)
        errorsDiffer += other.errorsDiffer
    }
}

@Suite struct SGP4Tests {

    static let millimetre = 1.0e-6   // kilometres
    static let micrometre = 1.0e-9

    static let improved = CChar(UInt8(ascii: "i"))
    static let wgs72 = Int32(SGP4ORACLE_WGS72)

    /// One case run through its times on both sides. `core` is GPKit's, initialised by the caller.
    static func run(_ core: SGP4Core, against oracle: OpaquePointer, times: [Double]) -> Comparison {
        var core = core
        var result = Comparison()
        for t in VerificationCase.times(start: times[0], stop: times[1], step: times[2]) {
            var r = (0.0, 0.0, 0.0), v = (0.0, 0.0, 0.0)
            var or = [0.0, 0.0, 0.0], ov = [0.0, 0.0, 0.0]
            _ = core.sgp4(t, &r, &v)
            let oerror = sgp4oracle_sgp4(oracle, t, &or, &ov)
            result.add(r, v, core.error, oracle: or, ov, oerror)
        }
        return result
    }

    static func core(_ e: sgp4oracle_elements) -> SGP4Core {
        SGP4Core(.wgs72, afspc: false, epoch: e.epoch, xbstar: e.bstar, xndot: e.ndot, xnddot: e.nddot, xecco: e.ecco,
                 xargpo: e.argpo, xinclo: e.inclo, xmo: e.mo, xno_kozai: e.no_kozai, xnodeo: e.nodeo)
    }

    /// The port against the C++ on the same doubles: both are initialised from what the C++'s reader made of the
    /// lines, so any difference is the propagator's. The verification cases cover near-Earth and deep-space
    /// orbits, the half-day and one-day resonances, and the runs that end in each error.
    @Test func thePortMatchesTheOracleOnTheVerificationCases() throws {
        var total = Comparison()
        var deep = 0
        let cases = try VerificationCase.all()
        #expect(cases.count == 33)
        for c in cases {
            var e = sgp4oracle_elements()
            var times = [0.0, 0.0, 0.0]
            let oracle = try #require(sgp4oracle_twoline(c.line1, c.line2WithTimes, 1, SGP4Tests.improved, SGP4Tests.wgs72, &e, &times))
            defer { sgp4oracle_free(oracle) }
            let core = SGP4Tests.core(e)
            #expect(core.deepSpace == (sgp4oracle_is_deep_space(oracle) == 1), "\(c.catalogField)")
            deep += core.deepSpace ? 1 : 0
            let one = SGP4Tests.run(core, against: oracle, times: times)
            #expect(one.errorsDiffer == 0, "\(c.catalogField): the error codes differ at \(one.errorsDiffer) steps")
            #expect(one.maxPosition <= SGP4Tests.micrometre, "\(c.catalogField): \(one.maxPosition * 1.0e6) mm")
            total.merge(one)
        }
        print("SGP4, the port against the C++ oracle on the same inputs: \(cases.count) cases (\(deep) deep space), \(total.steps) steps, "
              + "\(total.identical) identical to the bit, largest difference \(total.maxPosition * 1.0e6) mm and \(total.maxVelocity * 1.0e6) mm/s")
        #expect(deep == 24)
        #expect(total.steps == 2349)
        #expect(total.maxPosition <= SGP4Tests.micrometre)
        #expect(total.maxVelocity <= SGP4Tests.micrometre)
    }

    /// From the two lines on both sides: the C++'s reader and propagator, GPKit's reader and propagator.
    ///
    /// The two readers do not make the same epoch of a line. GPKit keeps the epoch field exactly; the C++ takes it
    /// through a month, a day, an hour, a minute and a second and back to a Julian date, and comes out up to
    /// twenty microseconds away. Standing at the C++'s epoch, GPKit agrees with it to a micrometre. Standing at its
    /// own, it differs by what that epoch difference is worth: under half a millimetre everywhere but for one
    /// case, 23333, a deep-space orbit of eccentricity 0.97, where it is four millimetres.
    @Test func gpkitMatchesTheOracleFromTheLines() throws {
        var atTheirEpoch = Comparison(), atItsOwn = Comparison()
        var worst: [(String, Double)] = []
        for c in try VerificationCase.all() {
            var e = sgp4oracle_elements()
            var times = [0.0, 0.0, 0.0]
            // every verification line is read by GPKit's strict reader; four carry checksums that are not their lines'
            let set = try TLE.parse(line1: c.line1, line2: c.line2, checksum: .ignore)

            var oracle = try #require(sgp4oracle_twoline(c.line1, c.line2WithTimes, 1, SGP4Tests.improved, SGP4Tests.wgs72, &e, &times))
            let same = SGP4Tests.run(SGP4Core(set, epoch: e.epoch), against: oracle, times: times)
            sgp4oracle_free(oracle)
            #expect(same.errorsDiffer == 0, "\(c.catalogField)")
            #expect(same.maxPosition <= SGP4Tests.micrometre, "\(c.catalogField): \(same.maxPosition * 1.0e6) mm at the C++'s epoch")
            atTheirEpoch.merge(same)

            oracle = try #require(sgp4oracle_twoline(c.line1, c.line2WithTimes, 1, SGP4Tests.improved, SGP4Tests.wgs72, &e, &times))
            let own = SGP4Tests.run(SGP4Core(set), against: oracle, times: times)
            sgp4oracle_free(oracle)
            #expect(own.errorsDiffer == 0, "\(c.catalogField)")
            #expect(abs(set.epoch.daysSince1950 - e.epoch) * 86_400.0 < 25.0e-6, "\(c.catalogField): the two epochs are more than 25 microseconds apart")
            worst.append((c.catalogField, own.maxPosition))
            atItsOwn.merge(own)
        }
        worst.sort { $0.1 > $1.1 }
        print("SGP4, GPKit against the C++ oracle from the lines, at the C++ reader's epoch: \(atTheirEpoch.steps) steps, \(atTheirEpoch.identical) "
              + "identical to the bit, largest difference \(atTheirEpoch.maxPosition * 1.0e6) mm")
        print("SGP4, GPKit against the C++ oracle from the lines, at the epoch the line states: largest differences "
              + worst.prefix(3).map { "\($0.0) \($0.1 * 1.0e6) mm" }.joined(separator: ", "))
        #expect(atTheirEpoch.maxPosition <= SGP4Tests.micrometre)
        #expect(worst[0].0 == "23333" && worst[0].1 < 5 * SGP4Tests.millimetre)
        #expect(worst[1].1 < SGP4Tests.millimetre)
    }

    /// A call does not depend on the calls before it: a fresh copy at each time gives what a run through the times gives.
    @Test func aStepDoesNotDependOnTheStepsBefore() throws {
        for c in try VerificationCase.all() {
            var e = sgp4oracle_elements()
            var times = [0.0, 0.0, 0.0]
            let oracle = try #require(sgp4oracle_twoline(c.line1, c.line2WithTimes, 1, SGP4Tests.improved, SGP4Tests.wgs72, &e, &times))
            sgp4oracle_free(oracle)
            let fresh = SGP4Tests.core(e)
            var running = fresh
            for t in VerificationCase.times(start: times[0], stop: times[1], step: times[2]) {
                var r1 = (0.0, 0.0, 0.0), v1 = (0.0, 0.0, 0.0), r2 = (0.0, 0.0, 0.0), v2 = (0.0, 0.0, 0.0)
                var copy = fresh
                _ = running.sgp4(t, &r1, &v1)
                _ = copy.sgp4(t, &r2, &v2)
                #expect(r1 == r2 && v1 == v2 && running.error == copy.error, "\(c.catalogField) at \(t)")
            }
        }
    }

    /// The other two sets of constants and the other operation mode, against the C++ on the same inputs.
    @Test func theOtherConstantsAndTheOtherMode() throws {
        for (gravity, which) in [(SGP4Core.Gravity.wgs72old, SGP4ORACLE_WGS72OLD), (.wgs72, SGP4ORACLE_WGS72), (.wgs84, SGP4ORACLE_WGS84)] {
            for (afspc, mode) in [(false, "i"), (true, "a")] {
                var total = Comparison()
                for c in try VerificationCase.all() {
                    var e = sgp4oracle_elements()
                    var times = [0.0, 0.0, 0.0]
                    let reader = try #require(sgp4oracle_twoline(c.line1, c.line2WithTimes, 1, SGP4Tests.improved, SGP4Tests.wgs72, &e, &times))
                    sgp4oracle_free(reader)
                    let oracle = try #require(sgp4oracle_init(Int32(which), CChar(UInt8(ascii: Unicode.Scalar(mode)!)), &e))
                    defer { sgp4oracle_free(oracle) }
                    let core = SGP4Core(gravity, afspc: afspc, epoch: e.epoch, xbstar: e.bstar, xndot: e.ndot, xnddot: e.nddot, xecco: e.ecco,
                                        xargpo: e.argpo, xinclo: e.inclo, xmo: e.mo, xno_kozai: e.no_kozai, xnodeo: e.nodeo)
                    total.merge(SGP4Tests.run(core, against: oracle, times: times))
                }
                #expect(total.errorsDiffer == 0, "\(gravity) \(mode)")
                #expect(total.maxPosition <= SGP4Tests.micrometre, "\(gravity) \(mode): \(total.maxPosition * 1.0e6) mm")
                print("SGP4, \(gravity), mode \(mode): \(total.steps) steps, \(total.identical) identical to the bit, largest difference \(total.maxPosition * 1.0e6) mm")
            }
        }
    }

    @Test func theEpochAsDaysSince1950() throws {
        #expect(try Epoch(ccsds: "1949-12-31T00:00:00").daysSince1950 == 0)
        #expect(try Epoch(ccsds: "1950-01-01T12:00:00").daysSince1950 == 1.5)
        #expect(try Epoch(ccsds: "2000-01-01T12:00:00").daysSince1950 == 2451545.0 - 2433281.5)
        #expect(try Epoch(ccsds: "2016-12-31T23:59:60").daysSince1950 == (try Epoch(ccsds: "2017-01-01T00:00:00").daysSince1950))
    }
}
