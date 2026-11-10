import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A GET as GPKitSources makes it: an address and its headers. Its own type, not URLRequest, so that the module
/// builds where Foundation has no networking (WebAssembly), with transports only where there is one.
public struct HTTPRequest: Sendable, Hashable {
    public var url: URL
    public var headers: [String: String]

    public init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }
}

/// An HTTP answer as it came: its status and its body, whatever the status.
public struct HTTPAnswer: Sendable, Hashable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// How a request is made. A transport asks once and gives back the answer as it came, a redirect too (it is never
/// followed), and throws only where no HTTP answer came at all.
public protocol Transport: Sendable {
    func get(_ request: HTTPRequest) async throws -> HTTPAnswer
}

/// Answers from a record instead of the network: for tests, and for working offline from answers kept earlier. It
/// counts what it was asked. An address with no recorded answer throws `RecordedTransport.NotRecorded`.
public final class RecordedTransport: Transport, @unchecked Sendable {

    public struct NotRecorded: Error, Equatable { public let url: URL }

    private let lock = NSLock()
    private let answers: [URL: HTTPAnswer]
    private var made: [HTTPRequest] = []

    public init(_ answers: [URL: HTTPAnswer]) {
        self.answers = answers
    }

    /// Every request made of it, in order.
    public var requests: [HTTPRequest] { lock.withLock { made } }

    public func get(_ request: HTTPRequest) async throws -> HTTPAnswer {
        lock.withLock { made.append(request) }
        guard let answer = answers[request.url] else { throw NotRecorded(url: request.url) }
        return answer
    }
}

#if canImport(FoundationNetworking) || canImport(Darwin)
/// The network, through URLSession: a plain GET that takes nothing from a cache, sends no cookie, follows no
/// redirect and gives up after `timeout` seconds. Nothing is repeated.
public final class URLSessionTransport: NSObject, Transport, URLSessionTaskDelegate, @unchecked Sendable {

    public let timeout: TimeInterval
    private let session: URLSession

    public init(timeout: TimeInterval = 60) {
        self.timeout = timeout
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        self.session = URLSession(configuration: configuration)
        super.init()
    }

    public func get(_ request: HTTPRequest) async throws -> HTTPAnswer {
        var asked = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        asked.httpMethod = "GET"
        asked.httpShouldHandleCookies = false
        for (name, value) in request.headers { asked.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: asked, delegate: self)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return HTTPAnswer(status: http.statusCode, body: data)
    }

    /// A redirect is an answer, not a step: it is given back as it came.
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
#endif

/// One request to a source and what came of it: what the quiet hours are counted from.
public struct Attempt: Codable, Hashable, Sendable {
    public var url: String
    /// When it was asked.
    public var askedAt: Date
    /// The answer's HTTP status; nil where none came.
    public var status: Int?
    public var bytes: Int

