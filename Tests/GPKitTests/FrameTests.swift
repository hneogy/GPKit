import Foundation
import Testing
@testable import GPKit

/// Skyfield's Earth-fixed states and right ascensions for the pass-check sets, made by
/// tools/skyfield_frames_reference.py and kept in Resources/skyfield-frames.json.
struct SkyfieldFrames: Decodable {
    struct Moment: Decodable {
        let time: String
        let dut1: Double
        let position, velocity: [Double]
        let right_ascension, declination, range: Double
    }
    struct Satellite: Decodable {
        let name, line1, line2: String
        let grid: [Moment]
    }
    let skyfield: String
    let observer: SkyfieldReference.Place
    let sets: [Satellite]

    static func load() throws -> SkyfieldFrames {
        let url = try #require(Bundle.module.url(forResource: "skyfield-frames", withExtension: "json", subdirectory: "Resources"))
        return try JSONDecoder().decode(SkyfieldFrames.self, from: Data(contentsOf: url))
    }
}

@Suite struct FrameTests {

    static func distance(_ a: Vector, _ b: [Double]) -> Double {
        ((a.x - b[0]) * (a.x - b[0]) + (a.y - b[1]) * (a.y - b[1]) + (a.z - b[2]) * (a.z - b[2])).squareRoot()
    }

    /// The angle between two directions on the sky, degrees.
    static func separation(_ a: EquatorialPosition, _ rightAscension: Double, _ declination: Double) -> Double {
        let r = Double.pi / 180
        let cosine = sin(a.declination * r) * sin(declination * r)
            + cos(a.declination * r) * cos(declination * r) * cos((a.rightAscension - rightAscension) * r)
        return acos(min(1, max(-1, cosine))) / r
    }

    @Test func theEarthFixedStateAgreesWithSkyfield() throws {
        let reference = try SkyfieldFrames.load()
        var position = 0.0, velocity = 0.0, ut1Position = 0.0, ut1Velocity = 0.0, count = 0
        for satellite in reference.sets {
            let propagator = try Propagator(try TLE.parse(line1: satellite.line1, line2: satellite.line2))
            for moment in satellite.grid {
                let time = try Epoch(ccsds: moment.time)
                let minutes = time.seconds(since: propagator.elementSet.epoch) / 60
                let mine = try propagator.earthFixedState(at: time)
                #expect(mine == (try propagator.earthFixed(minutes: minutes, ut1LessUTC: 0)))
                position = max(position, FrameTests.distance(mine.position, moment.position))
                velocity = max(velocity, FrameTests.distance(mine.velocity, moment.velocity))
                // with the Earth turned by Skyfield's UT1 less UTC, the frames themselves are compared
                let turned = try propagator.earthFixed(minutes: minutes, ut1LessUTC: moment.dut1)
                ut1Position = max(ut1Position, FrameTests.distance(turned.position, moment.position))
                ut1Velocity = max(ut1Velocity, FrameTests.distance(turned.velocity, moment.velocity))
                count += 1
            }
        }
        print("Earth-fixed state against Skyfield \(reference.skyfield) at \(count) times: position within \(position * 1000) m, velocity within \(velocity * 1000) m/s; "
            + "with UT1: position within \(ut1Position * 1000) m, velocity within \(ut1Velocity * 1000) m/s")
        // UT1 less UTC is up to 0.24 s for these sets' dates: in that time the Earth turns 1.7e-5 radians, some 120 m
        // at the ISS's distance and more at the Molniya's apogee, and a velocity of 10 km/s turns 0.17 m/s. As
        // found: 336 m and 0.13 m/s. Held to a kilometre and a metre a second.
        #expect(position < 1.0 && velocity < 0.001)
        // the same rotation, but for Skyfield's way to its Earth-fixed frame through the celestial one: as found,
        // 9 cm and 0.04 mm/s. Held to 20 cm and 0.1 mm/s.
        #expect(ut1Position < 0.0002 && ut1Velocity < 1.0e-7)
    }

