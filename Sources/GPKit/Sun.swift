#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(ucrt)
import ucrt
#endif

/// Where the sun is, as closely as two questions need it: is the sky dark at a place, and is a satellite in sunlight.
///
/// The position is worked out the way NOAA's solar calculators work it out, after Jean Meeus's Astronomical
/// Algorithms: the sun's mean longitude and mean anomaly with their slow changes, three terms for the ellipse of the
/// Earth's orbit, and the larger terms of aberration and nutation. Against the US Naval Observatory's figures for
/// these years it is good to a few thousandths of a degree, which moves a sunset by about a second. UTC stands in for
/// both of the time scales the formulas are written in; the difference is below that.
public enum Sun {

    /// The sun more than this far below the horizon is a dark sky: the end of civil twilight, degrees.
    public static let darkBelow = -6.0

    /// The radius of the Earth's shadow, kilometres: the WGS-84 equatorial radius.
    public static let shadowRadius = Frames.equatorialRadius

    /// Julian centuries from 2000 January 1, 12:00, to an instant.
    static func centuries(_ time: Epoch) -> Double {
        (time.julianDate - 2_451_545.0) / 36_525.0
    }

    /// The sun's longitude along the ecliptic as it is seen, and the tilt of the ecliptic to the equator, with the
    /// nodding of the Earth's axis in both: degrees. `nodding` is its part in the longitude alone.
    static func ecliptic(at time: Epoch) -> (longitude: Double, obliquity: Double, nodding: Double) {
        let t = centuries(time)
        let radians = Frames.radians
        let meanLongitude = 280.46646 + t * (36_000.76983 + 0.0003032 * t)
        let meanAnomaly = (357.52911 + t * (35_999.05029 - 0.0001537 * t)) * radians
        let centre = sin(meanAnomaly) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2.0 * meanAnomaly) * (0.019993 - 0.000101 * t)
            + sin(3.0 * meanAnomaly) * 0.000289
        // the node of the moon's orbit, which the nodding of the axis follows
        let node = (125.04 - 1934.136 * t) * radians
        let nodding = -0.00478 * sin(node)
        // 0.00569 degrees is the aberration of light: the sun is seen where it was eight minutes before
        let longitude = meanLongitude + centre - 0.00569 + nodding
        let seconds = 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))
        let obliquity = 23.0 + (26.0 + seconds / 60.0) / 60.0 + 0.00256 * cos(node)
        return (longitude, obliquity, nodding)
    }

    /// The sun's right ascension and declination at an instant of UTC as it is seen, for the equator and the equinox
    /// of that instant.
    public static func equatorial(at time: Epoch) -> EquatorialPosition {
        let (longitude, obliquity, _) = ecliptic(at: time)
        let lambda = longitude * Frames.radians, epsilon = obliquity * Frames.radians
        var rightAscension = atan2(cos(epsilon) * sin(lambda), cos(lambda)) * Frames.degrees
        if rightAscension < 0 { rightAscension += 360.0 }
        return EquatorialPosition(rightAscension: rightAscension, declination: asin(sin(epsilon) * sin(lambda)) * Frames.degrees)
    }

    /// How far the equinox itself is moved along the equator by the nodding of the Earth's axis, degrees: what
    /// sidereal time as the stars show it has over mean sidereal time.
    static func equationOfTheEquinoxes(at time: Epoch) -> Double {
        let (_, obliquity, nodding) = ecliptic(at: time)
        return nodding * cos(obliquity * Frames.radians)
    }

    /// Greenwich mean sidereal time, degrees from 0 up to 360: the angle by which `Propagator` turns TEME to the
    /// Earth-fixed frame, so that the sun and a satellite are turned alike.
    static func greenwichAngle(at time: Epoch) -> Double {
        SGP4Core.gstime(time.julianDate) * Frames.degrees
    }

    /// How far west of the Greenwich meridian the sun stands at an instant, degrees from 0 up to 360.
    static func greenwichHourAngle(at time: Epoch) -> Double {
        let angle = (greenwichAngle(at: time) + equationOfTheEquinoxes(at: time) - equatorial(at: time).rightAscension)
            .truncatingRemainder(dividingBy: 360.0)
        return angle < 0 ? angle + 360.0 : angle
    }

    /// The direction of the sun from the Earth's centre at an instant of UTC, a vector of length one in the frame
    /// `Propagator`'s positions are in, TEME: the equator of the day, z towards the north pole, and x towards the
    /// equinox without its nodding, which is where mean sidereal time is counted from.
    public static func direction(at time: Epoch) -> Vector {
        let sun = equatorial(at: time)
        let alpha = (sun.rightAscension - equationOfTheEquinoxes(at: time)) * Frames.radians
        let delta = sun.declination * Frames.radians
        return Vector(x: cos(delta) * cos(alpha), y: cos(delta) * sin(alpha), z: sin(delta))
    }

    /// How high the centre of the sun is at a place, degrees above the horizon; below it, negative. Geometric, like
    /// every angle in GPKit: the air's bending of the light, about half a degree at the horizon, is not allowed for.
    public static func elevation(at time: Epoch, from observer: Observer) -> Double {
        let sun = direction(at: time)
        let latitude = observer.latitude * Frames.radians
        let turned = (greenwichAngle(at: time) + observer.longitude) * Frames.radians
        // straight up at the place, the normal to the ellipsoid, in TEME
        let up = Vector(x: cos(latitude) * cos(turned), y: cos(latitude) * sin(turned), z: sin(latitude))
        return asin(min(1.0, max(-1.0, up.x * sun.x + up.y * sun.y + up.z * sun.z))) * Frames.degrees
    }

    /// Whether the sun shines on a point, kilometres from the Earth's centre in TEME, as `Propagator` gives it.
    ///
    /// The Earth's shadow is taken for a cylinder as wide as the equator, straight behind the Earth. The real one
    /// tapers a little, has a soft edge, and is narrower over the poles, so for a low orbit the instant a satellite
    /// goes into it or comes out can be a few seconds from what this says.
    public static func lights(_ position: Vector, at time: Epoch) -> Bool {
        let sun = direction(at: time)
        let along = position.x * sun.x + position.y * sun.y + position.z * sun.z
        if along >= 0 { return true }
        let across = Vector(x: position.x - along * sun.x, y: position.y - along * sun.y, z: position.z - along * sun.z)
        return across.magnitude > shadowRadius
    }
}

