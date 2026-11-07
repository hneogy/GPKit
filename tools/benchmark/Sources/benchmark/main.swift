// The propagation benchmark: 10,000 made-up element sets in four shells shaped like a large constellation's, read
// from CSV and propagated one at a time and in GPKit's batch, at one instant and over a day at one-minute steps.
//
//   swift run -c release --package-path tools/benchmark benchmark [--file PATH --format FORMAT] [--runs N]
//
// Each figure is the median of N runs (5 by default) after one run to warm up. The batch's results are checked
// against the one-at-a-time results, to the bit, before anything is timed. With --file the element sets are read
// from that file instead, and only their count and the times are printed.
import Foundation
import GPKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// The made-up constellation as CSV: element sets that look like a large constellation's, made from a rule, the same
/// on every run and every machine. No provider's data is in it.
func constellation(_ count: Int) -> String {
    var csv = "OBJECT_NAME,OBJECT_ID,EPOCH,MEAN_MOTION,ECCENTRICITY,INCLINATION,RA_OF_ASC_NODE,ARG_OF_PERICENTER,MEAN_ANOMALY,"
        + "EPHEMERIS_TYPE,CLASSIFICATION_TYPE,NORAD_CAT_ID,ELEMENT_SET_NO,REV_AT_EPOCH,BSTAR,MEAN_MOTION_DOT,MEAN_MOTION_DDOT\n"
    // revolutions a day and inclination: about 550 km at 53 degrees, 540 at 53.2, 570 at 70, 560 at 97.6
    let shells: [(motion: String, inclination: String)] = [("15.06000000", "53.0000"), ("15.10000000", "53.2000"),
                                                           ("14.98000000", "70.0000"), ("15.02000000", "97.6000")]
    for i in 0..<count {
        let shell = shells[i % 4]
        let plane = (i / 4) % 72, slot = i / 288
        let node = Double(plane) * 5.0 + Double(i % 4) * 1.25
        let anomaly = (Double(slot) * 10.4 + Double(plane) * 0.7).truncatingRemainder(dividingBy: 360)
        csv += "MADE-UP \(i),2026-000A,2026-11-01T00:00:00.000000,\(shell.motion),.0001500,\(shell.inclination),"
            + "\(String(format: "%.4f", node)),90.0000,\(String(format: "%.4f", anomaly)),0,U,\(100_000 + i),999,1,.10000E-3,.00001000,0\n"
    }
    return csv
}

var arguments = Array(CommandLine.arguments.dropFirst())
@MainActor func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    defer { arguments.removeSubrange(i...(i + 1)) }
    return arguments[i + 1]
}
let path = option("--file")
let formatName = option("--format")
let runs = option("--runs").flatMap(Int.init) ?? 5
guard arguments.isEmpty, runs > 0 else { fail("usage: benchmark [--file PATH --format csv|json|xml|kvn|tle] [--runs N]") }

func sysctl(_ name: String) -> String? {
    #if canImport(Darwin)
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: size)
    guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
    if name.hasPrefix("hw.") && size == 8 && !name.hasSuffix("model") {
        return String(bytes.withUnsafeBytes { $0.load(as: Int64.self) })
    }
    if size == 4 { return String(bytes.withUnsafeBytes { $0.load(as: Int32.self) }) }
    return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    #else
    return nil
    #endif
}

let process = ProcessInfo.processInfo
print("machine: \(sysctl("hw.model") ?? "?"), \(sysctl("machdep.cpu.brand_string") ?? "?"), "
    + "\(process.processorCount) cores (\(sysctl("hw.perflevel0.physicalcpu") ?? "?") performance, \(sysctl("hw.perflevel1.physicalcpu") ?? "?") efficiency), "
    + "\(process.physicalMemory / 1_073_741_824) GB")
print("system: \(process.operatingSystemVersionString)")
var load = [0.0, 0.0, 0.0]
if getloadavg(&load, 3) == 3 { print(String(format: "load at the start: %.2f %.2f %.2f", load[0], load[1], load[2])) }

