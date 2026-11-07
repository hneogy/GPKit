import Foundation
import Testing
@testable import GPKit

/// The sun's place, the Earth's shadow, the light of a pass, and a satellite's brightness.
///
/// The reference figures are GP Passes' (its SunTests, where each was read from its source on 2026-10-09, UTC):
///
/// - The 2026 equinoxes and solstices: the US Naval Observatory's data service, "Earth's Seasons",
///   https://aa.usno.navy.mil/api/seasons?year=2026 (API 4.0.1), in UT to the minute.
/// - Greenwich mean sidereal time: the same service, https://aa.usno.navy.mil/api/siderealtime with `coords=0,0`,
///   to a ten-thousandth of a second.
/// - The sun's declination, its Greenwich hour angle and its height at a place without the air's bending (`dec`,
///   `gha`, `hc`): the same service's celestial navigation data, https://aa.usno.navy.mil/api/celnav.
/// - The equation of time, the declination and the sun's height at a place: NOAA's Solar Position Calculator,
///   https://gml.noaa.gov/grad/solcalc/azel.html, with the offset to UTC at 0 and no daylight saving. It shows two
///   decimals, cut off and not rounded, and its height has the air's bending in it by the formula in the page's own
///   script.
///
/// The brightness is held to its source's definition: Mallama (2021), "The Brightness of VisorSat-Design Starlink
/// Satellites", arXiv:2101.00374, section 2 and Equation 1, read 2026-11-07.
@Suite struct SunTests {

    static func at(_ text: String) throws -> Epoch { try Epoch(ccsds: text) }

    /// A time of the clock as an angle: fifteen degrees to the hour.
    static func degrees(_ hours: Double, _ minutes: Double, _ seconds: Double) -> Double {
        (hours * 3600 + minutes * 60 + seconds) / 240
    }

    /// An angle brought into 0 up to 360 degrees.
    static func turned(_ angle: Double) -> Double {
        let part = angle.truncatingRemainder(dividingBy: 360)
        return part < 0 ? part + 360 : part
    }

    /// The hours of UTC into an instant's day.
    static func hours(_ time: Epoch) -> Double {
        Double(time.hour) + Double(time.minute) / 60 + Double(time.second) / 3600
    }

    /// The equation of time at an instant, minutes: how far the sun is ahead of a clock that keeps mean time.
    static func equationOfTime(at time: Epoch) -> Double {
        var ahead = Sun.greenwichHourAngle(at: time) - turned(15 * (hours(time) - 12))
        if ahead > 180 { ahead -= 360 }
        if ahead < -180 { ahead += 360 }
        return ahead * 4
    }

    @Test func siderealTimeAtGreenwichMatchesTheNavalObservatorys() throws {
        // (UT1, Greenwich mean sidereal time) as the service gave them
        let given: [(String, Double)] = [
            ("1987-04-10T00:00:00", SunTests.degrees(13, 10, 46.3701)),
            ("1987-04-10T19:21:00", SunTests.degrees(8, 34, 57.0929)),
            ("2026-03-20T14:46:00", SunTests.degrees(2, 38, 35.4683)),
            ("2026-10-08T15:30:00", SunTests.degrees(16, 39, 6.8808)),
        ]
        for (instant, theirs) in given {
            let mine = Sun.greenwichAngle(at: try SunTests.at(instant))
            // SGP4's formula is the one of 1982; the observatory's is the present definition. The two are four
            // thousandths of a second of time apart in these years. Held to a hundredth of a second.
            #expect(abs(mine - theirs) * 240 < 0.01, "\(instant): \(mine) against \(theirs), \((mine - theirs) * 240) s")
        }
    }

