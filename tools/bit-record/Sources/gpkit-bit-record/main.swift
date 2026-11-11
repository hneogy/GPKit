// The bit record: what GPKit's release build gives from Propagator.state, every number as its IEEE 754 bit pattern,
// for made-up element sets in every regime SGP4 treats apart, at fixed times. A platform's record is committed in
// conformance/bit-records/; checked against it, any number that moves, by however little, is reported and the run
// fails, so that a compiler, a toolchain or a system library that moves the last place is seen in CI and said in the
// changelog, not found later. GPKit does not promise the same bits on every platform or build (the 2.0.0 changelog,
// "Known platform difference"); the record holds one platform's release build to itself.
//
//   swift run -c release --package-path tools/bit-record gpkit-bit-record              the record, to standard output
//   swift run -c release --package-path tools/bit-record gpkit-bit-record --platform   the platform's name
//   swift run -c release --package-path tools/bit-record gpkit-bit-record --check FILE compared with FILE
//
// --check prints how many numbers differ and the largest difference, in units in the last place and in kilometres or
// kilometres per second, and exits 1 if any number, failure or line differs; 0 if every one is alike.
// The element sets are made from a rule, the same on every run and every machine: no provider's data, and none of
// Vallado's verification sets.
import Foundation
import GPKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

#if DEBUG
fail("the bit record is of the release build: run it with -c release")
#endif

/// The platform's name, as a record's file is named: the system and the processor.
let platform: String = {
    #if os(macOS)
    let system = "macos"
    #elseif os(Linux)
    let system = "linux"
    #elseif os(Windows)
    let system = "windows"
    #elseif os(iOS)
    let system = "ios"
    #elseif os(Android)
    let system = "android"
    #elseif os(WASI)
    let system = "wasi"
    #else
    let system = "other"
    #endif
    #if arch(arm64)
    let processor = "arm64"
    #elseif arch(x86_64)
    let processor = "x86_64"
    #elseif arch(wasm32)
    let processor = "wasm32"
    #else
    let processor = "other"
    #endif
    return system + "-" + processor
}()

/// One regime: revolutions a day, eccentricity, inclination in degrees, BSTAR, and the first derivative of the mean
/// motion. Each takes a branch of SGP4 of its own, or a case of one.
let regimes: [(name: String, motion: String, eccentricity: String, inclination: String, bstar: String, ndot: String)] = [
    ("low Earth, near circular", "15.50000000", ".0005000", "51.6000", ".30000E-3", ".00010000"),
    ("low Earth, perigee below 220 km (the simplified drag)", "16.20000000", ".0020000", "28.5000", ".30000E-3", ".00050000"),
    ("low Earth, eccentric", "13.00000000", ".1000000", "65.0000", ".10000E-3", ".00001000"),
    ("sun-synchronous", "14.20000000", ".0012000", "98.7000", ".50000E-4", ".00000500"),
    ("low Earth, equatorial", "14.80000000", ".0001000", "0.0500", ".10000E-3", ".00001000"),
    ("low Earth, retrograde", "14.60000000", ".0020000", "140.0000", ".10000E-3", ".00001000"),
    ("low Earth, decaying within days", "16.40000000", ".0004000", "51.6000", ".10000E-1", ".05000000"),
    ("medium Earth, half a day (deep space, the 12-hour resonance)", "2.00560000", ".0100000", "55.0000", "0", "0"),
    ("Molniya (deep space, the 12-hour resonance, eccentric)", "2.00600000", ".7200000", "63.4000", ".10000E-3", ".00000100"),
    ("transfer orbit (deep space, no resonance)", "2.27000000", ".7300000", "27.0000", ".10000E-3", ".00000100"),
    ("geosynchronous, equatorial (the 24-hour resonance, Lyddane's case)", "1.00270000", ".0002000", "0.0500", "0", "0"),
    ("geosynchronous, inclined (the 24-hour resonance)", "1.00270000", ".0003000", "8.0000", "0", "0"),
    ("high Earth, eccentric (deep space)", "0.50000000", ".6000000", "40.0000", "0", "0"),
]

/// The angles each regime is made at: right ascension of the node, argument of pericentre, mean anomaly.
let angles: [(node: String, pericentre: String, anomaly: String)] = [
    ("0.0000", "90.0000", "0.0000"), ("123.4567", "270.0000", "180.0000"), ("301.2500", "12.3456", "311.1111"),
]

/// The times, in minutes from the epoch: a day before, then every 720.5 minutes to ten days after.
let times: [Double] = [-1440] + (0...20).map { Double($0) * 720.5 }

