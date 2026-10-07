#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A place on the Earth, on the WGS-84 ellipsoid.
public struct Observer: Sendable, Hashable {
    /// Geodetic latitude, degrees, north positive.
    public var latitude: Double
    /// Longitude, degrees, east positive.
    public var longitude: Double
    /// Height above the ellipsoid, in metres. (A satellite's `GeodeticPosition.altitude` is in kilometres.)
    public var height: Double

    /// - Parameters:
    ///   - latitude: Geodetic latitude, degrees, north positive.
    ///   - longitude: Degrees, east positive.
    ///   - height: Metres above the WGS-84 ellipsoid. The default is on it.
    public init(latitude: Double, longitude: Double, height: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.height = height
    }

    /// The place in the Earth-fixed frame, kilometres.
    var earthFixed: Vector {
        let phi = latitude * Frames.radians, lambda = longitude * Frames.radians
        let n = Frames.equatorialRadius / (1.0 - Frames.eccentricitySquared * sin(phi) * sin(phi)).squareRoot()
        let h = height / 1000.0
        return Vector(x: (n + h) * cos(phi) * cos(lambda), y: (n + h) * cos(phi) * sin(lambda),
                      z: (n * (1.0 - Frames.eccentricitySquared) + h) * sin(phi))
    }
}

/// Where a satellite is over the Earth: the point of the WGS-84 ellipsoid beneath it, and how far above that point
/// it is. The point is the one a map shows the satellite at, and a run of them is its ground track.
public struct GeodeticPosition: Sendable, Hashable {
    /// Geodetic latitude, degrees, north positive: -90 to 90.
    public var latitude: Double
    /// Longitude, degrees, east positive: above -180, up to 180.
    public var longitude: Double
    /// Height above the ellipsoid, in kilometres. (An `Observer`'s `height` is in metres.)
    public var altitude: Double

    /// - Parameters:
    ///   - latitude: Geodetic latitude, degrees, north positive.
    ///   - longitude: Degrees, east positive.
    ///   - altitude: Kilometres above the WGS-84 ellipsoid.
    public init(latitude: Double, longitude: Double, altitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
}

/// Where a satellite is from a place: the direction to point in, how far it is, and how fast that distance is
/// changing.
///
/// The angles are geometric. The atmosphere bends the path of a signal, and near the horizon a satellite is heard
/// and seen a little before this elevation reaches zero; nothing here allows for that.
public struct Look: Sendable, Hashable {
    /// Degrees clockwise from north: 90 is east.
    public var azimuth: Double
    /// Degrees above the horizon; negative below it.
    public var elevation: Double
    /// The distance from the place to the satellite, in kilometres.
    public var range: Double
    /// How fast that distance is changing, in kilometres per second: positive while the satellite draws away,
    /// negative while it approaches.
    public var rangeRate: Double

    /// The speed of light, in kilometres per second.
    public static let speedOfLight = 299_792.458

    /// The frequency at which a signal the satellite sends on `transmitted` arrives here, in the unit given: higher
    /// while the satellite approaches, lower while it draws away. For a downlink, this is what to tune a receiver to.
    public func received(from transmitted: Double) -> Double {
        transmitted * (1.0 - rangeRate / Look.speedOfLight)
    }

    /// The frequency to send on from here for the signal to arrive at the satellite on `received`. For an uplink,
    /// this is what to tune a transmitter to.
    public func transmit(toBeReceivedAt received: Double) -> Double {
        received / (1.0 - rangeRate / Look.speedOfLight)
    }
}

/// The frames a position passes through between SGP4 and a place on the ground.
enum Frames {
    static let radians = SGP4Core.pi / 180.0
    static let degrees = 180.0 / SGP4Core.pi
    // WGS-84
    static let equatorialRadius = 6378.137                     // kilometres
    static let flattening = 1.0 / 298.257223563
    static let eccentricitySquared = flattening * (2.0 - flattening)
    /// The Earth's rotation, radians per second.
    static let rotationRate = 7.292115146706979e-5

    /// TEME to the Earth-fixed frame: a turn about the pole by Greenwich mean sidereal time, with the Earth's
    /// rotation taken out of the velocity. UT1 is taken to be UTC, which it is to within 0.9 s, and the motion of
    /// the pole is left out; together they move a place on the ground by well under a kilometre.
    static func earthFixed(_ state: StateVector, julianDate: Double) -> StateVector {
        let theta = SGP4Core.gstime(julianDate)
        let c = cos(theta), s = sin(theta)
        let r = Vector(x: c * state.position.x + s * state.position.y, y: -s * state.position.x + c * state.position.y, z: state.position.z)
        let v = Vector(x: c * state.velocity.x + s * state.velocity.y + rotationRate * r.y,
                       y: -s * state.velocity.x + c * state.velocity.y - rotationRate * r.x, z: state.velocity.z)
        return StateVector(position: r, velocity: v)
    }

