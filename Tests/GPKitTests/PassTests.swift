import Foundation
import Testing
@testable import GPKit
import SGP4Oracle

/// Skyfield's pass predictions for a few public element sets over one fixed place, made by
/// tools/skyfield_passes_reference.py and kept in Resources/skyfield-passes.json.
struct SkyfieldReference: Decodable {
    struct Place: Decodable { let latitude, longitude, height: Double }
    struct Moment: Decodable {
        let time: String
        let elevation, azimuth, range: Double
        let range_rate: Double
        let dut1: Double
        let latitude, longitude, altitude: Double
        let kind: String?
    }
    struct Satellite: Decodable {
        let name, line1, line2, start: String
        let duration: Double
        let events, grid: [Moment]
    }
    let skyfield: String
    let observer: Place
    let minimum_elevation: Double
    let sets: [Satellite]

    static func load() throws -> SkyfieldReference {
        let url = try #require(Bundle.module.url(forResource: "skyfield-passes", withExtension: "json", subdirectory: "Resources"))
        return try JSONDecoder().decode(SkyfieldReference.self, from: Data(contentsOf: url))
    }
}

@Suite struct PropagatorTests {

    @Test func thePublicPropagatorGivesWhatTheCoreGives() throws {
        let set = try TLE.parse(name: Sample.name, line1: Sample.line1, line2: Sample.line2)
        let propagator = try Propagator(set)
        var core = SGP4Core(set)
        for minutes in [0.0, 1.0, 90.0, 1440.0, -1440.0] {
            var r = (0.0, 0.0, 0.0), v = (0.0, 0.0, 0.0)
            _ = core.sgp4(minutes, &r, &v)
            let state = try propagator.state(minutesFromEpoch: minutes)
            #expect(state.position == Vector(x: r.0, y: r.1, z: r.2) && state.velocity == Vector(x: v.0, y: v.1, z: v.2))
        }
        // by instant: a day after the epoch is 1440 minutes from it
        let later = try set.epoch.advanced(by: 86_400)
        #expect(try propagator.state(at: later) == propagator.state(minutesFromEpoch: 1440))
        #expect(try propagator.state(at: set.epoch) == propagator.state(minutesFromEpoch: 0))
        // about 400 km up, about 7.7 km/s
        let state = try propagator.state(minutesFromEpoch: 0)
        #expect((6500...6900).contains(state.position.magnitude))
        #expect((7.4...7.9).contains(state.velocity.magnitude))
    }

    @Test func whatCannotBePropagatedIsRefusedWithItsReason() throws {
        var set = try TLE.parse(line1: Sample.line1, line2: Sample.line2)
        func kind(_ body: () throws -> Void) -> PropagationFailure.Kind? {
            do { try body(); return nil } catch { return (error as? PropagationFailure)?.kind }
        }
        set.meanElementTheory = "DSST"
        #expect(kind { _ = try Propagator(set) } == .notSGP4)
        set.meanElementTheory = "SGP/SGP4"
        set.ephemerisType = 4
        #expect(kind { _ = try Propagator(set) } == .notSGP4)
        set.ephemerisType = 0
        #expect(kind { _ = try Propagator(set).state(minutesFromEpoch: .nan) } == .time)
        // the verification cases that end in an error end in the same one here
        for c in try VerificationCase.all() {
            var e = sgp4oracle_elements()
            var times = [0.0, 0.0, 0.0]
            let oracle = try #require(sgp4oracle_twoline(c.line1, c.line2WithTimes, 1, SGP4Tests.improved, SGP4Tests.wgs72, &e, &times))
            defer { sgp4oracle_free(oracle) }
            let propagator = try Propagator(try TLE.parse(line1: c.line1, line2: c.line2, checksum: .ignore))
            for t in VerificationCase.times(start: times[0], stop: times[1], step: times[2]) {
                var or = [0.0, 0.0, 0.0], ov = [0.0, 0.0, 0.0]
                let code = sgp4oracle_sgp4(oracle, t, &or, &ov)
                let expected: PropagationFailure.Kind? = [1: .eccentricity, 2: .meanMotion, 3: .perturbedEccentricity, 4: .semiLatusRectum, 6: .decayed][Int(code)]
                #expect(kind { _ = try propagator.state(minutesFromEpoch: t) } == expected, "\(c.catalogField) at \(t)")
            }
        }
    }

