// equivalence DATA: for every element set held both as TLE and as OMM under DATA (a folder holding fixtures/<case>/raw/,
// as `gpconf fetch` writes it), the same satellite at the same epoch, it says
//   - whether GPKit's TLE writer, given the OMM, writes the provider's TLE lines (the eccentricity cut off, as
//     CelesTrak's lines have it), and whether the two then propagate to the bit;
//   - how far the OMM and the TLE as read propagate apart, at 0, 90 minutes, 12 hours, 1, 3 and 7 days from the epoch.
// Counts and largest differences only: no element and no position of a provider's is printed.
import Foundation
import GPKit

let times: [Double] = [0, 90, 720, 1440, 4320, 10080]
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: equivalence DATA\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("fixtures")
let formats: [String: Format] = ["csv": .csv, "json": .json, "xml": .xml, "kvn": .kvn, "tle": .tle, "2le": .tle, "3le": .tle, "txt": .tle]

struct Held { let set: ElementSet; let file: String; let format: Format; var lines: (String, String)? = nil }
var tles: [Held] = [], omms: [Held] = []
var files = 0
var unread: [String] = []
let cases = (try? FileManager.default.contentsOfDirectory(atPath: root.path).sorted()) ?? []
for name in cases {
    let raw = root.appendingPathComponent(name).appendingPathComponent("raw")
    // beside each provider file `gpconf fetch` writes its record of the fetch, NAME.meta.json: not an element set file
    for file in ((try? FileManager.default.contentsOfDirectory(atPath: raw.path)) ?? []).sorted() where !file.hasSuffix(".meta.json") {
        guard let format = formats[(file as NSString).pathExtension.lowercased()],
              let data = FileManager.default.contents(atPath: raw.appendingPathComponent(file).path) else { continue }
        guard let read = try? ElementSets.read(data, as: format) else { unread.append("\(name)/\(file)"); continue }
        files += 1
        if format == .tle {
            // the provider's own two lines of each set, as the file has them
            let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            for (i, line) in lines.enumerated() where line.hasPrefix("1 ") && i + 1 < lines.count && lines[i + 1].hasPrefix("2 ") {
                if let set = try? TLE.parse(line1: line, line2: lines[i + 1]) {
                    tles.append(Held(set: set, file: "\(name)/\(file)", format: format, lines: (line, lines[i + 1])))
                }
            }
        } else {
            for set in read.elementSets { omms.append(Held(set: set, file: "\(name)/\(file)", format: format)) }
        }
    }
}

func distance(_ a: StateVector, _ b: StateVector) -> Double {
    let d = (a.position.x - b.position.x, a.position.y - b.position.y, a.position.z - b.position.z)
    return (d.0 * d.0 + d.1 * d.1 + d.2 * d.2).squareRoot()
}

// pairs: an OMM set and a TLE set of the same catalog number whose epochs are within a TLE epoch field's resolution
// (1e-8 day, 0.864 ms); a set held in several files is paired once per OMM file
var byCatalog: [Int: [Held]] = [:]
for t in tles { if let n = t.set.catalogNumber { byCatalog[n, default: []].append(t) } }
var pairs = 0, writtenAlike = 0, bitAlike = 0, notWritable = 0
var lineDiffs: [String: Int] = [:]
var largest: [Double: Double] = [:]  // minutes -> largest difference, km
var largestAll = 0.0
var failedAlike = 0, failedOnOneSide = 0
var worst: (Held, Held, Double)? = nil
var byFormat: [Format: Int] = [:]
var seen = Set<String>()
for o in omms {
    guard let n = o.set.catalogNumber, let candidates = byCatalog[n] else { continue }
    guard let t = candidates.first(where: { abs(o.set.epoch.seconds(since: $0.set.epoch)) < 0.000_864 }) else { continue }
    let key = "\(o.file)|\(n)|\(o.set.epoch)"
    if !seen.insert(key).inserted { continue }
    pairs += 1
    byFormat[o.format, default: 0] += 1
    // the OMM written as a TLE, beside the provider's lines (the element set number and the checksum included)
    if let written = try? TLE.write(o.set, eccentricity: .truncated), let given = t.lines {
        if written.line1 == given.0 && written.line2 == given.1 {
            writtenAlike += 1
            let fromOMM = try? TLE.parse(line1: written.line1, line2: written.line2)
            if let a = fromOMM.flatMap({ try? Propagator($0) }), let b = try? Propagator(t.set),
               times.allSatisfy({ m in (try? a.state(minutesFromEpoch: m)) == (try? b.state(minutesFromEpoch: m)) }) {
                bitAlike += 1
            }
        } else {
            for (i, (x, y)) in zip(written.line1 + written.line2, given.0 + given.1).enumerated() where x != y {
                lineDiffs[i < 69 ? "line 1 column \(i + 1)" : "line 2 column \(i - 68)", default: 0] += 1
            }
        }
    } else {
        notWritable += 1
    }
    // the OMM and the TLE as read, propagated from each one's own epoch to the same instants
    guard let a = try? Propagator(o.set), let b = try? Propagator(t.set) else { failedOnOneSide += 1; continue }
    for m in times {
        guard let at = try? o.set.epoch.advanced(by: m * 60) else { continue }
        let sa = try? a.state(at: at), sb = try? b.state(at: at)
        guard let sa, let sb else {
            if sa == nil && sb == nil { failedAlike += 1 } else { failedOnOneSide += 1 }
            continue
        }
        let d = distance(sa, sb)
        largest[m] = max(largest[m] ?? 0, d)
        if d > largestAll { largestAll = d; worst = (o, t, m) }
    }
}

