// GPKitSources's public interface, as the compiler states it: tools/public-api.sh writes this file; do not edit it.
// Left out: module prefixes, and what the compiler synthesises for Hashable, CaseIterable and RawRepresentable.
// Each declaration's documentation is in Sources/GPKitSources.

public enum CelesTrak {
  public static let host: String
  public static let gp: Foundation.URL
  public enum Query : Sendable, Hashable {
    case catalogNumber(Int)
    case internationalDesignator(String)
    case group(String)
    case name(String)
  }
  public enum AnswerFormat : String, Sendable, Hashable, CaseIterable {
    case csv, json, xml, kvn, tle
    public var format: Format { get }
  }
  public static func url(_ query: CelesTrak.Query, format: CelesTrak.AnswerFormat = .csv) -> Foundation.URL?
  public static func fetch(_ query: CelesTrak.Query, format: CelesTrak.AnswerFormat = .csv, with client: SourceClient, now: Foundation.Date = Date()) async -> Fetched<ElementSetFile>
}
public struct HTTPRequest : Sendable, Hashable {
  public var url: Foundation.URL
  public var headers: [String : String]
  public init(url: Foundation.URL, headers: [String : String] = [:])
}
public struct HTTPAnswer : Sendable, Hashable {
  public var status: Int
  public var body: Foundation.Data
  public init(status: Int, body: Foundation.Data)
}
public protocol Transport : Sendable {
  func get(_ request: HTTPRequest) async throws -> HTTPAnswer
}
final public class RecordedTransport : Transport, @unchecked Sendable {
  public struct NotRecorded : Error, Equatable {
    public let url: Foundation.URL
  }
  public init(_ answers: [Foundation.URL : HTTPAnswer])
  final public var requests: [HTTPRequest] { get }
  final public func get(_ request: HTTPRequest) async throws -> HTTPAnswer
}
final public class URLSessionTransport : Foundation.NSObject, Transport, Foundation.URLSessionTaskDelegate, @unchecked Sendable {
  final public let timeout: Foundation.TimeInterval
  public init(timeout: Foundation.TimeInterval = 60)
  final public func get(_ request: HTTPRequest) async throws -> HTTPAnswer
  final public func urlSession(_ session: Foundation.URLSession, task: Foundation.URLSessionTask, willPerformHTTPRedirection response: Foundation.HTTPURLResponse, newRequest request: Foundation.URLRequest) async -> Foundation.URLRequest?
}
public struct Attempt : Codable, Hashable, Sendable {
  public var url: String
  public var askedAt: Foundation.Date
  public var status: Int?
  public var bytes: Int
  public init(url: String, askedAt: Foundation.Date, status: Int? = nil, bytes: Int = 0)
  public func encode(to encoder: any Encoder) throws
  public init(from decoder: any Decoder) throws
}
public enum Fetched<Value> : Sendable where Value : Sendable {
  case fetched(Value, Attempt)
  case cached(Value, Attempt)
  case tooSoon(Attempt)
  case notAsked(String)
  case stopped(Attempt, excerpt: String)
  case unreadable(Attempt, reason: String, excerpt: String)
  case noAnswer(Attempt, reason: String)
}
public actor Ledger {
  public struct State : Codable, Hashable, Sendable {
    public var byURL: [String : Attempt]
    public var failedByHost: [String : Attempt]
    public init()
    public func encode(to encoder: any Encoder) throws
    public init(from decoder: any Decoder) throws
  }
  final public let quiet: Foundation.TimeInterval
  public var state: Ledger.State { get }
  public init(state: Ledger.State = State(), quiet: Foundation.TimeInterval = 2 * 3600)
  public func holding(_ url: Foundation.URL, at now: Foundation.Date) -> Attempt?
  public func nextAsk(_ url: Foundation.URL, at now: Foundation.Date) -> Foundation.Date?
  public func record(_ attempt: Attempt, host: String?)
  @_semantics("defaultActor") nonisolated final public var unownedExecutor: _Concurrency::UnownedSerialExecutor { get }
}
public actor AnswerCache {
  public init(folder: Foundation.URL? = nil)
  public func answer(for url: String) -> Foundation.Data?
  public func keep(_ data: Foundation.Data, for url: String)
  @_semantics("defaultActor") nonisolated final public var unownedExecutor: _Concurrency::UnownedSerialExecutor { get }
}
public struct SourceClient : Sendable {
  public let transport: any Transport
  public let ledger: Ledger
  public let cache: AnswerCache
  public let application: String
  public init(transport: any Transport, application: String, ledger: Ledger = Ledger(), cache: AnswerCache = AnswerCache())
  public var userAgent: String { get }
  public static let excerpt: Int
}
public struct FolderSource : Sendable {
  public let folder: Foundation.URL
  public let checksum: TLE.Checksum
  public init(folder: Foundation.URL, checksum: TLE.Checksum = .verify)
  public static func format(of name: String) -> Format?
  public struct Reading : Sendable {
    public var files: [(name: String, file: ElementSetFile)]
    public var failed: [(name: String, refusal: Refusal)]
    public var skipped: [String]
  }
  public func read() throws -> FolderSource.Reading
  public func load(into store: ElementSetStore) async throws -> (report: ElementSetStore.Report, reading: FolderSource.Reading)
}
public enum SatNOGS {
  public static let host: String
  public static let activeTransmitters: Foundation.URL
  public static let credit: String
  public struct Unreadable : Error, CustomStringConvertible {
    public let description: String
  }
  public static func transmitters(from data: Foundation.Data) throws(SatNOGS.Unreadable) -> [Transmitter]
  public static func fetchActiveTransmitters(with client: SourceClient, now: Foundation.Date = Date()) async -> Fetched<[Transmitter]>
}
public struct Transmitter : Sendable, Hashable, Identifiable {
  public var id: String
  public var description: String
  public var kind: String
  public var satelliteID: String?
  public var catalogNumber: Int?
  public var followedCatalogNumber: Int?
  public var downlinkLow: Int64?
  public var downlinkHigh: Int64?
  public var uplinkLow: Int64?
  public var uplinkHigh: Int64?
  public var mode: String?
  public var uplinkMode: String?
  public var baud: Double?
  public var inverting: Bool
  public var service: String?
  public var status: String?
  public var alive: Bool?
  public var unconfirmed: Bool
  public var updated: String?
  public func downlink(at look: Look) -> Double?
  public func uplink(at look: Look) -> Double?
  public func downlink(forUplink uplink: Double) -> Double?
  public typealias ID = String
}
extension Collection where Self.Element == Transmitter {
  public func of(catalogNumber: Int) -> [Transmitter]
}
public actor ElementSetStore {
  public struct Report : Sendable, Hashable {
    public var added: Int
    public var replaced: Int
    public var unchanged: Int
    public var older: Int
    public var conflicting: [Int]
    public var uncatalogued: Int
    public var refused: Int
    public init()
  }
  nonisolated final public let keep: Int
  public init(keep: Int = 4)
  public init(saved: Foundation.Data, keep: Int = 4) throws(Refusal)
  @discardableResult
  public func merge(_ file: ElementSetFile) -> ElementSetStore.Report
  @discardableResult
  public func merge(_ elementSets: [ElementSet]) -> ElementSetStore.Report
  public func current(_ catalogNumber: Int) -> ElementSet?
  public func history(_ catalogNumber: Int) -> [ElementSet]
  public var catalogNumbers: [Int] { get }
  public func stale(at time: Epoch, olderThan days: Double) -> [Int]
  public func save() -> Foundation.Data
  @_semantics("defaultActor") nonisolated final public var unownedExecutor: _Concurrency::UnownedSerialExecutor { get }
}
