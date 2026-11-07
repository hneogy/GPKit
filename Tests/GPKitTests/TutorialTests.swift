import Foundation
import Testing
import GPKit
#if canImport(SwiftUI)
import SwiftUI
#endif

// The DocC tutorials' code, compiled and run. Each code file a tutorial ends with, in Sources/GPKit/GPKit.docc/Resources,
// is a region here between a "tutorial:" line and its "end" line, its own indent taken off, under the imports
// `TutorialTests.imports` names; every earlier step of the same file is made of lines of it. `theTutorialsShowThisCode`
// holds both.

// tutorial: sky-chart-path-02.swift
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
// end

#if canImport(SwiftUI)
// tutorial: sky-chart-view-03.swift
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
// end
#endif

@Suite struct TutorialTests {

    /// The imports above each tutorial file's code, by the file's name without its step.
    static let imports = [
        "first-pass-code": "import GPKit",
        "sky-chart-path": "import Foundation\nimport GPKit",
        "sky-chart-view": "import SwiftUI\nimport GPKit",
        "doppler-code": "import GPKit",
    ]

    // MARK: Your first ISS pass in 10 lines

    @Test func yourFirstPass() throws {
        var printed: [String] = []
        func print(_ items: Any...) { printed.append(items.map { "\($0)" }.joined(separator: " ")) }
        // tutorial: first-pass-code-03.swift
        let tle = """
        ISS (ZARYA)
        1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    10
        2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05
        """
        let iss = try ElementSets.read(tle, as: .tle).elementSets[0]
        let propagator = try Propagator(iss)
        let home = Observer(latitude: 40.0, longitude: -75.0)
        let passes = propagator.passes(over: home, from: iss.epoch, for: .seconds(86_400))
        for pass in passes {
            if let rise = pass.rise {
                print(rise.time, "highest", Int(pass.culmination.look.elevation.rounded()), "degrees")
            }
        }
        // end
        Swift.print(printed.joined(separator: "\n"))
        // the first rise is the one Skyfield finds for this place (Resources/skyfield-passes.json, and the README)
        #expect(printed.first?.hasPrefix("1998-11-20T14:05:39.") == true)
        #expect(printed.count == passes.count && passes.failure == nil)
    }

    // MARK: Draw a pass on a sky chart

    @Test @MainActor func drawAPassOnASkyChart() throws {
        let iss = try ElementSets.read(Sample.tle, as: .tle).elementSets[0]
        let propagator = try Propagator(iss)
        let home = Observer(latitude: 40.0, longitude: -75.0)
        let passes = propagator.passes(over: home, from: iss.epoch, for: .seconds(86_400))
        let pass = try #require(passes.first { $0.rise != nil && $0.set != nil })
        let path = try skyPath(of: pass, with: propagator, from: home)
        #expect(path.count > 10)
        #expect(path.allSatisfy { $0.elevation >= -0.01 })
        // the zenith is the chart's centre and the horizon its rim; north is at the top (y is down) and east to the right
        for look in path {
            let point = chartPoint(look)
            #expect(abs(hypot(point.x, point.y) - (90 - look.elevation) / 90) < 1e-12)
            if look.elevation < 89 {
                let azimuth = atan2(point.x, -point.y) * 180 / .pi
                #expect(abs((azimuth - look.azimuth + 540).truncatingRemainder(dividingBy: 360) - 180) < 1e-9)
            }
        }
        Swift.print("sky chart: \(path.count) points, from azimuth \(Int(path[0].azimuth.rounded())) to \(Int(path[path.count - 1].azimuth.rounded())), "
                    + "highest \(Int(pass.culmination.look.elevation.rounded())) degrees")
        #if canImport(SwiftUI)
        Swift.print("sky chart, said: \(SkyChart(path: path).said)")
        #endif
    }

    // MARK: Doppler for your radio

