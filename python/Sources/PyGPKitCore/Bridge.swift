// pygpkit's native part: one C function, pygpkit_call, takes a request as JSON and gives the answer as JSON, which
// pygpkit_free gives back. Element sets and propagators stay here and are named to Python by a number.
//
// Requests, by "op":
//   read        {"data": base64, "format": "tle"|"csv"|"json"|"xml"|"kvn", "checksum": true|false}
//               -> {"entries": [{"set": id, "fields": {...}} | {"refusal": {...}}], "provider_message": text|null}
//   tle         {"set": id, "eccentricity": "rounded"|"truncated"} -> {"name", "line1", "line2"} | {"refusal": {...}}
//   propagator  {"set": id, "gravity": "wgs72"|"wgs84"|"wgs72old"} -> {"propagator": id} | {"failure": {...}}
//   state       {"propagator": id, "times": [epoch...]} or {"propagator": id, "minutes": [number...]}
//   look        {"propagator": id, "observer": [lat, lon, height m], "times": [epoch...]}
//   position    {"propagator": id, "times": [epoch...]}
//               -> {"results": [{"value": ...} | {"failure": {...}}]}
//   passes      {"propagator": id, "observer": [...], "start": epoch, "seconds": n, "above": degrees}
//               -> {"passes": [...], "failure": {...}|null}
//   release     {"ids": [id...]} -> {}
// A request that cannot be understood gets {"error": text}.
import Foundation
import GPKit
import PyGPKitShared

final class Registry: @unchecked Sendable {
    private let lock = NSLock()
    private var next = 1
    private var sets: [Int: ElementSet] = [:]
    private var propagators: [Int: Propagator] = [:]

    func add(_ set: ElementSet) -> Int { lock.withLock { defer { next += 1 }; sets[next] = set; return next } }
    func add(_ propagator: Propagator) -> Int { lock.withLock { defer { next += 1 }; propagators[next] = propagator; return next } }
    func set(_ id: Int) -> ElementSet? { lock.withLock { sets[id] } }
    func propagator(_ id: Int) -> Propagator? { lock.withLock { propagators[id] } }
    func release(_ ids: [Int]) { lock.withLock { for id in ids { sets[id] = nil; propagators[id] = nil } } }
}

let registry = Registry()

struct BadRequest: Error { let reason: String }

func handle(_ text: String) -> String {
    do {
        guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw BadRequest(reason: "the request is not a JSON object") }
        return try answer(object)
    } catch let bad as BadRequest {
        return JSON.object([("error", JSON.string(bad.reason))])
    } catch {
        return JSON.object([("error", JSON.string("the request is not JSON: \(error)"))])
    }
}