    @Test func timeArithmeticOnAnEpoch() throws {
        let epoch = try Epoch(ccsds: "2026-09-20T12:42:37.141056")
        #expect(epoch.unixTime == 1_789_908_157.141056)
        #expect(try Epoch(unixTime: 1_789_908_157.141056) == epoch)
        #expect(try Epoch(unixTime: 0).description == "1970-01-01T00:00:00.000000")
        #expect(try epoch.advanced(by: 86_400 - 37.141056).description == "2026-09-21T12:42:00.000000")
        #expect(try epoch.advanced(by: -45_757.141056).description == "2026-09-20T00:00:00.000000")
        #expect(try Epoch(ccsds: "2028-03-01T00:00:00").seconds(since: Epoch(ccsds: "2028-02-28T00:00:00")) == 2 * 86_400)
        #expect(try Epoch(ccsds: "2026-01-01T00:00:00.000001").seconds(since: Epoch(ccsds: "1957-10-04T19:28:34")) > 2.1e9)
        #expect(refusal { _ = try Epoch(unixTime: .infinity) }?.kind == .notAnEpoch)
        #expect(refusal { _ = try epoch.advanced(by: 3.0e11) }?.kind == .notAnEpoch)
    }
}

@Suite struct LookTests {

    @Test func straightUpIsNinetyDegreesAndTheHeightAway() {
        // a satellite 500 km above a place, at rest in the Earth-fixed frame
        for (latitude, longitude) in [(0.0, 0.0), (40.0, -75.0), (-33.9, 151.2), (89.0, 10.0)] {
            let place = Observer(latitude: latitude, longitude: longitude, height: 0)
            let above = Observer(latitude: latitude, longitude: longitude, height: 500_000).earthFixed
            let look = Frames.look(from: place, to: StateVector(position: above, velocity: Vector(x: 0, y: 0, z: 0)))
            #expect(abs(look.elevation - 90) < 1.0e-6)
            #expect(abs(look.range - 500) < 1.0e-9)
            #expect(look.rangeRate == 0)
        }
        // exactly overhead and exactly underfoot, where rounding must not take the elevation out of its range
        let pole = Observer(latitude: 90, longitude: 0)
        let still = Vector(x: 0, y: 0, z: 0)
        #expect(abs(Frames.look(from: pole, to: StateVector(position: Vector(x: 0, y: 0, z: 7000), velocity: still)).elevation - 90) < 1.0e-12)
        #expect(abs(Frames.look(from: pole, to: StateVector(position: Vector(x: 0, y: 0, z: -7000), velocity: still)).elevation + 90) < 1.0e-12)
        // due north on the horizon plane from the equator: a point straight up the z axis from the place
        let equator = Observer(latitude: 0, longitude: 0)
        let site = equator.earthFixed
        let north = Frames.look(from: equator, to: StateVector(position: Vector(x: site.x, y: 0, z: 1000), velocity: Vector(x: 0, y: 0, z: 1)))
        #expect(abs(north.azimuth) < 1.0e-9 && abs(north.elevation) < 1.0e-9 && abs(north.range - 1000) < 1.0e-9)
        #expect(abs(north.rangeRate - 1) < 1.0e-12)
        let east = Frames.look(from: equator, to: StateVector(position: Vector(x: site.x, y: 1000, z: 0), velocity: Vector(x: 0, y: -2, z: 0)))
        #expect(abs(east.azimuth - 90) < 1.0e-9 && abs(east.rangeRate + 2) < 1.0e-12)
    }