    @Test func theSunCrossesTheEquatorAtTheEquinoxesAndStandsHighestAtTheSolstices() throws {
        // the Naval Observatory's instants for 2026. The sun's declination changes by a sixtieth of a degree an hour
        // at an equinox, so five thousandths of a degree hold the formula to these instants within 18 minutes.
        for equinox in ["2026-03-20T14:46:00", "2026-09-23T00:05:00"] {
            let declination = Sun.equatorial(at: try SunTests.at(equinox)).declination
            #expect(abs(declination) < 0.005, "\(equinox): \(declination)")
        }
        for (solstice, rightAscension) in [("2026-06-21T08:24:00", 90.0), ("2026-12-21T20:50:00", 270.0)] {
            let time = try SunTests.at(solstice)
            let sun = Sun.equatorial(at: time)
            #expect(abs(sun.rightAscension - rightAscension) < 0.005, "\(solstice): \(sun.rightAscension)")
            let before = Sun.equatorial(at: try time.advanced(by: -86_400)).declination
            let after = Sun.equatorial(at: try time.advanced(by: 86_400)).declination
            #expect(abs(sun.declination) > abs(before) && abs(sun.declination) > abs(after))
        }
    }

    @Test func theSunsPlaceMatchesTheNavalObservatorys() throws {
        // (UT, latitude, longitude east, declination, Greenwich hour angle, height without the air's bending)
        let given: [(String, Double, Double, Double, Double, Double)] = [
            ("2026-10-08T15:30:00", 40.00, -75.00, -6.052086, 55.625084, 40.606724),
            ("2026-02-11T17:00:00", 40.00, -75.00, -13.858393, 71.456309, 36.040776),
            ("2026-12-21T02:00:00", -33.87, 151.21, -23.435012, 210.535291, 79.453801),
        ]
        for (instant, latitude, longitude, declination, hourAngle, height) in given {
            let time = try SunTests.at(instant)
            let place = Observer(latitude: latitude, longitude: longitude)
            let mine = (declination: Sun.equatorial(at: time).declination, hourAngle: Sun.greenwichHourAngle(at: time),
                        height: Sun.elevation(at: time, from: place))
            #expect(abs(mine.declination - declination) < 0.005, "\(instant): declination \(mine.declination) against \(declination)")
            #expect(abs(mine.hourAngle - hourAngle) < 0.01, "\(instant): hour angle \(mine.hourAngle) against \(hourAngle)")
            #expect(abs(mine.height - height) < 0.005, "\(instant): height \(mine.height) against \(height)")
        }
    }

    @Test func theSunsPlaceMatchesNOAAsCalculator() throws {
        /// What NOAA's page adds to a height for the air's bending, degrees, for a height from 5 to 85 degrees.
        func bending(at height: Double) -> Double {
            let tangent = tan(height * .pi / 180)
            return (58.1 / tangent - 0.07 / pow(tangent, 3) + 0.000086 / pow(tangent, 5)) / 3600
        }
        // (UT, latitude, longitude east, equation of time in minutes, declination, height), each as shown
        let shown: [(String, Double, Double, Double, Double, Double)] = [
            ("2026-09-23T16:52:30", 40.00, -75.00, 7.68, -0.28, 49.74),
            ("2026-11-03T17:00:00", 40.00, -75.00, 16.49, -15.22, 34.67),
            ("2026-02-11T17:00:00", 40.00, -75.00, -14.23, -13.86, 36.06),
            ("2026-06-21T16:00:00", 40.00, -75.00, -1.87, 23.43, 68.92),
            ("2026-12-21T02:00:00", -33.87, 151.21, 2.12, -23.44, 79.45),
        ]
        for (instant, latitude, longitude, equationOfTime, declination, height) in shown {
            let time = try SunTests.at(instant)
            let geometric = Sun.elevation(at: time, from: Observer(latitude: latitude, longitude: longitude))
            let mine = (equationOfTime: SunTests.equationOfTime(at: time), declination: Sun.equatorial(at: time).declination,
                        height: geometric + bending(at: geometric))
            // a figure cut off at two decimals stands for anything from itself to a hundredth more: the middle of
            // that, give or take half a hundredth and a little
            #expect(abs(mine.declination - (declination + 0.005)) < 0.005 + 0.005, "\(instant): declination \(mine.declination) against \(declination)")
            #expect(abs(mine.height - (height + 0.005)) < 0.005 + 0.01, "\(instant): height \(mine.height) against \(height)")
            // The page works its equation of time out by a shorter series than the sun's place, and the two sources
            // are themselves 0.05 of a minute apart (2026 February 11 at 17:00: -14.17 by the observatory's hour
            // angle, -14.23 on the page), so this one is held to 0.06 of a minute.
            #expect(abs(mine.equationOfTime - (equationOfTime + 0.005)) < 0.005 + 0.06, "\(instant): equation of time \(mine.equationOfTime) against \(equationOfTime)")
        }
        // and against the observatory's hour angles, which are the sun's own: within 0.03 of a minute
        for (instant, hourAngle) in [("2026-10-08T15:30:00", 55.625084), ("2026-02-11T17:00:00", 71.456309), ("2026-12-21T02:00:00", 210.535291)] {
            let time = try SunTests.at(instant)
            var theirs = (hourAngle - SunTests.turned(15 * (SunTests.hours(time) - 12))) * 4
            if theirs > 720 { theirs -= 1440 }
            #expect(abs(SunTests.equationOfTime(at: time) - theirs) < 0.03, "\(instant): \(SunTests.equationOfTime(at: time)) against \(theirs)")
        }
    }