func answer(_ request: [String: Any]) throws -> String {
    func value<T>(_ key: String, as: T.Type = T.self) throws -> T {
        guard let value = request[key] as? T else { throw BadRequest(reason: "\(key) is missing or of the wrong type") }
        return value
    }
    func number(_ any: Any) throws -> Double {
        if let n = any as? NSNumber { return n.doubleValue }
        throw BadRequest(reason: "\(any) is not a number")
    }
    func epochs(_ key: String) throws -> [Epoch] {
        try value(key, as: [String].self).map { text in
            do { return try Epoch(ccsds: text) } catch { throw BadRequest(reason: "\(text): \(error)") }
        }
    }
    func propagator() throws -> Propagator {
        let id = try value("propagator", as: Int.self)
        guard let propagator = registry.propagator(id) else { throw BadRequest(reason: "no propagator \(id)") }
        return propagator
    }
    func observer() throws -> Observer {
        let place = try value("observer", as: [Any].self).map(number)
        guard place.count == 3 else { throw BadRequest(reason: "observer is [latitude, longitude, height in metres]") }
        return Observer(latitude: place[0], longitude: place[1], height: place[2])
    }
    func results<T>(_ write: (T) -> String, _ each: (Epoch) throws(PropagationFailure) -> T) throws -> String {
        JSON.object([("results", JSON.array(try epochs("times").map { time in JSON.result({ () throws(PropagationFailure) -> T in try each(time) }, write) }))])
    }

    switch try value("op", as: String.self) {
    case "read":
        guard let data = Data(base64Encoded: try value("data", as: String.self)) else { throw BadRequest(reason: "data is not base64") }
        guard let format = Format(rawValue: try value("format", as: String.self)) else { throw BadRequest(reason: "format is csv, json, xml, kvn or tle") }
        let checksum: TLE.Checksum = (request["checksum"] as? Bool ?? true) ? .verify : .ignore
        do {
            let file = try ElementSets.read(data, as: format, checksum: checksum)
            let entries = file.entries.map { entry in
                switch entry {
                case .elementSet(let set): JSON.object([("set", String(registry.add(set))), ("fields", JSON.elementSet(set))])
                case .refusal(let refusal): JSON.object([("refusal", JSON.refusal(refusal))])
                }
            }
            return JSON.object([("entries", JSON.array(entries)), ("provider_message", JSON.optional(file.providerMessage, JSON.string))])
        } catch {
            return JSON.object([("refusal", JSON.refusal(error))])
        }
    case "tle":
        let id = try value("set", as: Int.self)
        guard let set = registry.set(id) else { throw BadRequest(reason: "no element set \(id)") }
        let truncated = (request["eccentricity"] as? String) == "truncated"
        do {
            let lines = try TLE.write(set, eccentricity: truncated ? .truncated : .rounded)
            return JSON.object([("name", JSON.optional(lines.name, JSON.string)), ("line1", JSON.string(lines.line1)), ("line2", JSON.string(lines.line2))])
        } catch {
            return JSON.object([("refusal", JSON.refusal(error))])
        }
    case "propagator":
        let id = try value("set", as: Int.self)
        guard let set = registry.set(id) else { throw BadRequest(reason: "no element set \(id)") }
        let gravity: Propagator.Gravity
        switch request["gravity"] as? String ?? "wgs72" {
        case "wgs72": gravity = .wgs72
        case "wgs84": gravity = .wgs84
        case "wgs72old": gravity = .wgs72old
        default: throw BadRequest(reason: "gravity is wgs72, wgs84 or wgs72old")
        }
        do {
            return JSON.object([("propagator", String(registry.add(try Propagator(set, gravity: gravity))))])
        } catch {
            return JSON.object([("failure", JSON.failure(error))])
        }
    case "state":
        let p = try propagator()
        if let minutes = request["minutes"] as? [Any] {
            let items = try minutes.map(number).map { m in JSON.result({ () throws(PropagationFailure) -> StateVector in try p.state(minutesFromEpoch: m) }, JSON.state) }
            return JSON.object([("results", JSON.array(items))])
        }
        return try results(JSON.state) { time throws(PropagationFailure) in try p.state(at: time) }
    case "look":
        let p = try propagator(), place = try observer()
        return try results(JSON.look) { time throws(PropagationFailure) in try p.look(from: place, at: time) }
    case "position":
        let p = try propagator()
        return try results(JSON.geodetic) { time throws(PropagationFailure) in try p.position(at: time) }
    case "passes":
        let p = try propagator(), place = try observer()
        let start: Epoch
        do { start = try Epoch(ccsds: try value("start", as: String.self)) } catch let bad as BadRequest { throw bad } catch { throw BadRequest(reason: "start: \(error)") }
        let seconds = try number(try value("seconds", as: Any.self))
        let above = try request["above"].map(number) ?? 0
        guard seconds.isFinite, seconds > 0, seconds < 1e10 else { throw BadRequest(reason: "seconds is a positive number") }
        let passes = p.passes(over: place, from: start, for: .milliseconds(Int64((seconds * 1000).rounded())), above: above)
        return JSON.object([("passes", JSON.array(passes.map(JSON.pass))), ("failure", JSON.optional(passes.failure, JSON.failure))])
    case "release":
        registry.release(try value("ids", as: [Int].self))
        return "{}"
    case let op:
        throw BadRequest(reason: "no op \(op)")
    }
}

@_cdecl("pygpkit_call")
public func pygpkit_call(_ request: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar> {
    let bytes = Array(handle(String(cString: request)).utf8CString)
    let out = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
    out.initialize(from: bytes, count: bytes.count)
    return out
}

@_cdecl("pygpkit_free")
public func pygpkit_free(_ answer: UnsafeMutablePointer<CChar>?) {
    answer?.deallocate()
}
