import Foundation
import Testing
@testable import GPKit

/// GPKit's propagation against python-sgp4's, over every element set of a gpconf corpus.
///
/// This runs only where it is pointed at a corpus that holds its provider files and at the reference
/// `tools/python_sgp4_reference.py` made from it; neither is in this repository, and CI has neither.
@Suite struct CrossCheckTests {

    static let corpus = ProcessInfo.processInfo.environment["GPKIT_CORPUS"]
    static let reference = ProcessInfo.processInfo.environment["GPKIT_PYTHON_SGP4_REFERENCE"]

    @Test(.enabled(if: corpus != nil && reference != nil))
    func gpkitAgreesWithPythonSGP4OnTheCorpus() throws {
        let corpus = try #require(CrossCheckTests.corpus), reference = try #require(CrossCheckTests.reference)
        let document = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: reference))) as? [String: Any])
        let times = try #require(document["times"] as? [Double])
        let files = try #require(document["files"] as? [[String: Any]])

        struct Tally {
            var files = 0, sets = 0, states = 0, errorsDiffer = 0
            var worst = 0.0          // kilometres
            var worstAt = 0.0        // minutes
            var overMillimetre = 0   // states
        }
        var tallies: [String: Tally] = [:]
        var mismatched: [String] = []
        for file in files {
            guard let records = file["records"] as? [[String: Any]], let path = file["path"] as? String, let name = file["format"] as? String,
                  let format = Format(rawValue: name) else { continue }
            let read = try ElementSets.read(Data(contentsOf: URL(fileURLWithPath: corpus).appendingPathComponent(path)), as: format)
            let sets = read.elementSets
            guard sets.count == records.count, read.refusals.isEmpty else {
                mismatched.append("\(path): GPKit read \(sets.count) and refused \(read.refusals.count), python-sgp4 read \(records.count)")
                continue
            }
            var tally = tallies[name] ?? Tally()
            tally.files += 1
            for (set, record) in zip(sets, records) {
                guard let id = record["id"] as? Int, let states = record["states"] as? [[Double]], id == set.catalogNumber else {
                    mismatched.append("\(path): the records are not in the same order")
                    break
                }
                tally.sets += 1
                let core = SGP4Core(set)
                for (t, theirs) in zip(times, states) {
                    var copy = core
                    var r = (0.0, 0.0, 0.0), v = (0.0, 0.0, 0.0)
                    _ = copy.sgp4(t, &r, &v)
                    tally.states += 1
                    if copy.error != Int(theirs[0]) {
                        tally.errorsDiffer += 1
                        continue
                    }
                    guard copy.error == 0 else { continue }
                    let d = max(abs(r.0 - theirs[1]), abs(r.1 - theirs[2]), abs(r.2 - theirs[3]))
                    if d > tally.worst {
                        tally.worst = d
                        tally.worstAt = t
                    }
                    if d > 1.0e-6 { tally.overMillimetre += 1 }
                }
            }
            tallies[name] = tally
        }
        print("python-sgp4 \(document["python_sgp4"] ?? "?") against GPKit over the corpus, times \(times) minutes from each epoch:")
        for (name, t) in tallies.sorted(by: { $0.key < $1.key }) {
            print("  \(name): \(t.files) files, \(t.sets) element sets, \(t.states) states; largest difference \(t.worst * 1.0e6) mm at \(t.worstAt) min; "
                  + "\(t.overMillimetre) states over a millimetre; error codes differ at \(t.errorsDiffer)")
        }
        for line in mismatched { print("  NOT COMPARED: \(line)") }
        #expect(mismatched.isEmpty)
        #expect(!tallies.isEmpty)
        for (name, t) in tallies {
            #expect(t.errorsDiffer == 0, "\(name)")
            #expect(t.worst <= 1.0e-6, "\(name): \(t.worst * 1.0e6) mm")   // a millimetre
        }
    }
}