    @Test func theDirectionIsOfLengthOneAndTheSunIsOverheadWhereItPointsDown() throws {
        let time = try SunTests.at("2026-10-08T15:30:00")
        #expect(abs(Sun.direction(at: time).magnitude - 1) < 1e-12)
        let declination = Sun.equatorial(at: time).declination
        var longitude = -Sun.greenwichHourAngle(at: time)
        if longitude < -180 { longitude += 360 }
        #expect(Sun.elevation(at: time, from: Observer(latitude: declination, longitude: longitude)) > 89.999)
        let opposite = Observer(latitude: -declination, longitude: longitude > 0 ? longitude - 180 : longitude + 180)
        #expect(Sun.elevation(at: time, from: opposite) < -89.999)
        // half past three in the afternoon at Greenwich: the sun is over the Atlantic, some 55 degrees west
        #expect(longitude < -50 && longitude > -60, "\(longitude)")
    }

    @Test func noonAndMidnightAtAPlace() throws {
        // latitude 40 north, longitude 75 west, on the day of the September equinox: NOAA's calculator puts the sun
        // on that meridian a few seconds before 16:52:30 UTC, 90 less the latitude up, plus its declination
        let place = Observer(latitude: 40, longitude: -75)
        let noonTime = try SunTests.at("2026-09-23T16:52:30")
        let noon = Sun.elevation(at: noonTime, from: place)
        #expect(abs(noon - (50 + Sun.equatorial(at: noonTime).declination)) < 0.01, "\(noon)")
        let before = try noonTime.advanced(by: -300), after = try noonTime.advanced(by: 300)
        #expect(Sun.elevation(at: before, from: place) < noon && Sun.elevation(at: after, from: place) < noon)
        let midnightTime = try SunTests.at("2026-09-23T04:52:30")
        let midnight = Sun.elevation(at: midnightTime, from: place)
        #expect(abs(midnight - (-50 + Sun.equatorial(at: midnightTime).declination)) < 0.01, "\(midnight)")
        #expect(Sunlight.Sky(sunElevation: noon) == .daylight && Sunlight.Sky(sunElevation: midnight) == .dark)
        #expect(Sunlight.Sky(sunElevation: -0.1) == .twilight && Sunlight.Sky(sunElevation: -6) == .twilight && Sunlight.Sky(sunElevation: -6.1) == .dark)
    }

