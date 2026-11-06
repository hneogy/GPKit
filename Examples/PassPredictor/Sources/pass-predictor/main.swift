// pass-predictor FILE LATITUDE LONGITUDE [--from TIME] [--hours N]
//
// The passes over a place of every element set in a file: OMM (.csv, .json, .xml, .kvn) or TLE (.tle, .txt).
// TIME is UTC in the CCSDS form, 2026-11-06T12:00:00; without it the search starts now.
import Foundation
import GPKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
@MainActor func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    defer { arguments.removeSubrange(i...(i + 1)) }
    return arguments[i + 1]
}
let from = option("--from")
let hours = option("--hours").map { Double($0) ?? 0 } ?? 24
guard arguments.count == 3, let latitude = Double(arguments[1]), let longitude = Double(arguments[2]), hours > 0 else {
    fail("usage: pass-predictor FILE LATITUDE LONGITUDE [--from 2026-11-06T12:00:00] [--hours 24]")
}
let path = arguments[0]
let formats: [String: Format] = ["csv": .csv, "json": .json, "xml": .xml, "kvn": .kvn, "tle": .tle, "txt": .tle]
guard let format = formats[(path as NSString).pathExtension.lowercased()] else {
    fail("\(path): the file's extension says which format it is in: .csv, .json, .xml, .kvn, .tle or .txt")
}
guard let data = FileManager.default.contents(atPath: path) else { fail("\(path): cannot be read") }

do {
    let file = try ElementSets.read(data, as: format)
    for refusal in file.refusals { print("not read: \(refusal)") }
    let start = try from.map { try Epoch(ccsds: $0) } ?? Epoch(Date())
    let home = Observer(latitude: latitude, longitude: longitude)
    for set in file.elementSets {
        print(set.objectName ?? "catalog number \(set.catalogNumber.map(String.init) ?? "unknown")")
        let passes = try Propagator(set).passes(over: home, from: start, for: .seconds(hours * 3600))
        for pass in passes {
            let rise = pass.rise.map { "\($0.time)" } ?? "already up"
            let set = pass.set.map { "\($0.time)" } ?? "still up"
            print("  \(rise)  highest \(Int(pass.culmination.look.elevation.rounded()))°  \(set)")
        }
        if passes.isEmpty { print("  no pass") }
        if let failure = passes.failure { print("  the search stopped: \(failure)") }
    }
} catch {
    fail("\(path): \(error)")
}
