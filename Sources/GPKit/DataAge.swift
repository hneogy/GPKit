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
/// The classes and their ranges are ESA's: ESA Space Debris Office, *ESA's Annual Space Environment Report*,
/// GEN-DB-LOG-00288-OPS-SD, Issue 10.0, 1 May 2026, section 1.1 "Definitions", Table 1.2 "Ranges defining each
/// orbital class", page 15 of 151 (https://www.sdo.esoc.esa.int/publications/Space_Environment_Report_I10R0_20260501.pdf).
/// Each class's raw value is the report's abbreviation. The report gives the ranges by perigee and apogee height (h_p,
/// h_a, km), semi-major axis (a, km), eccentricity (e) and inclination (i, degrees), and says its definitions belong
/// to its issue and can change between issues:
///
/// | class | range |
/// |---|---|
/// | GEO | i 0 to 25, h_p and h_a 35,586 to 35,986 |
/// | IGO | a 37,948 to 46,380, e 0 to 0.25, i 25 to 180 |
/// | EGO | a 37,948 to 46,380, e 0 to 0.25, i 0 to 25 |
/// | NSO | i 50 to 70, h_p and h_a 18,100 to 24,300 |
/// | GTO | i 0 to 90, h_p 0 to 2,000, h_a 31,570 to 40,002 |
/// | MEO | h_p and h_a 2,000 to 31,570 |
/// | GHO | h_p 31,570 to 40,002, h_a above 40,002 |
/// | LEO | h_p and h_a 0 to 2,000 |
/// | HAO | h_p and h_a above 40,002 |
/// | MGO | h_p 2,000 to 31,570, h_a 31,570 to 40,002 |
/// | HEO | h_p 0 to 31,570, h_a above 40,002 |
/// | LMO | h_p 0 to 2,000, h_a 2,000 to 31,570 |
/// | UFO | none of the above |
///
/// GPKit tests them in the table's order (`esaClasses`), the first that holds, each range written [x, y] in the report including
/// both its ends, so a geostationary orbit is GEO and not also EGO. The report's ESO (escape orbits) does not arise:
/// an element set's orbit is closed. The semi-major axis is Kepler's from the mean motion, with WGS-72's gravitational
/// parameter (398,600.8 km³/s²), and heights are above WGS-72's equatorial radius (6,378.135 km); the report names
/// no radius. Every perigee range starts at 0, so a set whose perigee is below that radius (one about to re-enter) is
/// UFO, as is a mean motion that is not positive.
///
/// The class is only as exact as that: the mean motion a set carries is SGP4's (Kozai's) mean, not an osculating
/// value, and Kepler's law on it puts the semi-major axis a few kilometres from the osculating one in low Earth, so a
/// satellite within a few kilometres of a range's end can change class from one fit to the next.
///
/// `OrbitClass` is a struct and not an enum, because ESA's list grows: Issue 10.0 added HAO. A class added later is
/// a new constant here and breaks no code, and a `switch` over classes needs a `default`, which is honest for a list
/// that can grow. Any abbreviation can be made with `init(rawValue:)`, so a table that names a class this release
/// does not know still reads.
public struct OrbitClass: RawRepresentable, Sendable, Hashable, Codable, CodingKeyRepresentable, CustomStringConvertible {
    /// ESA's abbreviation: "GEO", "LEO", "UFO" and so on.
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public static let geostationary = OrbitClass(rawValue: "GEO")
    public static let inclinedGeosynchronous = OrbitClass(rawValue: "IGO")
    public static let extendedGeostationary = OrbitClass(rawValue: "EGO")
    public static let navigationSatellite = OrbitClass(rawValue: "NSO")
    public static let geostationaryTransfer = OrbitClass(rawValue: "GTO")
    public static let mediumEarth = OrbitClass(rawValue: "MEO")
    public static let geoSuperGeoCrossing = OrbitClass(rawValue: "GHO")
    public static let lowEarth = OrbitClass(rawValue: "LEO")
    public static let highAltitude = OrbitClass(rawValue: "HAO")
    public static let meoGeoCrossing = OrbitClass(rawValue: "MGO")
    public static let highlyEccentric = OrbitClass(rawValue: "HEO")
    public static let leoMeoCrossing = OrbitClass(rawValue: "LMO")
    /// None of ESA's classes: ESA's "UFO".
    public static let undefined = OrbitClass(rawValue: "UFO")

