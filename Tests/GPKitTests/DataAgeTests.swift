import Foundation
import Testing
@testable import GPKit

@Suite struct DataAgeTests {

    @Test func esasOrbitClassesForKnownOrbits() throws {
        #expect(try TLE.parse(line1: Sample.line1, line2: Sample.line2).orbitClass == .lowEarth)
        // mean motion (rev/day), eccentricity, inclination (degrees): orbits of a known kind
        let cases: [(Double, Double, Double, OrbitClass, String)] = [
            (15.5, 0.0005, 51.6, .lowEarth, "the ISS"),
            (1.0027, 0.0002, 0.05, .geostationary, "a geostationary satellite"),
            (1.0027, 0.0002, 30, .inclinedGeosynchronous, "a geosynchronous orbit inclined 30 degrees"),
            (1.0027, 0.0002, 14, .geostationary, "a geostationary satellite drifted to 14 degrees: GEO runs to 25"),
            (1.0027, 0.01, 5, .extendedGeostationary, "a geosynchronous orbit too eccentric for GEO's band"),
            (0.95, 0.001, 3, .extendedGeostationary, "a graveyard orbit above GEO"),
            (2.0056, 0.01, 55, .navigationSatellite, "a GPS satellite"),
            (1.7048, 0.0002, 56, .navigationSatellite, "a Galileo satellite"),
            (2.1314, 0.0004, 64.8, .navigationSatellite, "a GLONASS satellite"),
            (2.2557, 0.0010, 25, .mediumEarth, "a navigation-like orbit out of NSO's inclinations"),
            (5.0, 0.0005, 0.04, .mediumEarth, "an O3b satellite"),
            (2.26, 0.73, 27, .geostationaryTransfer, "a transfer orbit's upper stage"),
            (2.006, 0.72, 63.4, .geostationaryTransfer, "a Molniya orbit, by ESA's numbers"),
            (0.25, 0.8, 30, .highlyEccentric, "a long HEO"),
            (0.5, 0.2, 10, .highAltitude, "beyond 40,002 km all the way round"),
            (0.7765, 0.15, 10, .geoSuperGeoCrossing, "from GEO's height to above it"),
            (1.6, 0.25, 10, .meoGeoCrossing, "from MEO to GEO's height"),
            (8.0, 0.3, 40, .leoMeoCrossing, "from LEO to MEO"),
        ]
        for (n, e, i, orbitClass, what) in cases {
            #expect(OrbitClass(meanMotion: n, eccentricity: e, inclination: i) == orbitClass, "\(what): n \(n), e \(e), i \(i)")
        }
    }

