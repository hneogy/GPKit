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
    /// Height above the ellipsoid, metres.
    public var height: Double

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
    /// Kilometres.
    public var range: Double
    /// Kilometres per second: positive while the satellite draws away, negative while it approaches.
    public var rangeRate: Double

    /// Kilometres per second.
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
        return Look(azimuth: azimuth, elevation: asin(up / range) * degrees, range: range, rangeRate: rate)
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
        let state = try state(minutesFromEpoch: minutes)
        let julianDate = elementSet.epoch.julianDate + minutes / 1440.0 + ut1LessUTC / 86_400.0
        return Frames.look(from: observer, to: Frames.earthFixed(state, julianDate: julianDate))
    }
}