    @Test func dopplerForADownlinkAndAnUplink() {
        // approaching at 7 km/s: a 437 MHz downlink arrives about 10.2 kHz high
        let approaching = Look(azimuth: 0, elevation: 10, range: 2000, rangeRate: -7)
        let downlink = 437_000_000.0
        #expect(abs(approaching.received(from: downlink) - downlink - 10_203.7) < 0.1)
        // and to arrive at the satellite on its uplink frequency, the same shift is taken off what is sent
        let uplink = 145_900_000.0
        #expect(approaching.transmit(toBeReceivedAt: uplink) < uplink)
        #expect(abs(approaching.received(from: approaching.transmit(toBeReceivedAt: uplink)) - uplink) < 1.0e-6)
        let receding = Look(azimuth: 0, elevation: 10, range: 2000, rangeRate: 7)
        #expect(receding.received(from: downlink) < downlink)
        #expect(Look(azimuth: 0, elevation: 90, range: 400, rangeRate: 0).received(from: downlink) == downlink)
    }
}

@Suite struct PassTests {

    /// Skyfield's events gathered into passes: a rise if there is one, every culmination, a set if there is one.
    static func skyfieldPasses(_ events: [SkyfieldReference.Moment]) -> [(rise: SkyfieldReference.Moment?, culminations: [SkyfieldReference.Moment], set: SkyfieldReference.Moment?)] {
        var passes: [(rise: SkyfieldReference.Moment?, culminations: [SkyfieldReference.Moment], set: SkyfieldReference.Moment?)] = []
        var open = false
        for event in events {
            if event.kind == "rise" || !open {
                passes.append((nil, [], nil))
                open = true
            }
            switch event.kind {
            case "rise": passes[passes.count - 1].rise = event
            case "culmination": passes[passes.count - 1].culminations.append(event)
            default:
                passes[passes.count - 1].set = event
                open = false
            }
        }
        return passes
    }

