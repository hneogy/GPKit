/// A point or a rate in three dimensions, in the unit of what it holds: kilometres for a position, kilometres per
/// second for a velocity.
public struct Vector: Sendable, Hashable {
    /// The first component: kilometres in a position, kilometres per second in a velocity.
    public var x: Double
    /// The second component: kilometres in a position, kilometres per second in a velocity.
    public var y: Double
    /// The third component: kilometres in a position, kilometres per second in a velocity.
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// The length: kilometres for a position, kilometres per second for a velocity.
    public var magnitude: Double { (x * x + y * y + z * z).squareRoot() }
}

/// Where a satellite is and how it is moving, in the frame SGP4 works in: true equator, mean equinox of the
/// instant (TEME), with the Earth's centre at the origin.
public struct StateVector: Sendable, Hashable {
    /// The position, in kilometres from the Earth's centre.
    public var position: Vector
    /// The velocity, in kilometres per second.
    public var velocity: Vector
}

/// Why an element set cannot be propagated, or cannot be propagated to a time.
public struct PropagationFailure: Error, Sendable, Hashable, CustomStringConvertible {

    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// The element set is not for SGP4: its `MEAN_ELEMENT_THEORY` is another, or its ephemeris type is 4 (SGP4-XP).
        case notSGP4
        /// The mean eccentricity has reached 1, or gone below -0.001.
        case eccentricity
        /// The mean motion is zero or negative.
        case meanMotion
        /// The eccentricity with the lunar and solar terms applied is outside 0 to 1.
        case perturbedEccentricity
        /// The semi-latus rectum is negative.
        case semiLatusRectum
        /// The satellite has decayed: the position comes out below the Earth's surface.
        case decayed
        /// The time asked for is not one this library can count to.
        case time
    }

    public let kind: Kind
    /// Minutes from the element set's epoch at which propagation stopped; nil when it never began.
    public let minutesFromEpoch: Double?

    public var description: String {
        let what: String
        switch kind {
        case .notSGP4: what = "the element set is not for SGP4"
        case .eccentricity: what = "the mean eccentricity is 1 or more, or below -0.001"
        case .meanMotion: what = "the mean motion is zero or less"
        case .perturbedEccentricity: what = "the perturbed eccentricity is outside 0 to 1"
        case .semiLatusRectum: what = "the semi-latus rectum is negative"
        case .decayed: what = "the satellite has decayed"
        case .time: what = "the time is outside what can be counted"
        }
        return minutesFromEpoch.map { "\(what), at \($0) minutes from the epoch" } ?? what
    }
}

/// SGP4 for one element set.
///
/// The propagator is a port of David Vallado's SGP4, checked in the tests against the C++ itself (see NOTICE and the
/// README). A `Propagator` is a value: making one does the initialisation, and every call after that is
/// independent of the calls before it, so one can be shared between tasks.
public struct Propagator: Sendable {

    /// The constants the Earth's gravity is modelled with. Element sets are fitted with WGS-72, and that is the
    /// default; the others are for comparison with software that uses them.
    public enum Gravity: Sendable, Hashable {
        case wgs72
        case wgs84
        /// The constants of the 1980 report, as its FORTRAN had them.
        case wgs72old
    }

    public let elementSet: ElementSet
    public let gravity: Gravity
    let core: SGP4Core

    /// How the element set's epoch becomes the count of days SGP4 starts from.
    public enum EpochReading: Sendable, Hashable {
        /// The epoch exactly as the set states it: the default, and what every other initialiser uses.
        case exact
        /// The epoch as David Vallado's C++ reader makes it from a TLE's epoch field: the field's day of the year
        /// read as a `Double`, taken through a month, a day, an hour, a minute and a second (his `days2mdhms`), and
        /// back to a Julian date and its fraction (his `jday`), whose sum less 2,433,281.5 is the count. It lands up to
        /// about 20 microseconds from the exact epoch. A set that did not come from a TLE is first rounded as a TLE
        /// writes its epoch, to a hundred-millionth of a day.
        ///
        /// For matching his published verification output, `tcppver.out`, to its last digits: with it, set 23333 of
        /// `SGP4-VER.TLE` (eccentricity 0.97) agrees to 7e-9 km, where the exact epoch puts it 4e-6 km away. Times
        /// given to `state(minutesFromEpoch:)` are minutes from this epoch, as his `tsince` is; `state(at:)` still
        /// counts them from the set's stated epoch.
        case vallado
    }

    /// Initialises the propagation of an element set. Refuses one that is not for SGP4.
    ///
    /// The epoch is the element set's own, exactly. Vallado's reader takes a TLE's epoch through a calendar date
    /// and back and lands up to 20 microseconds away, so a position from here and one from that reader can differ
    /// by what those microseconds are worth: nothing that shows for most orbits, millimetres for a few. To match his
    /// reader instead, use `init(_:gravity:epochReading:)` with `.vallado`.
    public init(_ elementSet: ElementSet, gravity: Gravity = .wgs72) throws(PropagationFailure) {
        try self.init(elementSet, gravity: gravity, epochReading: .exact)
    }

    /// Initialises the propagation of an element set with its epoch read as `epochReading` says. Refuses one that is
    /// not for SGP4.
    public init(_ elementSet: ElementSet, gravity: Gravity = .wgs72, epochReading: EpochReading) throws(PropagationFailure) {
        guard elementSet.isSGP4, elementSet.ephemerisType != 4 else {
            throw PropagationFailure(kind: .notSGP4, minutesFromEpoch: nil)
        }
        self.elementSet = elementSet
        self.gravity = gravity
        let model: SGP4Core.Gravity
        switch gravity {
        case .wgs72: model = .wgs72
        case .wgs84: model = .wgs84
        case .wgs72old: model = .wgs72old
        }
        switch epochReading {
        case .exact: core = SGP4Core(elementSet, gravity: model)
        case .vallado: core = SGP4Core(elementSet, gravity: model, epoch: elementSet.epoch.valladoDaysSince1950)
        }
    }

    /// The state a number of minutes from the element set's epoch, before it or after.
    public func state(minutesFromEpoch minutes: Double) throws(PropagationFailure) -> StateVector {
        guard minutes.isFinite else { throw PropagationFailure(kind: .time, minutesFromEpoch: minutes) }
        var copy = core
        var r = (0.0, 0.0, 0.0), v = (0.0, 0.0, 0.0)
        _ = copy.sgp4(minutes, &r, &v)
        switch copy.error {
        case 0: return StateVector(position: Vector(x: r.0, y: r.1, z: r.2), velocity: Vector(x: v.0, y: v.1, z: v.2))
        case 1: throw PropagationFailure(kind: .eccentricity, minutesFromEpoch: minutes)
        case 2: throw PropagationFailure(kind: .meanMotion, minutesFromEpoch: minutes)
        case 3: throw PropagationFailure(kind: .perturbedEccentricity, minutesFromEpoch: minutes)
        case 4: throw PropagationFailure(kind: .semiLatusRectum, minutesFromEpoch: minutes)
        default: throw PropagationFailure(kind: .decayed, minutesFromEpoch: minutes)
        }
    }

    /// The state at an instant of UTC.
    public func state(at time: Epoch) throws(PropagationFailure) -> StateVector {
        try state(minutesFromEpoch: time.seconds(since: elementSet.epoch) / 60.0)
    }
}
