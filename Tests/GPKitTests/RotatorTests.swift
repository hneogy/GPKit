import Foundation
import Testing
@testable import GPKit

/// A rotator's track through a pass: within its limits, continuous where it can be, flipped where it must be, and
/// written as Hamlib's set-position command. Hamlib itself follows it in CI (tools/check-rotator.sh).
@Suite struct RotatorTests {

    static let home = Observer(latitude: 40.0, longitude: -75.0)

    static func iss() throws -> (Propagator, ElementSet) {
        let set = try TLE.parse(name: Sample.name, line1: Sample.line1, line2: Sample.line2)
        return (try Propagator(set), set)
    }

    /// The direction a rotator points, as a unit vector: east, north, up.
    static func direction(azimuth: Double, elevation: Double) -> (Double, Double, Double) {
        let a = azimuth * .pi / 180, e = elevation * .pi / 180
        return (cos(e) * sin(a), cos(e) * cos(a), sin(e))
    }

    @Test func hamlibsCommandToATenth() throws {
        let time = try Epoch(ccsds: "1998-11-20T14:05:39.422")
        #expect(RotatorPoint(time: time, azimuth: 202.2349, elevation: 0).hamlibCommand == "P 202.2 0.0")
        #expect(RotatorPoint(time: time, azimuth: 359.96, elevation: 89.95).hamlibCommand == "P 360.0 90.0")
        #expect(RotatorPoint(time: time, azimuth: -12.36, elevation: -0.04).hamlibCommand == "P -12.4 0.0")
        #expect(RotatorPoint(time: time, azimuth: 0.05, elevation: 7).hamlibCommand == "P 0.1 7.0")
    }

    @Test func theTutorialsFirstPassFromRiseToSet() throws {
        let (propagator, set) = try RotatorTests.iss()
        let passes = propagator.passes(over: RotatorTests.home, from: set.epoch, for: .seconds(86_400))
        let pass = try #require(passes.first { $0.rise != nil })
        let rise = try #require(pass.rise), end = try #require(pass.set)
        let track = propagator.rotatorTrack(for: pass, from: RotatorTests.home, every: 10)
        #expect(track.first?.time == rise.time && track.last?.time == end.time)
        #expect(track.count == Int((end.time.seconds(since: rise.time) / 10).rounded(.up)) + 1)
        // the tutorial's figures: up at 202 degrees, down at 69
        #expect(track.first?.hamlibCommand == "P 202.2 0.0" && track.last?.hamlibCommand == "P 69.1 0.0")
        #expect(track.allSatisfy { (0...360).contains($0.azimuth) && (0...90).contains($0.elevation) })
        // each point is the look at its instant, the elevation held at the horizon below it
        for point in track {
            let look = try propagator.look(from: RotatorTests.home, at: point.time)
            #expect(point.azimuth == look.azimuth && point.elevation == max(0, look.elevation))
        }
        let highest = try #require(track.map(\.elevation).max())
        #expect(abs(highest - pass.culmination.look.elevation) < 0.1)
        #expect(propagator.rotatorTrack(for: pass, from: RotatorTests.home, every: 0).isEmpty)
    }

    /// A pass of the sample set whose azimuth crosses north, found in ten days.
    static func passOverNorth() throws -> (Propagator, Pass) {
        let (propagator, set) = try iss()
        for pass in propagator.passes(over: home, from: set.epoch, for: .seconds(10 * 86_400)) where pass.rise != nil && pass.set != nil {
            let looks = propagator.rotatorTrack(for: pass, from: home, every: 5, limits: RotatorLimits(azimuth: -720...720))
            let raw = try looks.map { try propagator.look(from: home, at: $0.time).azimuth }
            if zip(raw, raw.dropFirst()).contains(where: { abs($0 - $1) > 180 }) { return (propagator, pass) }
        }
        throw CancellationError()
    }

    @Test func aPassOverNorthGoesOnThroughWhereTheRotatorCan() throws {
        let (propagator, pass) = try RotatorTests.passOverNorth()
        func largestStep(_ track: [RotatorPoint]) -> Double {
            zip(track, track.dropFirst()).map { abs($1.azimuth - $0.azimuth) }.max() ?? 0
        }
        // 0 to 450: the azimuth runs on past 360, no step of more than a few degrees
        let overlap = propagator.rotatorTrack(for: pass, from: RotatorTests.home, every: 5, limits: RotatorLimits(azimuth: 0...450))
        #expect(largestStep(overlap) < 20 && overlap.allSatisfy { (0...450).contains($0.azimuth) })
        // -180 to 180: north is the middle of the range, so it is crossed without a jump
        let centred = propagator.rotatorTrack(for: pass, from: RotatorTests.home, every: 5, limits: RotatorLimits(azimuth: -180...180))
        #expect(largestStep(centred) < 20)
        // 0 to 360 with elevation to 90: nothing can be done but turn round, once
        let standard = propagator.rotatorTrack(for: pass, from: RotatorTests.home, every: 5)
        #expect(largestStep(standard) > 300)
        #expect(zip(standard, standard.dropFirst()).filter { abs($1.azimuth - $0.azimuth) > 180 }.count == 1)
    }

    @Test func aRotatorThatFlipsPointsTheSameWayOverTheZenith() throws {
        let (propagator, pass) = try RotatorTests.passOverNorth()
        let limits = RotatorLimits(azimuth: 0...360, elevation: 0...180)
        let flipped = propagator.rotatorTrack(for: pass, from: RotatorTests.home, every: 5, limits: limits)
        #expect(!flipped.isEmpty)
        // no turn round: the azimuth stays on the far side of north
        #expect(zip(flipped, flipped.dropFirst()).allSatisfy { abs($1.azimuth - $0.azimuth) < 20 })
        #expect(flipped.allSatisfy { limits.azimuth.contains($0.azimuth) && limits.elevation.contains($0.elevation) && $0.elevation >= 90 })
        // the same direction as the look, wherever the satellite is above the horizon
        for point in flipped {
            let look = try propagator.look(from: RotatorTests.home, at: point.time)
            guard look.elevation > 0 else { continue }
            let want = RotatorTests.direction(azimuth: look.azimuth, elevation: look.elevation)
            let got = RotatorTests.direction(azimuth: point.azimuth, elevation: point.elevation)
            #expect(abs(want.0 - got.0) < 1e-9 && abs(want.1 - got.1) < 1e-9 && abs(want.2 - got.2) < 1e-9)
        }
        // a pass that does not cross the range's end is not flipped
        let (p, set) = try RotatorTests.iss()
        let first = try #require(p.passes(over: RotatorTests.home, from: set.epoch, for: .seconds(86_400)).first { $0.rise != nil })
        #expect(p.rotatorTrack(for: first, from: RotatorTests.home, every: 10, limits: limits).allSatisfy { $0.elevation <= 90 })
    }
}