    /// A point of the Earth-fixed frame, kilometres, as latitude, longitude and height on the WGS-84 ellipsoid.
    ///
    /// The latitude is found by repeating the step from a latitude to the one it implies, which gains more than
    /// two digits a turn for a point on or above the ground and stops changing at the last bit within a few turns.
    /// The height is then taken along the vertical at that latitude, in a form that holds at the poles.
    static func geodetic(_ r: Vector) -> GeodeticPosition {
        let p = (r.x * r.x + r.y * r.y).squareRoot()
        var phi = atan2(r.z, p * (1.0 - eccentricitySquared))   // exact on the ellipsoid, and a start off it
        for _ in 0..<12 {
            let s = sin(phi)
            let n = equatorialRadius / (1.0 - eccentricitySquared * s * s).squareRoot()
            let next = atan2(r.z + n * eccentricitySquared * s, p)
            let moved = abs(next - phi)
            phi = next
            if moved < 1.0e-15 { break }
        }
        let s = sin(phi), c = cos(phi)
        let altitude = p * c + r.z * s - equatorialRadius * (1.0 - eccentricitySquared * s * s).squareRoot()
        var longitude = atan2(r.y, r.x) * degrees
        if longitude <= -180.0 { longitude += 360.0 }
        return GeodeticPosition(latitude: phi * degrees, longitude: longitude, altitude: altitude)
    }

    /// The look from a place to a satellite, both in the Earth-fixed frame.
    static func look(from observer: Observer, to satellite: StateVector) -> Look {
        let site = observer.earthFixed
        let phi = observer.latitude * radians, lambda = observer.longitude * radians
        let dx = satellite.position.x - site.x, dy = satellite.position.y - site.y, dz = satellite.position.z - site.z
        let east = -sin(lambda) * dx + cos(lambda) * dy
        let north = -sin(phi) * cos(lambda) * dx - sin(phi) * sin(lambda) * dy + cos(phi) * dz
        let up = cos(phi) * cos(lambda) * dx + cos(phi) * sin(lambda) * dy + sin(phi) * dz
        let range = (dx * dx + dy * dy + dz * dz).squareRoot()
        var azimuth = atan2(east, north) * degrees
        if azimuth < 0 { azimuth += 360.0 }
        // the place does not move in this frame, so the satellite's velocity is the rate of the line between them
        let rate = (dx * satellite.velocity.x + dy * satellite.velocity.y + dz * satellite.velocity.z) / range
        // by the arc tangent, which is good to the last digits straight overhead, where an arc sine of up over
        // range is not, and where rounding can put that ratio above one
        let elevation = atan2(up, (east * east + north * north).squareRoot()) * degrees
        return Look(azimuth: azimuth, elevation: elevation, range: range, rangeRate: rate)
    }
}

extension Propagator {

    /// The satellite as seen from a place at an instant of UTC.
    public func look(from observer: Observer, at time: Epoch) throws(PropagationFailure) -> Look {
        try look(from: observer, minutes: time.seconds(since: elementSet.epoch) / 60.0)
    }

    /// The look at a number of minutes from the element set's epoch. `ut1LessUTC`, seconds, turns the Earth by
    /// UT1 in place of UTC; the public interface leaves it at zero, and the tests use it to measure what that costs.
    func look(from observer: Observer, minutes: Double, ut1LessUTC: Double = 0) throws(PropagationFailure) -> Look {
        Frames.look(from: observer, to: try earthFixed(minutes: minutes, ut1LessUTC: ut1LessUTC))
    }

    /// The point of the ellipsoid beneath the satellite, in degrees, and its height above that point, in
    /// kilometres, at an instant of UTC: where to draw it on a map. Asked for at a run of instants, it is the
    /// ground track.
    public func position(at time: Epoch) throws(PropagationFailure) -> GeodeticPosition {
        try position(minutes: time.seconds(since: elementSet.epoch) / 60.0)
    }

    /// The same at a number of minutes from the element set's epoch, with the tests' door for UT1.
    func position(minutes: Double, ut1LessUTC: Double = 0) throws(PropagationFailure) -> GeodeticPosition {
        Frames.geodetic(try earthFixed(minutes: minutes, ut1LessUTC: ut1LessUTC).position)
    }

    /// The state in the Earth-fixed frame at a number of minutes from the element set's epoch.
    func earthFixed(minutes: Double, ut1LessUTC: Double) throws(PropagationFailure) -> StateVector {
        let state = try state(minutesFromEpoch: minutes)
        let julianDate = elementSet.epoch.julianDate + minutes / 1440.0 + ut1LessUTC / 86_400.0
        return Frames.earthFixed(state, julianDate: julianDate)
    }
}
