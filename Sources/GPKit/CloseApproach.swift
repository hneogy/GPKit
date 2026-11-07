#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(ucrt)
import ucrt
#elseif canImport(Android)
import Android
#elseif canImport(WASILibc)
import WASILibc
#endif

/// A rough screen for close approaches between satellites, on GP data propagated with SGP4.
///
/// **What it is.** It looks through a span of time for the moments two objects come nearest each other, and gives
/// each such moment as a candidate: the two objects, the time, the miss distance and the relative speed. That is all
/// it gives. It works out no probability of collision and no risk, and says nothing about either.
///
/// **What it is not.** GP data and SGP4 place an object to roughly a kilometre near the element set's epoch, and to
/// several kilometres or more a few days on; an element set says nothing of how uncertain it is. So a miss distance
/// here is SGP4's, not the objects', and **it is not for operational collision avoidance**: an operator screens with
/// precise ephemerides and their covariances, and with the conjunction data messages the agencies issue. And **no
/// approach found does not mean the objects are safe**: only that, in SGP4's positions, sampled as asked, none came
/// within the distance asked.
///
/// It suits a first look among tens to a few thousand objects: which pairs come near each other, and when.
public enum CloseApproach {

    /// One moment two objects come nearest each other in SGP4's positions: a candidate to look at with better data,
    /// never a finding about the real objects.
    public struct Candidate: Sendable, Hashable {
        /// The two objects, by their place in the list screened; `first` is the lower.
        public var first: Int
        public var second: Int
        /// The instant of the smallest separation, UTC, to about a tenth of a millisecond.
        public var time: Epoch
        /// The separation then, kilometres: SGP4's, with SGP4's error, which is roughly a kilometre or more.
        public var missDistance: Double
        /// How fast the two move relative to each other then, kilometres per second.
        public var relativeSpeed: Double
        /// True when the separation is smallest at the start or the end of the span: the nearest the two came inside
        /// it, which need not be the nearest they come.
        public var atEdgeOfSpan: Bool
    }

    /// An object SGP4 could not propagate through the span, which was screened for none of its pairs.
    public struct Unscreened: Sendable, Hashable {
        public var index: Int
        public var failure: PropagationFailure
    }

    /// What a screen found.
    public struct Screen: Sendable, Hashable {
        /// The candidates within the distance asked, the nearest first.
        public var candidates: [Candidate]
        /// Objects left out for want of a propagation through the span.
        public var unscreened: [Unscreened]
        /// Pairs passed over because their orbits' heights never come within the distance asked (with a margin).
        public var pairsPassedOver: Int
        /// Pairs looked at.
        public var pairsScreened: Int
    }

    /// The margin, kilometres, added to the distance asked when pairs are passed over by their perigee and apogee:
    /// those are worked out from the mean elements, which differ from SGP4's positions by tens of kilometres.
    public static let heightMargin = 100.0

