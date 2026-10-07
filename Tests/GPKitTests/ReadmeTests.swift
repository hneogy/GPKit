import Foundation
import Testing
import GPKit

/// The README's examples, compiled and held to the words the README prints.
@Suite struct ReadmeTests {

    @Test func theFirstExample() throws {
        let csv = Sample.csv
        // the three lines as the README has them. The sample is the Space Station's first element set, of 1998, so
        // what they find from today is not looked at: only that they compile and run.
        let iss = try ElementSets.read(csv, as: .csv).elementSets[0]
        let passes = try Propagator(iss).passes(over: Observer(latitude: 40.0, longitude: -75.0), from: Epoch(.now), for: .seconds(86_400))
        if let rise = passes.first?.rise { print(rise.time) }
        // the same from the element set's own epoch, where the first rise is the one Skyfield has for this place
        // (Resources/skyfield-passes.json), and prints as the README says a time prints
        let then = try Propagator(iss).passes(over: Observer(latitude: 40.0, longitude: -75.0), from: iss.epoch, for: .seconds(86_400))
        let rise = try #require(then.first?.rise)
        #expect("\(rise.time)".hasPrefix("1998-11-20T14:05:39."))
        #expect("\(rise.time)".count == "YYYY-MM-DDThh:mm:ss.ffffff".count)
        #expect(then.failure == nil)
        // bytes and Data are read as the String is
        #expect(try ElementSets.read(Data(csv.utf8), as: .csv).elementSets[0] == iss)
        #expect(try ElementSets.read(Array(csv.utf8), as: .csv).elementSets[0] == iss)
    }

    @Test func reading() throws {
        let bytes = Array(("[" + Sample.jsonRecord() + "," + Sample.jsonRecord(catalog: "\"A0000\"") + "]").utf8)
        let file = try ElementSets.read(bytes, as: .json)
        for set in file.elementSets {
            #expect(set.catalogNumber == 25_544)
            #expect(set.objectID == "1998-067A")
            #expect("\(set.epoch)" == "1998-11-20T06:49:59.999808")
            #expect("\(set.meanMotion)" == "16.05064833")
            #expect(set.meanMotion.double == 16.05064833)
        }
        #expect(file.elementSets.count == 1 && file.refusals.count == 1)
        for refusal in file.refusals {
            #expect("\(refusal)" == "NORAD_CAT_ID \"A0000\" is not an integer of up to nine digits (record 2 of the file)")
            #expect(refusal.kind == .catalogNumber)
            #expect(refusal.field == "NORAD_CAT_ID")
            #expect(refusal.text == "A0000")
        }
    }

    @Test func theSameValueFromThreeSources() throws {
        let fromTLE = try TLE.parse(line1: withChecksum(replacing(Sample.line1, 53..<61, with: " 15975-3")), line2: Sample.line2).bstar
        #expect(ExactDecimal(".15975E-3") == fromTLE)
        #expect(ExactDecimal("0.00015975") == fromTLE)
    }

    @Test func writing() throws {
        var set = try only(Sample.json, .json)
        set.catalogNumber = 100_000
        let lines = try TLE.write(set)
        #expect(lines.line1.hasPrefix("1 A0000U "))
        #expect(lines.text.split(separator: "\n").count == 3)
        #expect(try TLE.write(set, eccentricity: .truncated).line2 == lines.line2)
    }

    @Test func propagatingAndPasses() throws {
        let set = try TLE.parse(name: Sample.name, line1: Sample.line1, line2: Sample.line2)
        let propagator = try Propagator(set)
        let time = try set.epoch.advanced(by: 5400)
        let state = try propagator.state(at: time)
        #expect(state.position.magnitude > 6000 && state.velocity.magnitude > 7)
        #expect(try propagator.state(minutesFromEpoch: 90) == state)

        let home = Observer(latitude: 40.0, longitude: -75.0, height: 100)
        let now = set.epoch
        let beneath = try propagator.position(at: time)
        #expect(abs(beneath.latitude) < 52 && beneath.longitude > -180 && beneath.longitude <= 180 && beneath.altitude > 150)

        let passes = propagator.passes(over: home, from: now, for: .seconds(86_400))
        #expect(!passes.isEmpty && passes.failure == nil)
        for pass in passes {
            #expect((pass.rise?.time ?? now) <= pass.culmination.time)
            #expect(pass.culmination.look.elevation >= 0)
            if let azimuth = pass.set?.look.azimuth { #expect((0..<360).contains(azimuth)) }
        }
        let look = try propagator.look(from: home, at: now)
        #expect((0..<360).contains(look.azimuth) && (-90...90).contains(look.elevation) && look.range > 0)
        #expect(abs(look.received(from: 437_000_000) - 437_000_000) < 12_000)
        #expect(abs(look.transmit(toBeReceivedAt: 145_900_000) - 145_900_000) < 4_000)
        // to and from Foundation's Date, and a count of Unix time
        #expect(try Epoch(now.date) == now)
        #expect(try Epoch(unixTime: now.unixTime) == now)
    }

    @Test func formIsCheckedNotPhysics() throws {
        #expect(try only(Sample.csv.replacingFirst(",.0125362,", with: ",2,"), .csv).eccentricity == ExactDecimal(2))
    }
}