let input: String
let format: Format
if let path {
    guard let name = formatName, let named = Format(rawValue: name) else { fail("--file wants --format csv, json, xml, kvn or tle") }
    guard let data = FileManager.default.contents(atPath: path) else { fail("\(path): cannot be read") }
    input = String(decoding: data, as: UTF8.self)
    format = named
} else {
    input = constellation(10_000)
    format = .csv
}

let clock = ContinuousClock()
/// The median of `runs` timings of `work`, after one run to warm up, in seconds.
func median(_ work: () async throws -> Void) async rethrows -> Double {
    try await work()
    var times: [Double] = []
    for _ in 0..<runs {
        let start = clock.now
        try await work()
        let elapsed = clock.now - start
        times.append(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }
    return times.sorted()[times.count / 2]
}
func say(_ what: String, _ seconds: Double, states: Int? = nil) {
    var line = String(format: "%@: %.4f s", what, seconds)
    if let states { line += String(format: ", %.0f ns a state, %.2f million states a second", seconds / Double(states) * 1e9, Double(states) / seconds / 1e6) }
    print(line)
}

do {
    let file = try ElementSets.read(input, as: format)
    let sets = file.elementSets
    let propagators = try sets.map { try Propagator($0) }
    let instant = try Epoch(ccsds: path == nil ? "2026-11-01T06:00:00" : sets[0].epoch.description).advanced(by: 0)
    print("\(path == nil ? "made-up element sets" : "element sets read"): \(sets.count) (\(file.refusals.count) refused)")

    // the batch gives what one at a time gives, before anything is timed
    let one = propagators.map { p in Result { () throws(PropagationFailure) -> StateVector in try p.state(at: instant) } }
    let batch = await Propagator.states(of: propagators, at: instant)
    guard one.count == batch.count, zip(one, batch).allSatisfy({ (a, b) in
        switch (a, b) { case (.success(let x), .success(let y)): x == y; case (.failure(let x), .failure(let y)): x == y; default: false }
    }) else { fail("the batch does not give what one propagator at a time gives") }
    let day = 1440
    let run = await Propagator.states(of: Array(propagators.prefix(200)), from: instant, every: 60, count: day)
    for (p, states) in zip(propagators.prefix(200), run) {
        for (i, state) in states.enumerated() where i % 97 == 0 {
            let single = Result { () throws(PropagationFailure) -> StateVector in try p.state(at: try! instant.advanced(by: Double(i) * 60)) }
            switch (state, single) {
            case (.success(let x), .success(let y)) where x == y: continue
            case (.failure(let x), .failure(let y)) where x == y: continue
            default: fail("the batch's run does not give what one propagator gives")
            }
        }
    }
    print("the batch's results are one at a time's, to the bit: checked")

    say("read the file", try await median { _ = try ElementSets.read(input, as: format) })
    say("make the propagators", try await median { _ = try sets.map { try Propagator($0) } })
    var sink = 0.0
    say("one instant, one at a time", await median {
        for p in propagators { if let s = try? p.state(at: instant) { sink += s.position.x } }
    }, states: propagators.count)
    say("one instant, the batch", await median {
        for case .success(let s) in await Propagator.states(of: propagators, at: instant) { sink += s.position.x }
    }, states: propagators.count)
    say("a day at one-minute steps, one at a time", await median {
        for p in propagators {
            let first = instant.seconds(since: p.elementSet.epoch) / 60
            for minute in 0..<day { if let s = try? p.state(minutesFromEpoch: first + Double(minute)) { sink += s.position.x } }
        }
    }, states: propagators.count * day)
    say("a day at one-minute steps, the batch", await median {
        for states in await Propagator.states(of: propagators, from: instant, every: 60, count: day) {
            for case .success(let s) in states { sink += s.position.x }
        }
    }, states: propagators.count * day)
    if getloadavg(&load, 3) == 3 { print(String(format: "load at the end: %.2f %.2f %.2f", load[0], load[1], load[2])) }
    if sink.isNaN { print("") }   // the sums are used, so no loop is optimized away
} catch {
    fail("\(error)")
}
