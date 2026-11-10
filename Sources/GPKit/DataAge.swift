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

/// The class of orbit an element set describes, by ESA's orbit classes: what the error to expect at an age depends on
/// most, so the data-age measurement is kept by class.
///
/// The classes and their ranges are those of the ESA Space Debris Office's Annual Space Environment Report (the table
/// "Orbit class definitions"; ESA/ESOC, Darmstadt), each the report's abbreviation as its raw value. They are given
/// there by perigee and apogee height (h_p, h_a, km), semi-major axis (a, km), eccentricity (e) and inclination
/// (i, degrees):
///
/// | class | range |
/// |---|---|
/// | GEO | i 0 to 25, h_p and h_a 35,586 to 35,986 |
/// | IGO | a 37,948 to 46,380, e 0 to 0.25, i 25 to 180 |
/// | EGO | a 37,948 to 46,380, e 0 to 0.25, i 0 to 25 |
/// | NSO | i 50 to 70, h_p and h_a 18,100 to 24,300 |
/// | GTO | i 0 to 90, h_p 0 to 2,000, h_a 31,570 to 40,000 |
/// | MEO | h_p and h_a 2,000 to 31,570 |
/// | GHO | h_p 31,570 to 40,000, h_a above 40,000 |
/// | LEO | h_p and h_a 0 to 2,000 |
/// | HEO | h_p 0 to 31,570, h_a above 40,000 |
/// | MGO | h_p 2,000 to 31,570, h_a 31,570 to 40,000 |
/// | LMO | h_p 0 to 2,000, h_a 2,000 to 31,570 |
/// | UFO | none of the above |
///
/// GPKit tests them in that order, the first that holds, each range including both its ends, so a geostationary orbit
/// is GEO and not also EGO. The report's ESO (escape orbits) does not arise: an element set's orbit is closed. The
/// semi-major axis is Kepler's from the mean motion, with WGS-72's gravitational parameter (398,600.8 km³/s²), and
/// heights are above WGS-72's equatorial radius (6,378.135 km); a set below the surface at perigee is still LEO or
/// another class by its numbers, never refused, and a mean motion that is not positive is UFO.
///
/// The class is only as exact as that: the mean motion a set carries is SGP4's (Kozai's) mean, not an osculating
/// value, and Kepler's law on it puts the semi-major axis a few kilometres from the osculating one in low Earth, so a
/// satellite within a few kilometres of a range's end can change class from one fit to the next.
public enum OrbitRegime: String, Sendable, Hashable, CaseIterable {
    case geostationary = "GEO"
    case inclinedGeosynchronous = "IGO"
    case extendedGeostationary = "EGO"
    case navigationSatellites = "NSO"
    case geostationaryTransfer = "GTO"
    case mediumEarth = "MEO"
    case geoSuperGeoCrossing = "GHO"
    case lowEarth = "LEO"
    case highlyEccentric = "HEO"
    case meoGeoCrossing = "MGO"
    case leoMeoCrossing = "LMO"
    case undefined = "UFO"

    /// The class of an orbit of `meanMotion` revolutions a day, eccentricity `eccentricity` and inclination
    /// `inclination` degrees.
    public init(meanMotion: Double, eccentricity: Double, inclination: Double) {
        let mu = 398_600.8, radius = 6_378.135
        guard meanMotion > 0, meanMotion.isFinite else { self = .undefined; return }
        let n = meanMotion * 2 * Double.pi / 86_400
        let a = pow(mu / (n * n), 1.0 / 3.0)
        self.init(semiMajorAxis: a, eccentricity: eccentricity, inclination: inclination, radius: radius)
    }

    init(semiMajorAxis a: Double, eccentricity e: Double, inclination i: Double, radius: Double) {
        let hp = a * (1 - e) - radius, ha = a * (1 + e) - radius
        func within(_ x: Double, _ lo: Double, _ hi: Double) -> Bool { x >= lo && x <= hi }
        if within(i, 0, 25) && within(hp, 35_586, 35_986) && within(ha, 35_586, 35_986) { self = .geostationary }
        else if within(a, 37_948, 46_380) && within(e, 0, 0.25) && within(i, 25, 180) { self = .inclinedGeosynchronous }
        else if within(a, 37_948, 46_380) && within(e, 0, 0.25) && within(i, 0, 25) { self = .extendedGeostationary }
        else if within(i, 50, 70) && within(hp, 18_100, 24_300) && within(ha, 18_100, 24_300) { self = .navigationSatellites }
        else if within(i, 0, 90) && hp <= 2_000 && within(ha, 31_570, 40_000) { self = .geostationaryTransfer }
        else if within(hp, 2_000, 31_570) && within(ha, 2_000, 31_570) { self = .mediumEarth }
        else if within(hp, 31_570, 40_000) && ha > 40_000 { self = .geoSuperGeoCrossing }
        else if hp <= 2_000 && ha <= 2_000 { self = .lowEarth }
        else if hp <= 31_570 && ha > 40_000 { self = .highlyEccentric }
        else if within(hp, 2_000, 31_570) && within(ha, 31_570, 40_000) { self = .meoGeoCrossing }
        else if hp <= 2_000 && within(ha, 2_000, 31_570) { self = .leoMeoCrossing }
        else { self = .undefined }
    }
}

