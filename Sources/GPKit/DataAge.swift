/// The kind of orbit an element set describes, by its mean motion and eccentricity: what the error to expect at an
/// age depends on most, so the data-age measurement is kept by regime.
///
/// The boundaries are GPKit's own, stated here so a measurement can be repeated: an eccentricity of 0.25 or more is
/// highly elliptical; otherwise 0.99 to 1.01 revolutions a day is geosynchronous, 11.25 or more (a period of 128
/// minutes or less) low Earth, and anything between medium Earth.
public enum OrbitRegime: String, Sendable, Hashable, CaseIterable {
    case lowEarth
    case mediumEarth
    case geosynchronous
    case highlyElliptical

    /// The regime of an orbit of `meanMotion` revolutions a day and eccentricity `eccentricity`.
    public init(meanMotion: Double, eccentricity: Double) {
        if eccentricity >= 0.25 {
            self = .highlyElliptical
        } else if (0.99...1.01).contains(meanMotion) {
            self = .geosynchronous
        } else if meanMotion >= 11.25 {
            self = .lowEarth
        } else {
            self = .mediumEarth
        }
    }
}

extension ElementSet {
    /// The regime of the orbit this set describes.
    public var regime: OrbitRegime { OrbitRegime(meanMotion: meanMotion.double, eccentricity: eccentricity.double) }

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
        /// The difference along the newer set's track, in the direction it moves: ahead, positive. Kilometres.
        public let inTrack: Double
        /// The difference across the newer set's orbital plane, along its angular momentum. Kilometres.
        public let crossTrack: Double
    }

    /// Every pair of sets of one satellite, the older propagated to the newer's epoch, the age more than 0 and at most
    /// `maximumAge` days. Sets with no catalog number are left out, and so are pairs of sets with the same epoch.
    /// A pair that either set cannot be propagated for is counted in `failures`, and no sample is made of it.
    public static func samples(_ sets: [ElementSet], maximumAge: Double = 30) -> (samples: [Sample], failures: Int) {
        var bySatellite: [Int: [ElementSet]] = [:]
        for set in sets {
            guard let number = set.catalogNumber else { continue }
            bySatellite[number, default: []].append(set)
        }
        var samples: [Sample] = []
        var failures = 0
        for number in bySatellite.keys.sorted() {
            let ordered = bySatellite[number]!.sorted { $0.epoch < $1.epoch }
            for (i, older) in ordered.enumerated() {
                for newer in ordered[(i + 1)...] {
                    let age = older.age(at: newer.epoch)
                    guard age > 0, age <= maximumAge else { continue }
                    guard let drifted = try? Propagator(older).state(at: newer.epoch),
                          let truth = try? Propagator(newer).state(at: newer.epoch) else {
                        failures += 1
                        continue
                    }
                    let (radial, inTrack, crossTrack) = components(of: difference(drifted.position, truth.position), along: truth)
                    samples.append(Sample(catalogNumber: number, regime: older.regime, older: older.epoch, newer: newer.epoch, age: age,
                                          positionError: difference(drifted.position, truth.position).magnitude,
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

    /// A table from samples: one row for each regime and each span of age between consecutive `edges` (days,
    /// increasing) that holds at least one sample. A sample older than the last edge is in no row.
    public static func table(_ samples: [Sample], edges: [Double] = [0, 1, 2, 3, 5, 7, 10, 14, 21, 30]) -> [Row] {
        var rows: [Row] = []
        for regime in OrbitRegime.allCases {
            for (from, to) in zip(edges, edges.dropFirst()) {
                let errors = samples.filter { $0.regime == regime && $0.age > from && $0.age <= to }.map(\.positionError)
                if let percentiles = Percentiles(errors) {
                    rows.append(Row(regime: regime, fromAge: from, toAge: to, positionError: percentiles))
                }
            }
        }
        return rows
    }

    /// The row of `table` for this set at `time`: its regime, and the span its age falls in. nil when the table has
    /// none, a set used before its epoch included: nothing is extrapolated.
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
