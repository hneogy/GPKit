// GPKit's own answers for pygpkit's tests: each input file read, each element set written as a TLE, and its
// propagator's states, looks, map positions and passes, computed here with GPKit directly and written as JSON.
//
//   swift run -c release --package-path python pygpkit-reference > python/tests/reference.json   (from GPKit's root)
//
// The Python tests ask pygpkit the same questions and hold its answers to these, to the bit. CI writes the file again
// and stops if it differs from the one committed. It is built for release, as the library the package ships is: on
// Apple's systems an optimised build calls __sincos_stret where sin and cos meet, whose sine is a different Double
// from sin's for about 3 arguments in 10,000, so a debug build's answers can differ from it in the last bit.
import Foundation
import GPKit
import PyGPKitShared

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let inputs: [(path: String, format: Format)] = [
    ("../Examples/data/iss-1998.tle", .tle),
    ("../Tests/GPKitTests/Resources/pass-check-sets.tle", .tle),
    ("tests/data/iss-1998-bad-checksum.tle", .tle),
]
let observer = Observer(latitude: 40.0, longitude: -75.0, height: 100.0)
let minutes: [Double] = [-1440, -90.5, 0, 0.001, 45, 90, 720, 1440, 4320.25, 10080]

var files: [String] = []
for input in inputs {
    let data = try Data(contentsOf: root.appendingPathComponent(input.path))
    let file = try ElementSets.read(data, as: input.format)
    var entries: [String] = []
    for entry in file.entries {
        switch entry {
        case .refusal(let refusal):
            entries.append(JSON.object([("refusal", JSON.refusal(refusal))]))
        case .elementSet(let set):
            let tle: String
            do {
                let lines = try TLE.write(set)
                tle = JSON.object([("name", JSON.optional(lines.name, JSON.string)), ("line1", JSON.string(lines.line1)), ("line2", JSON.string(lines.line2))])
            } catch {
                tle = JSON.object([("refusal", JSON.refusal(error))])
            }
            let propagator = try Propagator(set)
            // every ten minutes for two hours from the epoch
            let times = try (0...12).map { try set.epoch.advanced(by: Double($0) * 600) }
            let byMinute = minutes.map { m in JSON.result({ () throws(PropagationFailure) -> StateVector in try propagator.state(minutesFromEpoch: m) }, JSON.state) }
            let byTime = times.map { t in JSON.result({ () throws(PropagationFailure) -> StateVector in try propagator.state(at: t) }, JSON.state) }
            let looks = times.map { t in JSON.result({ () throws(PropagationFailure) -> Look in try propagator.look(from: observer, at: t) }, JSON.look) }
            let positions = times.map { t in JSON.result({ () throws(PropagationFailure) -> GeodeticPosition in try propagator.position(at: t) }, JSON.geodetic) }
            let passes = propagator.passes(over: observer, from: set.epoch, for: .seconds(2 * 86_400), above: 10)
            entries.append(JSON.object([
                ("fields", JSON.elementSet(set)),
                ("tle", tle),
                ("times", JSON.array(times.map { JSON.string($0.description) })),
                ("states_by_minute", JSON.array(byMinute)),
                ("states_by_time", JSON.array(byTime)),
                ("looks", JSON.array(looks)),
                ("positions", JSON.array(positions)),
                ("passes", JSON.object([("passes", JSON.array(passes.map(JSON.pass))), ("failure", JSON.optional(passes.failure, JSON.failure))])),
            ]))
        }
    }
    files.append(JSON.object([("path", JSON.string(input.path)), ("format", JSON.string(input.format.rawValue)), ("entries", JSON.array(entries))]))
}
print(JSON.object([
    ("observer", JSON.array([JSON.number(observer.latitude), JSON.number(observer.longitude), JSON.number(observer.height)])),
    ("minutes", JSON.array(minutes.map(JSON.number))),
    ("pass_search", JSON.object([("seconds", "172800"), ("above", "10")])),
    ("files", JSON.array(files)),
]))
