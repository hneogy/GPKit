import Foundation
import Testing
@testable import GPKit

/// The close-approach screen, held to closest approaches worked out another way: by formula for straight-line motion,
/// and by a brute-force search of the same SGP4 positions for a pair built to meet. It screens; it says nothing of
/// collision probability, and neither do these tests.
func v3(_ x: Double, _ y: Double, _ z: Double) -> Vector { Vector(x: x, y: y, z: z) }

@Suite struct CloseApproachTests {

    /// Two objects in straight lines: the second at r0 + v t relative to the first. Nearest at t = -(r0 · v) / |v|²,
    /// at |r0 + v t| then: the formula the screen's search is held to.
    static func straight(_ r0: Vector, _ v: Vector) -> (Double) -> (Vector, Vector)? {
        { t in (v3(r0.x + v.x * t, r0.y + v.y * t, r0.z + v.z * t), v) }
    }

    static func closest(_ r0: Vector, _ v: Vector) -> (time: Double, distance: Double) {
        let t = -(r0.x * v.x + r0.y * v.y + r0.z * v.z) / (v.x * v.x + v.y * v.y + v.z * v.z)
        return (t, v3(r0.x + v.x * t, r0.y + v.y * t, r0.z + v.z * t).magnitude)
    }

    @Test func straightLinesMeetWhereTheFormulaSays() {
        let cases: [(Vector, Vector)] = [
            (v3(-500, 3, 0), v3(7.5, 0, 0)),          // passes 3 km by at t = 66.67 s
            (v3(-9000, 1, 2), v3(10, 0.001, -0.002)),  // 2.2 km at about 900 s
            (v3(4000, -4000, 0.5), v3(-7, 7, 0)),      // 0.5 km at about 571 s
        ]
        for (r0, v) in cases {
            let want = CloseApproachTests.closest(r0, v)
            let found = CloseApproach.nearest(span: 3600, step: 60, within: 10, CloseApproachTests.straight(r0, v))
            #expect(found.count == 1, "\(r0), \(v): \(found)")
            guard let got = found.first else { continue }
            #expect(abs(got.seconds - want.time) < 1.0e-4 && abs(got.distance - want.distance) < 1.0e-6 && !got.atEdge,
                    "\(got) against \(want)")
            #expect(abs(got.speed - v.magnitude) < 1e-12)
        }
        // nearer than asked, or not: 3 km is not within 2
        #expect(CloseApproach.nearest(span: 3600, step: 60, within: 2, CloseApproachTests.straight(v3(-500, 3, 0), v3(7.5, 0, 0))).isEmpty)
        // nearest before the span begins: the start is the nearest inside it, and says so
        let receding = CloseApproach.nearest(span: 600, step: 60, within: 10, CloseApproachTests.straight(v3(1, 2, 0), v3(1, 0, 0)))
        #expect(receding.count == 1 && receding[0].atEdge && receding[0].seconds == 0)
        // nearest after it ends: the end, and says so
        let closing = CloseApproach.nearest(span: 600, step: 60, within: 10, CloseApproachTests.straight(v3(-603, 1, 0), v3(1, 0, 0)))
        #expect(closing.count == 1 && closing[0].atEdge && closing[0].seconds == 600)
    }

    @Test func twoCirclesMeetTwiceARevolution() {
        // two circular orbits of one radius in planes 10 degrees apart, with the same phase: they meet at the line
        // of nodes, twice a revolution, at distance zero, when the phase is a whole multiple of half a turn
        let radius = 6778.0, period = 5553.6
        let w = 2 * Double.pi / period, tilt = 10 * Double.pi / 180
        let relative: (Double) -> (Vector, Vector)? = { t in
            let u = w * t + 0.3
            let a = v3(radius * cos(u), radius * sin(u), 0)
            let b = v3(radius * cos(u), radius * sin(u) * cos(tilt), radius * sin(u) * sin(tilt))
            let va = v3(-radius * w * sin(u), radius * w * cos(u), 0)
            let vb = v3(-radius * w * sin(u), radius * w * cos(u) * cos(tilt), radius * w * cos(u) * sin(tilt))
            return (v3(b.x - a.x, b.y - a.y, b.z - a.z), v3(vb.x - va.x, vb.y - va.y, vb.z - va.z))
        }
        let found = CloseApproach.nearest(span: 2 * period, step: 60, within: 1, relative)
        // u = pi, 2 pi, 3 pi and 4 pi in two revolutions from u = 0.3: t = (k pi - 0.3) / w
        let want = [1.0, 2.0, 3.0, 4.0].map { ($0 * Double.pi - 0.3) / w }
        #expect(found.count == 4, "\(found)")
        for (got, t) in zip(found, want) {
            #expect(abs(got.seconds - t) < 1.0e-3 && got.distance < 1.0e-3, "\(got) against \(t)")
        }
    }

    /// The sample Space Station set, and the same set tilted a degree: the two cross each other's plane at the line of
    /// nodes, in step, so they come within a few kilometres twice a revolution.
    static func pair() throws -> [Propagator] {
        let set = try TLE.parse(name: Sample.name, line1: Sample.line1, line2: Sample.line2)
        var tilted = set
        tilted.inclination = try #require(ExactDecimal("52.5908"))
        tilted.objectName = "TILTED"
        return [try Propagator(set), try Propagator(tilted)]
    }

    @Test func anSGP4PairIsWhereABruteForceSearchOfTheSamePositionsFindsIt() throws {
        let propagators = try CloseApproachTests.pair()
        let start = propagators[0].elementSet.epoch
        let span = 6.0 * 3600
        let screen = CloseApproach.screen(propagators, from: start, for: span, step: 60, within: 50)
        #expect(screen.pairsScreened == 1 && screen.unscreened.isEmpty)
        // twice a revolution for six hours
        #expect(screen.candidates.count >= 7 && screen.candidates.count <= 9, "\(screen.candidates.count)")
        func separation(_ t: Double) throws -> Double {
            let a = try propagators[0].state(at: try start.advanced(by: t)).position
            let b = try propagators[1].state(at: try start.advanced(by: t)).position
            return Vector(x: b.x - a.x, y: b.y - a.y, z: b.z - a.z).magnitude
        }
        // by brute force: every second over the span, every local minimum within 50 km, then every 10 ms around it
        var minima: [(t: Double, d: Double)] = []
        var previous = try separation(0), current = try separation(1)
        var t = 1.0
        while t < span {
            let next = try separation(t + 1)
            if current < previous && current <= next && current < 50 {
                var best = (t: t, d: current)
                var u = t - 1
                while u <= t + 1 {
                    let d = try separation(u)
                    if d < best.d { best = (u, d) }
                    u += 0.01
                }
                minima.append(best)
            }
            previous = current
            current = next
            t += 1
        }
        let found = screen.candidates.sorted { $0.time < $1.time }
        #expect(found.count == minima.count, "screen \(found.count), brute force \(minima.count)")
        for (candidate, minimum) in zip(found, minima) {
            let seconds = candidate.time.seconds(since: start)
            #expect(abs(seconds - minimum.t) < 0.02, "\(seconds) against \(minimum.t)")
            #expect(abs(candidate.missDistance - minimum.d) < 0.001, "\(candidate.missDistance) km against \(minimum.d) km")
            #expect(candidate.first == 0 && candidate.second == 1 && !candidate.atEdgeOfSpan)
        }
        // the nearest first
        #expect(zip(screen.candidates, screen.candidates.dropFirst()).allSatisfy { $0.missDistance <= $1.missDistance })
        print("close approaches of the tilted pair in six hours: \(found.count), nearest \(screen.candidates.first.map { "\($0.missDistance) km" } ?? "none")")
    }

    @Test func pairsThatCannotMeetArePassedOverAndWhatCannotBePropagatedIsSaid() throws {
        var propagators = try CloseApproachTests.pair()
        // the same set lifted to about geostationary height: its orbit never comes within 50 km of the station's
        var high = propagators[0].elementSet
        high.meanMotion = try #require(ExactDecimal("1.00270000"))
        high.eccentricity = try #require(ExactDecimal(".0001000"))
        propagators.append(try Propagator(high))
        // the rocket body of 1990, which has come down by the end of 2026
        propagators.append(try Propagator(try TLE.parse(line1: "1 20453U 90008B   26263.56914166  .00350177  49935-4  75989-3 0  9996",
                                                       line2: "2 20453  35.5934 307.3932 0022512 310.3690  49.5094 15.96788691956793")))
        let screen = CloseApproach.screen(propagators, from: try Epoch(ccsds: "2026-12-31T00:00:00"), for: 3600, step: 60, within: 50)
        #expect(screen.unscreened.map(\.index) == [3])
        // the two low ones with the high one: passed over; the low pair screened
        #expect(screen.pairsPassedOver == 2 && screen.pairsScreened == 1)
        #expect(screen.candidates.allSatisfy { $0.first == 0 && $0.second == 1 })
        #expect(CloseApproach.screen(propagators, from: try Epoch(ccsds: "2026-12-31T00:00:00"), for: 0).candidates.isEmpty)
    }
}
