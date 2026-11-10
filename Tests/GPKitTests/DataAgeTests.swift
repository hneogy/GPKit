import Testing
@testable import GPKit

@Suite struct DataAgeTests {

    @Test func esasOrbitClassesForKnownOrbits() throws {
        #expect(try TLE.parse(line1: Sample.line1, line2: Sample.line2).regime == .lowEarth)
        // mean motion (rev/day), eccentricity, inclination (degrees): orbits of a known kind
        let cases: [(Double, Double, Double, OrbitRegime, String)] = [
            (15.5, 0.0005, 51.6, .lowEarth, "the ISS"),
            (1.0027, 0.0002, 0.05, .geostationary, "a geostationary satellite"),
            (1.0027, 0.0002, 30, .inclinedGeosynchronous, "a geosynchronous orbit inclined 30 degrees"),
            (1.0027, 0.0002, 14, .geostationary, "a geostationary satellite drifted to 14 degrees: GEO runs to 25"),
            (1.0027, 0.01, 5, .extendedGeostationary, "a geosynchronous orbit too eccentric for GEO's band"),
            (0.95, 0.001, 3, .extendedGeostationary, "a graveyard orbit above GEO"),
            (2.0056, 0.01, 55, .navigationSatellites, "a GPS satellite"),
            (1.7048, 0.0002, 56, .navigationSatellites, "a Galileo satellite"),
            (2.1314, 0.0004, 64.8, .navigationSatellites, "a GLONASS satellite"),
            (2.2557, 0.0010, 25, .mediumEarth, "a navigation-like orbit out of NSO's inclinations"),
            (5.0, 0.0005, 0.04, .mediumEarth, "an O3b satellite"),
            (2.26, 0.73, 27, .geostationaryTransfer, "a transfer orbit's upper stage"),
            (2.006, 0.72, 63.4, .geostationaryTransfer, "a Molniya orbit, by ESA's numbers"),
            (0.25, 0.8, 30, .highlyEccentric, "a long HEO"),
            (0.5, 0.2, 10, .undefined, "beyond 40,000 km all the way round"),
            (0.7765, 0.15, 10, .geoSuperGeoCrossing, "from GEO's height to above it"),
            (1.6, 0.25, 10, .meoGeoCrossing, "from MEO to GEO's height"),
            (8.0, 0.3, 40, .leoMeoCrossing, "from LEO to MEO"),
        ]
        for (n, e, i, regime, what) in cases {
            #expect(OrbitRegime(meanMotion: n, eccentricity: e, inclination: i) == regime, "\(what): n \(n), e \(e), i \(i)")
        }
    }

