// GPKit's adapter for the gpconf runner, in its command protocol (docs/ADAPTERS.md of gp-omm-conformance).
//
//   gpkit-gpconf parse <format>   a file on standard input; a JSON array of records and refusals on standard output;
//                                 exit 3 for a format GPKit does not read
//   gpkit-gpconf vectors          {"op": ..., "input": ...} on standard input; {"result": ...} or {"error": ...}
//   gpkit-gpconf write            one record on standard input; the TLE's lines on standard output; a non-zero exit
//                                 when GPKit refuses to write it
//
// The adapter decides nothing. A record is what GPKit read, a refusal carries GPKit's reason, and a refusal of the
// whole file ends the run with a non-zero exit and that reason on standard error.

import Foundation
import GPKit

func jsonString(_ text: String) -> String {
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

/// A JSON value as text: a string as it is, a number in digits. Foundation hands numbers back as different types
/// on macOS and on Linux, so each is tried.
func plainText(_ value: Any?) -> String? {
    if let string = value as? String { return string }
    if let integer = value as? Int { return String(integer) }
    if let number = value as? NSNumber { return number.stringValue }
    if let double = value as? Double { return "\(double)" }
    return nil
}

func emit(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let arguments = CommandLine.arguments.dropFirst()
let input = FileHandle.standardInput.readDataToEndOfFile()

switch arguments.first {

case "parse":
    let name = arguments.dropFirst().first ?? ""
    guard let format = Format(rawValue: name == "2le" ? "tle" : name) else { exit(3) }
    let file: ElementSetFile
    do {
        file = try ElementSets.read(input, as: format)
    } catch {
        fail("GPKit refused the file: \(error)")
    }
    var items = ["{\"_adapter\":{\"refusals\":true}}"]
    for entry in file.entries {
        switch entry {
        case .refusal(let refusal):
            var parts = ["\"_refused\":\(jsonString(refusal.description))"]
            if let field = refusal.catalogField { parts.append("\"_field\":\(jsonString(field))") }
            if let text = refusal.text { parts.append("\"_input\":\(jsonString(text))") }
            items.append("{" + parts.joined(separator: ",") + "}")
        case .elementSet(let set):
            var parts: [String] = []
            func text(_ key: String, _ value: String?) { parts.append("\"\(key)\":\(value.map(jsonString) ?? "null")") }
            func integer(_ key: String, _ value: Int?) { if let value { parts.append("\"\(key)\":\(value)") } }
            // a decimal goes out as a string, so the runner compares the digits and not a float
            func decimal(_ key: String, _ value: ExactDecimal) { parts.append("\"\(key)\":\"\(value)\"") }
            integer("norad_cat_id", set.catalogNumber)
            text("object_name", set.objectName)
            text("object_id", set.objectID)
            text("epoch", set.epoch.description)
            decimal("mean_motion", set.meanMotion)
            decimal("eccentricity", set.eccentricity)
            decimal("inclination", set.inclination)
            decimal("ra_of_asc_node", set.rightAscension)
            decimal("arg_of_pericenter", set.argumentOfPericenter)
            decimal("mean_anomaly", set.meanAnomaly)
            decimal("bstar", set.bstar)
            decimal("mean_motion_dot", set.meanMotionDot)
            decimal("mean_motion_ddot", set.meanMotionDDot)
            integer("ephemeris_type", set.ephemerisType)
            if let classification = set.classification { text("classification_type", classification) }
            integer("element_set_no", set.elementSetNumber)
            integer("rev_at_epoch", set.revolutionAtEpoch)
            text("center_name", set.centerName)
            text("ref_frame", set.referenceFrame)
            text("time_system", set.timeSystem)
            text("mean_element_theory", set.meanElementTheory)
            items.append("{" + parts.joined(separator: ",") + "}")
        }
    }
    emit("[" + items.joined(separator: ",") + "]\n")

case "vectors":
    guard let request = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any], let op = request["op"] as? String else {
        emit("{\"error\":\"the request is not {op, input}\"}")
        exit(1)
    }
    let text = plainText(request["input"]) ?? ""
    do {
        switch op {
        case "alpha5_decode":
            emit("{\"result\":\(try Alpha5.decode(text))}")
        case "alpha5_encode":
            guard let number = Int(text) else { throw Refusal(.cannotEncode, "\"\(text)\" is not a whole number") }
            emit("{\"result\":\(jsonString(try Alpha5.encode(number)))}")
        case "two_digit_year":
            guard text.utf8.count == 2, let year = Int(text), year >= 0 else { throw Refusal(.notANumber, "\"\(text)\" is not a two-digit year") }
            emit("{\"result\":\(TLE.fullYear(twoDigit: year))}")
        case "parse_epoch":
            var epoch = try Epoch(ccsds: text)
            if epoch.second == 60 {
                // The runner reads the answer into a type that has no second 60. GPKit keeps the leap second; here it
                // is given as the instant the runner's own vector allows for it, the midnight that follows.
                let lastDay = epoch.dayOfYear == (epoch.year % 4 == 0 && (epoch.year % 100 != 0 || epoch.year % 400 == 0) ? 366 : 365)
                epoch = try Epoch(year: lastDay ? epoch.year + 1 : epoch.year, dayOfYear: lastDay ? 1 : epoch.dayOfYear + 1,
                                  hour: 0, minute: 0, second: 0, attosecond: epoch.attosecond)
            }
            // to the microsecond, which is what the runner's reader takes
            emit("{\"result\":\(jsonString(String(epoch.description.prefix(26))))}")
        case "parse_catalog_id":
            emit("{\"result\":\(try OMM.catalogNumber(text))}")
        default:
            emit("{\"error\":\(jsonString("unknown op \(op)"))}")
            exit(1)
        }
    } catch {
        emit("{\"error\":\(jsonString("\(error)"))}")
        exit(1)
    }

case "write":
    guard let record = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else { fail("the record is not a JSON object", code: 2) }
    func string(_ key: String) -> String? {
        plainText(record[key]).flatMap { $0.isEmpty ? nil : $0 }
    }
    func integer(_ key: String) -> Int? {
        string(key).flatMap { Int($0) }
    }
    do {
        func decimal(_ key: String) throws(Refusal) -> ExactDecimal {
            guard let text = string(key) else { return .zero }
            guard let value = ExactDecimal(text) else { throw Refusal(.notANumber, "\(key) \"\(text)\" is not a number", field: key, text: text) }
            return value
        }
        let set = ElementSet(
            catalogNumber: integer("norad_cat_id"), objectName: string("object_name"), objectID: string("object_id"),
            classification: string("classification_type"), epoch: try Epoch(ccsds: string("epoch") ?? ""),
            meanMotion: try decimal("mean_motion"), eccentricity: try decimal("eccentricity"), inclination: try decimal("inclination"),
            rightAscension: try decimal("ra_of_asc_node"), argumentOfPericenter: try decimal("arg_of_pericenter"),
            meanAnomaly: try decimal("mean_anomaly"), bstar: try decimal("bstar"), meanMotionDot: try decimal("mean_motion_dot"),
            meanMotionDDot: try decimal("mean_motion_ddot"), ephemerisType: integer("ephemeris_type"),
            elementSetNumber: integer("element_set_no"), revolutionAtEpoch: integer("rev_at_epoch"))
        emit(try TLE.write(set).text + "\n")
    } catch {
        fail("GPKit refused to write the record: \(error)")
    }

default:
    fail("usage: gpkit-gpconf parse <format> | vectors | write", code: 2)
}
