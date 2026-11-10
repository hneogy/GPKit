import Testing
@testable import GPKit

// Ephemeris type 4 marks an element set made for SGP4-XP, whose model and drag term are not SGP4's; SGP4 run on one
// gives positions that look right and are not. GPKit reads such a set as written, from a TLE and from every OMM
// format, and refuses to propagate it with a kind of its own, `PropagationFailure.Kind.sgp4XP`. Its type-0 twin, the
// same values with type 0, propagates as any other set.
@Suite struct SGP4XPTests {

    /// A TLE line with its ephemeris type (column 63) set to `type` and the checksum recomputed.
    static func line1(_ line: String, ephemerisType type: Character) -> String {
        var characters = Array(line)
        characters[62] = type
        let body = String(characters[0..<68])
        return body + String(TLE.checksum(of: body + "0"))
    }

    func kind(_ body: () throws -> Void) -> PropagationFailure.Kind? {
        do { try body(); return nil } catch { return (error as? PropagationFailure)?.kind }
    }

    /// The sample in every format GPKit reads, with EPHEMERIS_TYPE `type`.
    static func sample(ephemerisType type: Int) -> [(Format, String)] {
        let t = String(type)
        return [
            (.tle, [Sample.name, line1(Sample.line1, ephemerisType: Character(t)), Sample.line2].joined(separator: "\r\n") + "\r\n"),
            (.csv, Sample.csvHeader + "\r\n" + Sample.csvRow.replacingOccurrences(of: ",359.7454,0,U,", with: ",359.7454,\(t),U,") + "\r\n"),
            (.json, Sample.json.replacingOccurrences(of: "\"EPHEMERIS_TYPE\":0", with: "\"EPHEMERIS_TYPE\":\(t)")),
            (.xml, Sample.xml().replacingOccurrences(of: "<EPHEMERIS_TYPE>0<", with: "<EPHEMERIS_TYPE>\(t)<")),
            (.kvn, Sample.kvn.replacingOccurrences(of: "EPHEMERIS_TYPE      = 0", with: "EPHEMERIS_TYPE      = \(t)")),
        ]
    }

    @Test func aTypeFourSetIsReadAsWrittenAndRefusedFromEveryFormat() throws {
        for (format, text) in Self.sample(ephemerisType: 4) {
            let set = try only(text, format)
            #expect(set.ephemerisType == 4, "\(format)")
            #expect(kind { _ = try Propagator(set) } == .sgp4XP, "\(format)")
            for gravity in [Propagator.Gravity.wgs72, .wgs84, .wgs72old] {
                #expect(kind { _ = try Propagator(set, gravity: gravity) } == .sgp4XP, "\(format), \(gravity)")
            }
        }
    }

    @Test func theTypeZeroTwinPropagatesFromEveryFormatAlike() throws {
        let twins = try Self.sample(ephemerisType: 0).map { try Propagator(only($1, $0)) }
        let reference = try twins[0].state(minutesFromEpoch: 0)
        for propagator in twins {
            #expect(try propagator.state(minutesFromEpoch: 0) == reference)
        }
        // each type-4 set, its type set to 0, is exactly its twin
        for ((format, text), twin) in zip(Self.sample(ephemerisType: 4), twins) {
            var set = try only(text, format)
            set.ephemerisType = 0
            for minutes in [-1440.0, 0, 90, 1440] {
                #expect(try Propagator(set).state(minutesFromEpoch: minutes) == twin.state(minutesFromEpoch: minutes), "\(format)")
            }
        }
    }

    @Test func meanElementTheorySGP4XPIsRefusedAlike() throws {
        let kvn = Sample.kvn.replacingOccurrences(of: "MEAN_ELEMENT_THEORY = SGP/SGP4", with: "MEAN_ELEMENT_THEORY = SGP4-XP")
        let set = try only(kvn, .kvn)
        #expect(set.meanElementTheory == "SGP4-XP" && set.ephemerisType == 0)
        #expect(kind { _ = try Propagator(set) } == .sgp4XP)
        // both: the theory and type 4, as an SGP4-XP OMM would carry them
        let both = try only(kvn.replacingOccurrences(of: "EPHEMERIS_TYPE      = 0", with: "EPHEMERIS_TYPE      = 4"), .kvn)
        #expect(kind { _ = try Propagator(both) } == .sgp4XP)
        // a theory that is neither is still not SGP4, under its own kind
        var other = set
        other.meanElementTheory = "DSST"
        #expect(kind { _ = try Propagator(other) } == .notSGP4)
    }

    @Test func aDraggedSetOfTypeFourIsRefusedAndItsTwinPropagates() throws {
        // DELTA 2 R/B(1), 20453, from pass-check-sets.tle: a near-earth set with a large BSTAR, where SGP4-XP's drag
        // term and SGP4's part most
        let line1 = "1 20453U 90008B   26263.56914166  .00350177  49935-4  75989-3 0  9996"
        let line2 = "2 20453  35.5934 307.3932 0022512 310.3690  49.5094 15.96788691956793"
        let typeFour = try TLE.parse(line1: Self.line1(line1, ephemerisType: "4"), line2: line2)
        #expect(typeFour.ephemerisType == 4)
        #expect(kind { _ = try Propagator(typeFour) } == .sgp4XP)
        let twin = try TLE.parse(line1: Self.line1(line1, ephemerisType: "0"), line2: line2)
        #expect(twin.ephemerisType == 0)
        #expect(try Propagator(twin).state(minutesFromEpoch: 0) == Propagator(TLE.parse(line1: line1, line2: line2)).state(minutesFromEpoch: 0))
    }

    @Test func theFailureSaysWhatTheSetIs() {
        let failure = PropagationFailure(kind: .sgp4XP, minutesFromEpoch: nil)
        #expect(failure.description.contains("SGP4-XP"))
        #expect(failure.description.contains("ephemeris type 4"))
    }

    @Test func writingKeepsTheTypeAsRead() throws {
        // a type-4 set is data, not an error: the TLE writer keeps it, so it can be passed on to an SGP4-XP library
        let set = try only(Self.sample(ephemerisType: 4)[0].1, .tle)
        let lines = try TLE.write(set)
        #expect(Array(lines.line1)[62] == "4")
    }
}