    @Test func theEarthsShadowIsACylinderBehindIt() throws {
        let time = try SunTests.at("2026-10-08T15:30:00")
        let sun = Sun.direction(at: time)
        func point(along: Double, across: Double) -> Vector {
            let side = Vector(x: -sun.y, y: sun.x, z: 0)
            let length = side.magnitude
            return Vector(x: along * sun.x + across * side.x / length, y: along * sun.y + across * side.y / length, z: along * sun.z)
        }
        #expect(Sun.lights(point(along: 6800, across: 0), at: time))
        #expect(Sun.lights(point(along: 0, across: 6800), at: time))
        #expect(!Sun.lights(point(along: -6800, across: 0), at: time))
        #expect(!Sun.lights(point(along: -42_000, across: 3000), at: time))
        #expect(!Sun.lights(point(along: -3000, across: Sun.shadowRadius - 1), at: time))
        #expect(Sun.lights(point(along: -3000, across: Sun.shadowRadius + 1), at: time))
    }

    // MARK: - The light of a pass

    static let place = Observer(latitude: 40.0, longitude: -75.0)

    /// Ten days of the sample ISS's passes over the tutorials' place, with the light of each.
    /// The southern place of the Naval Observatory's figures above.
    static let south = Observer(latitude: -33.87, longitude: 151.21)

    static func tenDays(over place: Observer = place) throws -> (propagator: Propagator, passes: Passes, lights: [PassVisibility?]) {
        let iss = try ElementSets.read(Sample.tle, as: .tle).elementSets[0]
        let propagator = try Propagator(iss)
        let passes = propagator.passes(over: place, from: iss.epoch, for: .seconds(10 * 86_400))
        return (propagator, passes, passes.map { propagator.visibility(of: $0, from: place) })
    }

    @Test func everyPassHasItsLightAndTheStretchesLieInsideOneAnother() throws {
        let (propagator, passes, lights) = try SunTests.tenDays()
        #expect(passes.failure == nil && passes.count > 30)
        var seen = 0, daylight = 0, shadow = 0, partly = 0
        for (pass, light) in zip(passes, lights) {
            let light = try #require(light)
            let start = pass.rise?.time ?? pass.culmination.time, end = pass.set?.time ?? pass.culmination.time
            #expect(light.culmination == (try propagator.sunlight(from: SunTests.place, at: pass.culmination.time)))
            if light.culmination.sky == .daylight {
                daylight += 1
                #expect(!light.canBeSeen)
            }
            guard let sunlit = light.sunlit else {
                shadow += 1
                #expect(light.visible == nil)
                continue
            }
            #expect(sunlit.start >= start && sunlit.end <= end)
            if sunlit.start.seconds(since: start) > 1 || end.seconds(since: sunlit.end) > 1 { partly += 1 }
            if let visible = light.visible {
                seen += 1
                #expect(visible.start >= sunlit.start && visible.end <= sunlit.end)
                // in the middle of the stretch, by the two questions themselves: the satellite lit, the sky dark
                let middle = try visible.start.advanced(by: visible.end.seconds(since: visible.start) / 2)
                #expect(try propagator.sunlight(from: SunTests.place, at: middle).canBeSeen)
            }
        }
        #expect(seen > 0 && daylight > 0 && partly > 0, "\(seen) seen, \(daylight) in daylight, \(shadow) in shadow, \(partly) partly lit, of \(passes.count)")
    }