    @Test func theRightAscensionAndDeclinationAgreeWithSkyfield() throws {
        let reference = try SkyfieldFrames.load()
        let place = Observer(latitude: reference.observer.latitude, longitude: reference.observer.longitude, height: reference.observer.height)
        var worst = 0.0, ut1Worst = 0.0, count = 0
        for satellite in reference.sets {
            let propagator = try Propagator(try TLE.parse(line1: satellite.line1, line2: satellite.line2))
            for moment in satellite.grid {
                let time = try Epoch(ccsds: moment.time)
                let minutes = time.seconds(since: propagator.elementSet.epoch) / 60
                let mine = try propagator.equatorial(from: place, at: time)
                #expect((0..<360).contains(mine.rightAscension) && (-90...90).contains(mine.declination))
                worst = max(worst, FrameTests.separation(mine, moment.right_ascension, moment.declination))
                let turned = try propagator.equatorial(from: place, minutes: minutes, ut1LessUTC: moment.dut1)
                ut1Worst = max(ut1Worst, FrameTests.separation(turned, moment.right_ascension, moment.declination))
                count += 1
            }
        }
        print("right ascension and declination from \(place.latitude), \(place.longitude) against Skyfield \(reference.skyfield) at \(count) times: within \(worst) degrees; with UT1: within \(ut1Worst) degrees")
        // as found: 0.0010 degrees, and with UT1 0.00042, which is what is left of the equation of the equinoxes by
        // the sun's terms of nutation against Skyfield's full series
        #expect(worst < 0.005)
        #expect(ut1Worst < 0.001)
    }

    @Test func theGroundTrackIsThePointBeneathAtEachStep() throws {
        let reference = try SkyfieldReference.load()
        for satellite in reference.sets {
            let propagator = try Propagator(try TLE.parse(line1: satellite.line1, line2: satellite.line2))
            // Skyfield's grid: every ten minutes for six hours from the epoch cut to the minute
            let start = try Epoch(ccsds: satellite.grid[0].time)
            let track = propagator.groundTrack(from: start, for: .seconds(6 * 3600), every: .seconds(600))
            #expect(track.failure == nil && track.count == satellite.grid.count)
            for (point, moment) in zip(track, satellite.grid) {
                #expect(point.time == (try Epoch(ccsds: moment.time)))
                #expect(point.position == (try propagator.position(at: point.time)))
                #expect(abs(point.position.latitude - moment.latitude) < 1.0e-4, "\(satellite.name) at \(moment.time)")
                var east = abs(point.position.longitude - moment.longitude)
                if east > 180 { east = 360 - east }
                #expect(east * cos(moment.latitude * .pi / 180) < 0.002, "\(satellite.name) at \(moment.time)")
            }
        }
        let iss = try TLE.parse(name: Sample.name, line1: Sample.line1, line2: Sample.line2)
        let propagator = try Propagator(iss)
        // the start and every step up to the end included; a step longer than the span is the start alone
        #expect(propagator.groundTrack(from: iss.epoch, for: .seconds(60), every: .seconds(20)).count == 4)
        #expect(propagator.groundTrack(from: iss.epoch, for: .seconds(59), every: .seconds(20)).count == 3)
        #expect(propagator.groundTrack(from: iss.epoch, for: .seconds(10), every: .seconds(20)).count == 1)
        #expect(propagator.groundTrack(from: iss.epoch, for: .seconds(0), every: .seconds(20)).isEmpty)
        #expect(propagator.groundTrack(from: iss.epoch, for: .seconds(60), every: .seconds(0)).isEmpty)
        #expect(propagator.groundTrack(from: iss.epoch, for: .seconds(2_000_000), every: .seconds(1)).isEmpty)
    }

