import Foundation
import Testing
@testable import GPKit
import SGP4Oracle

/// Vallado's published verification output, `tcppver.out`, line for line: each printed number of each line made again
/// from GPKit (`Propagator.EpochReading.vallado`, WGS-72, opsmode 'i') and from Vallado's C++ as this package compiles
/// it, and compared with the file at the file's own digits.
///
/// GPKit does not ship `tcppver.out` (its bundling waits on permission, as gpconf's does), so this test runs only when
/// `GPKIT_SGP4_VER` names a directory holding it beside `SGP4-VER.TLE`, the bytes checked against the SHA-256s below;
/// elsewhere it is skipped. `conformance/vallado-tcppver-*.txt` records a run.
///
/// A line is the time, the TEME position (km) and velocity (km/s), and, after a block's first line, the osculating
/// elements (a in km, e, i, Ω, ω, ν and M in degrees) and the calendar time. The elements are `rv2coe` of the state, by
/// Vallado's own function, and the time is `invjday` of the reader's epoch plus the minutes, so those columns say the
/// state and the epoch are his to the digits printed; the epoch is GPKit's to the bit (`ValladoEpochTests`).
@Suite struct TcppverTests {

    static let directory = ProcessInfo.processInfo.environment["GPKIT_SGP4_VER"]
    static let sha256 = (tle: "d246d1d9d768ace445a38a965713fa9ba52d80fd8a41a0502ff83d7acffe2881",
                         out: "687bf28dbe52df86e8e60ab5cb4a08d1aa3dbcaf4e63b1f7ab95f044fbe3833b")

    /// One printed line, its numbers as text, the calendar time as one field ("Y M D h:m:s").
    struct Line {
        var numbers: [String]
        var date: [String]
    }