/// A direction on the sky: right ascension and declination, degrees.
public struct EquatorialPosition: Sendable, Hashable {
    /// Degrees east along the equator from the equinox, 0 up to 360.
    public var rightAscension: Double
    /// Degrees north of the equator, -90 to 90.
    public var declination: Double

    public init(rightAscension: Double, declination: Double) {
        self.rightAscension = rightAscension
        self.declination = declination
    }
}

/// The light at one instant: the sky at a place, and the sun on a satellite seen from there.
public struct Sunlight: Sendable, Hashable {

    /// The sky at a place, by how high the sun is.
    public enum Sky: String, Sendable, Hashable, CaseIterable {
        /// The sun is above the horizon.
        case daylight
        /// The sun is below the horizon by no more than six degrees.
        case twilight
        /// The sun is more than six degrees down.
        case dark

        public init(sunElevation: Double) {
            if sunElevation > 0 {
                self = .daylight
            } else if sunElevation >= Sun.darkBelow {
                self = .twilight
            } else {
                self = .dark
            }
        }
    }

    /// How high the sun is at the place, degrees.
    public var sunElevation: Double
    /// Whether the satellite is in sunlight.
    public var isSunlit: Bool
    /// The angle at the satellite between the sun and the place, degrees: 0 when the place sees its whole lit face,
    /// 180 when it sees none of it.
    public var phaseAngle: Double
    /// The distance from the place to the satellite, kilometres.
    public var range: Double