extension ElementSet {
    /// The regime of the orbit this set describes.
    public var regime: OrbitRegime {
        OrbitRegime(meanMotion: meanMotion.double, eccentricity: eccentricity.double, inclination: inclination.double)
    }

    /// How old this set is at `time`, in days: the time since its epoch, negative before it.
    public func age(at time: Epoch) -> Double { time.seconds(since: epoch) / 86_400 }
}

/// The error to expect from an element set as it ages, **measured, not quoted**: older sets of a satellite are
/// propagated to the epochs of its newer sets and compared with them there, and the differences are summed up as
/// percentiles by regime and age.
///
/// The newer set at its own epoch stands for the truth. It is not the truth: it is the provider's next fit, with
/// errors of its own, so what this measures is how far an old set drifts from the fits that follow it. GPKit ships
/// no table of its own yet: a measurement is made with `samples(_:maximumAge:)` and `table(_:edges:)`, and an
/// estimate read from such a table with `estimate(for:at:from:)`.
public enum DataAge {

    /// One older set of a satellite at the epoch of one newer set of the same satellite.
    public struct Sample: Sendable, Hashable {
        /// The catalog number both sets carry.
        public let catalogNumber: Int
        /// The older set's regime.
        public let regime: OrbitRegime
        /// The older set's epoch.
        public let older: Epoch
        /// The newer set's epoch, where the two are compared.
        public let newer: Epoch
        /// The older set's age at the newer set's epoch, in days.
        public let age: Double
        /// The distance between the two positions, in kilometres.
        public let positionError: Double
        /// The difference (older minus newer) along the newer set's position: up, positive. Kilometres.
        public let radial: Double
        /// The difference in the newer set's orbital plane at right angles to the radial, toward its motion (the
        /// transverse direction, c × r): ahead, positive. Kilometres. On a circular orbit it is along the velocity; on
        /// an eccentric one the two part by the flight-path angle.
        public let inTrack: Double
        /// The difference across the newer set's orbital plane, along its angular momentum. Kilometres.
        public let crossTrack: Double
    }

    /// Every pair of sets of one satellite, the older propagated to the newer's epoch, the age more than 0 and at most
    /// `maximumAge` days, by catalog number, then the older set's epoch, then the newer's.
    ///
    /// Sets with no catalog number are left out. A set given more than once (the same set in overlapping files) counts
    /// once. Sets of one satellite that share an epoch and differ are all left out: which is the provider's fit cannot
    /// be told. A pair that either set cannot be propagated for is counted in `failures`, and no sample is made of it.
    public static func samples(_ sets: [ElementSet], maximumAge: Double = 30) -> (samples: [Sample], failures: Int) {
        var bySatellite: [Int: Set<ElementSet>] = [:]
        for set in sets {
            guard let number = set.catalogNumber else { continue }
            bySatellite[number, default: []].insert(set)
        }
        var samples: [Sample] = []
        var failures = 0
        for number in bySatellite.keys.sorted() {
            let byEpoch = Dictionary(grouping: bySatellite[number]!, by: \.epoch)
            let ordered = byEpoch.values.compactMap { $0.count == 1 ? $0[0] : nil }.sorted { $0.epoch < $1.epoch }
            // each set's propagator, and its state at its own epoch (the truth for every pair it ends), made once
            let propagators = ordered.map { try? Propagator($0) }
            let truths = zip(ordered, propagators).map { set, propagator in try? propagator?.state(at: set.epoch) }
            for i in ordered.indices {
                for j in ordered.indices where j > i {
                    let age = ordered[i].age(at: ordered[j].epoch)
                    guard age <= maximumAge else { break }   // sorted by epoch: every later pair is older still
                    guard let drifted = try? propagators[i]?.state(at: ordered[j].epoch), let truth = truths[j] else {
                        failures += 1
                        continue
                    }
                    let delta = difference(drifted.position, truth.position)
                    let (radial, inTrack, crossTrack) = components(of: delta, along: truth)
                    samples.append(Sample(catalogNumber: number, regime: ordered[i].regime, older: ordered[i].epoch,
                                          newer: ordered[j].epoch, age: age, positionError: delta.magnitude,
                                          radial: radial, inTrack: inTrack, crossTrack: crossTrack))
                }
            }
        }
        return (samples, failures)
    }

