// GPKit's public interface, as the compiler states it: tools/public-api.sh writes this file; do not edit it.
// Left out: module prefixes, and what the compiler synthesises for Hashable, CaseIterable and RawRepresentable.
// Each declaration's documentation is in Sources/GPKit.

public enum Alpha5 {
  public static let ceiling: Int
  public static func decode(_ field: String) throws(Refusal) -> Int
  public static func encode(_ catalogNumber: Int) throws(Refusal) -> String
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
  public init(_ elementSet: ElementSet, gravity: Propagator.Gravity = .wgs72) throws(PropagationFailure)
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
