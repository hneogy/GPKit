// gpkit: GPKit from the terminal.
//
//   gpkit read FILE                               what the file holds: each element set, and each record refused
//   gpkit tle FILE [--truncated]                  every element set written as a TLE
//   gpkit passes FILE LATITUDE LONGITUDE [--height METRES] [--from TIME] [--hours N] [--above DEGREES] [--light]
//   gpkit where FILE [--at TIME] [--observer LATITUDE LONGITUDE [--height METRES]]
//   gpkit track FILE [--from TIME] [--minutes N] [--step SECONDS]
//   gpkit oem FILE [--from TIME] [--minutes N] [--step SECONDS] [--originator NAME]
//                                               a CCSDS OEM of the one element set's states, in TEME
//   gpkit rotator FILE LATITUDE LONGITUDE [--height METRES] [--from TIME] [--hours N] [--above DEGREES] [--pass N]
//                 [--step SECONDS] [--azimuth LOW:HIGH] [--elevation LOW:HIGH] [--follow]
//                                               Hamlib's set-position commands (P az el) for one pass, to pipe to rotctl
//
// FILE is OMM (.csv, .json, .xml, .kvn) or TLE (.tle, .txt), or - for standard input with --format. TIME is UTC in
// the CCSDS form, 2026-11-06T12:00:00; without it, now. Exit 0 when the command did what it was asked, 1 when GPKit
// refused it, 2 for a command line it does not understand.
import Foundation
import GPKit