    /// Percentiles of a sample of errors, by nearest rank: the smallest value with at least that share of the
    /// sample at or below it.
    public struct Percentiles: Sendable, Hashable {
        /// How many values they are of.
        public let count: Int
        public let median: Double
        public let p68: Double
        public let p95: Double
        public let maximum: Double

        /// nil for an empty sample, or one holding a value that is not finite.
        public init?(_ values: [Double]) {
            guard !values.isEmpty, values.allSatisfy(\.isFinite) else { return nil }
            let sorted = values.sorted()
            func rank(_ share: Double) -> Double {
                // nearest rank: the ceiling of share × count, counting from 1, in integers so 0.5 × 4 is exactly 2
                let n = sorted.count
                let hundredths = Int((share * 100).rounded())
                return sorted[max(1, (hundredths * n + 99) / 100) - 1]
            }
            count = sorted.count
            median = rank(0.5)
            p68 = rank(0.68)
            p95 = rank(0.95)
            maximum = sorted[sorted.count - 1]
        }
    }

    /// One row of a measured table: the position errors of one regime's sets at ages from `fromAge` (exclusive) to
    /// `toAge` (inclusive), in days.
    public struct Row: Sendable, Hashable {
        public let regime: OrbitRegime
        public let fromAge: Double
        public let toAge: Double
        public let positionError: Percentiles

        public init(regime: OrbitRegime, fromAge: Double, toAge: Double, positionError: Percentiles) {
            self.regime = regime
            self.fromAge = fromAge
            self.toAge = toAge
            self.positionError = positionError
        }
    }

    /// A table from samples: one row for each class and each span of age between consecutive `edges` (days, each
    /// greater than the one before, or the call stops) that holds at least one sample, in `OrbitRegime.allCases`'s
    /// order and then by age. A sample older than the last edge is in no row, and an error that is not finite is
    /// left out of its row.
    public static func table(_ samples: [Sample], edges: [Double] = [0, 1, 2, 3, 5, 7, 10, 14, 21, 30]) -> [Row] {
        precondition(edges.count >= 2 && zip(edges, edges.dropFirst()).allSatisfy { $0 < $1 },
                     "the edges are at least two, each greater than the one before")
        var rows: [Row] = []
        for regime in OrbitRegime.allCases {
            for (from, to) in zip(edges, edges.dropFirst()) {
                let errors = samples.filter { $0.regime == regime && $0.age > from && $0.age <= to }.map(\.positionError)
                    .filter(\.isFinite)
                if let percentiles = Percentiles(errors) {
                    rows.append(Row(regime: regime, fromAge: from, toAge: to, positionError: percentiles))
                }
            }
        }
        return rows
    }

    /// The row of `table` for this set at `time`: its class, and the span its age falls in, each span holding its
    /// upper end and not its lower. nil when the table has none: for a class it has no row for, an age past its last
    /// span, and a time at the set's epoch or before it (age 0 is in no span, since every span starts above its lower
    /// end). Nothing is extrapolated.
    public static func estimate(for set: ElementSet, at time: Epoch, from table: [Row]) -> Row? {
        let age = set.age(at: time)
        let regime = set.regime
        return table.first { $0.regime == regime && age > $0.fromAge && age <= $0.toAge }
    }

    static func difference(_ a: Vector, _ b: Vector) -> Vector { Vector(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }

    /// `delta` in the radial, in-track and cross-track directions of `state`.
    static func components(of delta: Vector, along state: StateVector) -> (Double, Double, Double) {
        func dot(_ a: Vector, _ b: Vector) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
        func cross(_ a: Vector, _ b: Vector) -> Vector {
            Vector(x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x)
        }
        func unit(_ a: Vector) -> Vector { let m = a.magnitude; return Vector(x: a.x / m, y: a.y / m, z: a.z / m) }
        let r = unit(state.position)
        let c = unit(cross(state.position, state.velocity))
        let t = cross(c, r)
        return (dot(delta, r), dot(delta, t), dot(delta, c))
    }
}