    @Test func esasRangesAtTheirEnds() {
        // a circular orbit at height h, i degrees: a = R + h, the radius GPKit uses
        func circular(_ h: Double, _ i: Double = 0) -> OrbitRegime {
            OrbitRegime(semiMajorAxis: 6_378.135 + h, eccentricity: 0, inclination: i, radius: 6_378.135)
        }
        #expect(circular(1_999.99) == .lowEarth)
        #expect(circular(2_000.01) == .mediumEarth)         // 2,000 km itself is MEO's too, and MEO is tested first
        #expect(circular(35_586) == .geostationary)
        #expect(circular(35_585.999) == .extendedGeostationary)   // just below GEO's band: a = 41,964 km is in EGO's
        #expect(circular(35_786, 25) == .geostationary)
        #expect(circular(35_786, 25.001) == .inclinedGeosynchronous)
        #expect(circular(20_200, 50) == .navigationSatellites)
        #expect(circular(20_200, 49.999) == .mediumEarth)
        #expect(circular(31_569) == .mediumEarth)            // a = 37,947.1 km, below EGO's
        #expect(circular(31_570.01) == .extendedGeostationary)   // a = 37,948 km and more: EGO, tested before MEO
        #expect(circular(50_000) == .undefined)             // circular beyond 40,000 km: none of the classes
        // from the mean motion, with WGS-72's mu and radius: circular 1,999 and 2,001 km up (a radius of 6,371 km, say,
        // would put both above 2,000)
        #expect(OrbitRegime(meanMotion: 11.322952506624489, eccentricity: 0, inclination: 0) == .lowEarth)
        #expect(OrbitRegime(meanMotion: 11.318898767133655, eccentricity: 0, inclination: 0) == .mediumEarth)
        #expect(OrbitRegime.allCases.map(\.rawValue)
                == ["GEO", "IGO", "EGO", "NSO", "GTO", "MEO", "GHO", "LEO", "HEO", "MGO", "LMO", "UFO"])
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
        let (samples, failures) = DataAge.samples([c, a, b])
        #expect(failures == 0)
        // every pair, older to newer: a to b, a to c, b to c
        #expect(samples.map(\.age) == [1, 2.5, 1.5])
        for (sample, (older, newer)) in zip(samples, [(a, b), (a, c), (b, c)]) {
            let drifted = try Propagator(older).state(at: newer.epoch).position
            let truth = try Propagator(newer).state(at: newer.epoch).position
            let distance = Vector(x: drifted.x - truth.x, y: drifted.y - truth.y, z: drifted.z - truth.z).magnitude
            #expect(sample.positionError == distance)
            #expect(sample.positionError > 0)
            #expect(sample.older == older.epoch && sample.newer == newer.epoch && sample.regime == .lowEarth)
            // the three components make up the whole difference
            let sum = (sample.radial * sample.radial + sample.inTrack * sample.inTrack + sample.crossTrack * sample.crossTrack).squareRoot()
            #expect(abs(sum - sample.positionError) <= 1e-9 * sample.positionError)
        }
    }

    @Test func whatMakesNoSampleIsLeftOut() throws {
        let a = try moved(0)
        // the same epoch twice, no catalog number, one satellite alone, an age beyond the maximum
        #expect(DataAge.samples([a, a]).samples.isEmpty)
        #expect(DataAge.samples([try moved(0, catalog: nil), try moved(1, catalog: nil)]).samples.isEmpty)
        #expect(DataAge.samples([a, try moved(1, catalog: 99999)]).samples.isEmpty)
        #expect(DataAge.samples([a, try moved(31)]).samples.isEmpty)
        #expect(DataAge.samples([a, try moved(31)], maximumAge: 31).samples.count == 1)
        // a pair either set cannot be propagated for is counted, not sampled
        var sgp4XP = a
        sgp4XP.ephemerisType = 4
        let (samples, failures) = DataAge.samples([sgp4XP, try moved(1)])
        #expect(samples.isEmpty && failures == 1)
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

    @Test func aTableAndTheEstimateReadFromIt() throws {
        let base = try moved(0)
        func sample(_ age: Double, _ error: Double, _ regime: OrbitRegime = .lowEarth) throws -> DataAge.Sample {
            DataAge.Sample(catalogNumber: 1, regime: regime, older: base.epoch, newer: try base.epoch.advanced(by: age * 86_400),
                           age: age, positionError: error, radial: 0, inTrack: error, crossTrack: 0)
        }
        let samples = [try sample(0.5, 1), try sample(0.9, 3), try sample(1, 2), try sample(4, 10), try sample(4, 20, .mediumEarth), try sample(40, 99)]
        let table = DataAge.table(samples, edges: [0, 1, 7])
        #expect(table.map { "\($0.regime) \($0.fromAge)-\($0.toAge) \($0.positionError.count)" }
                == ["mediumEarth 1.0-7.0 1", "lowEarth 0.0-1.0 3", "lowEarth 1.0-7.0 1"])
        #expect(table[1].positionError.median == 2)
        // the ISS set a day old is in the first row (the span includes its end), three days old in the second
        #expect(DataAge.estimate(for: base, at: try base.epoch.advanced(by: 86_400), from: table) == table[1])
        #expect(DataAge.estimate(for: base, at: try base.epoch.advanced(by: 3 * 86_400), from: table) == table[2])
        // nothing before the epoch, at it, or past the last span
        #expect(DataAge.estimate(for: base, at: try base.epoch.advanced(by: -60), from: table) == nil)
        #expect(DataAge.estimate(for: base, at: base.epoch, from: table) == nil)
        #expect(DataAge.estimate(for: base, at: try base.epoch.advanced(by: 8 * 86_400), from: table) == nil)
    }
}
