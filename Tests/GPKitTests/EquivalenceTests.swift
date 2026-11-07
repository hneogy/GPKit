import Testing
import GPKit

/// An element set read as OMM and the same set read as a TLE: GPKit writes the OMM as the TLE's own lines, and the
/// two then propagate to the bit (conformance/omm-tle-equivalence-*.txt measures it over the provider files held).
@Suite struct EquivalenceTests {

    static let times: [Double] = [0, 90, 720, 1440, 4320, 10080]

    @Test(arguments: [Format.csv, .json, .kvn])
    func anOMMWrittenAsATLEIsTheTLEAndPropagatesAsIt(_ format: Format) throws {
        let text = switch format { case .csv: Sample.csv; case .json: Sample.json; default: Sample.kvn }
        let omm = try #require(try ElementSets.read(text, as: format).elementSets.first)
        let tle = try TLE.parse(line1: Sample.line1, line2: Sample.line2)
        let written = try TLE.write(omm, eccentricity: .truncated)
        #expect(written.line1 == Sample.line1 && written.line2 == Sample.line2)
        let fromOMM = try Propagator(try TLE.parse(line1: written.line1, line2: written.line2)), fromTLE = try Propagator(tle)
        for m in EquivalenceTests.times {
            #expect(try fromOMM.state(minutesFromEpoch: m) == fromTLE.state(minutesFromEpoch: m), "at \(m) min")
        }
    }

    /// Read as given, the two differ only by what the TLE's columns round away: for this set, under a centimetre.
    @Test func asReadTheyDifferByTheTLEsRounding() throws {
        let omm = try #require(try ElementSets.read(Sample.csv, as: .csv).elementSets.first)
        let tle = try TLE.parse(line1: Sample.line1, line2: Sample.line2)
        let a = try Propagator(omm), b = try Propagator(tle)
        for m in EquivalenceTests.times {
            let at = try omm.epoch.advanced(by: m * 60)
            let d = try a.state(at: at).position, e = try b.state(at: at).position
            let gap = ((d.x - e.x) * (d.x - e.x) + (d.y - e.y) * (d.y - e.y) + (d.z - e.z) * (d.z - e.z)).squareRoot()
            #expect(gap < 0.01, "at \(m) min: \(gap * 1000) m")
        }
    }
}
