// A small sky view: paste an element set, say where you are, and see the next pass drawn on a chart of the sky.
// `swift run` in this folder opens it on a Mac. The chart is the one the "Draw a pass on a sky chart" tutorial builds.
// `swift run SkyView FILE [--from-epoch]` opens it with a TLE file's text already in, searching from its epoch.
import SwiftUI
import GPKit

@main
struct SkyViewApp: App {
    var body: some Scene {
        WindowGroup("Sky view") {
            ContentView()
                .frame(minWidth: 520, minHeight: 640)
        }
        .defaultSize(width: 680, height: 900)
    }
}

struct ContentView: View {
    @State private var text = Launch.text
    @State private var latitude = 40.0
    @State private var longitude = -75.0
    @State private var fromEpoch = Launch.fromEpoch

    var body: some View {
        Form {
            Section("Element set, as a TLE") {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .frame(minHeight: 70)
                    .accessibilityLabel("Element set")
            }
            Section("Where you are") {
                TextField("Latitude, degrees north", value: $latitude, format: .number)
                TextField("Longitude, degrees east", value: $longitude, format: .number)
                Toggle("Search from the element set's epoch, not now", isOn: $fromEpoch)
            }
            Section("The next pass") {
                switch nextPass {
                case .success(let found):
                    if let found {
                        SkyChart(path: found.path)
                            .frame(maxWidth: 300)
                        Text(found.said)
                    } else {
                        Text("No pass in the next two days.")
                    }
                case .failure(let error):
                    Text(verbatim: "\(error)")
                }
            }
        }
        .formStyle(.grouped)
    }

    struct Found {
        let path: [Look]
        let said: String
    }

    var nextPass: Result<Found?, any Error> {
        Result {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let set = try ElementSets.read(text, as: .tle).elementSets.first
            guard let set else { return nil }
            let propagator = try Propagator(set)
            let home = Observer(latitude: latitude, longitude: longitude)
            let start = fromEpoch ? set.epoch : try Epoch(Date())
            let passes = propagator.passes(over: home, from: start, for: .seconds(2 * 86_400))
            guard let pass = passes.first(where: { $0.rise != nil && $0.set != nil }), let rise = pass.rise else { return nil }
            let path = try skyPath(of: pass, with: propagator, from: home)
            return Found(path: path, said: "Rises \(rise.time) UTC, highest \(Int(pass.culmination.look.elevation.rounded()))°")
        }
    }
}

/// What the command line gave: a TLE file to start with, and whether to search from its epoch.
enum Launch {
    static let arguments = CommandLine.arguments.dropFirst()
    static let text = arguments.first { !$0.hasPrefix("-") }.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? ""
    static let fromEpoch = arguments.contains("--from-epoch")
}

// The tutorial's code, as it is there.

func skyPath(of pass: Pass, with propagator: Propagator, from home: Observer) throws -> [Look] {
    guard let rise = pass.rise, let set = pass.set else { return [] }
    var path: [Look] = []
    var time = rise.time
    while time < set.time {
        path.append(try propagator.look(from: home, at: time))
        time = try time.advanced(by: 10)
    }
    path.append(set.look)
    return path
}

func chartPoint(_ look: Look) -> (x: Double, y: Double) {
    let radius = (90 - look.elevation) / 90
    let angle = look.azimuth * .pi / 180
    return (x: radius * sin(angle), y: -radius * cos(angle))
}

struct SkyChart: View {
    let path: [Look]

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let horizon = CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius)
            context.stroke(Path(ellipseIn: horizon), with: .color(.secondary))
            var track = Path()
            track.addLines(path.map { look in
                let point = chartPoint(look)
                return CGPoint(x: centre.x + point.x * radius, y: centre.y + point.y * radius)
            })
            context.stroke(track, with: .color(.accentColor), lineWidth: 3)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(said)
    }

    var said: String {
        guard let first = path.first, let last = path.last, let top = path.max(by: { $0.elevation < $1.elevation }) else {
            return "No pass"
        }
        return "Rises at azimuth \(Int(first.azimuth.rounded())) degrees, highest \(Int(top.elevation.rounded())) degrees, "
            + "sets at azimuth \(Int(last.azimuth.rounded())) degrees"
    }
}