    /// GPKit's passes against Skyfield's, pass for pass, and GPKit's look against Skyfield's at Skyfield's times.
    ///
    /// The two list a pass a little differently, and the comparison allows for both differences. Skyfield gives
    /// every peak of the elevation as a culmination, and GPKit the highest: a Molniya's pass here has two. And for
    /// a pass still rising when the search ends Skyfield gives no culmination, where GPKit gives the highest point
    /// inside the search, which is its end.
    @Test func passesAgreeWithSkyfield() throws {
        let reference = try SkyfieldReference.load()
        let place = Observer(latitude: reference.observer.latitude, longitude: reference.observer.longitude, height: reference.observer.height)
        var worstCrossing = 0.0, worstCulmination = 0.0
        var worstElevation = 0.0, worstAzimuth = 0.0, worstRange = 0.0, worstRate = 0.0
        var crossings = 0, culminations = 0, passCount = 0, looks = 0
        // the same four with the Earth turned by Skyfield's UT1 in place of UTC
        var ut1Elevation = 0.0, ut1Azimuth = 0.0, ut1Range = 0.0, ut1Rate = 0.0, largestDUT1 = 0.0
        for satellite in reference.sets {
            let set = try TLE.parse(name: satellite.name, line1: satellite.line1, line2: satellite.line2)
            let propagator = try Propagator(set)
            let start = try Epoch(ccsds: satellite.start)
            let end = try start.advanced(by: satellite.duration)
            let mine = propagator.passes(over: place, from: start, for: .seconds(satellite.duration), above: reference.minimum_elevation)
            #expect(mine.failure == nil)
            let theirs = PassTests.skyfieldPasses(satellite.events)
            #expect(mine.count == theirs.count, "\(satellite.name): \(mine.count) passes, Skyfield has \(theirs.count)")
            guard mine.count == theirs.count else { continue }
            passCount += mine.count
            var here = 0.0
            for (pass, other) in zip(mine, theirs) {
                #expect((pass.rise == nil) == (other.rise == nil) && (pass.set == nil) == (other.set == nil), "\(satellite.name): a pass has a rise or a set on one side only")
                if let rise = pass.rise, let theirRise = other.rise {
                    let d = abs(rise.time.seconds(since: try Epoch(ccsds: theirRise.time)))
                    worstCrossing = max(worstCrossing, d)
                    here = max(here, d)
                    crossings += 1
                }
                if let set = pass.set, let theirSet = other.set {
                    let d = abs(set.time.seconds(since: try Epoch(ccsds: theirSet.time)))
                    worstCrossing = max(worstCrossing, d)
                    here = max(here, d)
                    crossings += 1
                }
                if let highest = other.culminations.max(by: { $0.elevation < $1.elevation }) {
                    let d = abs(pass.culmination.time.seconds(since: try Epoch(ccsds: highest.time)))
                    worstCulmination = max(worstCulmination, d)
                    here = max(here, d)
                    #expect(abs(pass.culmination.look.elevation - highest.elevation) < 0.01, "\(satellite.name)")
                    culminations += 1
                } else {
                    // Skyfield has no culmination for it: the pass is cut off, and GPKit's highest point is the cut
                    #expect(pass.culmination.time == start || pass.culmination.time == end, "\(satellite.name)")
                }
            }
            for moment in satellite.events + satellite.grid {
                let look = try propagator.look(from: place, at: try Epoch(ccsds: moment.time))
                worstElevation = max(worstElevation, abs(look.elevation - moment.elevation))
                var azimuth = abs(look.azimuth - moment.azimuth)
                if azimuth > 180 { azimuth = 360 - azimuth }
                worstAzimuth = max(worstAzimuth, azimuth * cos(moment.elevation * .pi / 180))   // as an angle on the sky
                worstRange = max(worstRange, abs(look.range - moment.range))
                worstRate = max(worstRate, abs(look.rangeRate - moment.range_rate))
                looks += 1
                let minutes = try Epoch(ccsds: moment.time).seconds(since: set.epoch) / 60.0
                let turned = try propagator.look(from: place, minutes: minutes, ut1LessUTC: moment.dut1)
                ut1Elevation = max(ut1Elevation, abs(turned.elevation - moment.elevation))
                var turnedAzimuth = abs(turned.azimuth - moment.azimuth)
                if turnedAzimuth > 180 { turnedAzimuth = 360 - turnedAzimuth }
                ut1Azimuth = max(ut1Azimuth, turnedAzimuth * cos(moment.elevation * .pi / 180))
                ut1Range = max(ut1Range, abs(turned.range - moment.range))
                ut1Rate = max(ut1Rate, abs(turned.rangeRate - moment.range_rate))
                largestDUT1 = max(largestDUT1, abs(moment.dut1))
            }
            print("passes, \(satellite.name): \(mine.count) passes as Skyfield has them; largest time difference \(here) s")
        }
        print("passes against Skyfield \(reference.skyfield): \(reference.sets.count) element sets over \(reference.observer.latitude), \(reference.observer.longitude), "
              + "\(passCount) passes; \(crossings) rises and sets within \(worstCrossing) s, \(culminations) culminations within \(worstCulmination) s")
        print("look against Skyfield at \(looks) of its times: elevation within \(worstElevation) degrees, azimuth within \(worstAzimuth) degrees on the sky, "
              + "range within \(worstRange * 1000) m, range rate within \(worstRate * 1000) m/s")
        print("look against Skyfield with the Earth turned by its UT1 less UTC (up to \(largestDUT1) s here): elevation within \(ut1Elevation) degrees, "
              + "azimuth within \(ut1Azimuth) degrees on the sky, range within \(ut1Range * 1000) m, range rate within \(ut1Rate * 1000) m/s")
        #expect(passCount == 49 && crossings == 95 && culminations == 47)
        // nearly all of the difference is UT1 less UTC: with it applied the two agree some hundred times closer
        #expect(ut1Elevation < 0.0005 && ut1Azimuth < 0.0005 && ut1Range < 0.005 && ut1Rate < 0.0001)
        // the gate: within a few seconds. Skyfield's own search stops within half a second of an event.
        #expect(worstCrossing < 2.0)
        #expect(worstCulmination < 2.0)
        #expect(worstElevation < 0.02 && worstAzimuth < 0.02)
        #expect(worstRange < 0.5 && worstRate < 0.005)
    }

