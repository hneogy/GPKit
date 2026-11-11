// GPKit's public interface, as the compiler states it: tools/public-api.sh writes this file; do not edit it.
// Left out: module prefixes, and what the compiler synthesises for Hashable, CaseIterable and RawRepresentable.
// Each declaration's documentation is in Sources/GPKit.

public enum Alpha5 {
  public static let ceiling: Int
  public static func decode(_ field: String) throws(Refusal) -> Int
  public static func encode(_ catalogNumber: Int) throws(Refusal) -> String
}
extension Propagator {
  public static func states(of propagators: [Propagator], at time: Epoch, chunk: Int = 512) async -> [Result<StateVector, PropagationFailure>]
  public static func states(of propagators: [Propagator], from start: Epoch, every step: Double, count: Int, chunk: Int = 64) async -> [[Result<StateVector, PropagationFailure>]]
}
public enum CloseApproach {
  public struct Candidate : Sendable, Hashable {
    public var first: Int
    public var second: Int
    public var time: Epoch
    public var missDistance: Double
    public var relativeSpeed: Double
    public var atEdgeOfSpan: Bool
  }
  public struct Unscreened : Sendable, Hashable {
    public var index: Int
    public var failure: PropagationFailure
  }
  public struct Screen : Sendable, Hashable {
    public var candidates: [CloseApproach.Candidate]
    public var unscreened: [CloseApproach.Unscreened]
    public var pairsPassedOver: Int
    public var pairsScreened: Int
  }
  public static let heightMargin: Double
  public static func screen(_ propagators: [Propagator], from start: Epoch, for seconds: Double, step: Double = 60, within: Double = 10) -> CloseApproach.Screen
}
public struct OrbitClass : RawRepresentable, Sendable, Hashable, Codable, CodingKeyRepresentable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String)
  public static let geostationary: OrbitClass
  public static let inclinedGeosynchronous: OrbitClass
  public static let extendedGeostationary: OrbitClass
  public static let navigationSatellite: OrbitClass
  public static let geostationaryTransfer: OrbitClass
  public static let mediumEarth: OrbitClass
  public static let geoSuperGeoCrossing: OrbitClass
  public static let lowEarth: OrbitClass
  public static let highAltitude: OrbitClass
  public static let meoGeoCrossing: OrbitClass
  public static let highlyEccentric: OrbitClass
  public static let leoMeoCrossing: OrbitClass
  public static let undefined: OrbitClass
  public static let esaClasses: [OrbitClass]
  public var description: String { get }
  public init(from decoder: any Decoder) throws
  public func encode(to encoder: any Encoder) throws
  public var codingKey: any CodingKey { get }
  public init?<T>(codingKey: T) where T : CodingKey
  public init(meanMotion: Double, eccentricity: Double, inclination: Double)
}
extension ElementSet {
  public var orbitClass: OrbitClass { get }
  public func age(at time: Epoch) -> Double
}
public enum DataAge {
  public static let method: String
  public static let gpkitVersion: String
  public struct Sample : Sendable, Hashable {
    public let catalogNumber: Int
    public let orbitClass: OrbitClass
    public let older: Epoch
    public let newer: Epoch
    public let age: Double
    public let positionError: Double
    public let radial: Double
    public let inTrack: Double
    public let crossTrack: Double
  }
  public struct Measurement : Sendable, Hashable {
    public let samples: [DataAge.Sample]
    public let failures: [PropagationFailure.Kind : Int]
    public let sets: [OrbitClass : Int]
    public let epochs: ClosedRange<Epoch>?
    public var failureCount: Int { get }
  }
  public static func measure(_ sets: [ElementSet], maximumAge: Double = 30) -> DataAge.Measurement
  public struct Percentiles : Sendable, Hashable, Codable {
    public let count: Int
    public let median: Double
    public let p68: Double
    public let p95: Double
    public let maximum: Double
    public init?(_ values: [Double])
    public init?(count: Int, median: Double, p68: Double, p95: Double, maximum: Double)
    public init(from decoder: any Decoder) throws
    public func encode(to encoder: any Encoder) throws
  }
  public struct Row : Sendable, Hashable, Codable {
    public let orbitClass: OrbitClass
    public let fromAge: Double
    public let toAge: Double
    public let positionError: DataAge.Percentiles
    public init(orbitClass: OrbitClass, fromAge: Double, toAge: Double, positionError: DataAge.Percentiles)
    public func encode(to encoder: any Encoder) throws
    public init(from decoder: any Decoder) throws
  }
  public enum Estimate : Sendable, Hashable {
    case row(DataAge.Row)
    case unclassified(OrbitClass)
    case olderThanTable(age: Double)
    case noRowForAge(age: Double)
    case notAfterEpoch
  }
}
public struct DataAgeTable : Sendable, Hashable, Codable {
  public struct Provenance : Sendable, Hashable, Codable {
    public let source: String
    public let earliestEpoch: Epoch
    public let latestEpoch: Epoch
    public let sets: [OrbitClass : Int]
    public let gpkitVersion: String
    public let method: String
    public init(source: String, earliestEpoch: Epoch, latestEpoch: Epoch, sets: [OrbitClass : Int], gpkitVersion: String, method: String)
    public init?(source: String, measurement: DataAge.Measurement)
    public init(from decoder: any Decoder) throws
    public func encode(to encoder: any Encoder) throws
  }
  public static let defaultEdges: [Double]
  public let rows: [DataAge.Row]
  public let edges: [Double]
  public let provenance: DataAgeTable.Provenance
  public init(_ measurement: DataAge.Measurement, edges: [Double] = DataAgeTable.defaultEdges, provenance: DataAgeTable.Provenance)
  public init?(rows: [DataAge.Row], edges: [Double], provenance: DataAgeTable.Provenance)
  public init(from decoder: any Decoder) throws
  public func encode(to encoder: any Encoder) throws
  public func estimate(for set: ElementSet, at time: Epoch) -> DataAge.Estimate
}
// only where Foundation can be imported (Sources/GPKit/Date.swift)
extension Epoch {
  public init(_ date: Foundation.Date) throws(Refusal)
  public var date: Foundation.Date { get }
}
public struct ElementSet : Sendable, Hashable {
  public var catalogNumber: Int?
  public var objectName: String?
  public var objectID: String?
  public var classification: String?
  public var epoch: Epoch
  public var meanMotion: ExactDecimal
  public var eccentricity: ExactDecimal
  public var inclination: ExactDecimal
  public var rightAscension: ExactDecimal
  public var argumentOfPericenter: ExactDecimal
  public var meanAnomaly: ExactDecimal
  public var bstar: ExactDecimal
  public var meanMotionDot: ExactDecimal
  public var meanMotionDDot: ExactDecimal
  public var ephemerisType: Int?
  public var elementSetNumber: Int?
  public var revolutionAtEpoch: Int?
  public var centerName: String
  public var referenceFrame: String
  public var timeSystem: String
  public var meanElementTheory: String
  public var defaulted: Set<String>
  public var otherKeywords: [String : String]
  public var source: Format?
  public static let defaultCenterName: String
  public static let defaultReferenceFrame: String
  public static let defaultTimeSystem: String
  public static let defaultMeanElementTheory: String
  public var isSGP4: Bool { get }
  public init(catalogNumber: Int?, objectName: String? = nil, objectID: String? = nil, classification: String? = nil, epoch: Epoch, meanMotion: ExactDecimal, eccentricity: ExactDecimal, inclination: ExactDecimal, rightAscension: ExactDecimal, argumentOfPericenter: ExactDecimal, meanAnomaly: ExactDecimal, bstar: ExactDecimal = .zero, meanMotionDot: ExactDecimal = .zero, meanMotionDDot: ExactDecimal = .zero, ephemerisType: Int? = nil, elementSetNumber: Int? = nil, revolutionAtEpoch: Int? = nil, centerName: String? = nil, referenceFrame: String? = nil, timeSystem: String? = nil, meanElementTheory: String? = nil, otherKeywords: [String : String] = [:])
}
public enum Format : String, Sendable, Hashable, CaseIterable {
  case csv
  case json
  case xml
  case kvn
  case tle
}
public struct ElementSetFile : Sendable, Hashable {
  public enum Entry : Sendable, Hashable {
    case elementSet(ElementSet)
    case refusal(Refusal)
  }
  public let entries: [ElementSetFile.Entry]
  public let providerMessage: String?
  public var elementSets: [ElementSet] { get }
  public var refusals: [Refusal] { get }
}
public enum ElementSets {
  public static let emptyAnswers: [String]
  public static func read<Bytes>(_ input: Bytes, as format: Format, checksum: TLE.Checksum = .verify) throws(Refusal) -> ElementSetFile where Bytes : Collection, Bytes.Element == UInt8
  public static func read(_ text: String, as format: Format, checksum: TLE.Checksum = .verify) throws(Refusal) -> ElementSetFile
}
public struct Epoch : Sendable, Hashable, Comparable, CustomStringConvertible {
  public let year: Int
  public let month: Int
  public let day: Int
  public let hour: Int
  public let minute: Int
  public let second: Int
  public let attosecond: UInt64
  public init(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, attosecond: UInt64 = 0) throws(Refusal)
  public init(year: Int, dayOfYear: Int, hour: Int, minute: Int, second: Int, attosecond: UInt64 = 0) throws(Refusal)
  public init(ccsds text: String) throws(Refusal)
  public var dayOfYear: Int { get }
  public var microsecond: Int { get }
  public var nanosecond: Int { get }
  public var description: String { get }
  public static func < (a: Epoch, b: Epoch) -> Bool
  public var unixTime: Double { get }
  public init(unixTime: Double) throws(Refusal)
  public func seconds(since other: Epoch) -> Double
  public func advanced(by seconds: Double) throws(Refusal) -> Epoch
}
public struct ExactDecimal : Sendable, Hashable, CustomStringConvertible, LosslessStringConvertible {
  public let isNegative: Bool
  public static let zero: ExactDecimal
  public init?(_ text: String)
  public init(_ value: Int)
  public init?(_ value: Double)
  public var isZero: Bool { get }
  public var description: String { get }
  public var double: Double { get }
}
public struct GroundTrack : Sendable, Hashable, RandomAccessCollection {
  public struct Point : Sendable, Hashable {
    public var time: Epoch
    public var position: GeodeticPosition
  }
  public let failure: PropagationFailure?
  public var startIndex: Int { get }
  public var endIndex: Int { get }
  public subscript(position: Int) -> GroundTrack.Point { get }
  public typealias Element = GroundTrack.Point
  public typealias Index = Int
  public typealias Indices = Range<Int>
  public typealias Iterator = IndexingIterator<GroundTrack>
  public typealias SubSequence = Slice<GroundTrack>
}
extension Propagator {
  public func earthFixedState(at time: Epoch) throws(PropagationFailure) -> StateVector
  public func equatorial(from observer: Observer, at time: Epoch) throws(PropagationFailure) -> EquatorialPosition
  public func groundTrack(from start: Epoch, for duration: Duration, every step: Duration) -> GroundTrack
}
extension GeodeticPosition {
  public func footprint(minimumElevation: Double = 0, points: Int = 72) -> [GeodeticPosition]
}
public enum OEM {
  public static func write(_ propagator: Propagator, from start: Epoch, every step: Double, count: Int, originator: String, created: Epoch) throws(PropagationFailure) -> String
}
public enum OMM {
  public static func catalogNumber(_ text: String) throws(Refusal) -> Int
}
public struct Observer : Sendable, Hashable {
  public var latitude: Double
  public var longitude: Double
  public var height: Double
  public init(latitude: Double, longitude: Double, height: Double = 0)
}
public struct GeodeticPosition : Sendable, Hashable {
  public var latitude: Double
  public var longitude: Double
  public var altitude: Double
  public init(latitude: Double, longitude: Double, altitude: Double)
}
public struct Look : Sendable, Hashable {
  public var azimuth: Double
  public var elevation: Double
  public var range: Double
  public var rangeRate: Double
  public static let speedOfLight: Double
  public func received(from transmitted: Double) -> Double
  public func transmit(toBeReceivedAt received: Double) -> Double
}
extension Propagator {
  public func look(from observer: Observer, at time: Epoch) throws(PropagationFailure) -> Look
  public func position(at time: Epoch) throws(PropagationFailure) -> GeodeticPosition
}
public struct Pass : Sendable, Hashable {
  public struct Event : Sendable, Hashable {
    public var time: Epoch
    public var look: Look
  }
  public var rise: Pass.Event?
  public var culmination: Pass.Event
  public var set: Pass.Event?
}
public struct Passes : Sendable, Hashable, RandomAccessCollection {
  public let failure: PropagationFailure?
  public var startIndex: Int { get }
  public var endIndex: Int { get }
  public subscript(position: Int) -> Pass { get }
  public typealias Element = Pass
  public typealias Index = Int
  public typealias Indices = Range<Int>
  public typealias Iterator = IndexingIterator<Passes>
  public typealias SubSequence = Slice<Passes>
}
extension Propagator {
  public func passes(over observer: Observer, from start: Epoch, for duration: Duration, above minimumElevation: Double = 0) -> Passes
}
public struct Vector : Sendable, Hashable {
  public var x: Double
  public var y: Double
  public var z: Double
  public init(x: Double, y: Double, z: Double)
  public var magnitude: Double { get }
}
public struct StateVector : Sendable, Hashable {
  public var position: Vector
  public var velocity: Vector
}
public struct PropagationFailure : Error, Sendable, Hashable, CustomStringConvertible {
  public enum Kind : String, Sendable, Hashable, CaseIterable {
    case notSGP4
    case sgp4XP
    case eccentricity
    case meanMotion
    case perturbedEccentricity
    case semiLatusRectum
    case decayed
    case time
  }
  public let kind: PropagationFailure.Kind
  public let minutesFromEpoch: Double?
  public var description: String { get }
}
public struct Propagator : Sendable {
  public enum Gravity : Sendable, Hashable {
    case wgs72
    case wgs84
    case wgs72old
  }
  public let elementSet: ElementSet
  public let gravity: Propagator.Gravity
  public enum EpochReading : Sendable, Hashable {
    case exact
    case vallado
  }
  public init(_ elementSet: ElementSet, gravity: Propagator.Gravity = .wgs72) throws(PropagationFailure)
  public init(_ elementSet: ElementSet, gravity: Propagator.Gravity = .wgs72, epochReading: Propagator.EpochReading) throws(PropagationFailure)
  public func state(minutesFromEpoch minutes: Double) throws(PropagationFailure) -> StateVector
  public func state(at time: Epoch) throws(PropagationFailure) -> StateVector
}
public struct Refusal : Error, Sendable, Hashable, CustomStringConvertible {
  public enum Kind : String, Sendable, Hashable, CaseIterable {
    case emptyInput
    case notUTF8
    case malformedFile
    case cutShort
    case lineLength
    case checksum
    case missingLine2
    case missingLine1
    case strayLine
    case layout
    case catalogNumber
    case notANumber
    case notAnInteger
    case notAnEpoch
    case notText
    case missingKeyword
    case duplicateKeyword
    case malformedRecord
    case cannotEncode
  }
  public let kind: Refusal.Kind
  public let message: String
  public let field: String?
  public let text: String?
  public let catalogField: String?
  public let record: Int?
  public let line: Int?
  public init(_ kind: Refusal.Kind, _ message: String, field: String? = nil, text: String? = nil, catalogField: String? = nil, record: Int? = nil, line: Int? = nil)
  public var description: String { get }
}
public struct RotatorLimits : Sendable, Hashable {
  public var azimuth: ClosedRange<Double>
  public var elevation: ClosedRange<Double>
  public init(azimuth: ClosedRange<Double> = 0...360, elevation: ClosedRange<Double> = 0...90)
  public static let standard: RotatorLimits
}
public struct RotatorPoint : Sendable, Hashable {
  public var time: Epoch
  public var azimuth: Double
  public var elevation: Double
  public init(time: Epoch, azimuth: Double, elevation: Double)
  public var hamlibCommand: String { get }
}
extension Propagator {
  public func rotatorTrack(for pass: Pass, from observer: Observer, every step: Double = 1, limits: RotatorLimits = .standard) -> [RotatorPoint]
}
extension Propagator {
  public static let defaultStreamBudget: Int
  public static var bytesPerStreamedState: Int { get }
  public static func streamBlockLength(satellites: Int, budget: Int = defaultStreamBudget) -> Int
  public static func streamStates(of propagators: [Propagator], from start: Epoch, every step: Double, count: Int, budget: Int = defaultStreamBudget, chunk: Int = 512, isolation: isolated (any _Concurrency::Actor)? = #isolation, _ body: (StateBlock) async throws -> Void) async rethrows
}
public struct StateBlock : Sendable {
  public let firstStep: Int
  public let steps: Int
  public let satellites: Int
  public subscript(step: Int, satellite: Int) -> Result<StateVector, PropagationFailure> { get }
}
public enum Sun {
  public static let darkBelow: Double
  public static let shadowRadius: Double
  public static func equatorial(at time: Epoch) -> EquatorialPosition
  public static func direction(at time: Epoch) -> Vector
  public static func elevation(at time: Epoch, from observer: Observer) -> Double
  public static func lights(_ position: Vector, at time: Epoch) -> Bool
}
public struct EquatorialPosition : Sendable, Hashable {
  public var rightAscension: Double
  public var declination: Double
  public init(rightAscension: Double, declination: Double)
}
public struct Sunlight : Sendable, Hashable {
  public enum Sky : String, Sendable, Hashable, CaseIterable {
    case daylight
    case twilight
    case dark
    public init(sunElevation: Double)
  }
  public var sunElevation: Double
  public var isSunlit: Bool
  public var phaseAngle: Double
  public var range: Double
  public init(sunElevation: Double, isSunlit: Bool, phaseAngle: Double, range: Double)
  public var sky: Sunlight.Sky { get }
  public var canBeSeen: Bool { get }
  public func magnitude(standard: Double) -> Double?
}
public struct PassVisibility : Sendable, Hashable {
  public struct Stretch : Sendable, Hashable {
    public var start: Epoch
    public var end: Epoch
    public init(start: Epoch, end: Epoch)
  }
  public var culmination: Sunlight
  public var sunlit: PassVisibility.Stretch?
  public var visible: PassVisibility.Stretch?
  public init(culmination: Sunlight, sunlit: PassVisibility.Stretch?, visible: PassVisibility.Stretch?)
  public var canBeSeen: Bool { get }
}
extension Propagator {
  public func sunlight(from observer: Observer, at time: Epoch) throws(PropagationFailure) -> Sunlight
  public func visibility(of pass: Pass, from observer: Observer) -> PassVisibility?
}
public enum TLE {
  public enum Checksum : Sendable, Hashable {
    case verify
    case ignore
  }
  public static let yearPivot: Int
  public static func fullYear(twoDigit year: Int) -> Int
  public static func checksum(of line: String) -> Int
  public static func parse(name: String? = nil, line1: String, line2: String, checksum: TLE.Checksum = .verify) throws(Refusal) -> ElementSet
  public struct Lines : Sendable, Hashable {
    public let name: String?
    public let line1: String
    public let line2: String
    public var text: String { get }
  }
  public enum Resolution : Sendable {
    case rounded
    case truncated
  }
  public static func write(_ set: ElementSet, eccentricity: TLE.Resolution = .rounded) throws(Refusal) -> TLE.Lines
}
