import Foundation
import Testing
@testable import GPKit

/// The CCSDS OEM writer: its text read back here, every state the propagator's to the last place written. In CI a
/// named OEM reader, the `oem` package for Python, reads what `gpkit oem` writes (tools/check_oem.py).
@Suite struct OEMTests {

    static func iss() throws -> Propagator {
        try Propagator(try TLE.parse(name: Sample.name, line1: Sample.line1, line2: Sample.line2))
    }

    @Test func theMessageHoldsTheStatesToTheMillimetre() throws {
        let propagator = try OEMTests.iss()
        let start = propagator.elementSet.epoch
        let created = try Epoch(ccsds: "2026-11-07T00:00:00")
        let text = try OEM.write(propagator, from: start, every: 60, count: 95, originator: "GPKit tests", created: created)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(Array(lines.prefix(14)) == [
            "CCSDS_OEM_VERS = 2.0", "CREATION_DATE = 2026-11-07T00:00:00.000000", "ORIGINATOR = GPKit tests", "",
            "META_START", "OBJECT_NAME = ISS (ZARYA)", "OBJECT_ID = 1998-067A", "CENTER_NAME = EARTH", "REF_FRAME = TEME",
            "TIME_SYSTEM = UTC", "START_TIME = 1998-11-20T06:49:59.999808", "STOP_TIME = 1998-11-20T08:23:59.999808",
            "META_STOP", "",
        ])
        let data = lines.filter { $0.first?.isNumber == true }
        #expect(data.count == 95 && text.hasSuffix("\n"))
        for (i, line) in data.enumerated() {
            let fields = line.split(separator: " ")
            #expect(fields.count == 7)
            let time = try Epoch(ccsds: String(fields[0]))
            #expect(time == (try start.advanced(by: Double(i) * 60)))
            let state = try propagator.state(at: time)
            let written = fields[1...].map { Double(String($0))! }
            let wanted = [state.position.x, state.position.y, state.position.z, state.velocity.x, state.velocity.y, state.velocity.z]
            for (k, (w, s)) in zip(written, wanted).enumerated() {
                // half a millimetre, and half a nanometre a second
                #expect(abs(w - s) <= (k < 3 ? 5.0e-7 : 5.0e-10) + 1e-15, "line \(i), value \(k): \(w) against \(s)")
            }
        }
    }

    @Test func numbersAreWrittenToTheirPlaceWithoutFoundation() {
        #expect(OEM.fixed(1234.5678904, 6) == "1234.567890")
        #expect(OEM.fixed(-0.0000004, 6) == "0.000000")
        #expect(OEM.fixed(-0.0000006, 6) == "-0.000001")
        #expect(OEM.fixed(-7.12345678951, 9) == "-7.123456790")
        #expect(OEM.fixed(42, 6) == "42.000000")
    }

    @Test func whatCannotBeWrittenIsNotWritten() throws {
        let propagator = try OEMTests.iss()
        let start = propagator.elementSet.epoch, created = try Epoch(ccsds: "2026-11-07T00:00:00")
        #expect(throws: PropagationFailure.self) { _ = try OEM.write(propagator, from: start, every: 60, count: 0, originator: "x", created: created) }
        #expect(throws: PropagationFailure.self) { _ = try OEM.write(propagator, from: start, every: 0, count: 5, originator: "x", created: created) }
        // the rocket body of 1990 has come down by the end of 2026: no message, the failure
        let decayed = try Propagator(try TLE.parse(line1: "1 20453U 90008B   26263.56914166  .00350177  49935-4  75989-3 0  9996",
                                                   line2: "2 20453  35.5934 307.3932 0022512 310.3690  49.5094 15.96788691956793"))
        #expect(throws: PropagationFailure.self) {
            _ = try OEM.write(decayed, from: try Epoch(ccsds: "2026-12-31T00:00:00"), every: 60, count: 5, originator: "x", created: created)
        }
        // a line in a name cannot start another keyword
        let text = try OEM.write(propagator, from: start, every: 60, count: 1, originator: "a\nCENTER_NAME = MARS", created: created)
        #expect(text.contains("ORIGINATOR = a CENTER_NAME = MARS") && !text.contains("\nCENTER_NAME = MARS"))
    }
}
