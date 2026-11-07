#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(ucrt)
import ucrt
#endif

/// A satellite's path over the ground: the point beneath it at a run of instants.
///
/// It is a collection of its points, so `for point in` and `first` work on it as on an array.
public struct GroundTrack: Sendable, Hashable, RandomAccessCollection {

    /// The point beneath the satellite at an instant.
    public struct Point: Sendable, Hashable {
        public var time: Epoch
        public var position: GeodeticPosition
    }

    let points: [Point]

    /// Why the track stops before the end of its span, and at how many minutes from the element set's epoch; nil
    /// when it runs to the end. The points are the ones found up to there.
    public let failure: PropagationFailure?

    public var startIndex: Int { points.startIndex }
    public var endIndex: Int { points.endIndex }
    public subscript(position: Int) -> Point { points[position] }
}

extension Propagator {

    /// The satellite's position and velocity in the Earth-fixed frame at an instant of UTC, kilometres and kilometres
    /// per second: TEME turned about the pole by Greenwich mean sidereal time, with the Earth's rotation taken out of
    /// the velocity. UT1 is taken to be UTC and the motion of the pole is left out, as for every Earth-fixed figure
    /// GPKit gives; the frame is the one its looks and map positions are worked out in.
    public func earthFixedState(at time: Epoch) throws(PropagationFailure) -> StateVector {
        try earthFixed(minutes: time.seconds(since: elementSet.epoch) / 60.0, ut1LessUTC: 0)
    }

    /// Where the satellite is on the sky from a place at an instant of UTC: its right ascension and declination, for
    /// the true equator and equinox of the date, as seen from the place rather than from the Earth's centre, which
    /// for a low orbit moves it by up to a degree a hundred kilometres away. Geometric: no aberration, no bending by
    /// the air.
    ///
    /// TEME's x axis lies along the true equator at the mean equinox; the equinox of the date is the equation of the
    /// equinoxes from there, worked out with the sun's nutation terms (see ``Sun``), which are good to about a
    /// thousandth of a degree.
    public func equatorial(from observer: Observer, at time: Epoch) throws(PropagationFailure) -> EquatorialPosition {
        try equatorial(from: observer, minutes: time.seconds(since: elementSet.epoch) / 60.0)
    }

    /// The same at a number of minutes from the element set's epoch, with the tests' door for UT1.
    func equatorial(from observer: Observer, minutes: Double, ut1LessUTC: Double = 0) throws(PropagationFailure) -> EquatorialPosition {
        let satellite = try state(minutesFromEpoch: minutes).position
        let julianDate = elementSet.epoch.julianDate + minutes / 1440.0
        // the place in TEME: its Earth-fixed position turned back by the angle the satellite is turned by
        let theta = SGP4Core.gstime(julianDate + ut1LessUTC / 86_400.0)
        let fixed = observer.earthFixed
        let dx = satellite.x - (cos(theta) * fixed.x - sin(theta) * fixed.y)
        let dy = satellite.y - (sin(theta) * fixed.x + cos(theta) * fixed.y)
        let dz = satellite.z - fixed.z
        var rightAscension = atan2(dy, dx) * Frames.degrees + Sun.equationOfTheEquinoxes(julianDate: julianDate)
        rightAscension = rightAscension.truncatingRemainder(dividingBy: 360.0)
        if rightAscension < 0 { rightAscension += 360.0 }
        let declination = atan2(dz, (dx * dx + dy * dy).squareRoot()) * Frames.degrees
        return EquatorialPosition(rightAscension: rightAscension, declination: declination)
    }

    /// The point beneath the satellite from an instant of UTC, every `step`, for a span: its ground track, the start
    /// and every step up to the end of the span included.
    ///
    /// If the element set cannot be propagated to some instant, the track stops there, with the reason in `failure`.
    /// A span or step that is not above zero gives an empty track, as does one of more than a million points.
    public func groundTrack(from start: Epoch, for duration: Duration, every step: Duration) -> GroundTrack {
        func seconds(_ duration: Duration) -> Double {
            let (whole, fraction) = duration.components
            return Double(whole) + Double(fraction) / 1.0e18
        }
        let span = seconds(duration), interval = seconds(step)
        guard span > 0, interval > 0, span / interval < 1_000_000 else { return GroundTrack(points: [], failure: nil) }
        let count = Int((span / interval).rounded(.down))
        var points: [GroundTrack.Point] = []
        points.reserveCapacity(count + 1)
        for i in 0...count {
            guard let time = try? start.advanced(by: Double(i) * interval) else {
                return GroundTrack(points: points, failure: PropagationFailure(kind: .time, minutesFromEpoch: nil))
            }
            do {
                points.append(GroundTrack.Point(time: time, position: try position(at: time)))
            } catch {
                return GroundTrack(points: points, failure: error)
            }
        }
        return GroundTrack(points: points, failure: nil)
    }
}

extension GeodeticPosition {

    /// The edge of the satellite's coverage: the places on the ground, on the WGS-84 ellipsoid, from which a
    /// satellite here stands `minimumElevation` degrees above the horizon, one on each of `points` bearings from the
    /// point beneath it, evenly spaced clockwise from north. Inside the ring the satellite is higher, outside lower.
    ///
    /// Each place is found by narrowing the distance along its bearing until the satellite's elevation from it is the
    /// one asked for, to about a millionth of a degree; the bearing is followed as a great circle. Empty when
    /// `minimumElevation` is not from 0 up to 90, `points` is below 3, or the satellite is not above the ground.
    public func footprint(minimumElevation: Double = 0, points: Int = 72) -> [GeodeticPosition] {
        guard (0.0..<90.0).contains(minimumElevation), points >= 3, altitude > 0 else { return [] }
        let satellite = StateVector(position: Observer(latitude: latitude, longitude: longitude, height: altitude * 1000).earthFixed,
                                    velocity: Vector(x: 0, y: 0, z: 0))
        let phi = latitude * Frames.radians, lambda = longitude * Frames.radians
        /// The place `angle` radians along a great circle from the point beneath, on a bearing of `theta` radians.
        func place(_ theta: Double, _ angle: Double) -> Observer {
            let to = asin(sin(phi) * cos(angle) + cos(phi) * sin(angle) * cos(theta))
            var east = (lambda + atan2(sin(theta) * sin(angle) * cos(phi), cos(angle) - sin(phi) * sin(to))) * Frames.degrees
            east = (east + 180.0).truncatingRemainder(dividingBy: 360.0)
            if east <= 0 { east += 360.0 }
            return Observer(latitude: to * Frames.degrees, longitude: east - 180.0)
        }
        var ring: [GeodeticPosition] = []
        ring.reserveCapacity(points)
        for i in 0..<points {
            let theta = 2.0 * SGP4Core.pi * Double(i) / Double(points)
            // straight beneath, the satellite is overhead; a quarter of the way round the Earth, below the horizon
            var near = 0.0, far = SGP4Core.pi / 2.0
            while far - near > 1.0e-9 {
                let middle = (near + far) / 2.0
                if Frames.look(from: place(theta, middle), to: satellite).elevation > minimumElevation { near = middle } else { far = middle }
            }
            let edge = place(theta, (near + far) / 2.0)
            ring.append(GeodeticPosition(latitude: edge.latitude, longitude: edge.longitude, altitude: 0))
        }
        return ring
    }
}