    @Test func theEdgeOfTheShadowIsFoundToTheSecondAndIsWhereTheSunIsAsFarDownAsTheHorizonDips() throws {
        var edges = 0
        for place in [SunTests.place, SunTests.south] {
        let (propagator, passes, lights) = try SunTests.tenDays(over: place)
        func lit(_ time: Epoch) throws -> Bool { Sun.lights(try propagator.state(at: time).position, at: time) }
        for (pass, light) in zip(passes, lights) {
            guard let rise = pass.rise, let set = pass.set, let sunlit = light?.sunlit else { continue }
            var edge: Epoch?
            if set.time.seconds(since: sunlit.end) > 3 {
                #expect(try lit(sunlit.end.advanced(by: -2)) && !(try lit(sunlit.end.advanced(by: 2))))
                edge = sunlit.end
            }
            if sunlit.start.seconds(since: rise.time) > 3 {
                #expect(try lit(sunlit.start.advanced(by: 2)) && !(try lit(sunlit.start.advanced(by: -2))))
                edge = sunlit.start
            }
            guard let edge else { continue }
            edges += 1
            // by the geometry of the edge: there the sun is as far below the satellite's own horizon, the plane square
            // to its line from the Earth's centre, as that horizon dips to the shadow's radius. The edge is found to
            // a second, in which a low orbit turns about 0.065 degrees round the Earth.
            let r = try propagator.state(at: edge).position, sun = Sun.direction(at: edge)
            let below = asin((r.x * sun.x + r.y * sun.y + r.z * sun.z) / r.magnitude) * 180 / .pi
            let dip = acos(Sun.shadowRadius / r.magnitude) * 180 / .pi
            #expect(abs(below - -dip) < 0.1, "sun \(below), dip \(dip)")
        }
        }
        #expect(edges > 3, "\(edges)")
    }

    // MARK: - Brightness

    @Test func theStandardMagnitudeIsTheBrightnessAtAThousandKilometresAndNinetyDegrees() throws {
        func light(phase: Double, range: Double, lit: Bool = true) -> Sunlight {
            Sunlight(sunElevation: -20, isSunlit: lit, phaseAngle: phase, range: range)
        }
        // the definition (Mallama 2021, section 2): a half-lit sphere at 1000 km is its standard magnitude
        #expect(abs(try #require(light(phase: 90, range: 1000).magnitude(standard: -1.3)) - -1.3) < 1e-12)
        // Equation 1 at B = 0: the whole face lit, 0.753 brighter, to the paper's three decimals
        #expect(abs(try #require(light(phase: 0, range: 1000).magnitude(standard: 4)) - (4 - 0.753)) < 0.0005)
        // the inverse square: ten times the distance is five magnitudes fainter
        #expect(abs(try #require(light(phase: 90, range: 10_000).magnitude(standard: 4)) - 9) < 1e-12)
        // in the Earth's shadow it is not seen at all
        #expect(light(phase: 90, range: 1000, lit: false).magnitude(standard: 4) == nil)
    }

    @Test func thePhaseAngleIsTheAngleAtTheSatellite() throws {
        let (propagator, passes, lights) = try SunTests.tenDays()
        for (pass, light) in zip(passes, lights) {
            guard let light else { continue }
            let time = pass.culmination.time
            // by another road: in the Earth-fixed frame, the satellite as the look has it and the sun turned there
            let julianDate = time.julianDate
            let satellite = Frames.earthFixed(try propagator.state(at: time), julianDate: julianDate).position
            let theta = SGP4Core.gstime(julianDate)
            let teme = Sun.direction(at: time)
            let sun = Vector(x: cos(theta) * teme.x + sin(theta) * teme.y, y: -sin(theta) * teme.x + cos(theta) * teme.y, z: teme.z)
            let site = SunTests.place.earthFixed
            let toPlace = Vector(x: site.x - satellite.x, y: site.y - satellite.y, z: site.z - satellite.z)
            let angle = acos((toPlace.x * sun.x + toPlace.y * sun.y + toPlace.z * sun.z) / toPlace.magnitude) * 180 / .pi
            // the two roads count the instant's Julian date by different sums, a few microseconds apart at most
            #expect(abs(light.culmination.phaseAngle - angle) < 1e-4, "\(light.culmination.phaseAngle) against \(angle)")
            // the range is the look's own, to a metre
            #expect(abs(light.culmination.range - pass.culmination.look.range) < 0.001)
        }
    }
}