    @Test func aPassUnderWayAtEitherEndHasNoRiseOrNoSet() throws {
        let reference = try SkyfieldReference.load()
        let place = Observer(latitude: reference.observer.latitude, longitude: reference.observer.longitude, height: reference.observer.height)
        let satellite = reference.sets[0]
        let propagator = try Propagator(try TLE.parse(line1: satellite.line1, line2: satellite.line2))
        let start = try Epoch(ccsds: satellite.start)
        let first = try #require(propagator.passes(over: place, from: start, for: .seconds(satellite.duration)).first)
        let rise = try #require(first.rise), set = try #require(first.set)
        #expect(rise.time < first.culmination.time && first.culmination.time < set.time)
        #expect(abs(rise.look.elevation) < 0.01 && abs(set.look.elevation) < 0.01)
        #expect(first.culmination.look.elevation > rise.look.elevation)
        #expect(rise.look.rangeRate < 0 && set.look.rangeRate > 0)
        #expect(abs(first.culmination.look.rangeRate) < 0.2)   // closest about when highest
        // a search that begins at the culmination and ends before the set: one pass, with neither end
        let middle = first.culmination.time
        let inside = propagator.passes(over: place, from: middle, for: .seconds(30))
        #expect(inside.count == 1 && inside[0].rise == nil && inside[0].set == nil)
        // from the culmination to after the set: no rise
        let tail = propagator.passes(over: place, from: middle, for: .seconds(3600))
        #expect(tail.first?.rise == nil && tail.first?.set != nil)
        // a higher threshold gives a shorter pass, inside the first, or none
        let high = propagator.passes(over: place, from: start, for: .seconds(satellite.duration), above: 10)
        let highFirst = try #require(high.first?.rise)
        #expect(highFirst.time > rise.time)
        #expect(propagator.passes(over: place, from: start, for: .seconds(satellite.duration), above: 89.9).isEmpty)
        // nothing to search: no passes, and nothing failed
        for none in [Duration.zero, .seconds(-60)] {
            let found = propagator.passes(over: place, from: start, for: none)
            #expect(found.isEmpty && found.failure == nil)
        }
        // a span that is not a whole number of seconds is searched to its end: the pass is cut where the span is
        let cut = propagator.passes(over: place, from: middle, for: .milliseconds(12_345))
        #expect(cut.count == 1 && cut[0].set == nil)
        #expect(cut[0].culmination.time.seconds(since: middle) <= 12.345)
        // the result is a collection of its passes
        let all = propagator.passes(over: place, from: start, for: .seconds(satellite.duration))
        #expect(all.count == Array(all).count && all.first == all[0] && all.last == all[all.count - 1])
        #expect(all.indices == 0..<all.count && all.map(\.culmination.time) == all.map(\.culmination.time).sorted())
    }

    @Test func aPassShorterThanTheSamplingStepIsFound() throws {
        // a threshold just under a pass's highest point leaves a few seconds above it
        let reference = try SkyfieldReference.load()
        let place = Observer(latitude: reference.observer.latitude, longitude: reference.observer.longitude, height: reference.observer.height)
        let satellite = reference.sets[0]
        let propagator = try Propagator(try TLE.parse(line1: satellite.line1, line2: satellite.line2))
        let start = try Epoch(ccsds: satellite.start)
        let first = try #require(propagator.passes(over: place, from: start, for: .seconds(86_400)).first)
        let threshold = first.culmination.look.elevation - 0.002
        let brief = propagator.passes(over: place, from: start, for: .seconds(86_400), above: threshold).filter { $0.rise != nil && $0.set != nil }
        let found = try #require(brief.first { abs($0.culmination.time.seconds(since: first.culmination.time)) < 1 })
        let length = try #require(found.set).time.seconds(since: try #require(found.rise).time)
        #expect(length > 0 && length < 30, "\(length) s")
    }

    /// The verification element set with this catalog field.
    static func verification(_ catalog: String) throws -> Propagator {
        let c = try #require(try VerificationCase.all().first { $0.catalogField == catalog })
        return try Propagator(try TLE.parse(line1: c.line1, line2: c.line2, checksum: .ignore))
    }