print("files read: \(files); refused whole: \(unread.isEmpty ? "none" : unread.joined(separator: ", "))")
print("element sets: \(tles.count) from TLE files, \(omms.count) from OMM files")
print("pairs, an OMM set with the TLE of the same satellite and epoch: \(pairs), \(Set(seen.map { $0.split(separator: "|").dropFirst().joined(separator: "|") }).count) satellites at an epoch ("
      + byFormat.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue) \($0.value)" }.joined(separator: ", ") + ")")
print("the OMM written as a TLE by GPKit, eccentricity cut off: \(writtenAlike) of \(pairs) are the provider's lines, character for character; \(notWritable) could not be written")
print("  of those, propagated at \(times.map { "\(Int($0))" }.joined(separator: ", ")) minutes: \(bitAlike) identical to the bit")
if !lineDiffs.isEmpty {
    print("  where the lines differ: " + lineDiffs.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key) (\($0.value))" }.joined(separator: ", "))
}
print("the OMM and the TLE as read, propagated to the same instants: largest position difference")
for m in times { print("  at \(Int(m)) min from the epoch: \(String(format: "%.6f", (largest[m] ?? 0) * 1000)) m") }
print("  overall: \(String(format: "%.6f", largestAll * 1000)) m")
print("propagations that failed: \(failedAlike) on both sides alike, \(failedOnOneSide) on one side only")

// which of the TLE's rounded fields makes the largest difference: each field of the worst pair's OMM in turn given
// the TLE's value, and the difference at that time measured again
if let (o, t, m) = worst, let at = try? o.set.epoch.advanced(by: m * 60), let b = try? Propagator(t.set), let sb = try? b.state(at: at) {
    let fields: [(String, (inout ElementSet) -> Void)] = [
        ("epoch", { $0.epoch = t.set.epoch }),
        ("mean motion", { $0.meanMotion = t.set.meanMotion }),
        ("eccentricity", { $0.eccentricity = t.set.eccentricity }),
        ("inclination", { $0.inclination = t.set.inclination }),
        ("right ascension", { $0.rightAscension = t.set.rightAscension }),
        ("argument of pericenter", { $0.argumentOfPericenter = t.set.argumentOfPericenter }),
        ("mean anomaly", { $0.meanAnomaly = t.set.meanAnomaly }),
        ("BSTAR", { $0.bstar = t.set.bstar }),
    ]
    var parts: [String] = []
    for (name, take) in fields {
        var set = o.set
        take(&set)
        if let a = try? Propagator(set), let sa = try? a.state(at: at) {
            parts.append("\(name) \(String(format: "%.1f", distance(sa, sb) * 1000)) m")
        }
    }
    print("the largest difference, \(String(format: "%.1f", largestAll * 1000)) m at \(Int(m)) min (\(o.format.rawValue)), with one field of the OMM given the TLE's value:")
    print("  " + parts.joined(separator: ", "))
}
