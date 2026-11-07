/// What an antenna rotator can turn to: its azimuth and elevation ranges, in degrees.
///
/// Azimuth is counted clockwise from north as a rotator counts it, which may run past 360 (an overlap, as in 0 to 450)
/// or start below 0 (as in -180 to 180). Elevation is 0 to 90 for most rotators; one whose elevation runs to 180 can
/// "flip", tracking a pass that crosses north over the zenith instead of turning the whole way round.
public struct RotatorLimits: Sendable, Hashable {
    public var azimuth: ClosedRange<Double>
    public var elevation: ClosedRange<Double>

    public init(azimuth: ClosedRange<Double> = 0...360, elevation: ClosedRange<Double> = 0...90) {
        self.azimuth = azimuth
        self.elevation = elevation
    }

    /// The common one: 0 to 360 and 0 to 90.
    public static let standard = RotatorLimits()
}

/// Where to point a rotator at one instant of a pass, in its own counting of azimuth.
public struct RotatorPoint: Sendable, Hashable {
    public var time: Epoch
    /// Degrees, as the rotator counts them: within its limits, which can be past 360 or below 0.
    public var azimuth: Double
    public var elevation: Double

    public init(time: Epoch, azimuth: Double, elevation: Double) {
        self.time = time
        self.azimuth = azimuth
        self.elevation = elevation
    }

    /// The point as Hamlib's rotator command `P`, set position, as rotctl and rotctld take it: `P 202.2 0.0`, degrees
    /// to a tenth.
    public var hamlibCommand: String {
        "P \(RotatorPoint.tenth(azimuth)) \(RotatorPoint.tenth(elevation))"
    }

    /// A number to one decimal, rounded, with no minus sign on a zero.
    static func tenth(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        let sign = tenths < 0 ? "-" : ""
        let magnitude = tenths < 0 ? -tenths : tenths
        return "\(sign)\(magnitude / 10).\(magnitude % 10)"
    }
}

extension Propagator {

    /// Where to point a rotator through a pass: every `step` seconds from the pass's rise to its set (or from its
    /// culmination where it has neither), the last instant included, within the rotator's limits.
    ///
    /// - The elevation is the look's, held to the limits: never below the lower, so the antenna waits at the horizon
    ///   for a rise and stays there after a set.
    /// - The azimuth is the look's, counted the rotator's way. Where its range is wider than a turn, each point takes
    ///   the count nearest the one before, so a pass crossing north goes on through 360 instead of turning back the
    ///   whole way. Where the range is one turn and the elevation runs to 180, a pass that would cross the end of the
    ///   range is tracked flipped: the azimuth half a turn round and the elevation 180 less the look's, the same
    ///   direction reached over the zenith.
    ///
    /// Empty when the step is not above zero, or when the satellite cannot be propagated through the pass.
    public func rotatorTrack(for pass: Pass, from observer: Observer, every step: Double = 1, limits: RotatorLimits = .standard) -> [RotatorPoint] {
        let start = pass.rise?.time ?? pass.culmination.time
        let end = pass.set?.time ?? pass.culmination.time
        let length = end.seconds(since: start)
        guard step > 0, step.isFinite, length >= 0, length / step < 1_000_000 else { return [] }
        var looks: [(time: Epoch, look: Look)] = []
        var offset = 0.0
        while true {
            let seconds = min(offset, length)
            guard let time = try? start.advanced(by: seconds), let look = try? look(from: observer, at: time) else { return [] }
            looks.append((time, look))
            if seconds >= length { break }
            offset += step
        }
        let azimuths = limits.azimuth, elevations = limits.elevation
        let width = azimuths.upperBound - azimuths.lowerBound
        func held(_ value: Double, _ range: ClosedRange<Double>) -> Double { min(max(value, range.lowerBound), range.upperBound) }
        /// The count of an azimuth within the range nearest `near`, or the nearest end where none is within it.
        func counted(_ azimuth: Double, near: Double?) -> Double {
            // whole turns added to the look's own number, so that the count with none is that number exactly
            let candidates = (-3...3).map { azimuth + Double($0) * 360 }.filter { azimuths.contains($0) }
            guard !candidates.isEmpty else { return held(azimuth, azimuths) }
            guard let near else { return candidates[0] }
            return candidates.min { abs($0 - near) < abs($1 - near) }!
        }

        // one turn or less, and an elevation axis that reaches past the zenith: flip a pass whose azimuth would leave
        // the range's continuous span
        if width < 360 + 1e-9, elevations.upperBound >= 180 {
            var unwrapped: [Double] = []
            for (_, look) in looks {
                let a = look.azimuth
                if let last = unwrapped.last {
                    var d = a - last.truncatingRemainder(dividingBy: 360)
                    if d > 180 { d -= 360 }
                    if d < -180 { d += 360 }
                    unwrapped.append(last + d)
                } else {
                    unwrapped.append(a)
                }
            }
            let span = (unwrapped.max() ?? 0) - (unwrapped.min() ?? 0)
            // the pass as the rotator would count it without a flip: does it leave the range anywhere?
            let base = counted(unwrapped[0], near: nil) - unwrapped[0]
            let fits = unwrapped.allSatisfy { azimuths.contains($0 + base) } && span <= width
            if !fits {
                return looks.map { item in
                    let flipped = (item.look.azimuth + 180).truncatingRemainder(dividingBy: 360)
                    return RotatorPoint(time: item.time, azimuth: counted(flipped, near: nil), elevation: held(180 - item.look.elevation, elevations))
                }
            }
        }
        var points: [RotatorPoint] = []
        var previous: Double?
        for (time, look) in looks {
            let azimuth = counted(look.azimuth, near: previous)
            previous = azimuth
            points.append(RotatorPoint(time: time, azimuth: azimuth, elevation: held(look.elevation, elevations)))
        }
        return points
    }
}