    /// `tcppver.out`'s blocks, by header, in file order.
    static func blocks(_ text: String) -> [(catalog: String, lines: [Line])] {
        var blocks: [(String, [Line])] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let fields = raw.split(separator: " ").map(String.init)
            if fields.count == 2, fields[1] == "xx" { blocks.append((fields[0], [])); continue }
            guard !blocks.isEmpty, fields.count >= 7 else { continue }
            let numbers = Array(fields.prefix(fields.count >= 14 ? 14 : 7))
            // the time of day is printed %2i:%2i:%9.6f, so its fields split on spaces in more than one way
            let rest = fields.count > 14 ? Array(fields[14...]) : []
            var date: [String] = []
            if rest.count >= 4 {
                date = Array(rest.prefix(3)) + rest.dropFirst(3).joined().split(separator: ":").map(String.init)
            }
            blocks[blocks.count - 1].1.append(Line(numbers: numbers, date: date))
        }
        return blocks
    }

    /// `value` printed with as many decimals as `printed` has, a minus sign on zero dropped, as C's %f prints it
    /// rounded.
    static func same(_ value: Double, as printed: String) -> Bool {
        let decimals = printed.split(separator: ".").dropFirst().first?.count ?? 0
        func clean(_ s: String) -> String {
            s.hasPrefix("-") && s.dropFirst().allSatisfy({ $0 == "0" || $0 == "." }) ? String(s.dropFirst()) : s
        }
        return clean(String(format: "%.\(decimals)f", value)) == clean(printed)
    }

    /// Half a unit in the last printed digit of `printed`.
    static func halfUnit(_ printed: String) -> Double {
        let decimals = printed.split(separator: ".").dropFirst().first?.count ?? 0
        return 0.5 * pow(10, -Double(decimals))
    }

    /// The numbers a line prints for minutes `t` and a state, the elements and the time after the block's first line.
    static func line(t: Double, r: [Double], v: [Double], mu: Double, jd: Double, jdFraction: Double,
                     full: Bool) -> (numbers: [Double], date: [Double]) {
        var numbers = [t] + r + v
        guard full else { return (numbers, []) }
        var p = 0.0, a = 0.0, ecc = 0.0, incl = 0.0, node = 0.0, argp = 0.0, nu = 0.0, m = 0.0
        sgp4oracle_rv2coe(r, v, mu, &p, &a, &ecc, &incl, &node, &argp, &nu, &m)
        let degrees = 180 / Double.pi
        numbers += [a, ecc, incl * degrees, node * degrees, argp * degrees, nu * degrees, m * degrees]
        // as the verification driver does it: the epoch's two parts and the minutes summed into one Julian date
        let day = jd + jdFraction + t / 1440.0, fraction = 0.0
        var year: Int32 = 0, month: Int32 = 0, dayOfMonth: Int32 = 0, hour: Int32 = 0, minute: Int32 = 0
        var second = 0.0
        sgp4oracle_invjday(day, fraction, &year, &month, &dayOfMonth, &hour, &minute, &second)
        return (numbers, [Double(year), Double(month), Double(dayOfMonth), Double(hour), Double(minute), second])
    }

    struct Tally {
        /// The groups of a line's columns: 1 the time, 2-7 the state, 8-14 the elements, 15-20 the calendar time.
        static let groups = [("state", 1..<7), ("elements", 7..<14), ("time", 14..<20)]
        var lines = 0, linesAsPrinted = 0
        /// Per group: lines with the group printed, lines it is printed alike, lines within half a printed unit.
        var group: [String: (printed: Int, alike: Int, within: Int)] = [:]
        var largestState = (position: 0.0, velocity: 0.0)
        var off: [String: [String]] = [:]

        mutating func add(_ mine: (numbers: [Double], date: [Double]), _ printed: Line, where label: String) {
            lines += 1
            let values = mine.numbers + mine.date, texts = printed.numbers + printed.date
            var allAlike = values.count == texts.count
            for (name, range) in Self.groups where range.upperBound <= texts.count && range.upperBound <= values.count {
                var alike = true, within = true
                for i in range {
                    let text = texts[i]
                    if !TcppverTests.same(values[i], as: text) { alike = false }
                    let difference = abs(values[i] - (Double(text) ?? .nan))
                    if !(difference <= TcppverTests.halfUnit(text) * (1 + 1e-6)) {
                        within = false
                        off[name, default: []].append("\(label) column \(i + 1): \(values[i]) against \(text)")
                    }
                    if name == "state" {
                        if i < 4 { largestState.position = max(largestState.position, difference) }
                        else { largestState.velocity = max(largestState.velocity, difference) }
                    }
                }
                var g = group[name] ?? (0, 0, 0)
                g.printed += 1
                g.alike += alike ? 1 : 0
                g.within += within ? 1 : 0
                group[name] = g
                allAlike = allAlike && alike
            }
            linesAsPrinted += allAlike ? 1 : 0
        }

        var summary: String {
            var parts = ["\(lines) lines, \(linesAsPrinted) printed alike in every number"]
            for (name, _) in Self.groups {
                let g = group[name] ?? (0, 0, 0)
                parts.append("\(name): \(g.alike) of \(g.printed) printed alike, \(g.within) within half a printed unit")
            }
            parts.append(String(format: "largest state difference %.3g km and %.3g km/s", largestState.position, largestState.velocity))
            return parts.joined(separator: "; ")
        }
    }

    @Test(.enabled(if: directory != nil, "GPKIT_SGP4_VER names no directory holding tcppver.out"))
    func gpkitAgainstTcppverLineForLine() throws {
        let dir = URL(fileURLWithPath: try #require(Self.directory))
        let tleText = try String(contentsOf: dir.appendingPathComponent("SGP4-VER.TLE"), encoding: .ascii)
        let outText = try String(contentsOf: dir.appendingPathComponent("tcppver.out"), encoding: .ascii)
        #expect(sha256Hex(Array(tleText.utf8)) == Self.sha256.tle, "SGP4-VER.TLE is not the file this test was written for")
        #expect(sha256Hex(Array(outText.utf8)) == Self.sha256.out, "tcppver.out is not the file this test was written for")

        var cases: [VerificationCase] = []
        let lines = tleText.split(whereSeparator: \.isNewline).map(String.init)
        for (i, line) in lines.enumerated() where line.hasPrefix("1 ") && i + 1 < lines.count && lines[i + 1].hasPrefix("2 ") {
            cases.append(VerificationCase(line1: line, line2: String(lines[i + 1].prefix(69)), line2WithTimes: lines[i + 1]))
        }
        let blocks = Self.blocks(outText)
        #expect(blocks.count == cases.count)

        var gpkit = Tally(), cpp = Tally()
        var bySet: [String] = []
        var repeated: [String] = []
        for (c, block) in zip(cases, blocks) {
            #expect(Int(c.catalogField.trimmingCharacters(in: .whitespaces)) == Int(block.catalog))
            var e = sgp4oracle_elements()
            var times = [0.0, 0.0, 0.0]
            let oracle = try #require(sgp4oracle_twoline(c.line1, c.line2WithTimes, 1, CChar(UInt8(ascii: "i")),
                                                         Int32(SGP4ORACLE_WGS72), &e, &times))
            defer { sgp4oracle_free(oracle) }
            var jd = 0.0, jdFraction = 0.0
            sgp4oracle_epoch(oracle, &jd, &jdFraction)
            let mu = sgp4oracle_mu(oracle)
            let set = try TLE.parse(line1: c.line1, line2: c.line2, checksum: .ignore)
            let propagator = try Propagator(set, epochReading: .vallado)
            var mine = Tally()
            for (k, printed) in block.lines.enumerated() {
                let t = try #require(Double(printed.numbers[0]))
                let full = !printed.date.isEmpty
                let label = "\(block.catalog) t = \(printed.numbers[0])"
                var r = [0.0, 0.0, 0.0], v = [0.0, 0.0, 0.0]
                let code = sgp4oracle_sgp4(oracle, t, &r, &v)
                let s: StateVector
                do {
                    s = try propagator.state(minutesFromEpoch: t)
                } catch {
                    // the set whose run fails at its first step: the driver prints the previous set's last line again
                    // (gpconf grades its code, not that line); GPKit and the C++ both fail there
                    #expect(code != 0 && k == 0 && block.lines.count == 1, "\(label): GPKit failed (\(error)) where the C++ gave \(code)")
                    repeated.append("\(label): GPKit and the C++ both stop at the first step (\(error); C++ error \(code)); the line repeats the set before")
                    continue
                }
                let g = Self.line(t: t, r: [s.position.x, s.position.y, s.position.z], v: [s.velocity.x, s.velocity.y, s.velocity.z],
                                  mu: mu, jd: jd, jdFraction: jdFraction, full: full)
                gpkit.add(g, printed, where: label)
                mine.add(g, printed, where: label)
                #expect(code == 0, "\(label): the C++ gave error \(code) on a printed line")
                cpp.add(Self.line(t: t, r: r, v: v, mu: mu, jd: jd, jdFraction: jdFraction, full: full), printed, where: label)
                _ = k
            }
            if mine.linesAsPrinted < mine.lines {
                bySet.append("\(block.catalog): \(mine.lines) lines, \(mine.linesAsPrinted) printed alike, state within half a unit on \(mine.group["state"]?.within ?? 0)")
            }
        }
        print("tcppver.out, GPKit (.vallado): \(gpkit.summary)")
        print("tcppver.out, Vallado's C++ as compiled here: \(cpp.summary)")
        for line in bySet { print("  \(line)") }
        for line in repeated { print("  \(line)") }
        for (name, _) in Tally.groups {
            for line in gpkit.off[name] ?? [] { print("  GPKit, \(name), off: \(line)") }
        }
        // what the C++ compiled here prints otherwise than the file, and GPKit alike
        #expect(gpkit.off.mapValues(\.count) == cpp.off.mapValues(\.count))
        // GPKit gives what the C++ gives, line for line: every line the C++ prints as the file does, GPKit does too
        for (name, _) in Tally.groups { #expect(gpkit.group[name]?.within == cpp.group[name]?.within, "\(name)") }
        #expect(gpkit.lines == 666 && repeated.count == 1)
        // every element printed alike, and every state within gpconf's bar of the file, 2e-7 km and km/s per component
        #expect(gpkit.group["elements"].map { $0.alike == $0.printed } == true)
        #expect(gpkit.largestState.position <= 2e-7 && gpkit.largestState.velocity <= 2e-7)
    }
}

/// SHA-256 of `bytes`, in hex: FIPS 180-4, here so the test needs nothing beyond Foundation on every platform.
func sha256Hex(_ bytes: [UInt8]) -> String {
    var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98,
        0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
        0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8,
        0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819,
        0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
        0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ]
    var message = bytes
    let length = UInt64(bytes.count) * 8
    message.append(0x80)
    while message.count % 64 != 56 { message.append(0) }
    for i in (0..<8).reversed() { message.append(UInt8(truncatingIfNeeded: length >> (UInt64(i) * 8))) }
    func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
    for chunk in stride(from: 0, to: message.count, by: 64) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            w[i] = (0..<4).reduce(0) { $0 << 8 | UInt32(message[chunk + 4 * i + $1]) }
        }
        for i in 16..<64 {
            let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
        for i in 0..<64 {
            let t1 = hh &+ (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) &+ ((e & f) ^ (~e & g)) &+ k[i] &+ w[i]
            let t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) &+ ((a & b) ^ (a & c) ^ (b & c))
            (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
        }
        for (i, x) in [a, b, c, d, e, f, g, hh].enumerated() { h[i] = h[i] &+ x }
    }
    return h.map { String(format: "%08x", $0) }.joined()
}
