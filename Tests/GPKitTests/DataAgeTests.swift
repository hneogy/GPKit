import Testing
@testable import GPKit

@Suite struct DataAgeTests {

    @Test func regimesAtTheirBoundaries() throws {
        #expect(try TLE.parse(line1: Sample.line1, line2: Sample.line2).regime == .lowEarth)
        let cases: [(Double, Double, OrbitRegime)] = [
            (15.5, 0.0005, .lowEarth), (11.25, 0.1, .lowEarth), (11.24, 0.1, .mediumEarth),
            (2.0056, 0.01, .mediumEarth), (1.0027, 0.0002, .geosynchronous), (0.99, 0.0, .geosynchronous),
            (1.01, 0.0, .geosynchronous), (1.011, 0.0, .mediumEarth), (0.98, 0.0, .mediumEarth),
            (2.006, 0.72, .highlyElliptical), (15.5, 0.25, .highlyElliptical), (1.0027, 0.3, .highlyElliptical),
        ]
        for (n, e, regime) in cases {
            #expect(OrbitRegime(meanMotion: n, eccentricity: e) == regime, "n \(n), e \(e)")
        }
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
                == ["lowEarth 0.0-1.0 3", "lowEarth 1.0-7.0 1", "mediumEarth 1.0-7.0 1"])
        #expect(table[0].positionError.median == 2)
        // the ISS set a day old is in the first row (the span includes its end), three days old in the second
        #expect(DataAge.estimate(for: base, at: try base.epoch.advanced(by: 86_400), from: table) == table[0])
        #expect(DataAge.estimate(for: base, at: try base.epoch.advanced(by: 3 * 86_400), from: table) == table[1])
        // nothing before the epoch, at it, or past the last span
        #expect(DataAge.estimate(for: base, at: try base.epoch.advanced(by: -60), from: table) == nil)
        #expect(DataAge.estimate(for: base, at: base.epoch, from: table) == nil)
        #expect(DataAge.estimate(for: base, at: try base.epoch.advanced(by: 8 * 86_400), from: table) == nil)
    }
}
