import Foundation
import Testing
@testable import GPKit

@Suite struct PositionTests {

    /// `Observer.earthFixed` goes from latitude, longitude and height to the Earth-fixed frame by the closed
    /// formula; `Frames.geodetic` has to come back by its own way to where that started.
    @Test func geodeticComesBackFromTheEarthFixedFrame() {
        var worstAngle = 0.0, worstHeight = 0.0, count = 0
        for latitude in [-90.0, -89.9999, -66.5, -45.0, -0.001, 0.0, 0.001, 23.4, 40.0, 51.6, 89.9999, 90.0] {
            for longitude in [-179.999, -135.0, -75.0, -0.001, 0.0, 0.001, 75.0, 135.0, 180.0] {
                for kilometres in [-5.0, 0.0, 0.1, 8.8, 210.0, 420.0, 1500.0, 20_200.0, 35_786.0, 384_400.0] {
                    let r = Observer(latitude: latitude, longitude: longitude, height: kilometres * 1000).earthFixed
                    let back = Frames.geodetic(r)
                    worstAngle = max(worstAngle, abs(back.latitude - latitude))
                    if abs(latitude) < 90 {
                        worstAngle = max(worstAngle, abs(back.longitude - longitude) * cos(latitude * .pi / 180))
                    }
                    worstHeight = max(worstHeight, abs(back.altitude - kilometres))
                    #expect((-90.0...90.0).contains(back.latitude) && back.longitude > -180 && back.longitude <= 180)
                    count += 1
                }
            }
        }
        print("geodetic and back, \(count) points from 5 km under the ellipsoid to the Moon's distance: within \(worstAngle) degrees and \(worstHeight * 1.0e6) mm")
        #expect(worstAngle < 1.0e-11)
        #expect(worstHeight < 1.0e-9)    // a thousandth of a millimetre
        // the west end of the range of longitude is given as the east end, and the centre of the Earth is no trouble
        #expect(Frames.geodetic(Vector(x: -7000, y: -0.0, z: 0)).longitude == 180)
        let centre = Frames.geodetic(Vector(x: 0, y: 0, z: 0))
        #expect(centre.latitude == 0 && centre.longitude == 0 && centre.altitude == -Frames.equatorialRadius)
        let pole = Frames.geodetic(Vector(x: 0, y: 0, z: 7000))
        #expect(pole.latitude == 90 && abs(pole.altitude - (7000 - 6356.752314245179)) < 1.0e-9)
    }

    /// From the point beneath it, a satellite is straight up and its altitude away.
    @Test func thePointBeneathLooksStraightUp() throws {
        let reference = try SkyfieldReference.load()
        for satellite in reference.sets {
            let propagator = try Propagator(try TLE.parse(line1: satellite.line1, line2: satellite.line2))
            for moment in satellite.grid {
                let time = try Epoch(ccsds: moment.time)
                let beneath = try propagator.position(at: time)
                let look = try propagator.look(from: Observer(latitude: beneath.latitude, longitude: beneath.longitude), at: time)
                #expect(look.elevation > 89.99999, "\(satellite.name) at \(moment.time): \(look.elevation)")
                #expect(abs(look.range - beneath.altitude) < 1.0e-6, "\(satellite.name) at \(moment.time)")
            }
        }
        // the Space Station's first element set: within its inclination of the equator, a few hundred kilometres up
        let set = try TLE.parse(name: Sample.name, line1: Sample.line1, line2: Sample.line2)
        let propagator = try Propagator(set)
        var track: [GeodeticPosition] = []
        for minute in 0..<93 {
            track.append(try propagator.position(at: set.epoch.advanced(by: Double(minute) * 60)))
        }
        #expect(track.allSatisfy { abs($0.latitude) < 51.8 && (150.0...450.0).contains($0.altitude) })
        #expect(track.map(\.latitude).max()! > 51.0 && track.map(\.latitude).min()! < -51.0)
        #expect(try propagator.position(at: set.epoch) == propagator.position(minutes: 0))
    }

