/// An ephemeris as a CCSDS Orbit Ephemeris Message (OEM), version 2.0, in KVN, the text form of CCSDS's Orbit Data
/// Messages standard (502.0): one segment of states, position in kilometres and velocity in kilometres per second, at
/// even steps.
///
/// The states are SGP4's, in TEME, the frame they are worked out in, and the time system is UTC; the message says so in
/// its metadata, and in comments says that they come from SGP4 and from which element set. An OEM from SGP4 is only as
/// good as SGP4: a position kilometres from the truth a few days from the element set's epoch is still written to the
/// millimetre.
public enum OEM {

    /// Writes the states from `start`, every `step` seconds, `count` of them.
    ///
    /// - Parameters:
    ///   - propagator: The element set's propagator; the message is of its satellite.
    ///   - start: The first state's instant, UTC.
    ///   - step: Seconds from one state to the next.
    ///   - count: How many states, the first at `start`.
    ///   - originator: Who made the message, the `ORIGINATOR` keyword: for example your program's or your
    ///     organisation's name.
    ///   - created: The `CREATION_DATE`. A program passes the time it writes the message; it is a parameter so that
    ///     the same states give the same text.
    /// - Throws: The first failure to propagate; nothing is written then. `PropagationFailure.Kind.time` for a count
    ///   that is not positive, a step that is not above zero, or an instant outside the years an `Epoch` holds.
    public static func write(_ propagator: Propagator, from start: Epoch, every step: Double, count: Int,
                             originator: String, created: Epoch) throws(PropagationFailure) -> String {
        guard count > 0, step > 0, step.isFinite else { throw PropagationFailure(kind: .time, minutesFromEpoch: nil) }
        var times: [Epoch] = []
        times.reserveCapacity(count)
        for i in 0..<count {
            guard let time = try? start.advanced(by: Double(i) * step) else { throw PropagationFailure(kind: .time, minutesFromEpoch: nil) }
            times.append(time)
        }
        let states = try times.map { time throws(PropagationFailure) in try propagator.state(at: time) }
        let set = propagator.elementSet
        func clean(_ text: String) -> String {
            // a value is the rest of its line: nothing in it may start another
            String(text.unicodeScalars.map { $0.value < 0x20 || $0.value == 0x7F ? " " : Character($0) })
        }
        let name = set.objectName.map(clean) ?? set.catalogNumber.map { String($0) } ?? "UNKNOWN"
        let id = set.objectID.map(clean) ?? "UNKNOWN"
        var lines = [
            "CCSDS_OEM_VERS = 2.0",
            "CREATION_DATE = \(created)",
            "ORIGINATOR = \(clean(originator))",
            "",
            "META_START",
            "OBJECT_NAME = \(name)",
            "OBJECT_ID = \(id)",
            "CENTER_NAME = EARTH",
            "REF_FRAME = TEME",
            "TIME_SYSTEM = UTC",
            "START_TIME = \(times[0])",
            "STOP_TIME = \(times[times.count - 1])",
            "META_STOP",
            "",
            "COMMENT Propagated by GPKit with SGP4 from the element set of epoch \(set.epoch)\(set.catalogNumber.map { ", catalog number \($0)" } ?? "").",
            "COMMENT Positions in km, velocities in km/s, in TEME: SGP4's own frame.",
        ]
        for (time, state) in zip(times, states) {
            let p = state.position, v = state.velocity
            lines.append("\(time) \(fixed(p.x, 6)) \(fixed(p.y, 6)) \(fixed(p.z, 6)) \(fixed(v.x, 9)) \(fixed(v.y, 9)) \(fixed(v.z, 9))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A number with `places` decimals, rounded half away from zero: kilometres to the millimetre, kilometres a second
    /// to the nanometre a second. Without Foundation, so in whole numbers of the last place.
    static func fixed(_ value: Double, _ places: Int) -> String {
        var scale = 1.0
        for _ in 0..<places { scale *= 10 }
        let scaled = (abs(value) * scale).rounded()
        guard scaled < 9.0e18 else { return "\(value)" }
        let units = Int64(scaled)
        var unit: Int64 = 1
        for _ in 0..<places { unit *= 10 }
        var fraction = String(units % unit)
        while fraction.count < places { fraction = "0" + fraction }
        return (value < 0 && units != 0 ? "-" : "") + "\(units / unit).\(fraction)"
    }
}