    @Test func esasRangesAtTheirEnds() {
        // a circular orbit at height h, i degrees: a = R + h, the radius GPKit uses
        func circular(_ h: Double, _ i: Double = 0) -> OrbitClass {
            OrbitClass(semiMajorAxis: 6_378.135 + h, eccentricity: 0, inclination: i, radius: 6_378.135)
        }
        #expect(circular(1_999.99) == .lowEarth)
        #expect(circular(2_000.01) == .mediumEarth)         // 2,000 km itself is MEO's too, and MEO is tested first
        #expect(circular(35_586) == .geostationary)
        #expect(circular(35_585.999) == .extendedGeostationary)   // just below GEO's band: a = 41,964 km is in EGO's
        #expect(circular(35_786, 25) == .geostationary)
        #expect(circular(35_786, 25.001) == .inclinedGeosynchronous)
        #expect(circular(20_200, 50) == .navigationSatellite)
        #expect(circular(20_200, 49.999) == .mediumEarth)
        #expect(circular(31_569) == .mediumEarth)            // a = 37,947.1 km, below EGO's
        #expect(circular(31_570.01) == .extendedGeostationary)   // a = 37,948 km and more: EGO, tested before MEO
        #expect(circular(50_000) == .highAltitude)          // circular beyond 40,002 km: HAO
        // from the mean motion, with WGS-72's mu and radius: circular 1,999 and 2,001 km up (a radius of 6,371 km, say,
        // would put both above 2,000)
        #expect(OrbitClass(meanMotion: 11.322952506624489, eccentricity: 0, inclination: 0) == .lowEarth)
        #expect(OrbitClass(meanMotion: 11.318898767133655, eccentricity: 0, inclination: 0) == .mediumEarth)
        // perigee and apogee given directly: a = R + (h_p + h_a) / 2, e = (h_a - h_p) / (2a)
        func orbit(_ hp: Double, _ ha: Double, _ i: Double) -> OrbitClass {
            let a = 6_378.135 + (hp + ha) / 2
            return OrbitClass(semiMajorAxis: a, eccentricity: (ha - hp) / (2 * a), inclination: i, radius: 6_378.135)
        }
        #expect(orbit(250, 35_786, 90) == .geostationaryTransfer)
        #expect(orbit(250, 35_786, 90.01) == .undefined)             // GTO's inclinations end at 90, and no other class holds it
        #expect(orbit(-20, 35_786, 27) == .undefined)    // a perigee below the equatorial radius: every h_p range starts at 0
        #expect(orbit(0, 35_786, 27) == .geostationaryTransfer)
        #expect(orbit(250, 40_002, 27) == .geostationaryTransfer)
        #expect(orbit(250, 40_002.01, 27) == .highlyEccentric)
        #expect(orbit(31_570, 70_000, 27) == .geoSuperGeoCrossing)    // 31,570 is in both GHO and HEO; GHO is tested first
        #expect(orbit(31_569, 70_000, 27) == .highlyEccentric)
        #expect(orbit(31_570, 40_001, 27) == .inclinedGeosynchronous) // a = 42,164 km, e 0.1: IGO, before both
        #expect(orbit(31_571, 50_000, 27) == .geoSuperGeoCrossing)
        #expect(orbit(40_002, 50_000, 27) == .geoSuperGeoCrossing)
        #expect(orbit(40_002.01, 50_000, 27) == .highAltitude)
        #expect(orbit(2_001, 40_002, 27) == .meoGeoCrossing)
        #expect(orbit(2_001, 40_002.01, 27) == .highlyEccentric)
        #expect(orbit(2_001, 35_000, 27) == .meoGeoCrossing)
        #expect(orbit(1_999, 35_000, 27) == .geostationaryTransfer)
        #expect(orbit(1_999, 20_000, 27) == .leoMeoCrossing)
        #expect(orbit(-20, 1_000, 97) == .undefined)
        #expect(orbit(0, 1_000, 97) == .lowEarth)
        #expect(orbit(-0.01, 20_000, 27) == .undefined)
        #expect(OrbitClass(meanMotion: -15.5, eccentricity: 0, inclination: 51.6) == .undefined)
        #expect(OrbitClass(meanMotion: 0, eccentricity: 0, inclination: 51.6) == .undefined)
        #expect(OrbitClass.esaClasses.map(\.rawValue)
                == ["GEO", "IGO", "EGO", "NSO", "GTO", "MEO", "GHO", "LEO", "HAO", "MGO", "HEO", "LMO", "UFO"])
    }

    @Test func ageIsDaysSinceTheEpoch() throws {
        let set = try TLE.parse(line1: Sample.line1, line2: Sample.line2)
        #expect(set.age(at: set.epoch) == 0)
        #expect(set.age(at: try set.epoch.advanced(by: 86_400)) == 1)
        #expect(abs(set.age(at: try set.epoch.advanced(by: -43_200)) + 0.5) < 1e-12)   // the time of day is a Double
    }

    /// The ISS sample, its epoch moved by `days`: the same elements at another epoch, as a later fit would be.
    func moved(_ days: Double, catalog: Int? = 25544) throws -> ElementSet {
        var set = try TLE.parse(line1: Sample.line1, line2: Sample.line2)
        set.epoch = try set.epoch.advanced(by: days * 86_400)
        set.catalogNumber = catalog
        return set
    }

    @Test func eachSampleIsTheOlderSetAtTheNewerSetsEpoch() throws {
        let (a, b, c) = (try moved(0), try moved(1), try moved(2.5))
        let (samples, failures) = split(DataAge.measure([c, a, b]))
        #expect(failures == 0)
        // every pair, older to newer: a to b, a to c, b to c
        #expect(samples.map(\.age) == [1, 2.5, 1.5])
        for (sample, (older, newer)) in zip(samples, [(a, b), (a, c), (b, c)]) {
            let drifted = try Propagator(older).state(at: newer.epoch).position
            let truth = try Propagator(newer).state(at: newer.epoch).position
            let distance = Vector(x: drifted.x - truth.x, y: drifted.y - truth.y, z: drifted.z - truth.z).magnitude
            #expect(sample.positionError == distance)
            #expect(sample.positionError > 0)
            #expect(sample.older == older.epoch && sample.newer == newer.epoch && sample.orbitClass == .lowEarth)
            // the three components make up the whole difference
            let sum = (sample.radial * sample.radial + sample.inTrack * sample.inTrack + sample.crossTrack * sample.crossTrack).squareRoot()
            #expect(abs(sum - sample.positionError) <= 1e-9 * sample.positionError)
        }
    }

    @Test func whatMakesNoSampleIsLeftOut() throws {
        let a = try moved(0)
        // the same epoch twice, no catalog number, one satellite alone, an age beyond the maximum
        #expect(DataAge.measure([a, a]).samples.isEmpty)
        #expect(DataAge.measure([try moved(0, catalog: nil), try moved(1, catalog: nil)]).samples.isEmpty)
        #expect(DataAge.measure([a, try moved(1, catalog: 99999)]).samples.isEmpty)
        #expect(DataAge.measure([a, try moved(31)]).samples.isEmpty)
        #expect(DataAge.measure([a, try moved(31)], maximumAge: 31).samples.count == 1)
        // a pair either set cannot be propagated for is counted, not sampled
        var sgp4XP = a
        sgp4XP.ephemerisType = 4
        let (samples, failures) = split(DataAge.measure([sgp4XP, try moved(1)]))
        #expect(samples.isEmpty && failures == 1)
    }

    @Test func aSetGivenTwiceCountsOnceAndSetsSharingAnEpochAreLeftOut() throws {
        let (a, b, c) = (try moved(0), try moved(1), try moved(2))
        // the same set twice, as overlapping files give it: one pair, not two
        #expect(DataAge.measure([a, a, b]).samples.count == 1)
        #expect(DataAge.measure([a, b, a, b, b]).samples.count == 1)
        // two different sets at one epoch: neither is used, the pairs of the others stand
        var other = a
        other.bstar = try #require(ExactDecimal("0.0001"))
        let (samples, failures) = split(DataAge.measure([a, other, b, c]))
        #expect(samples.map(\.age) == [1] && failures == 0)
    }

    @Test func failuresAreCountedByPairWhicheverSetFails() throws {
        var bad = try moved(1)
        bad.ephemerisType = 4
        // the failing set as the newer of a pair, and as the older of another: two pairs fail, a to c stands
        let (samples, failures) = split(DataAge.measure([try moved(0), bad, try moved(2)]))
        #expect(failures == 2)
        #expect(samples.map(\.age) == [2])
    }

    @Test func pairsPastTheMaximumAgeAreLeftAndTheRestKept() throws {
        // a to c is 40 days, past 30; a to b and b to c are 20 each
        let (samples, failures) = split(DataAge.measure([try moved(0), try moved(20), try moved(40)]))
        #expect(samples.map(\.age) == [20, 20] && failures == 0)
    }

    @Test func theComponentsAreInTheNewerSetsFrame() throws {
        let (a, b) = (try moved(0), try moved(1))
        let sample = try #require(DataAge.measure([a, b]).samples.first)
        // the frame worked out here, from the newer set's own state, apart from DataAge's code
        let truth = try Propagator(b).state(at: b.epoch)
        let drifted = try Propagator(a).state(at: b.epoch).position
        let d = (drifted.x - truth.position.x, drifted.y - truth.position.y, drifted.z - truth.position.z)
        let p = truth.position, v = truth.velocity
        let pm = p.magnitude
        let r = (p.x / pm, p.y / pm, p.z / pm)
        var c = (p.y * v.z - p.z * v.y, p.z * v.x - p.x * v.z, p.x * v.y - p.y * v.x)
        let cm = (c.0 * c.0 + c.1 * c.1 + c.2 * c.2).squareRoot()
        c = (c.0 / cm, c.1 / cm, c.2 / cm)
        let t = (c.1 * r.2 - c.2 * r.1, c.2 * r.0 - c.0 * r.2, c.0 * r.1 - c.1 * r.0)
        func dot(_ u: (Double, Double, Double), _ w: (Double, Double, Double)) -> Double { u.0 * w.0 + u.1 * w.1 + u.2 * w.2 }
        let tolerance = 1e-9 * sample.positionError
        #expect(abs(sample.radial - dot(d, r)) <= tolerance)
        #expect(abs(sample.inTrack - dot(d, t)) <= tolerance)
        #expect(abs(sample.crossTrack - dot(d, c)) <= tolerance)
    }

    @Test func theSampleTakesTheOlderSetsClass() throws {
        let older = try moved(0)
        var newer = try moved(1)
        newer.meanMotion = try #require(ExactDecimal("11.0"))    // about 2,200 km up: MEO, where the older set is LEO
        #expect(older.orbitClass == .lowEarth && newer.orbitClass == .mediumEarth)
        let sample = try #require(DataAge.measure([older, newer]).samples.first)
        #expect(sample.orbitClass == .lowEarth)
    }

    @Test func componentsAlongTheTrack() {
        // a satellite at 7000 km on x, moving along y: radial is x, in-track y, cross-track z
        let state = StateVector(position: Vector(x: 7000, y: 0, z: 0), velocity: Vector(x: 0, y: 7.5, z: 0))
        let (r, t, c) = DataAge.components(of: Vector(x: 1, y: 2, z: 3), along: state)
        #expect(r == 1 && t == 2 && c == 3)
    }

    @Test func percentilesByNearestRank() throws {
        let p = try #require(DataAge.Percentiles((1...20).map(Double.init).reversed()))
        #expect(p.count == 20 && p.median == 10 && p.p68 == 14 && p.p95 == 19 && p.maximum == 20)
        let one = try #require(DataAge.Percentiles([3]))
        #expect(one.median == 3 && one.p95 == 3)
        let four = try #require(DataAge.Percentiles([4, 1, 3, 2]))
        #expect(four.median == 2 && four.p68 == 3 && four.p95 == 4)
        #expect(DataAge.Percentiles([]) == nil)
        #expect(DataAge.Percentiles([1, .nan]) == nil)
        #expect(DataAge.Percentiles([1, .infinity]) == nil)
    }

    /// A measurement's samples and its failures as a count, for the tests written against the pair it replaced.
    func split(_ m: DataAge.Measurement) -> ([DataAge.Sample], Int) { (m.samples, m.failureCount) }

    @Test func failuresAreCountedByKind() throws {
        var xp = try moved(0)
        xp.ephemerisType = 4
        var theory = try moved(1)
        theory.meanElementTheory = "SGP8"
        let m = DataAge.measure([xp, theory, try moved(2)])
        // xp to theory and xp to the third fail on xp's kind; theory to the third on theory's
        #expect(m.failures == [.sgp4XP: 2, .notSGP4: 1])
        #expect(m.failureCount == 3 && m.samples.isEmpty)
    }

    @Test func theMeasurementSaysWhatItWasMadeFrom() throws {
        let (a, b, c) = (try moved(0), try moved(1), try moved(2))
        var other = c
        other.bstar = try #require(ExactDecimal("0.0001"))   // shares c's epoch and differs: both left out
        let m = DataAge.measure([a, b, a, c, other, try moved(5, catalog: nil)])
        #expect(m.sets == [.lowEarth: 2])
        #expect(m.epochs == a.epoch...b.epoch)
        #expect(DataAge.measure([]).epochs == nil && DataAge.measure([]).sets.isEmpty)
        #expect(DataAgeTable.Provenance(source: "none", measurement: DataAge.measure([])) == nil)
    }

    /// Samples made up for the table's tests: catalog 1, from the ISS set's epoch.
    func made(_ age: Double, _ error: Double, _ orbitClass: OrbitClass = .lowEarth) throws -> DataAge.Sample {
        let base = try moved(0)
        return DataAge.Sample(catalogNumber: 1, orbitClass: orbitClass, older: base.epoch,
                              newer: try base.epoch.advanced(by: age * 86_400), age: age, positionError: error,
                              radial: 0, inTrack: error, crossTrack: 0)
    }

    func madeTable() throws -> DataAgeTable {
        let base = try moved(0)
        let samples = [try made(0.5, 1), try made(0.9, 3), try made(1, 2), try made(4, 10), try made(4, 20, .mediumEarth),
                       try made(40, 99), try made(2, .nan)]
        let m = DataAge.Measurement(samples: samples, failures: [:], sets: [.lowEarth: 3, .mediumEarth: 1],
                                    epochs: base.epoch...(try base.epoch.advanced(by: 40 * 86_400)))
        let provenance = try #require(DataAgeTable.Provenance(source: "made up for a test", measurement: m))
        return DataAgeTable(m, edges: [0, 1, 7, 10], provenance: provenance)
    }

    @Test func aTableByClassAndAge() throws {
        let table = try madeTable()
        // ESA's order (MEO before LEO), then by age; the sample past the last edge in no row, the NaN left out
        #expect(table.rows.map { "\($0.orbitClass) \($0.fromAge)-\($0.toAge) \($0.positionError.count)" }
                == ["MEO 1.0-7.0 1", "LEO 0.0-1.0 3", "LEO 1.0-7.0 1"])
        #expect(table.rows[1].positionError.median == 2)
        #expect(table.edges == [0, 1, 7, 10])
        #expect(table.provenance.gpkitVersion == DataAge.gpkitVersion && table.provenance.method == DataAge.method)
        #expect(table.provenance.sets == [.lowEarth: 3, .mediumEarth: 1])
    }

    @Test func eachEstimateSaysWhy() throws {
        let table = try madeTable()
        let base = try moved(0)
        func at(_ days: Double) throws -> Epoch { try base.epoch.advanced(by: days * 86_400) }
        // a day old: the first span, which holds its end; three days: the second
        #expect(table.estimate(for: base, at: try at(1)) == .row(table.rows[1]))
        #expect(table.estimate(for: base, at: try at(3)) == .row(table.rows[2]))
        #expect(table.estimate(for: base, at: base.epoch) == .notAfterEpoch)
        #expect(table.estimate(for: base, at: try at(-0.01)) == .notAfterEpoch)
        // past 7 and within 10: LEO has no row there
        #expect(table.estimate(for: base, at: try at(8)) == .noRowForAge(age: 8))
        #expect(table.estimate(for: base, at: try at(11)) == .olderThanTable(age: 11))
        // a class the table measured nothing of
        var high = base
        high.meanMotion = try #require(ExactDecimal("1.0027"))
        high.eccentricity = try #require(ExactDecimal("0.0002"))
        high.inclination = try #require(ExactDecimal("0.05"))
        #expect(table.estimate(for: high, at: try at(1)) == .unclassified(.geostationary))
    }

    @Test func aTableReadsBackAsWritten() throws {
        let table = try madeTable()
        let encoded = try JSONLikeCoder.encode(table)
        let decoded = try JSONLikeCoder.decode(DataAgeTable.self, from: encoded)
        #expect(decoded == table)
        // the epochs as text, every digit kept; the classes as ESA's abbreviations, keys of the counts
        #expect(encoded.contains("\"earliestEpoch\":\"\(table.provenance.earliestEpoch)\""))
        #expect(encoded.contains("\"orbitClass\":\"LEO\""))
        #expect(encoded.contains("\"sets\":{"))
    }

    @Test func aDamagedTableIsRefused() throws {
        let good = try JSONLikeCoder.encode(try madeTable())
        func refused(_ change: (String) -> String) -> Bool {
            let text = change(good)
            #expect(text != good, "the change did not apply")
            return (try? JSONLikeCoder.decode(DataAgeTable.self, from: text)) == nil
        }
        #expect(refused { $0.replacingFirst("\"edges\":[0,1,7,10]", with: "\"edges\":[0,7,1,10]") })   // not increasing
        #expect(refused { $0.replacingFirst("\"edges\":[0,1,7,10]", with: "\"edges\":[0]") })            // one edge
        #expect(refused { $0.replacingFirst("\"toAge\":7", with: "\"toAge\":8") })                       // off the edges
        #expect(refused { $0.replacingFirst("\"median\":2,", with: "\"median\":3.5,") })                   // median above p68
        #expect(refused { $0.replacingFirst("\"count\":3", with: "\"count\":0") })
        #expect(refused { $0.replacingFirst("\"earliestEpoch\":\"", with: "\"earliestEpoch\":\"x") })
        // a row given twice
        let table = try madeTable()
        #expect(DataAgeTable(rows: table.rows + [table.rows[0]], edges: table.edges, provenance: table.provenance) == nil)
        #expect(DataAgeTable(rows: table.rows, edges: table.edges, provenance: table.provenance) == table)
        // edges that are not valid, the rows fitting them all the same
        for edges: [Double] in [[0, 1, 7, 10, 10], [0, 1, 7, 10, 5], [0, 1, 7, 10, .infinity]] {
            #expect(DataAgeTable(rows: table.rows, edges: edges, provenance: table.provenance) == nil, "edges \(edges)")
        }
    }

    @Test func percentilesFromTheirFigures() throws {
        let p = try #require(DataAge.Percentiles(count: 4, median: 2, p68: 3, p95: 4, maximum: 4))
        #expect(p == DataAge.Percentiles([4, 1, 3, 2]))
        #expect(DataAge.Percentiles(count: 0, median: 2, p68: 3, p95: 4, maximum: 4) == nil)
        #expect(DataAge.Percentiles(count: 4, median: 3, p68: 2, p95: 4, maximum: 4) == nil)
        #expect(DataAge.Percentiles(count: 4, median: 2, p68: 3, p95: 5, maximum: 4) == nil)
        #expect(DataAge.Percentiles(count: 4, median: -1, p68: 3, p95: 4, maximum: 4) == nil)
        #expect(DataAge.Percentiles(count: 4, median: 2, p68: 3, p95: 4, maximum: .infinity) == nil)
    }

    @Test func aClassThisReleaseDoesNotKnowStillReads() throws {
        // a later ESA issue's class, in a table read by this release
        let future = OrbitClass(rawValue: "XYZ")
        #expect(!OrbitClass.esaClasses.contains(future) && future.description == "XYZ")
        let text = "{\"orbitClass\":\"XYZ\",\"fromAge\":0,\"toAge\":1,\"positionError\":{\"count\":1,\"median\":1,\"p68\":1,\"p95\":1,\"maximum\":1}}"
        let row = try JSONLikeCoder.decode(DataAge.Row.self, from: text)
        #expect(row.orbitClass == future)
    }

    @Test(.enabled(if: theSourceTreeIsHere, "reads CHANGELOG.md, which is not on the device"))
    func theVersionATableRecordsIsTheChangelogs() throws {
        // the first release heading of CHANGELOG.md, dated or not, is the version a table built here records
        let changelog = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
            .replacingOccurrences(of: "\r\n", with: "\n")
        let heading = try #require(changelog.split(separator: "\n").first { $0.hasPrefix("## ") && $0.dropFirst(3).first?.isNumber == true })
        #expect(heading.dropFirst(3).hasPrefix(DataAge.gpkitVersion + " "), "CHANGELOG's first release heading is \(heading)")
    }
}

/// JSON through Foundation's coder, keys sorted and no spaces, as text.
enum JSONLikeCoder {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }
}