    /// ESA's classes in the order of the report's table, which is the order they are tested in, `undefined` last.
    public static let esaClasses: [OrbitClass] = [
        .geostationary, .inclinedGeosynchronous, .extendedGeostationary, .navigationSatellite, .geostationaryTransfer,
        .mediumEarth, .geoSuperGeoCrossing, .lowEarth, .highAltitude, .meoGeoCrossing, .highlyEccentric,
        .leoMeoCrossing, .undefined,
    ]

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var codingKey: any CodingKey { Key(stringValue: rawValue) }

    public init?<T: CodingKey>(codingKey: T) { self.init(rawValue: codingKey.stringValue) }

    struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

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
        else if within(i, 50, 70) && within(hp, 18_100, 24_300) && within(ha, 18_100, 24_300) { self = .navigationSatellite }
        else if within(i, 0, 90) && within(hp, 0, 2_000) && within(ha, 31_570, 40_002) { self = .geostationaryTransfer }
        else if within(hp, 2_000, 31_570) && within(ha, 2_000, 31_570) { self = .mediumEarth }
        else if within(hp, 31_570, 40_002) && ha > 40_002 { self = .geoSuperGeoCrossing }
        else if within(hp, 0, 2_000) && within(ha, 0, 2_000) { self = .lowEarth }
        else if hp > 40_002 && ha > 40_002 { self = .highAltitude }
        else if within(hp, 2_000, 31_570) && within(ha, 31_570, 40_002) { self = .meoGeoCrossing }
        else if within(hp, 0, 31_570) && ha > 40_002 { self = .highlyEccentric }
        else if within(hp, 0, 2_000) && within(ha, 2_000, 31_570) { self = .leoMeoCrossing }
        else { self = .undefined }
    }
}

extension ElementSet {
    /// The class of the orbit this set describes, among ESA's orbit classes.
    public var orbitClass: OrbitClass {
        OrbitClass(meanMotion: meanMotion.double, eccentricity: eccentricity.double, inclination: inclination.double)
    }

    /// How old this set is at `time`, in days: the time since its epoch, negative before it.
    public func age(at time: Epoch) -> Double { time.seconds(since: epoch) / 86_400 }
}

/// The error to expect from an element set as it ages, **measured, not quoted**: older sets of a satellite are
/// propagated to the epochs of its newer sets and compared with them there, and the differences are summed up as
/// percentiles by orbit class and age.
///
/// The newer set at its own epoch stands for the truth. It is not the truth: it is the provider's next fit, with
/// errors of its own, so what this measures is how far an old set drifts from the fits that follow it. GPKit ships
/// no table of its own yet: a measurement is made with `measure(_:maximumAge:)`, a table built from it with
/// `DataAgeTable.init(_:edges:provenance:)`, and an estimate read from the table with
/// `DataAgeTable.estimate(for:at:)`. A table is `Codable`, so a published one, with what it was measured from, is
/// read back with any decoder.
public enum DataAge {

    /// The name of the method `measure(_:maximumAge:)` and `DataAgeTable.init(_:edges:provenance:)` follow, as a
    /// table's provenance gives it: each older set of a satellite propagated to each newer set's epoch and compared
    /// with the newer set there, and the position errors summed up as nearest-rank percentiles. A later change to the
    /// method is a new name.
    public static let method = "GPKit DataAge 1: older set at newer set's epoch, nearest-rank percentiles"

    /// GPKit's version, as a table built here records it.
    public static let gpkitVersion = "2.0.0"

    /// One older set of a satellite at the epoch of one newer set of the same satellite.
    public struct Sample: Sendable, Hashable {
        /// The catalog number both sets carry.
        public let catalogNumber: Int
        /// The older set's orbit class.
        public let orbitClass: OrbitClass
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

    /// What a measurement found: its samples, the pairs it could not propagate, and the sets it was made from.
    public struct Measurement: Sendable, Hashable {
        /// Every pair measured, by catalog number, then the older set's epoch, then the newer's.
        public let samples: [Sample]
        /// The pairs that were not measured because a set of the pair could not be propagated, by the kind of the
        /// failure: the older set's at the newer set's epoch, or the newer set's at its own (the older set's first,
        /// when both fail). No sample is made of such a pair.
        public let failures: [PropagationFailure.Kind: Int]
        /// The sets the measurement took part in, by their orbit class: each distinct set with a catalog number
        /// once, those left out for sharing an epoch with a different set of their satellite not counted.
        public let sets: [OrbitClass: Int]
        /// The earliest and latest epochs of those sets; nil when there were none.
        public let epochs: ClosedRange<Epoch>?