    /// 22312 is one of the verification sets that ends in an error: its mean eccentricity leaves SGP4's range a
    /// little over eight hours after its epoch, and stays out.
    @Test func aSearchThatMeetsAFailureKeepsWhatItFound() throws {
        let propagator = try PassTests.verification("22312")
        let epoch = propagator.elementSet.epoch
        // a place the satellite goes straight over hours before the failure, and one it is over when the failure comes
        var lastMinute = 0.0
        while (try? propagator.state(minutesFromEpoch: lastMinute + 1)) != nil { lastMinute += 1 }
        #expect(lastMinute == 489)
        for minutes in [200.0, lastMinute] {
            let beneath = try propagator.position(at: epoch.advanced(by: minutes * 60))
            let place = Observer(latitude: beneath.latitude, longitude: beneath.longitude)
            let found = propagator.passes(over: place, from: epoch, for: .seconds(86_400))
            let failure = try #require(found.failure)
            let failedAt = try #require(failure.minutesFromEpoch)
            #expect(failure.kind == .eccentricity)
            // the search samples every half minute: it failed at the first sample that cannot be propagated to
            #expect(failedAt == failedAt.rounded(.down) || failedAt == failedAt.rounded(.down) + 0.5)
            #expect((try? propagator.state(minutesFromEpoch: failedAt)) == nil)
            #expect((try? propagator.state(minutesFromEpoch: failedAt - 0.5)) != nil)
            // and what it found is what a search that ends at the last sample that worked finds
            let short = propagator.passes(over: place, from: epoch, for: .seconds((failedAt - 0.5) * 60))
            #expect(short.failure == nil)
            #expect(!found.isEmpty && Array(found) == Array(short))
            #expect(found.contains { abs($0.culmination.time.seconds(since: epoch) / 60 - minutes) < 1 && $0.culmination.look.elevation > 80 })
            let last = try #require(found.last)
            if minutes == lastMinute {
                // the pass under way when the failure came: it rose, it has no set, and its highest point is no later
                // than the last sample that worked, to the millisecond an event's time is given to
                #expect(last.rise != nil && last.set == nil)
                #expect(last.culmination.time.seconds(since: epoch) <= (failedAt - 0.5) * 60 + 0.001)
                #expect(found.dropLast().allSatisfy { $0.set != nil })
            }
            print("a search that met a failure, 22312 over the point beneath it at \(minutes) minutes: \(found.count) passes kept, "
                  + "the last \(last.set == nil ? "under way" : "complete"); stopped at \(failedAt) minutes: \(failure)")
        }
    }

    @Test func aSearchStopsAtTheFirstFailureAndSaysWhichOne() throws {
        // 33334 cannot be propagated at all: no passes, and the reason
        let never = try PassTests.verification("33334")
        let nothing = never.passes(over: Observer(latitude: 0, longitude: 0), from: never.elementSet.epoch, for: .seconds(3600))
        #expect(nothing.isEmpty && nothing.failure?.kind == .perturbedEccentricity && nothing.failure?.minutesFromEpoch == 0)
        // 29141, in the last stage of decay, comes out below the ground at times and above it again later. The
        // search stops at the first such time: nothing after it is looked at.
        let decaying = try PassTests.verification("29141")
        let epoch = decaying.elementSet.epoch
        #expect((try? decaying.state(minutesFromEpoch: 3000)) != nil)
        let found = decaying.passes(over: Observer(latitude: 40, longitude: -75), from: epoch, for: .seconds(3 * 86_400))
        let failedAt = try #require(found.failure?.minutesFromEpoch)
        #expect(found.failure?.kind == .decayed && failedAt > 422 && failedAt <= 423)
        #expect(found.allSatisfy { $0.culmination.time.seconds(since: epoch) / 60 < failedAt })
        // a start or a span that cannot be counted is a failure too, with no time to give
        let far = decaying.passes(over: Observer(latitude: 0, longitude: 0), from: try Epoch(ccsds: "9999-12-31T00:00:00"), for: .seconds(2 * 86_400))
        #expect(far.isEmpty && far.failure?.kind == .time && far.failure?.minutesFromEpoch == nil)
        let long = decaying.passes(over: Observer(latitude: 0, longitude: 0), from: epoch, for: .seconds(Int64.max))
        #expect(long.isEmpty && long.failure?.kind == .time)
    }
}