    /// Screens every pair of `propagators` from `start` for `seconds`, sampled every `step` seconds, and gives the
    /// moments each pair is nearest within `within` kilometres.
    ///
    /// A pair is sampled every `step` seconds, and between two samples where the two go from closing to drawing apart
    /// the moment of the smallest separation is found to about a tenth of a millisecond. Two moments in one step are
    /// seen as one, so the step should be well under a quarter of the shorter period: 60 seconds for low orbits.
    /// See ``CloseApproach`` for what the result is and is not.
    public static func screen(_ propagators: [Propagator], from start: Epoch, for seconds: Double, step: Double = 60,
                              within: Double = 10) -> Screen {
        var result = Screen(candidates: [], unscreened: [], pairsPassedOver: 0, pairsScreened: 0)
        guard seconds > 0, seconds.isFinite, step > 0, step.isFinite, within > 0, seconds / step < 10_000_000 else { return result }
        // each object's minutes from its epoch at the start, and whether it propagates through the span
        var offsets: [Double?] = []
        for (index, propagator) in propagators.enumerated() {
            let first = start.seconds(since: propagator.elementSet.epoch) / 60.0
            var failed: PropagationFailure?
            var t = 0.0
            while t <= seconds {
                do { _ = try propagator.state(minutesFromEpoch: first + t / 60.0) } catch { failed = error; break }
                t += step
            }
            if failed == nil {
                do { _ = try propagator.state(minutesFromEpoch: first + seconds / 60.0) } catch { failed = error }
            }
            if let failed {
                result.unscreened.append(Unscreened(index: index, failure: failed))
                offsets.append(nil)
            } else {
                offsets.append(first)
            }
        }
        let heights = propagators.map(radii)
        for i in propagators.indices {
            guard let a = offsets[i] else { continue }
            for j in propagators.indices where j > i {
                guard let b = offsets[j] else { continue }
                if heights[i].perigee - heights[j].apogee > within + heightMargin || heights[j].perigee - heights[i].apogee > within + heightMargin {
                    result.pairsPassedOver += 1
                    continue
                }
                result.pairsScreened += 1
                let p = propagators[i], q = propagators[j]
                let found = nearest(span: seconds, step: step, within: within) { t in
                    guard let x = try? p.state(minutesFromEpoch: a + t / 60.0), let y = try? q.state(minutesFromEpoch: b + t / 60.0) else { return nil }
                    return (Vector(x: y.position.x - x.position.x, y: y.position.y - x.position.y, z: y.position.z - x.position.z),
                            Vector(x: y.velocity.x - x.velocity.x, y: y.velocity.y - x.velocity.y, z: y.velocity.z - x.velocity.z))
                }
                for approach in found {
                    guard let time = try? start.advanced(by: approach.seconds) else { continue }
                    result.candidates.append(Candidate(first: i, second: j, time: time, missDistance: approach.distance,
                                                       relativeSpeed: approach.speed, atEdgeOfSpan: approach.atEdge))
                }
            }
        }
        result.candidates.sort { $0.missDistance < $1.missDistance }
        return result
    }

    /// Perigee and apogee radii from the mean elements, kilometres from the Earth's centre, by Kepler's third law.
    static func radii(_ propagator: Propagator) -> (perigee: Double, apogee: Double) {
        let set = propagator.elementSet
        let n = set.meanMotion.double * 2.0 * SGP4Core.pi / 86_400.0      // radians a second
        guard n > 0 else { return (0, .infinity) }
        let a = cbrt(398_600.4418 / (n * n))
        let e = set.eccentricity.double
        return (a * (1.0 - e), a * (1.0 + e))
    }

    /// The moments of smallest separation of one pair over `span` seconds, sampled every `step`, within `within`
    /// kilometres. `relative(t)` is the second object's position and velocity less the first's at `t` seconds, or nil
    /// where it cannot be had. The separation is shrinking while the relative position and velocity point against
    /// each other (their dot product is negative) and growing once it is positive: a minimum lies between two samples
    /// where it turns from negative to positive, and is found there by halving the interval.
    static func nearest(span: Double, step: Double, within: Double, _ relative: (Double) -> (Vector, Vector)?) -> [(seconds: Double, distance: Double, speed: Double, atEdge: Bool)] {
        func dot(_ t: Double) -> Double? {
            guard let (r, v) = relative(t) else { return nil }
            return r.x * v.x + r.y * v.y + r.z * v.z
        }
        func measured(_ t: Double, edge: Bool) -> (seconds: Double, distance: Double, speed: Double, atEdge: Bool)? {
            guard let (r, v) = relative(t) else { return nil }
            return (t, r.magnitude, v.magnitude, edge)
        }
        var times: [Double] = []
        var t = 0.0
        while t < span {
            times.append(t)
            t += step
        }
        times.append(span)
        let dots = times.map(dot)
        var found: [(seconds: Double, distance: Double, speed: Double, atEdge: Bool)] = []
        // drawing apart from the start: the start is the nearest the two come there
        if let first = dots.first, let d = first, d > 0, let m = measured(0, edge: true), m.distance <= within { found.append(m) }
        for k in 0..<(times.count - 1) {
            guard let before = dots[k], let after = dots[k + 1], before < 0, after >= 0 else { continue }
            var low = times[k], high = times[k + 1]
            while high - low > 1.0e-4 {
                let middle = (low + high) / 2.0
                guard let d = dot(middle) else { break }
                if d < 0 { low = middle } else { high = middle }
            }
            if let m = measured((low + high) / 2.0, edge: false), m.distance <= within { found.append(m) }
        }
        // still closing at the end: the end is the nearest the two came inside the span
        if let last = dots.last, let d = last, d < 0, let m = measured(span, edge: true), m.distance <= within { found.append(m) }
        return found
    }
}