        /// How many pairs were not measured.
        public var failureCount: Int { failures.values.reduce(0, +) }
    }

    /// Every pair of sets of one satellite, the older propagated to the newer's epoch, the age more than 0 and at most
    /// `maximumAge` days.
    ///
    /// Sets with no catalog number are left out. A set given more than once (the same set in overlapping files) counts
    /// once. Sets of one satellite that share an epoch and differ are all left out: which is the provider's fit cannot
    /// be told. A pair that either set cannot be propagated for is counted in `failures` by the failure's kind, and
    /// no sample is made of it.
    public static func measure(_ sets: [ElementSet], maximumAge: Double = 30) -> Measurement {
        var bySatellite: [Int: Set<ElementSet>] = [:]
        for set in sets {
            guard let number = set.catalogNumber else { continue }
            bySatellite[number, default: []].insert(set)
        }
        var samples: [Sample] = []
        var failures: [PropagationFailure.Kind: Int] = [:]
        var used: [OrbitClass: Int] = [:]
        var earliest: Epoch?, latest: Epoch?
        for number in bySatellite.keys.sorted() {
            let byEpoch = Dictionary(grouping: bySatellite[number]!, by: \.epoch)
            let ordered = byEpoch.values.compactMap { $0.count == 1 ? $0[0] : nil }.sorted { $0.epoch < $1.epoch }
            for set in ordered {
                used[set.orbitClass, default: 0] += 1
                earliest = earliest.map { min($0, set.epoch) } ?? set.epoch
                latest = latest.map { max($0, set.epoch) } ?? set.epoch
            }
            // each set's propagator, and its state at its own epoch (the truth for every pair it ends), made once
            let propagators: [Result<Propagator, PropagationFailure>] = ordered.map { set in
                Result { () throws(PropagationFailure) -> Propagator in try Propagator(set) }
            }
            let truths: [Result<StateVector, PropagationFailure>] = zip(ordered, propagators).map { set, propagator in
                propagator.flatMap { p in Result { () throws(PropagationFailure) -> StateVector in try p.state(at: set.epoch) } }
            }
            for i in ordered.indices {
                for j in ordered.indices where j > i {
                    let age = ordered[i].age(at: ordered[j].epoch)
                    guard age <= maximumAge else { break }   // sorted by epoch: every later pair is older still
                    let drifted = propagators[i].flatMap { p in
                        Result { () throws(PropagationFailure) -> StateVector in try p.state(at: ordered[j].epoch) }
                    }
                    let truth: StateVector, moved: StateVector
                    switch (drifted, truths[j]) {
                    case (.failure(let failure), _), (.success, .failure(let failure)):
                        failures[failure.kind, default: 0] += 1
                        continue
                    case (.success(let d), .success(let t)):
                        moved = d
                        truth = t
                    }
                    let delta = difference(moved.position, truth.position)
                    let (radial, inTrack, crossTrack) = components(of: delta, along: truth)
                    samples.append(Sample(catalogNumber: number, orbitClass: ordered[i].orbitClass, older: ordered[i].epoch,
                                          newer: ordered[j].epoch, age: age, positionError: delta.magnitude,
                                          radial: radial, inTrack: inTrack, crossTrack: crossTrack))
                }
            }
        }
        let epochs = earliest.flatMap { e in latest.map { e...$0 } }
        return Measurement(samples: samples, failures: failures, sets: used, epochs: epochs)
    }

    /// Percentiles of a sample of errors, by nearest rank: the smallest value with at least that share of the
    /// sample at or below it.
    public struct Percentiles: Sendable, Hashable, Codable {
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

        /// Percentiles from their figures, as a published table gives them. nil unless the count is at least 1, every
        /// figure is finite and not negative, and median ≤ p68 ≤ p95 ≤ maximum, as percentiles of distances are.
        public init?(count: Int, median: Double, p68: Double, p95: Double, maximum: Double) {
            let figures = [median, p68, p95, maximum]
            guard count >= 1, figures.allSatisfy({ $0.isFinite && $0 >= 0 }),
                  median <= p68, p68 <= p95, p95 <= maximum else { return nil }
            self.count = count
            self.median = median
            self.p68 = p68
            self.p95 = p95
            self.maximum = maximum
        }