let usage = """
usage: gpkit read FILE
       gpkit tle FILE [--truncated]
       gpkit passes FILE LATITUDE LONGITUDE [--height METRES] [--from TIME] [--hours N] [--above DEGREES] [--light]
       gpkit where FILE [--at TIME] [--observer LATITUDE LONGITUDE [--height METRES]]
       gpkit track FILE [--from TIME] [--minutes N] [--step SECONDS]
       gpkit oem FILE [--from TIME] [--minutes N] [--step SECONDS] [--originator NAME]
       gpkit rotator FILE LATITUDE LONGITUDE [--height METRES] [--from TIME] [--hours N] [--above DEGREES] [--pass N]
                     [--step SECONDS] [--azimuth LOW:HIGH] [--elevation LOW:HIGH] [--follow]
FILE: .csv, .json, .xml, .kvn, .tle or .txt, or - with --format FORMAT. TIME: UTC, 2026-11-06T12:00:00.
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var arguments = Array(CommandLine.arguments.dropFirst())

@MainActor func flag(_ name: String) -> Bool {
    guard let i = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: i)
    return true
}

@MainActor func option(_ name: String, count: Int = 1) -> [String]? {
    guard let i = arguments.firstIndex(of: name) else { return nil }
    guard i + count < arguments.count else { fail("\(name) wants \(count == 1 ? "a value" : "\(count) values")\n\(usage)", code: 2) }
    defer { arguments.removeSubrange(i...(i + count)) }
    return Array(arguments[(i + 1)...(i + count)])
}

@MainActor func number(_ name: String) -> Double? {
    guard let text = option(name)?[0] else { return nil }
    guard let value = Double(text), value.isFinite else { fail("\(name): \(text) is not a number", code: 2) }
    return value
}

@MainActor func time(_ name: String) -> Epoch {
    do {
        if let text = option(name)?[0] { return try Epoch(ccsds: text) }
        return try Epoch(Date())
    } catch {
        fail("\(name): \(error)", code: 2)
    }
}

func degrees(_ text: String, _ what: String, within limit: Double) -> Double {
    guard let value = Double(text), value.isFinite, abs(value) <= limit else { fail("\(what): \(text) is not from -\(Int(limit)) to \(Int(limit))", code: 2) }
    return value
}

/// The file, read as its extension or --format says.
@MainActor func elementSets(_ path: String) -> ElementSetFile {
    let formats: [String: Format] = ["csv": .csv, "json": .json, "xml": .xml, "kvn": .kvn, "tle": .tle, "txt": .tle]
    let named = option("--format")?[0]
    let data: Data?
    let format: Format?
    if path == "-" {
        data = FileHandle.standardInput.readDataToEndOfFile()
        format = named.flatMap { formats[$0.lowercased()] }
        if format == nil { fail("standard input: --format csv, json, xml, kvn or tle says which format it is in", code: 2) }
    } else {
        data = FileManager.default.contents(atPath: path)
        format = formats[(named ?? (path as NSString).pathExtension).lowercased()]
        if format == nil { fail("\(path): the extension, or --format, says which format it is in: csv, json, xml, kvn or tle", code: 2) }
    }
    guard let data, let format else { fail("\(path): cannot be read") }
    do {
        return try ElementSets.read(data, as: format)
    } catch {
        fail("\(path): \(error)")
    }
}

func name(_ set: ElementSet) -> String {
    let catalog = set.catalogNumber.map { "catalog number \($0)" } ?? "no catalog number"
    return set.objectName.map { "\($0) (\(catalog))" } ?? catalog
}

func propagator(_ set: ElementSet) -> Propagator? {
    do {
        return try Propagator(set)
    } catch {
        print("  cannot be propagated: \(error)")
        return nil
    }
}

func angle(_ value: Double) -> String { String(format: "%.1f°", value) }

guard !arguments.isEmpty else { fail(usage, code: 2) }
let command = arguments.removeFirst()
var refused = false

switch command {

case "read":
    guard arguments.count >= 1 else { fail(usage, code: 2) }
    let path = arguments.removeFirst()
    let file = elementSets(path)
    guard arguments.isEmpty else { fail(usage, code: 2) }
    for entry in file.entries {
        switch entry {
        case .elementSet(let set): print("\(name(set))  epoch \(set.epoch)")
        case .refusal(let refusal): print("not read: \(refusal)"); refused = true
        }
    }
    if let message = file.providerMessage { print("the provider says: \(message)") }
    print("\(file.elementSets.count) read, \(file.refusals.count) refused")

case "tle":
    guard arguments.count >= 1 else { fail(usage, code: 2) }
    let path = arguments.removeFirst()
    let truncated = flag("--truncated")
    let file = elementSets(path)
    guard arguments.isEmpty else { fail(usage, code: 2) }
    for refusal in file.refusals { FileHandle.standardError.write(Data("not read: \(refusal)\n".utf8)); refused = true }
    for set in file.elementSets {
        do {
            print(try TLE.write(set, eccentricity: truncated ? .truncated : .rounded).text)
        } catch {
            FileHandle.standardError.write(Data("\(name(set)): not written: \(error)\n".utf8))
            refused = true
        }
    }

case "passes":
    guard arguments.count >= 3 else { fail(usage, code: 2) }
    let path = arguments.removeFirst()
    let height = number("--height") ?? 0
    let start = time("--from")
    let hours = number("--hours") ?? 24
    let above = number("--above") ?? 0
    let light = flag("--light")
    let file = elementSets(path)
    guard arguments.count == 2, hours > 0, hours <= 24 * 366, (0..<90).contains(above) else { fail(usage, code: 2) }
    let home = Observer(latitude: degrees(arguments[0], "latitude", within: 90), longitude: degrees(arguments[1], "longitude", within: 180), height: height)
    for refusal in file.refusals { print("not read: \(refusal)"); refused = true }
    for set in file.elementSets {
        print(name(set))
        guard let propagator = propagator(set) else { refused = true; continue }
        let passes = propagator.passes(over: home, from: start, for: .seconds(hours * 3600), above: above)
        for pass in passes {
            let rise = pass.rise.map { "\($0.time)" } ?? "already up"
            let set = pass.set.map { "\($0.time)" } ?? "still up"
            var line = "  \(rise)  highest \(Int(pass.culmination.look.elevation.rounded()))°  \(set)"
            if light, let visibility = propagator.visibility(of: pass, from: home) {
                if let visible = visibility.visible {
                    line += "  can be seen \(visible.start) to \(visible.end)"
                } else if visibility.sunlit == nil {
                    line += "  in the Earth's shadow"
                } else {
                    line += "  \(visibility.culmination.sky.rawValue)"
                }
            }
            print(line)
        }
        if passes.isEmpty { print("  no pass") }
        if let failure = passes.failure { print("  the search stopped: \(failure)"); refused = true }
    }

case "where":
    guard arguments.count >= 1 else { fail(usage, code: 2) }
    let path = arguments.removeFirst()
    let at = time("--at")
    let height = number("--height") ?? 0
    let observer = option("--observer", count: 2).map {
        Observer(latitude: degrees($0[0], "latitude", within: 90), longitude: degrees($0[1], "longitude", within: 180), height: height)
    }
    let file = elementSets(path)
    guard arguments.isEmpty else { fail(usage, code: 2) }
    for refusal in file.refusals { print("not read: \(refusal)"); refused = true }
    print("at \(at)")
    for set in file.elementSets {
        print(name(set))
        guard let propagator = propagator(set) else { refused = true; continue }
        do {
            let beneath = try propagator.position(at: at)
            print(String(format: "  beneath %.4f, %.4f  altitude %.1f km", beneath.latitude, beneath.longitude, beneath.altitude))
            if let observer {
                let look = try propagator.look(from: observer, at: at)
                let sky = try propagator.equatorial(from: observer, at: at)
                let light = try propagator.sunlight(from: observer, at: at)
                print("  azimuth \(angle(look.azimuth))  elevation \(angle(look.elevation))" + String(format: "  range %.1f km", look.range))
                print("  right ascension \(angle(sky.rightAscension))  declination \(angle(sky.declination))")
                print("  \(light.isSunlit ? "sunlit" : "in the Earth's shadow"), the sky \(light.sky.rawValue)" + String(format: ", the sun %.1f°", light.sunElevation))
            }
        } catch {
            print("  cannot be propagated: \(error)")
            refused = true
        }
    }

case "track":
    guard arguments.count >= 1 else { fail(usage, code: 2) }
    let path = arguments.removeFirst()
    let start = time("--from")
    let minutes = number("--minutes") ?? 95
    let step = number("--step") ?? 60
    let file = elementSets(path)
    guard arguments.isEmpty, minutes > 0, step > 0, minutes * 60 / step <= 1_000_000 else { fail(usage, code: 2) }
    for refusal in file.refusals { print("not read: \(refusal)"); refused = true }
    for set in file.elementSets {
        print(name(set))
        guard let propagator = propagator(set) else { refused = true; continue }
        let track = propagator.groundTrack(from: start, for: .seconds(minutes * 60), every: .seconds(step))
        for point in track {
            print(String(format: "  \(point.time)  %9.4f  %9.4f  %8.1f km", point.position.latitude, point.position.longitude, point.position.altitude))
        }
        if let failure = track.failure { print("  the track stopped: \(failure)"); refused = true }
    }

case "oem":
    guard arguments.count >= 1 else { fail(usage, code: 2) }
    let path = arguments.removeFirst()
    let start = time("--from")
    let minutes = number("--minutes") ?? 95
    let step = number("--step") ?? 60
    let originator = option("--originator")?[0] ?? "GPKIT"
    let file = elementSets(path)
    guard arguments.isEmpty, minutes > 0, step > 0, minutes * 60 / step <= 1_000_000 else { fail(usage, code: 2) }
    guard file.elementSets.count == 1 else { fail("\(path): the file holds \(file.elementSets.count) element sets; an OEM is of one", code: 2) }
    let set = file.elementSets[0]
    guard let propagator = propagator(set) else { exit(1) }
    do {
        let created = try Epoch(Date())
        print(try OEM.write(propagator, from: start, every: step, count: Int((minutes * 60 / step).rounded(.down)) + 1,
                            originator: originator, created: created), terminator: "")
    } catch let failure as PropagationFailure {
        fail("\(name(set)): cannot be propagated: \(failure)")
    } catch {
        fail("\(error)")
    }

case "rotator":
    guard arguments.count >= 3 else { fail(usage, code: 2) }
    let path = arguments.removeFirst()
    let height = number("--height") ?? 0
    let start = time("--from")
    let hours = number("--hours") ?? 24
    let above = number("--above") ?? 0
    let which = number("--pass") ?? 1
    let step = number("--step") ?? 1
    func range(_ name: String, _ fallback: ClosedRange<Double>) -> ClosedRange<Double> {
        guard let text = option(name)?[0] else { return fallback }
        let parts = text.split(separator: ":").map { Double($0) }
        guard parts.count == 2, let low = parts[0], let high = parts[1], low.isFinite, high.isFinite, low < high else {
            fail("\(name): \(text) is not LOW:HIGH, such as 0:360", code: 2)
        }
        return low...high
    }
    let limits = RotatorLimits(azimuth: range("--azimuth", 0...360), elevation: range("--elevation", 0...90))
    let follow = flag("--follow")
    let file = elementSets(path)
    guard arguments.count == 2, hours > 0, hours <= 24 * 366, (0..<90).contains(above), which >= 1, which == which.rounded(),
          step > 0, file.elementSets.count == 1 else {
        if file.elementSets.count != 1 { fail("\(path): the file holds \(file.elementSets.count) element sets; a rotator follows one", code: 2) }
        fail(usage, code: 2)
    }
    let home = Observer(latitude: degrees(arguments[0], "latitude", within: 90), longitude: degrees(arguments[1], "longitude", within: 180), height: height)
    let set = file.elementSets[0]
    guard let propagator = propagator(set) else { exit(1) }
    // the commands alone on standard output, for rotctl to read; what they are of, on standard error
    func note(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
    let passes = propagator.passes(over: home, from: start, for: .seconds(hours * 3600), above: above)
    guard passes.indices.contains(Int(which) - 1) else {
        note("\(name(set)): pass \(Int(which)) is not in the \(passes.count) found in \(hours) hours")
        exit(1)
    }
    let pass = passes[Int(which) - 1]
    let track = propagator.rotatorTrack(for: pass, from: home, every: step, limits: limits)
    guard !track.isEmpty else { note("\(name(set)): the pass cannot be propagated through"); exit(1) }
    note("\(name(set)): pass \(Int(which)), \(track.first!.time) to \(track.last!.time), \(track.count) positions every \(step) s")
    for point in track {
        if follow {
            // each command at its own instant: wait for it, and leave out what is already past
            let wait = point.time.unixTime - Date().timeIntervalSince1970
            if wait < -step { continue }
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }
        // written at once, not held in a buffer: with --follow each command reaches rotctl at its instant
        FileHandle.standardOutput.write(Data((point.hamlibCommand + "\n").utf8))
    }

case "help", "--help", "-h":
    print(usage)

default:
    fail("gpkit: no command \(command)\n\(usage)", code: 2)
}

exit(refused ? 1 : 0)
