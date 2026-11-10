import Foundation
import GPKit

/// The element sets a program holds, by catalog number: the newest of each object, and up to `keep` sets of it in
/// all, newest first, so that what came before is there to compare with (an old set propagated forward against a
/// newer one is how GPKit's data age is measured).
///
/// It decides nothing a provider has not said: a set from an answer is merged as it came, by its epoch, and what the
/// merge did is counted in a `Report`. Two sets of one object at one epoch that differ are a conflict, and the one
/// held first is kept. A set with no catalog number is not held, since nothing names the object it belongs to.
///
/// It makes no request. Feed it from `CelesTrak.fetch`, from a `FolderSource`, or from any `ElementSetFile`; save it
/// with `save()` and give the saved text back to `init(saved:keep:)` in the next run.
public actor ElementSetStore {

    /// What one merge did, set by set.
    public struct Report: Sendable, Hashable {
        /// Sets of an object the store did not hold.
        public var added = 0
        /// Sets newer than the one held, which is now the object's previous set.
        public var replaced = 0
        /// Sets the store already held, the same in every value.
        public var unchanged = 0
        /// Sets older than the newest held: kept in the object's history, while it has room for them.
        public var older = 0
        /// The catalog numbers of sets at an epoch already held, with other values; the held set is kept.
        public var conflicting: [Int] = []
        /// Sets with no catalog number, not held.
        public var uncatalogued = 0
        /// Records the file refused, which hold no set to merge.
        public var refused = 0

        public init() {}
    }

    /// The most sets of one object held, the newest first among them.
    public nonisolated let keep: Int
    private var sets: [Int: [ElementSet]] = [:]

    /// - Parameter keep: at least 1; 4 by default.
    public init(keep: Int = 4) {
        self.keep = max(1, keep)
    }

    /// A store read back from `save()`'s text. A record the text does not hold as a set is a refusal, and throws.
    public init(saved: Data, keep: Int = 4) throws(Refusal) {
        self.keep = max(1, keep)
        let file = try ElementSets.read(saved, as: .json)
        if let refusal = file.refusals.first { throw refusal }
        var held: [Int: [ElementSet]] = [:]
        for set in file.elementSets { _ = Self.merge(set, into: &held, keep: self.keep) }
        self.sets = held
    }

    /// Merges every set of a file and says what came of each; the file's refusals are counted.
    @discardableResult
    public func merge(_ file: ElementSetFile) -> Report {
        var report = merge(file.elementSets)
        report.refused = file.refusals.count
        return report
    }

    /// Merges sets, from a file or built in code, and says what came of each.
    @discardableResult
    public func merge(_ elementSets: [ElementSet]) -> Report {
        var report = Report()
        for set in elementSets {
            switch Self.merge(set, into: &sets, keep: keep) {
            case .added: report.added += 1
            case .replaced: report.replaced += 1
            case .unchanged: report.unchanged += 1
            case .older: report.older += 1
            case .conflicting(let number): report.conflicting.append(number)
            case .uncatalogued: report.uncatalogued += 1
            }
        }
        return report
    }

    private enum Outcome { case added, replaced, unchanged, older, conflicting(Int), uncatalogued }

    /// The values that make two sets the same set: everything SGP4 and a TLE read, and the names.
    private static func same(_ a: ElementSet, _ b: ElementSet) -> Bool {
        var a = a, b = b
        a.source = nil
        b.source = nil
        return a == b
    }

    private static func merge(_ set: ElementSet, into sets: inout [Int: [ElementSet]], keep: Int) -> Outcome {
        guard let number = set.catalogNumber else { return .uncatalogued }
        var held = sets[number] ?? []
        if let atEpoch = held.first(where: { $0.epoch == set.epoch }) {
            return same(atEpoch, set) ? .unchanged : .conflicting(number)
        }
        let outcome: Outcome = held.isEmpty ? .added : (set.epoch > held[0].epoch ? .replaced : .older)
        let index = held.firstIndex { $0.epoch < set.epoch } ?? held.count
        held.insert(set, at: index)
        if held.count > keep { held.removeLast(held.count - keep) }
        sets[number] = held
        return outcome
    }

    /// The newest set held of an object.
    public func current(_ catalogNumber: Int) -> ElementSet? {
        sets[catalogNumber]?.first
    }

    /// Every set held of an object, the newest first.
    public func history(_ catalogNumber: Int) -> [ElementSet] {
        sets[catalogNumber] ?? []
    }

    /// The catalog numbers held, in order.
    public var catalogNumbers: [Int] {
        sets.keys.sorted()
    }

    /// The objects whose newest set is more than `days` days older than `time`, in catalog order: the ones a program
    /// would ask for again, within its source's rules.
    public func stale(at time: Epoch, olderThan days: Double) -> [Int] {
        sets.compactMap { number, held in
            guard let newest = held.first else { return nil }
            return time.seconds(since: newest.epoch) > days * 86_400 ? number : nil
        }.sorted()
    }

    /// Every set held, as an OMM in CelesTrak's JSON form: an array of records with CelesTrak's keys, each value as
    /// it was read (a number in its own digits, so nothing is rounded on the way back), and the four CCSDS keywords
    /// and every other keyword only where the source carried them. Read back by `init(saved:keep:)`, each set has the
    /// same values; its `source` is then `.json`.
    public func save() -> Data {
        var records: [String] = []
        for number in sets.keys.sorted() {
            for set in sets[number] ?? [] { records.append(Self.record(set)) }
        }
        return Data(("[" + records.joined(separator: ",\n") + "]\n").utf8)
    }

    private static func record(_ set: ElementSet) -> String {
        var parts: [String] = []
        func text(_ key: String, _ value: String?) { if let value { parts.append("\(quoted(key)):\(quoted(value))") } }
        func number(_ key: String, _ value: String?) { if let value { parts.append("\(quoted(key)):\(value)") } }
        text("OBJECT_NAME", set.objectName)
        text("OBJECT_ID", set.objectID)
        text("EPOCH", set.epoch.description)
        number("MEAN_MOTION", set.meanMotion.description)
        number("ECCENTRICITY", set.eccentricity.description)
        number("INCLINATION", set.inclination.description)
        number("RA_OF_ASC_NODE", set.rightAscension.description)
        number("ARG_OF_PERICENTER", set.argumentOfPericenter.description)
        number("MEAN_ANOMALY", set.meanAnomaly.description)
        number("EPHEMERIS_TYPE", set.ephemerisType.map(String.init))
        text("CLASSIFICATION_TYPE", set.classification)
        number("NORAD_CAT_ID", set.catalogNumber.map(String.init))
        number("ELEMENT_SET_NO", set.elementSetNumber.map(String.init))
        number("REV_AT_EPOCH", set.revolutionAtEpoch.map(String.init))
        number("BSTAR", set.bstar.description)
        number("MEAN_MOTION_DOT", set.meanMotionDot.description)
        number("MEAN_MOTION_DDOT", set.meanMotionDDot.description)
        for (key, value) in [("CENTER_NAME", set.centerName), ("REF_FRAME", set.referenceFrame),
                             ("TIME_SYSTEM", set.timeSystem), ("MEAN_ELEMENT_THEORY", set.meanElementTheory)]
        where !set.defaulted.contains(key) {
            text(key, value)
        }
        for key in set.otherKeywords.keys.sorted() { text(key, set.otherKeywords[key]) }
        return "{" + parts.joined(separator: ",") + "}"
    }

    private static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