func elementSets() -> [ElementSet] {
    var csv = "OBJECT_NAME,OBJECT_ID,EPOCH,MEAN_MOTION,ECCENTRICITY,INCLINATION,RA_OF_ASC_NODE,ARG_OF_PERICENTER,MEAN_ANOMALY,"
        + "EPHEMERIS_TYPE,CLASSIFICATION_TYPE,NORAD_CAT_ID,ELEMENT_SET_NO,REV_AT_EPOCH,BSTAR,MEAN_MOTION_DOT,MEAN_MOTION_DDOT\n"
    var number = 90_000
    for regime in regimes {
        for angle in angles {
            number += 1
            csv += "BIT RECORD \(number),2026-000A,2026-11-01T12:34:56.789000,\(regime.motion),\(regime.eccentricity),"
                + "\(regime.inclination),\(angle.node),\(angle.pericentre),\(angle.anomaly),0,U,\(number),999,1,"
                + "\(regime.bstar),\(regime.ndot),0\n"
        }
    }
    let file: ElementSetFile
    do { file = try ElementSets.read(Array(csv.utf8), as: .csv) } catch { fail("the made-up sets were not read: \(error)") }
    guard file.refusals.isEmpty, file.elementSets.count == regimes.count * angles.count else {
        fail("the made-up sets were not all read: \(file.refusals)")
    }
    return file.elementSets
}

func hex(_ value: Double) -> String {
    let text = String(value.bitPattern, radix: 16)
    return String(repeating: "0", count: 16 - text.count) + text
}

/// The record's lines: a header, then one line for each set at each time.
func record() -> [String] {
    var lines = [
        "# GPKit bit record: Propagator.state from the release build, TEME position (km) and velocity (km/s),",
        "# each number as the hex of its IEEE 754 bit pattern; a line \"fail KIND\" where propagation stopped.",
        "# Made by tools/bit-record from \(regimes.count * angles.count) made-up sets at \(times.count) times; WGS-72, the exact epoch.",
        "# platform \(platform)",
        "# catalog minutes x y z vx vy vz",
    ]
    for set in elementSets() {
        let propagator: Propagator
        do { propagator = try Propagator(set) } catch {
            lines.append("\(set.catalogNumber ?? 0) init fail \(error.kind.rawValue)")
            continue
        }
        for minutes in times {
            do {
                let s = try propagator.state(minutesFromEpoch: minutes)
                let numbers = [s.position.x, s.position.y, s.position.z, s.velocity.x, s.velocity.y, s.velocity.z]
                lines.append("\(set.catalogNumber ?? 0) \(minutes) " + numbers.map(hex).joined(separator: " "))
            } catch {
                lines.append("\(set.catalogNumber ?? 0) \(minutes) fail \(error.kind.rawValue)")
            }
        }
    }
    return lines
}

/// How far apart two doubles are in units in the last place, counted along the doubles in order.
func ulps(_ a: UInt64, _ b: UInt64) -> UInt64 {
    func ordered(_ bits: UInt64) -> Int64 {
        let signed = Int64(bitPattern: bits)
        return signed < 0 ? Int64.min &- signed : signed
    }
    let d = ordered(a).subtractingReportingOverflow(ordered(b)).partialValue
    return d == Int64.min ? UInt64.max : UInt64(abs(d))
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--platform"] {
    print(platform)
} else if arguments.isEmpty {
    print(record().joined(separator: "\n"))
} else if arguments.count == 2, arguments[0] == "--check" {
    guard let text = try? String(contentsOfFile: arguments[1], encoding: .utf8) else { fail("cannot read \(arguments[1])") }
    let held = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init).filter { !$0.hasPrefix("#") }
    let made = record().filter { !$0.hasPrefix("#") }
    if let header = text.split(separator: "\n").first(where: { $0.hasPrefix("# platform ") }), header != "# platform \(platform)" {
        print("the record is for another platform: \(header.dropFirst(11)), this is \(platform)")
        exit(1)
    }
    guard held.count == made.count else {
        print("the record has \(held.count) lines and this build makes \(made.count)")
        exit(1)
    }
    let names = ["x", "y", "z", "vx", "vy", "vz"]
    var numbers = 0, moved = 0, otherLines = 0
    var largest: (ulps: UInt64, line: String, component: String, held: Double, made: Double)?
    for (h, m) in zip(held, made) where h != m {
        let hf = h.split(separator: " "), mf = m.split(separator: " ")
        guard hf.count == 8, mf.count == 8, hf[0] == mf[0], hf[1] == mf[1] else {
            otherLines += 1
            if otherLines <= 5 { print("a line differs in kind:\n  record: \(h)\n  now:    \(m)") }
            continue
        }
        for i in 0..<6 where hf[i + 2] != mf[i + 2] {
            moved += 1
            guard let a = UInt64(hf[i + 2], radix: 16), let b = UInt64(mf[i + 2], radix: 16) else { fail("not hex: \(h)") }
            let u = ulps(a, b)
            if largest == nil || u > largest!.ulps {
                largest = (u, "\(hf[0]) at \(hf[1]) minutes", names[i], Double(bitPattern: a), Double(bitPattern: b))
            }
        }
    }
    for m in made { numbers += m.split(separator: " ").count == 8 ? 6 : 0 }
    if moved == 0, otherLines == 0 {
        print("the bit record holds on \(platform): \(numbers) numbers in \(made.count) lines, every one to the bit")
        exit(0)
    }
    print("the bit record does not hold on \(platform): \(moved) of \(numbers) numbers moved, \(otherLines) lines differ in kind")
    if let l = largest {
        print("largest: \(l.ulps) units in the last place, set \(l.line), \(l.component): record \(l.held), now \(l.made),"
            + " a difference of \(abs(l.made - l.held))")
    }
    exit(1)
} else {
    fail("usage: gpkit-bit-record [--platform | --check FILE]")
}