    /// GPKit's point beneath a satellite against Skyfield's, at Skyfield's times.
    @Test func thePointBeneathAgreesWithSkyfield() throws {
        let reference = try SkyfieldReference.load()
        var latitude = 0.0, longitude = 0.0, altitude = 0.0, count = 0
        var ut1Latitude = 0.0, ut1Longitude = 0.0, ut1Altitude = 0.0
        for satellite in reference.sets {
            let set = try TLE.parse(line1: satellite.line1, line2: satellite.line2)
            let propagator = try Propagator(set)
            for moment in satellite.events + satellite.grid {
                let time = try Epoch(ccsds: moment.time)
                func east(_ a: Double) -> Double {
                    var d = abs(a - moment.longitude)
                    if d > 180 { d = 360 - d }
                    return d * cos(moment.latitude * .pi / 180)     // as an angle on the ground
                }
                let mine = try propagator.position(at: time)
                latitude = max(latitude, abs(mine.latitude - moment.latitude))
                longitude = max(longitude, east(mine.longitude))
                altitude = max(altitude, abs(mine.altitude - moment.altitude))
                let turned = try propagator.position(minutes: time.seconds(since: set.epoch) / 60.0, ut1LessUTC: moment.dut1)
                ut1Latitude = max(ut1Latitude, abs(turned.latitude - moment.latitude))
                ut1Longitude = max(ut1Longitude, east(turned.longitude))
                ut1Altitude = max(ut1Altitude, abs(turned.altitude - moment.altitude))
                count += 1
            }
        }
        print("point beneath against Skyfield \(reference.skyfield) at \(count) of its times: latitude within \(latitude) degrees, "
              + "longitude within \(longitude) degrees on the ground, altitude within \(altitude * 1000) m")
        print("point beneath against Skyfield with the Earth turned by its UT1 less UTC: latitude within \(ut1Latitude) degrees, "
              + "longitude within \(ut1Longitude) degrees on the ground, altitude within \(ut1Altitude * 1000) m")
        #expect(count == 329)
        #expect(latitude < 0.0001 && longitude < 0.002 && altitude < 0.001)
        #expect(ut1Latitude < 2.0e-6 && ut1Longitude < 2.0e-6 && ut1Altitude < 0.0001)
    }
}

@Suite struct DateTests {

    @Test func toAndFromFoundationsDate() throws {
        let epoch = try Epoch(ccsds: "2026-09-20T12:42:37.141056")
        #expect(try Epoch(Date(timeIntervalSince1970: 1_789_908_157.141056)) == epoch)
        #expect(abs(epoch.date.timeIntervalSince1970 - 1_789_908_157.141056) < 1.0e-6)
        #expect(try Epoch(Date(timeIntervalSinceReferenceDate: 0)).description == "2001-01-01T00:00:00.000000")
        #expect(try Epoch(Date(timeIntervalSince1970: -0.25)).description == "1969-12-31T23:59:59.750000")
        #expect(try Epoch(ccsds: "2001-01-01T00:00:00").date.timeIntervalSinceReferenceDate == 0)
        // Foundation's own calendar reads the Date as the same UTC date and time
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        for text in ["1957-10-04T19:28:34", "1998-11-20T06:49:59", "2000-02-29T23:59:59", "2026-10-06T00:00:00", "2056-12-31T12:00:00"] {
            #expect(try formatter.string(from: Epoch(ccsds: text).date) == text + "Z")
            #expect(try Epoch(try #require(formatter.date(from: text + "Z"))).description == text + ".000000")
        }
        // an epoch of whole microseconds, which is what a TLE holds, comes back from a Date as itself
        for text in ["1998-11-20T06:49:59.999808", "2026-09-20T12:42:37.141056", "1957-10-04T19:28:34.000001", "2056-12-31T23:59:59.999999"] {
            let epoch = try Epoch(ccsds: text)
            #expect(try Epoch(epoch.date) == epoch, "\(text)")
        }
        // a leap second has no count of its own in a Date: it is the second after
        #expect(try Epoch(ccsds: "2016-12-31T23:59:60.5").date == Epoch(ccsds: "2017-01-01T00:00:00.5").date)
        #expect(try Epoch(.now).year >= 2026)
    }

    @Test func aDateOutsideTheYearsAnEpochHoldsIsRefused() throws {
        #expect(try Epoch(Date(timeIntervalSince1970: 253_402_300_799)).description == "9999-12-31T23:59:59.000000")
        #expect(try Epoch(Date(timeIntervalSince1970: -62_135_596_800)).description == "0001-01-01T00:00:00.000000")
        #expect(refusal { _ = try Epoch(Date(timeIntervalSince1970: 253_402_300_800)) }?.kind == .notAnEpoch)
        #expect(refusal { _ = try Epoch(Date(timeIntervalSince1970: -62_135_596_801)) }?.kind == .notAnEpoch)
        #expect(refusal { _ = try Epoch(Date(timeIntervalSinceReferenceDate: .infinity)) }?.kind == .notAnEpoch)
        #expect(refusal { _ = try Epoch(Date(timeIntervalSinceReferenceDate: .nan)) }?.kind == .notAnEpoch)
        // and the same door for a count of Unix time
        #expect(try Epoch(unixTime: 253_402_300_799).description == "9999-12-31T23:59:59.000000")
        #expect(refusal { _ = try Epoch(unixTime: 253_402_300_800) }?.kind == .notAnEpoch)
        #expect(refusal { _ = try Epoch(unixTime: -62_135_596_801) }?.kind == .notAnEpoch)
        #expect(refusal { _ = try Epoch(ccsds: "9999-12-31T23:59:59").advanced(by: 1) }?.kind == .notAnEpoch)
        #expect(try Epoch(ccsds: "9999-12-31T23:59:59").advanced(by: -315_537_897_599).description == "0001-01-01T00:00:00.000000")
    }
}