    public init(sunElevation: Double, isSunlit: Bool, phaseAngle: Double, range: Double) {
        self.sunElevation = sunElevation
        self.isSunlit = isSunlit
        self.phaseAngle = phaseAngle
        self.range = range
    }

    /// The sky at the place.
    public var sky: Sky { Sky(sunElevation: sunElevation) }

    /// True when the satellite is in sunlight and the sky at the place is dark: it can be seen with the eye, if it is
    /// bright enough and above the horizon.
    public var canBeSeen: Bool { isSunlit && sky == .dark }

    /// An estimate of how bright the satellite looks, as a visual magnitude, from its standard magnitude: the one it
    /// has at 1000 km with the sun at 90 degrees to the line of sight. nil when it is in the Earth's shadow.
    ///
    /// The satellite is taken for a sphere that scatters the light evenly, by the phase correction of Mallama (2021),
    /// "The Brightness of VisorSat-Design Starlink Satellites", Equation 1, and the distance by the inverse square.
    /// Few satellites are spheres, a flat panel least of all, and a glint off one can be magnitudes brighter; the
    /// standard magnitude comes from observations of the satellite, which GPKit does not hold.
    public func magnitude(standard: Double) -> Double? {
        guard isSunlit else { return nil }
        let lit = 0.5 + 0.5 * cos(phaseAngle * Frames.radians)
        guard lit > 0 else { return .infinity }
        // the paper's correction, added to the 1000-km magnitude to give the standard one, taken off again here. Its
        // constant is the one that makes the correction zero at 90 degrees, -2.5 log10(0.5), which it gives as 0.753.
        let correction = 2.5 * log10(lit) - 2.5 * log10(0.5)
        return standard - correction + 5.0 * log10(range / 1000.0)
    }
}

/// The light a pass happens in: the sky at the place when the satellite is highest, and when in the pass the
/// satellite is in sunlight, and in sunlight under a dark sky.
public struct PassVisibility: Sendable, Hashable {

    /// A stretch of a pass, from its first instant to its last, each found to a second.
    public struct Stretch: Sendable, Hashable {
        public var start: Epoch
        public var end: Epoch

        public init(start: Epoch, end: Epoch) {
            self.start = start
            self.end = end
        }
    }

    /// The light at the pass's culmination.
    public var culmination: Sunlight
    /// The stretch of the pass the satellite is in sunlight; nil when it is in the Earth's shadow all the way.
    public var sunlit: Stretch?
    /// The stretch it is in sunlight while the sky at the place is dark: when it can be seen with the eye, if it is
    /// bright enough. nil when there is none.
    public var visible: Stretch?

    public init(culmination: Sunlight, sunlit: Stretch?, visible: Stretch?) {
        self.culmination = culmination
        self.sunlit = sunlit
        self.visible = visible
    }

    /// True when the satellite can be seen at some time in the pass.
    public var canBeSeen: Bool { visible != nil }
}

extension Propagator {

    /// The light at an instant of UTC: the sky at a place, and the sun on the satellite as seen from there.
    public func sunlight(from observer: Observer, at time: Epoch) throws(PropagationFailure) -> Sunlight {
        let minutes = time.seconds(since: elementSet.epoch) / 60.0
        let satellite = try state(minutesFromEpoch: minutes).position
        // the place in TEME: its Earth-fixed position turned back by the angle the satellite is turned by
        let theta = SGP4Core.gstime(elementSet.epoch.julianDate + minutes / 1440.0)
        let fixed = observer.earthFixed
        let site = Vector(x: cos(theta) * fixed.x - sin(theta) * fixed.y, y: sin(theta) * fixed.x + cos(theta) * fixed.y, z: fixed.z)
        let toPlace = Vector(x: site.x - satellite.x, y: site.y - satellite.y, z: site.z - satellite.z)
        let sun = Sun.direction(at: time)
        let range = toPlace.magnitude
        let cosine = (toPlace.x * sun.x + toPlace.y * sun.y + toPlace.z * sun.z) / range
        return Sunlight(sunElevation: Sun.elevation(at: time, from: observer), isSunlit: Sun.lights(satellite, at: time),
                        phaseAngle: acos(min(1.0, max(-1.0, cosine))) * Frames.degrees, range: range)
    }

