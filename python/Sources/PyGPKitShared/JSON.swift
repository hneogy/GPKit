import GPKit

/// GPKit's values as JSON text. A number is written in the shortest form that reads back as the same Double, which is
/// what Python's float() reads it as, so a value goes from Swift to Python unchanged to the bit.
public enum JSON {

    public static func string(_ text: String) -> String {
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

    /// A finite number in its shortest round-trip form; a number that is not finite, which JSON has no form for, as null.
    public static func number(_ value: Double) -> String {
        value.isFinite ? "\(value)" : "null"
    }

    public static func optional<T>(_ value: T?, _ write: (T) -> String) -> String {
        value.map(write) ?? "null"
    }

    public static func object(_ fields: [(String, String)]) -> String {
        "{" + fields.map { "\(string($0.0)): \($0.1)" }.joined(separator: ", ") + "}"
    }

    public static func array(_ items: [String]) -> String {
        "[" + items.joined(separator: ", ") + "]"
    }

    public static func vector(_ v: Vector) -> String {
        array([number(v.x), number(v.y), number(v.z)])
    }

    public static func elementSet(_ set: ElementSet) -> String {
        object([
            ("catalog_number", optional(set.catalogNumber) { String($0) }),
            ("object_name", optional(set.objectName, string)),
            ("object_id", optional(set.objectID, string)),
            ("classification", optional(set.classification, string)),
            ("epoch", string(set.epoch.description)),
            ("mean_motion", string(set.meanMotion.description)),
            ("eccentricity", string(set.eccentricity.description)),
            ("inclination", string(set.inclination.description)),
            ("right_ascension", string(set.rightAscension.description)),
            ("argument_of_pericenter", string(set.argumentOfPericenter.description)),
            ("mean_anomaly", string(set.meanAnomaly.description)),
            ("bstar", string(set.bstar.description)),
            ("mean_motion_dot", string(set.meanMotionDot.description)),
            ("mean_motion_ddot", string(set.meanMotionDDot.description)),
            ("ephemeris_type", optional(set.ephemerisType) { String($0) }),
            ("element_set_number", optional(set.elementSetNumber) { String($0) }),
            ("revolution_at_epoch", optional(set.revolutionAtEpoch) { String($0) }),
            ("center_name", string(set.centerName)),
            ("reference_frame", string(set.referenceFrame)),
            ("time_system", string(set.timeSystem)),
            ("mean_element_theory", string(set.meanElementTheory)),
            ("defaulted", array(set.defaulted.sorted().map(string))),
            ("other_keywords", object(set.otherKeywords.sorted { $0.key < $1.key }.map { ($0.key, string($0.value)) })),
            ("source", optional(set.source) { string($0.rawValue) }),
        ])
    }

    public static func refusal(_ refusal: Refusal) -> String {
        object([
            ("kind", string(refusal.kind.rawValue)),
            ("message", string(refusal.message)),
            ("field", optional(refusal.field, string)),
            ("text", optional(refusal.text, string)),
            ("catalog_field", optional(refusal.catalogField, string)),
            ("record", optional(refusal.record) { String($0) }),
            ("line", optional(refusal.line) { String($0) }),
            ("description", string("\(refusal)")),
        ])
    }

    public static func failure(_ failure: PropagationFailure) -> String {
        object([
            ("kind", string(failure.kind.rawValue)),
            ("minutes_from_epoch", optional(failure.minutesFromEpoch, number)),
            ("description", string(failure.description)),
        ])
    }

    public static func state(_ state: StateVector) -> String {
        object([("position", vector(state.position)), ("velocity", vector(state.velocity))])
    }

    public static func look(_ look: Look) -> String {
        object([("azimuth", number(look.azimuth)), ("elevation", number(look.elevation)),
                ("range", number(look.range)), ("range_rate", number(look.rangeRate))])
    }

    public static func geodetic(_ position: GeodeticPosition) -> String {
        object([("latitude", number(position.latitude)), ("longitude", number(position.longitude)),
                ("altitude", number(position.altitude))])
    }

    public static func pass(_ pass: Pass) -> String {
        func event(_ event: Pass.Event) -> String {
            object([("time", string(event.time.description)), ("look", look(event.look))])
        }
        return object([("rise", optional(pass.rise, event)), ("culmination", event(pass.culmination)),
                       ("set", optional(pass.set, event))])
    }

    /// A result that is a value or a propagation failure.
    public static func result<T>(_ body: () throws(PropagationFailure) -> T, _ write: (T) -> String) -> String {
        do {
            return object([("value", write(try body()))])
        } catch {
            return object([("failure", failure(error))])
        }
    }
}