        enum CodingKeys: String, CodingKey { case count, median, p68, p95, maximum }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let made = Percentiles(count: try c.decode(Int.self, forKey: .count),
                                         median: try c.decode(Double.self, forKey: .median),
                                         p68: try c.decode(Double.self, forKey: .p68),
                                         p95: try c.decode(Double.self, forKey: .p95),
                                         maximum: try c.decode(Double.self, forKey: .maximum)) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription:
                    "percentiles need a count of at least 1 and finite figures, 0 ≤ median ≤ p68 ≤ p95 ≤ maximum"))
            }
            self = made
        }
    }

    /// One row of a measured table: the position errors of one class's sets at ages from `fromAge` (exclusive) to
    /// `toAge` (inclusive), in days.
    public struct Row: Sendable, Hashable, Codable {
        public let orbitClass: OrbitClass
        public let fromAge: Double
        public let toAge: Double
        public let positionError: Percentiles

        public init(orbitClass: OrbitClass, fromAge: Double, toAge: Double, positionError: Percentiles) {
            self.orbitClass = orbitClass
            self.fromAge = fromAge
            self.toAge = toAge
            self.positionError = positionError
        }
    }

    /// What a table says of a set at a time.
    public enum Estimate: Sendable, Hashable {
        /// The row the set's class and age fall in.
        case row(Row)
        /// The table has no row for the set's class: `undefined` (ESA's UFO), or a class it measured nothing of.
        case unclassified(OrbitClass)
        /// The set's age, in days, is past the table's last edge. Nothing is extrapolated.
        case olderThanTable(age: Double)
        /// The table has rows for the set's class, but none for the span its age, in days, falls in.
        case noRowForAge(age: Double)
        /// The time is at the set's epoch or before it: no age to estimate for, since every span starts above 0.
        case notAfterEpoch
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

/// A data-age table: rows of measured position errors by orbit class and span of age, the edges of the spans, and
/// what the table was measured from.
///
/// Built from a measurement with `init(_:edges:provenance:)`, or read back from a published one with any decoder;
/// decoding checks what it reads (the edges increase, each row's span is two consecutive edges, no class and span
/// twice, each set of percentiles in order), so a damaged table is refused rather than read.
public struct DataAgeTable: Sendable, Hashable, Codable {

    /// What a table was measured from.
    public struct Provenance: Sendable, Hashable, Codable {
        /// Where the element sets came from, in words: a provider and a fetch, a folder, a capture.
        public let source: String
        /// The earliest epoch among the sets measured.
        public let earliestEpoch: Epoch
        /// The latest epoch among the sets measured.
        public let latestEpoch: Epoch
        /// The sets measured, by orbit class.
        public let sets: [OrbitClass: Int]
        /// The GPKit release that made the table.
        public let gpkitVersion: String
        /// The method followed, by name (`DataAge.method` for a table made by this release).
        public let method: String

        public init(source: String, earliestEpoch: Epoch, latestEpoch: Epoch, sets: [OrbitClass: Int],
                    gpkitVersion: String, method: String) {
            self.source = source
            self.earliestEpoch = earliestEpoch
            self.latestEpoch = latestEpoch
            self.sets = sets
            self.gpkitVersion = gpkitVersion
            self.method = method
        }

        /// The provenance of a table made by this release from `measurement`: its sets and epochs, this release's
        /// version and `DataAge.method`. nil for a measurement of no sets.
        public init?(source: String, measurement: DataAge.Measurement) {
            guard let epochs = measurement.epochs else { return nil }
            self.init(source: source, earliestEpoch: epochs.lowerBound, latestEpoch: epochs.upperBound,
                      sets: measurement.sets, gpkitVersion: DataAge.gpkitVersion, method: DataAge.method)
        }

        enum CodingKeys: String, CodingKey { case source, earliestEpoch, latestEpoch, sets, gpkitVersion, method }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func epoch(_ key: CodingKeys) throws -> Epoch {
                let text = try c.decode(String.self, forKey: key)
                do { return try Epoch(ccsds: text) } catch {
                    throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "not an epoch: \(error)")
                }
            }
            self.init(source: try c.decode(String.self, forKey: .source), earliestEpoch: try epoch(.earliestEpoch),
                      latestEpoch: try epoch(.latestEpoch), sets: try c.decode([OrbitClass: Int].self, forKey: .sets),
                      gpkitVersion: try c.decode(String.self, forKey: .gpkitVersion),
                      method: try c.decode(String.self, forKey: .method))
            guard earliestEpoch <= latestEpoch else {
                throw DecodingError.dataCorruptedError(forKey: .latestEpoch, in: c, debugDescription: "the latest epoch is before the earliest")
            }
        }

        /// The epochs are written as text, `Epoch`'s description, every digit of the fraction kept.
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(source, forKey: .source)
            try c.encode(earliestEpoch.description, forKey: .earliestEpoch)
            try c.encode(latestEpoch.description, forKey: .latestEpoch)
            try c.encode(sets, forKey: .sets)
            try c.encode(gpkitVersion, forKey: .gpkitVersion)
            try c.encode(method, forKey: .method)
        }
    }

    /// The default edges of the spans of age, in days.
    public static let defaultEdges: [Double] = [0, 1, 2, 3, 5, 7, 10, 14, 21, 30]

    /// One row for each class and each span between consecutive `edges` that holds at least one sample, in
    /// `OrbitClass.esaClasses`'s order (any other class after them, by abbreviation) and then by age.
    public let rows: [DataAge.Row]
    /// The edges of the spans of age, in days, each greater than the one before.
    public let edges: [Double]
    /// What the table was measured from.
    public let provenance: Provenance

    /// A table from a measurement: its samples by class and by span between consecutive `edges` (days, at least two,
    /// each finite and greater than the one before, or the call stops). A sample older than the last edge is in no
    /// row, and an error that is not finite is left out of its row.
    public init(_ measurement: DataAge.Measurement, edges: [Double] = DataAgeTable.defaultEdges, provenance: Provenance) {
        precondition(Self.edgesValid(edges), "the edges are at least two, finite, each greater than the one before")
        let present = Set(measurement.samples.map(\.orbitClass))
        let order = OrbitClass.esaClasses + present.subtracting(OrbitClass.esaClasses).sorted { $0.rawValue < $1.rawValue }
        var rows: [DataAge.Row] = []
        for orbitClass in order where present.contains(orbitClass) {
            for (from, to) in zip(edges, edges.dropFirst()) {
                let errors = measurement.samples.filter { $0.orbitClass == orbitClass && $0.age > from && $0.age <= to }
                    .map(\.positionError).filter(\.isFinite)
                if let percentiles = DataAge.Percentiles(errors) {
                    rows.append(DataAge.Row(orbitClass: orbitClass, fromAge: from, toAge: to, positionError: percentiles))
                }
            }
        }
        self.rows = rows
        self.edges = edges
        self.provenance = provenance
    }

    /// A table from its parts, as published. nil unless the edges are valid (at least two, finite, increasing), each
    /// row's span is two consecutive edges, and no class and span has two rows.
    public init?(rows: [DataAge.Row], edges: [Double], provenance: Provenance) {
        guard Self.edgesValid(edges) else { return nil }
        let spans = Set(zip(edges, edges.dropFirst()).map { [$0, $1] })
        var seen = Set<[String]>()
        for row in rows {
            guard spans.contains([row.fromAge, row.toAge]),
                  seen.insert([row.orbitClass.rawValue, "\(row.fromAge)", "\(row.toAge)"]).inserted else { return nil }
        }
        self.rows = rows
        self.edges = edges
        self.provenance = provenance
    }

    static func edgesValid(_ edges: [Double]) -> Bool {
        edges.count >= 2 && edges.allSatisfy(\.isFinite) && zip(edges, edges.dropFirst()).allSatisfy { $0 < $1 }
    }

    enum CodingKeys: String, CodingKey { case rows, edges, provenance }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let made = DataAgeTable(rows: try c.decode([DataAge.Row].self, forKey: .rows),
                                      edges: try c.decode([Double].self, forKey: .edges),
                                      provenance: try c.decode(Provenance.self, forKey: .provenance)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription:
                "the edges must be at least two, finite and increasing, each row's span two consecutive edges, no class and span twice"))
        }
        self = made
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rows, forKey: .rows)
        try c.encode(edges, forKey: .edges)
        try c.encode(provenance, forKey: .provenance)
    }

    /// What this table says of `set` at `time`: the row its class and age fall in (each span holding its upper end
    /// and not its lower), or why there is none. Nothing is extrapolated.
    public func estimate(for set: ElementSet, at time: Epoch) -> DataAge.Estimate {
        let age = set.age(at: time)
        guard age > 0 else { return .notAfterEpoch }
        let orbitClass = set.orbitClass
        let mine = rows.filter { $0.orbitClass == orbitClass }
        guard !mine.isEmpty else { return .unclassified(orbitClass) }
        guard let last = edges.last, age <= last else { return .olderThanTable(age: age) }
        if let row = mine.first(where: { age > $0.fromAge && age <= $0.toAge }) { return .row(row) }
        return .noRowForAge(age: age)
    }
}
