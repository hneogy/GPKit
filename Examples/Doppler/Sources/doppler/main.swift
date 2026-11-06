// doppler FILE LATITUDE LONGITUDE DOWNLINK_HZ [--uplink HZ] [--from TIME] [--step SECONDS]
//
// What to tune a radio to through the next whole pass of the first element set in a file (see pass-predictor for
// the formats). TIME is UTC in the CCSDS form, 2026-11-06T12:00:00; without it the search starts now.
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
let uplink = option("--uplink").map { Double($0) }
let step = option("--step").map { Double($0) ?? 0 } ?? 30
guard arguments.count == 4, let latitude = Double(arguments[1]), let longitude = Double(arguments[2]),
      let downlink = Double(arguments[3]), uplink != .some(nil), step > 0 else {
    fail("usage: doppler FILE LATITUDE LONGITUDE DOWNLINK_HZ [--uplink HZ] [--from 2026-11-06T12:00:00] [--step 30]")
}
let path = arguments[0]
let formats: [String: Format] = ["csv": .csv, "json": .json, "xml": .xml, "kvn": .kvn, "tle": .tle, "txt": .tle]
guard let format = formats[(path as NSString).pathExtension.lowercased()] else {
    fail("\(path): the file's extension says which format it is in: .csv, .json, .xml, .kvn, .tle or .txt")
}
guard let data = FileManager.default.contents(atPath: path) else { fail("\(path): cannot be read") }

do {
    guard let set = try ElementSets.read(data, as: format).elementSets.first else { fail("\(path): no element set") }
    let propagator = try Propagator(set)
    let home = Observer(latitude: latitude, longitude: longitude)
    let start = try from.map { try Epoch(ccsds: $0) } ?? Epoch(Date())
    let passes = propagator.passes(over: home, from: start, for: .seconds(2 * 86_400))
    guard let pass = passes.first(where: { $0.rise != nil && $0.set != nil }), let rise = pass.rise, let end = pass.set else {
        fail("no whole pass in the next two days")
    }
    print(set.objectName ?? "catalog number \(set.catalogNumber.map(String.init) ?? "unknown")")
    print("time (UTC)                   azimuth  elevation  receive on (Hz)" + (uplink == nil ? "" : "  transmit on (Hz)"))
    var time = rise.time
    while true {
        let look = time < end.time ? try propagator.look(from: home, at: time) : end.look
        var line = "\(time)  \(String(format: "%6.1f", look.azimuth))°  \(String(format: "%8.1f", look.elevation))°"
        line += "  \(Int(look.received(from: downlink).rounded()))"
        if let uplink = uplink ?? nil { line += "      \(Int(look.transmit(toBeReceivedAt: uplink).rounded()))" }
        print(line)
        if time >= end.time { break }
        time = min(try time.advanced(by: step), end.time)
    }
} catch {
    fail("\(path): \(error)")
}
