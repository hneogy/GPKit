// gpkit-data-age OUT-DIR FILE... [--source TEXT]: the data-age measurement (GPKit's DataAge) over element-set files already on this
// computer. It makes no request: every set comes from the files named. Each file is read in the format its extension
// names (.tle or .txt, .csv, .json, .xml, .kvn); a file GPKit refuses, or a record it refuses, is counted and named.
//
// Writes, in OUT-DIR:
//   samples.csv   one line a pair: catalog number, orbit class, older and newer epochs, age in days, the position error and
//                 its radial, in-track and cross-track parts in km
//   table.csv     by orbit class and span of age: the count, median, 68th and 95th percentiles and maximum, in km
//   table.json    the same table as a DataAgeTable, with its provenance (the files' names as its source unless
//                 --source names it), which DataAgeTable's decoder reads back
//   inputs.txt    each file read, its size in bytes, sets and refusals, and the totals
// and says on standard output how many sets, satellites, pairs and failures there were, never a measured number:
// those stay in OUT-DIR (the owner's ruling, 2026-11-07: no number from the private pilot is published).
import Foundation
import GPKit

var arguments = Array(CommandLine.arguments.dropFirst())
var sourceText: String?
if let at = arguments.firstIndex(of: "--source"), at + 1 < arguments.count {
    sourceText = arguments[at + 1]
    arguments.removeSubrange(at...(at + 1))
}
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: gpkit-data-age OUT-DIR FILE... [--source TEXT]\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: arguments[0], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

var sets: [ElementSet] = []
var inputs: [String] = []
for path in arguments.dropFirst() {
    let ext = (path as NSString).pathExtension.lowercased()
    let format: Format
    switch ext {
    case "tle", "txt", "3le", "2le": format = .tle
    case "csv": format = .csv
    case "json": format = .json
    case "xml": format = .xml
    case "kvn": format = .kvn
    default:
        inputs.append("\(path): skipped, no format for .\(ext)")
        continue
    }
    guard let data = FileManager.default.contents(atPath: path) else {
        inputs.append("\(path): not readable")
        continue
    }
    do {
        let file = try ElementSets.read(data, as: format)
        sets += file.elementSets
        inputs.append("\(path): \(data.count) bytes, \(file.elementSets.count) sets, \(file.refusals.count) refused")
    } catch {
        inputs.append("\(path): refused whole, \(error)")
    }
}

let measurement = DataAge.measure(sets)
let samples = measurement.samples
let failures = measurement.failureCount
let satellites = Set(sets.compactMap(\.catalogNumber)).count
func number(_ x: Double) -> String { String(x) }
var csv = "catalog,class,older,newer,age_days,position_km,radial_km,in_track_km,cross_track_km\n"
for s in samples {
    csv += "\(s.catalogNumber),\(s.orbitClass.rawValue),\(s.older),\(s.newer),\(number(s.age)),\(number(s.positionError)),"
        + "\(number(s.radial)),\(number(s.inTrack)),\(number(s.crossTrack))\n"
}
try csv.write(to: out.appendingPathComponent("samples.csv"), atomically: true, encoding: .utf8)
let source = sourceText ?? "files: " + arguments.dropFirst().map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
var table = "class,from_days,to_days,count,median_km,p68_km,p95_km,max_km\n"
if let provenance = DataAgeTable.Provenance(source: source, measurement: measurement) {
    let made = DataAgeTable(measurement, provenance: provenance)
    for row in made.rows {
        let p = row.positionError
        table += "\(row.orbitClass.rawValue),\(number(row.fromAge)),\(number(row.toAge)),\(p.count),\(number(p.median)),"
            + "\(number(p.p68)),\(number(p.p95)),\(number(p.maximum))\n"
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    try encoder.encode(made).write(to: out.appendingPathComponent("table.json"))
}
try table.write(to: out.appendingPathComponent("table.csv"), atomically: true, encoding: .utf8)
let failed = measurement.failures.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue) \($0.value)" }.joined(separator: ", ")
inputs.append("totals: \(sets.count) sets, \(satellites) satellites, \(samples.count) pairs, \(failures) pairs not propagated" + (failed.isEmpty ? "" : " (\(failed))"))
try (inputs.joined(separator: "\n") + "\n").write(to: out.appendingPathComponent("inputs.txt"), atomically: true, encoding: .utf8)
let byClass = Dictionary(grouping: samples, by: \.orbitClass).mapValues(\.count)
print("\(sets.count) sets, \(satellites) satellites, \(samples.count) pairs (\(OrbitClass.esaClasses.map { "\($0.rawValue) \(byClass[$0] ?? 0)" }.joined(separator: ", "))), \(failures) not propagated; written to \(out.path)")
