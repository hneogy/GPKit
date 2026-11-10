// The playground's answers, as JSON text: what the page's module gives for each call, and what the native reference
// (playground-reference) gives for the same call, so that the two can be held equal byte for byte. Every number is
// GPKit's; nothing here reads a clock, a file or the network.
import GPKit

/// The answers as JSON text: written here, so that nothing reads JSON and no Foundation is needed. A number is in its
/// shortest form that reads back as the same Double, as pygpkit's writer does.
enum Out {
    static func string(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
    static func number(_ value: Double) -> String { value.isFinite ? "\(value)" : "null" }
    static func optional<T>(_ value: T?, _ write: (T) -> String) -> String { value.map(write) ?? "null" }
    static func object(_ fields: [(String, String)]) -> String { "{" + fields.map { "\(string($0.0)): \($0.1)" }.joined(separator: ", ") + "}" }
    static func array(_ items: [String]) -> String { "[" + items.joined(separator: ", ") + "]" }
    static func elementSet(_ set: ElementSet) -> String {
        object([("catalog_number", optional(set.catalogNumber) { String($0) }), ("object_name", optional(set.objectName, string)),
                ("object_id", optional(set.objectID, string)), ("epoch", string(set.epoch.description)),
                ("epoch_unix", number(set.epoch.unixTime)),
                ("mean_motion", string(set.meanMotion.description)), ("eccentricity", string(set.eccentricity.description)),
                ("inclination", string(set.inclination.description)), ("right_ascension", string(set.rightAscension.description)),
                ("argument_of_pericenter", string(set.argumentOfPericenter.description)), ("mean_anomaly", string(set.meanAnomaly.description)),
                ("bstar", string(set.bstar.description))])
    }
}

/// The format the text is in, told from its first characters as GPKit's own example tools do.
func format(of text: String) -> Format {
    let start = text.drop { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" || $0 == "\u{FEFF}" }
    if start.hasPrefix("{") || start.hasPrefix("[") { return .json }
    if start.hasPrefix("<") { return .xml }
    if start.hasPrefix("CCSDS_OMM_VERS") || start.hasPrefix("COMMENT") { return .kvn }
    if start.hasPrefix("OBJECT_NAME") || start.hasPrefix("CCSDS_OMM_VERS,") { return .csv }
    return .tle
}

func refusal(_ refusal: Refusal) -> String {
    Out.object([("kind", Out.string(refusal.kind.rawValue)), ("message", Out.string(refusal.message)),
                 ("line", Out.optional(refusal.line) { String($0) })])
}

func epoch(_ time: Epoch) -> String {
    Out.object([("utc", Out.string(time.description)), ("unix", Out.number(time.unixTime))])
}

/// The file read, or the reason it cannot be: its element sets in order, each with its index among them.
func readSets(_ input: String) -> (sets: [ElementSet], answer: String) {
    let format = format(of: input)
    let file: ElementSetFile
    do throws(Refusal) {
        file = try ElementSets.read(input, as: format)
    } catch {
        return ([], Out.object([("format", Out.string(format.rawValue)), ("refusal", refusal(error))]))
    }
    var sets: [ElementSet] = []
    var entries: [String] = []
    for entry in file.entries {
        switch entry {
        case .elementSet(let set):
            let tle: String
            do throws(Refusal) {
                let lines = try TLE.write(set)
                tle = Out.object([("line1", Out.string(lines.line1)), ("line2", Out.string(lines.line2))])
            } catch {
                tle = Out.object([("refusal", refusal(error))])
            }
            entries.append(Out.object([("index", String(sets.count)), ("set", Out.elementSet(set)), ("tle", tle)]))
            sets.append(set)
        case .refusal(let reason):
            entries.append(Out.object([("refusal", refusal(reason))]))
        }
    }
    return (sets, Out.object([("format", Out.string(format.rawValue)), ("entries", Out.array(entries)),
                               ("provider_message", Out.optional(file.providerMessage, Out.string))]))
}

func failure(_ failure: PropagationFailure) -> String {
    Out.object([("failure", Out.object([("kind", Out.string(failure.kind.rawValue)), ("message", Out.string(failure.description))]))])
}

/// Why an answer cannot be given.
struct Problem: Error { let words: String }

func problem(_ words: String) -> String {
    Out.object([("problem", Out.string(words))])
}

/// One set's propagator, from the text and the set's index, or why there is none.
func propagatorFor(_ input: String, _ index: Int32) -> Result<Propagator, Problem> {
    let sets = readSets(input).sets
    guard sets.indices.contains(Int(index)) else { return .failure(Problem(words: "there is no element set \(index) in the text")) }
    do throws(PropagationFailure) {
        return .success(try Propagator(sets[Int(index)]))
    } catch {
        return .failure(Problem(words: error.description))
    }
}

func lookJSON(_ look: Look) -> String {
    Out.object([("azimuth", Out.number(look.azimuth)), ("elevation", Out.number(look.elevation)),
                 ("range", Out.number(look.range)), ("range_rate", Out.number(look.rangeRate))])
}

func sunlightJSON(_ light: Sunlight) -> String {
    Out.object([("sky", Out.string(light.sky.rawValue)), ("sun_elevation", Out.number(light.sunElevation)),
                 ("sunlit", light.isSunlit ? "true" : "false"), ("can_be_seen", light.canBeSeen ? "true" : "false")])
}


/// The three calls the page makes, each answered as JSON text.
public enum Answers {

    /// The element sets in the text as GPKit reads them, and each one's TLE or GPKit's reason.
    public static func read(_ input: String) -> String { readSets(input).answer }

    /// Each element set's epoch in the text, in seconds from 1970, in the order `read` gives them their indexes.
    public static func epochs(_ input: String) -> [Double] { readSets(input).sets.map(\.epoch.unixTime) }

    /// Where one of them is from a place at an instant, and its light.
    public static func now(_ input: String, index: Int32, latitude: Double, longitude: Double, height: Double,
                           unixTime: Double) -> String {
        let propagator: Propagator
        switch propagatorFor(input, index) {
        case .success(let made): propagator = made
        case .failure(let why): return problem(why.words)
        }
        let observer = Observer(latitude: latitude, longitude: longitude, height: height)
        let time: Epoch
        do throws(Refusal) { time = try Epoch(unixTime: unixTime) } catch { return problem(error.message) }
        do throws(PropagationFailure) {
            let seen = try propagator.look(from: observer, at: time)
            let below = try propagator.position(at: time)
            let light = try propagator.sunlight(from: observer, at: time)
            return Out.object([("time", epoch(time)), ("look", lookJSON(seen)),
                               ("beneath", Out.object([("latitude", Out.number(below.latitude)), ("longitude", Out.number(below.longitude)),
                                                        ("altitude", Out.number(below.altitude))])),
                               ("light", sunlightJSON(light))])
        } catch {
            return failure(error)
        }
    }

    /// Its passes over the place, each with when it can be seen.
    public static func passes(_ input: String, index: Int32, latitude: Double, longitude: Double, height: Double,
                              unixStart: Double, seconds: Double, above: Double) -> String {
        let propagator: Propagator
        switch propagatorFor(input, index) {
        case .success(let made): propagator = made
        case .failure(let why): return problem(why.words)
        }
        let observer = Observer(latitude: latitude, longitude: longitude, height: height)
        let start: Epoch
        do throws(Refusal) { start = try Epoch(unixTime: unixStart) } catch { return problem(error.message) }
        let found = propagator.passes(over: observer, from: start, for: .seconds(seconds), above: above)
        func event(_ event: Pass.Event?) -> String {
            Out.optional(event) { Out.object([("time", epoch($0.time)), ("look", lookJSON($0.look))]) }
        }
        let passes = found.map { pass in
            let seen = propagator.visibility(of: pass, from: observer)
            return Out.object([("rise", event(pass.rise)), ("culmination", event(pass.culmination)), ("set", event(pass.set)),
                               ("visible", Out.optional(seen?.visible) { Out.object([("start", epoch($0.start)), ("end", epoch($0.end))]) }),
                               ("light", Out.optional(seen?.culmination, sunlightJSON))])
        }
        return Out.object([("passes", Out.array(passes)), ("failure", Out.optional(found.failure) { failure($0) })])
    }
}