    public init(url: String, askedAt: Date, status: Int? = nil, bytes: Int = 0) {
        self.url = url
        self.askedAt = askedAt
        self.status = status
        self.bytes = bytes
    }
}

/// What came of asking a source.
public enum Fetched<Value: Sendable>: Sendable {
    /// Asked, and read.
    case fetched(Value, Attempt)
    /// Not asked: the address was asked less than the quiet time ago, and this is what its last good answer gave.
    case cached(Value, Attempt)
    /// Not asked: the address, or the host after an answer that was not a 200, was asked less than the quiet time
    /// ago, and there is no answer kept from it.
    case tooSoon(Attempt)
    /// Not asked, and never will be as it stands: the request is one the source cannot answer. The reason says why.
    case notAsked(String)
    /// Asked, and answered with a status that is not 200. Nothing is kept; the excerpt is the answer's start.
    case stopped(Attempt, excerpt: String)
    /// Asked, answered with a 200, and what came is not what was asked for.
    case unreadable(Attempt, reason: String, excerpt: String)
    /// Asked, and no HTTP answer came: it counts toward the quiet time all the same.
    case noAnswer(Attempt, reason: String)
}

/// The rules every source in GPKitSources is asked by, kept where the caller keeps them.
///
/// - an address is asked at most once in `quiet` (two hours), whatever came of it: answered, refused or never
///   answered;
/// - after an answer that is not a 200, or none, from a host, nothing more is asked of that host for `quiet`;
/// - nothing is ever repeated by GPKitSources itself.
///
/// The state is plain data (`Ledger.State`), for the caller to save and give back, so that the rules hold from one
/// run of a program to the next.
public actor Ledger {

    public struct State: Codable, Hashable, Sendable {
        /// The last attempt at each address.
        public var byURL: [String: Attempt] = [:]
        /// The last attempt at each host that was not answered with a 200.
        public var failedByHost: [String: Attempt] = [:]
        public init() {}
    }

    public let quiet: TimeInterval
    public private(set) var state: State

    public init(state: State = State(), quiet: TimeInterval = 2 * 3600) {
        self.state = state
        self.quiet = quiet
    }

    /// The attempt that holds a request back at `now`, if one does.
    public func holding(_ url: URL, at now: Date) -> Attempt? {
        let key = url.absoluteString, host = url.host
        // an attempt dated after now is from before a clock was set back: it is dated now, so that it holds for quiet
        // from here and no longer
        if let last = state.byURL[key], last.askedAt > now { state.byURL[key]?.askedAt = now }
        if let host, let last = state.failedByHost[host], last.askedAt > now { state.failedByHost[host]?.askedAt = now }
        let candidates = [state.byURL[key], host.flatMap { state.failedByHost[$0] }].compactMap { $0 }
        return candidates.first { now < $0.askedAt.addingTimeInterval(quiet) }
    }

    /// When the rules next let `url` be asked, seen from `now`: nil when it may be asked now, else the end of the
    /// latest quiet time that holds it, its own or its host's. For a program that schedules its next fetch instead of
    /// trying and being told `tooSoon`; whether it is asked then is still `fetch`'s to decide.
    public func nextAsk(_ url: URL, at now: Date) -> Date? {
        guard holding(url, at: now) != nil else { return nil }
        let candidates = [state.byURL[url.absoluteString], url.host.flatMap { state.failedByHost[$0] }].compactMap { $0 }
        return candidates.map { $0.askedAt.addingTimeInterval(quiet) }.filter { $0 > now }.max()
    }

    public func record(_ attempt: Attempt, host: String?) {
        state.byURL[attempt.url] = attempt
        if let host, attempt.status != 200 { state.failedByHost[host] = attempt }
    }
}

/// The last good answer of each address, kept so that a program asked again within the quiet time has its data.
/// In memory, or in a folder where each answer is a file.
public actor AnswerCache {

    private var answers: [String: Data] = [:]
    private let folder: URL?

    public init(folder: URL? = nil) {
        self.folder = folder
    }

    private func file(_ url: String) -> URL? {
        folder?.appendingPathComponent(Data(url.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_"))
    }

    public func answer(for url: String) -> Data? {
        if let kept = answers[url] { return kept }
        guard let file = file(url), let data = try? Data(contentsOf: file) else { return nil }
        answers[url] = data
        return data
    }

    public func keep(_ data: Data, for url: String) {
        answers[url] = data
        guard let file = file(url) else { return }
        #if os(WASI)
        // WASI has no temporary files, which an atomic write needs
        try? data.write(to: file)
        #else
        try? data.write(to: file, options: .atomic)
        #endif
    }
}

/// A client of GPKitSources: a transport, the rules, a cache, and who is asking.
public struct SourceClient: Sendable {

    public let transport: any Transport
    public let ledger: Ledger
    public let cache: AnswerCache
    /// Names the program that asks, with an address where its makers can be found, for example
    /// `"MyApp/1.2 (+https://example.org/myapp)"`. GPKitSources adds its own name after it.
    public let application: String

    public init(transport: any Transport, application: String, ledger: Ledger = Ledger(), cache: AnswerCache = AnswerCache()) {
        self.transport = transport
        self.application = application
        self.ledger = ledger
        self.cache = cache
    }

    /// The User-Agent every request carries: the program's, then GPKitSources'.
    public var userAgent: String { "\(application) GPKitSources (+https://github.com/hneogy/GPKit)" }

    /// The most of an answer an excerpt holds.
    public static let excerpt = 2000

    /// Asks once, if the rules allow it, and reads a 200's body with `read`; `read` throws a reason for a body that
    /// is not what was asked for.
    func fetch<Value: Sendable>(_ url: URL, accept: String, now: Date, read: @Sendable (Data) throws -> Value) async -> Fetched<Value> {
        if let holding = await ledger.holding(url, at: now) {
            if let kept = await cache.answer(for: url.absoluteString), let value = try? read(kept) { return .cached(value, holding) }
            return .tooSoon(holding)
        }
        var attempt = Attempt(url: url.absoluteString, askedAt: now)
        // written down before the request goes: every attempt counts, whatever comes of it
        await ledger.record(attempt, host: nil)
        let request = HTTPRequest(url: url, headers: ["User-Agent": userAgent, "Accept": accept, "Accept-Language": "en"])
        let answer: HTTPAnswer
        do {
            answer = try await transport.get(request)
        } catch {
            await ledger.record(attempt, host: url.host)
            return .noAnswer(attempt, reason: "\(error)")
        }
        attempt.status = answer.status
        attempt.bytes = answer.body.count
        await ledger.record(attempt, host: url.host)
        let excerpt = String(decoding: answer.body.prefix(SourceClient.excerpt), as: UTF8.self)
        guard answer.status == 200 else { return .stopped(attempt, excerpt: excerpt) }
        do {
            let value = try read(answer.body)
            await cache.keep(answer.body, for: url.absoluteString)
            return .fetched(value, attempt)
        } catch {
            return .unreadable(attempt, reason: "\(error)", excerpt: excerpt)
        }
    }
}