    @Test func aGroundTrackStopsWhereTheSetCannotBePropagated() throws {
        // a set whose mean motion makes SGP4 refuse once its orbit has decayed, as in PropagatorTests
        let decaying = try TLE.parse(line1: "1 20453U 90008B   26263.56914166  .00350177  49935-4  75989-3 0  9996",
                                     line2: "2 20453  35.5934 307.3932 0022512 310.3690  49.5094 15.96788691956793")
        let propagator = try Propagator(decaying)
        let track = propagator.groundTrack(from: decaying.epoch, for: .seconds(60 * 86_400), every: .seconds(3600))
        let failure = try #require(track.failure)
        #expect(track.count > 0 && track.count < 60 * 24)
        // the last point is the last hour that could be propagated to, and the failure is at the next
        let last = try #require(track.last)
        #expect(throws: PropagationFailure.self) { _ = try propagator.position(at: try last.time.advanced(by: 3600)) }
        #expect(failure.minutesFromEpoch.map { abs($0 - (last.time.seconds(since: decaying.epoch) + 3600) / 60) < 1e-6 } == true)
    }

    @Test func fromEachPlaceOnTheFootprintTheSatelliteIsAtTheElevationAsked() throws {
        let iss = try TLE.parse(name: Sample.name, line1: Sample.line1, line2: Sample.line2)
        let molniya = try TLE.parse(line1: "1 08195U 75081A   06176.33215444  .00000099  00000-0  11873-3 0   813",
                                    line2: "2 08195  64.1586 279.0717 6877146 264.7651  20.2257  2.00491383225656")
        var worst = 0.0, worstRadius = 0.0
        for set in [iss, molniya] {
            let propagator = try Propagator(set)
            for hours in [0.0, 1.0, 5.0] {
                let time = try set.epoch.advanced(by: hours * 3600)
                let beneath = try propagator.position(at: time)
                for minimum in [0.0, 10.0, 45.0] {
                    let ring = beneath.footprint(minimumElevation: minimum, points: 36)
                    #expect(ring.count == 36)
                    // the textbook ring on a sphere of the equator's radius, an angle round the Earth's centre
                    let radius = Frames.equatorialRadius, r = minimum * .pi / 180
                    let sphere = acos(radius * cos(r) / (radius + beneath.altitude)) - r
                    for place in ring {
                        let look = try propagator.look(from: Observer(latitude: place.latitude, longitude: place.longitude), at: time)
                        worst = max(worst, abs(look.elevation - minimum))
                        #expect(place.altitude == 0 && (-90...90).contains(place.latitude) && place.longitude > -180 && place.longitude <= 180)
                        let p1 = beneath.latitude * .pi / 180, p2 = place.latitude * .pi / 180
                        let angle = acos(min(1, sin(p1) * sin(p2) + cos(p1) * cos(p2) * cos((place.longitude - beneath.longitude) * .pi / 180)))
                        worstRadius = max(worstRadius, abs(angle - sphere) / sphere)
                    }
                }
            }
        }
        print("footprints: the satellite within \(worst) degrees of the elevation asked from every place on them, and their radius within \(worstRadius * 100) % of a sphere's")
        #expect(worst < 1.0e-5)
        // the Earth is not a sphere: the ring is within one per cent of the sphere's
        #expect(worstRadius < 0.01)
        let beneath = GeodeticPosition(latitude: 0, longitude: 179.9, altitude: 420)
        // across the line of 180 degrees, longitudes stay in -180 up to 180
        #expect(beneath.footprint().allSatisfy { $0.longitude > -180 && $0.longitude <= 180 })
        #expect(beneath.footprint().contains { $0.longitude < 0 } && beneath.footprint().contains { $0.longitude > 0 })
        #expect(beneath.footprint(minimumElevation: 90).isEmpty && beneath.footprint(minimumElevation: -1).isEmpty)
        #expect(beneath.footprint(points: 2).isEmpty && GeodeticPosition(latitude: 0, longitude: 0, altitude: 0).footprint().isEmpty)
    }
}
