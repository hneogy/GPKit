import Testing
import GPKit

/// The README's examples, compiled and held to the words the README prints.
@Suite struct ReadmeTests {

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

    @Test func formIsCheckedNotPhysics() throws {
        #expect(try only(Sample.csv.replacingFirst(",.0125362,", with: ",2,"), .csv).eccentricity == ExactDecimal(2))
    }
}