    @Test func dopplerForYourRadio() throws {
        var printed: [String] = []
        func print(_ items: Any...) { printed.append(items.map { "\($0)" }.joined(separator: " ")) }
        // tutorial: doppler-code-03.swift
        let tle = """
        ISS (ZARYA)
        1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    10
        2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05
        """
        let iss = try ElementSets.read(tle, as: .tle).elementSets[0]
        let propagator = try Propagator(iss)
        let home = Observer(latitude: 40.0, longitude: -75.0)
        let passes = propagator.passes(over: home, from: iss.epoch, for: .seconds(86_400))

        let downlink = 145_800_000.0
        if let pass = passes.first(where: { $0.rise != nil && $0.set != nil }), let rise = pass.rise, let set = pass.set {
            var time = rise.time
            while time <= set.time {
                let look = try propagator.look(from: home, at: time)
                let tuneTo = look.received(from: downlink)
                print(time, "elevation", Int(look.elevation.rounded()), "tune to", Int(tuneTo.rounded()), "Hz")
                time = try time.advanced(by: 60)
            }
        }
        // end
        Swift.print(printed.joined(separator: "\n"))
        #expect(printed.count > 3)
        let pass = try #require(passes.first { $0.rise != nil && $0.set != nil })
        // tuned above the downlink while the satellite draws near, below it once it draws away
        let first = try propagator.look(from: home, at: pass.rise!.time), last = pass.set!.look
        #expect(first.rangeRate < 0 && first.received(from: downlink) > downlink)
        #expect(last.rangeRate > 0 && last.received(from: downlink) < downlink)
        // a low satellite moves at under 8 km/s, so the shift at 145.8 MHz is under 3.9 kHz
        #expect(abs(first.received(from: downlink) - downlink) < 3_900)
        // a transmitter is tuned the other way, so that the satellite hears the frequency asked for
        let up = 145_990_000.0
        #expect(abs(first.received(from: first.transmit(toBeReceivedAt: up)) - up) < 1e-3)
    }

    // MARK: The tutorials show this code

    @Test(.enabled(if: theSourceTreeIsHere, "reads the tutorials' files, which are not on the device"))
    func theTutorialsShowThisCode() throws {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resources = root.appendingPathComponent("Sources/GPKit/GPKit.docc/Resources")
        // a checkout on Windows can end its lines CR LF; the code is the same
        func read(_ url: URL) throws -> String {
            try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\r\n", with: "\n")
        }
        var regions: [String: [String]] = [:]
        var name: String?
        var indent = 0
        for line in try read(here).components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("// tutorial: ") {
                name = String(trimmed.dropFirst("// tutorial: ".count))
                indent = line.prefix { $0 == " " }.count
                regions[name!] = []
            } else if trimmed == "// end", name != nil {
                name = nil
            } else if let n = name {
                regions[n]!.append(line.isEmpty ? line : String(line.dropFirst(indent)))
            }
        }
        #expect(regions.count == 4)
        func file(_ name: String) -> String { String(name.dropLast(".swift".count).split(separator: "-").dropLast().joined(separator: "-")) }
        for (name, lines) in regions {
            let imports = try #require(TutorialTests.imports[file(name)], "\(name) has no imports named")
            let text = try read(resources.appendingPathComponent(name))
            #expect(text == imports + "\n\n" + lines.joined(separator: "\n") + "\n", "\(name) is not the code tested here")
        }
        // every step of a file is made of lines of its last step, the one tested here
        let shown = try FileManager.default.contentsOfDirectory(atPath: resources.path).filter { $0.hasSuffix(".swift") }
        let last = Dictionary(grouping: regions.keys, by: file).mapValues { $0[0] }
        #expect(Set(shown.map(file)) == Set(last.keys), "a code file of a tutorial whose last step is not tested here")
        for name in shown {
            let lastStep = try #require(last[file(name)], "\(name): its tutorial's last step is not tested here")
            let final = try Set(read(resources.appendingPathComponent(lastStep)).components(separatedBy: "\n"))
            for line in try read(resources.appendingPathComponent(name)).components(separatedBy: "\n")
            where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                #expect(final.contains(line), "\(name): \"\(line)\" is not in \(lastStep)")
            }
            #expect(name <= lastStep, "\(name) comes after the last step \(lastStep)")
        }
    }
}