    /// Whether the satellite is in sunlight at an instant, and whether the sky at a place is dark then; nil when the
    /// satellite cannot be propagated to it.
    func litAndDark(at time: Epoch, from observer: Observer) -> (lit: Bool, dark: Bool)? {
        do {
            let position = try state(at: time).position
            return (Sun.lights(position, at: time), Sun.elevation(at: time, from: observer) < Sun.darkBelow)
        } catch {
            return nil
        }
    }

    /// The light of a pass over a place: from its rise to its set, or from its culmination where it has no rise or no
    /// set (a pass cut off by the start or the end of its search). nil when the satellite cannot be propagated
    /// through the pass.
    ///
    /// The pass is looked at every ten seconds, at 240 instants at most, and each change, into the Earth's shadow or
    /// out, the sky darkening or growing light, is then narrowed to a second.
    public func visibility(of pass: Pass, from observer: Observer) -> PassVisibility? {
        let start = pass.rise?.time ?? pass.culmination.time
        let end = pass.set?.time ?? pass.culmination.time
        let length = end.seconds(since: start)
        guard length >= 0, let culmination = try? sunlight(from: observer, at: pass.culmination.time) else { return nil }

        func at(_ seconds: Double) -> Epoch? { try? start.advanced(by: seconds) }
        /// Whether the satellite is in sunlight a number of seconds into the pass, and whether the sky is dark then.
        func look(_ seconds: Double) -> (lit: Bool, dark: Bool)? {
            guard let time = at(seconds) else { return nil }
            return litAndDark(at: time, from: observer)
        }
        /// The second, between one where `wanted` holds and one where it does not, at which it changes.
        func change(from holds: Double, to fails: Double, _ wanted: ((lit: Bool, dark: Bool)) -> Bool) -> Double {
            var inside = holds, outside = fails
            while abs(outside - inside) > 1.0 {
                let middle = (inside + outside) / 2.0
                if let seen = look(middle), wanted(seen) { inside = middle } else { outside = middle }
            }
            return inside
        }
        typealias Sample = (seconds: Double, seen: (lit: Bool, dark: Bool))
        func stretch(_ samples: [Sample], _ wanted: ((lit: Bool, dark: Bool)) -> Bool) -> PassVisibility.Stretch? {
            guard let first = samples.firstIndex(where: { wanted($0.seen) }),
                  let last = samples.lastIndex(where: { wanted($0.seen) }) else { return nil }
            let from = first == 0 ? samples[0].seconds : change(from: samples[first].seconds, to: samples[first - 1].seconds, wanted)
            let to = last == samples.count - 1 ? samples[last].seconds : change(from: samples[last].seconds, to: samples[last + 1].seconds, wanted)
            guard let a = at(from), let b = at(max(from, to)) else { return nil }
            return PassVisibility.Stretch(start: a, end: b)
        }

        let steps = max(1, min(239, Int((length / 10.0).rounded(.up))))
        var samples: [Sample] = []
        samples.reserveCapacity(steps + 1)
        for i in 0...steps {
            let seconds = length * Double(i) / Double(steps)
            guard let seen = look(seconds) else { return nil }
            samples.append((seconds, seen))
        }
        return PassVisibility(culmination: culmination, sunlit: stretch(samples) { $0.lit },
                              visible: stretch(samples) { $0.lit && $0.dark })
    }
}
