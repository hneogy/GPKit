import Foundation
import Testing
import GPKit

/// Each kind of refusal has its page in Sources/GPKit/GPKit.docc/Refusals, and each page's example is what GPKit does:
/// its input, read (and for `cannotEncode` written) as the page says, is refused with that kind and that message.
@Suite struct RefusalPagesTests {

    struct Example {
        let operation: String
        let input: [UInt8]
        let says: String
    }

    static let pages = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/GPKit/GPKit.docc/Refusals")

    /// The page's example: the line before its first text block, that block, and the block after "GPKit says:".
    static func example(of kind: Refusal.Kind) throws -> Example {
        // a checkout on Windows can end its lines CR LF; the page is the same
        let text = try String(contentsOf: pages.appendingPathComponent("\(kind.rawValue).md"), encoding: .utf8)
            .replacingOccurrences(of: "\r\n", with: "\n")
        let lines = text.components(separatedBy: "\n")
        #expect(lines.first == "# ``GPKit/Refusal/Kind-swift.enum/\(kind.rawValue)``")
        #expect(text.contains("## What happened\n") && text.contains("## How to fix it\n"))
        func block(after index: Int) throws -> (lines: [String], end: Int) {
            let start = try #require(lines[index...].firstIndex(of: "```text"))
            let end = try #require(lines[(start + 1)...].firstIndex(of: "```"))
            return (Array(lines[(start + 1)..<end]), end)
        }
        let example = try #require(lines.firstIndex(of: "## Example"))
        let operationLine = try #require(lines[example...].first { $0.hasPrefix("Read as ") })
        let input = try block(after: example)
        let saysLine = try #require(lines[input.end...].firstIndex(of: "GPKit says:"))
        let says = try block(after: saysLine).lines
        #expect(says.count == 1)
        let operation = String(operationLine.dropLast())  // the colon
        let bytes: [UInt8]
        if operation.hasSuffix(", these bytes in hexadecimal") {
            bytes = try input.lines.joined(separator: " ").split(separator: " ").map { try #require(UInt8($0, radix: 16)) }
        } else {
            // as a file has it, its last line ended
            bytes = Array((input.lines.joined(separator: "\n") + "\n").utf8)
        }
        return Example(operation: operation, input: bytes, says: says.first ?? "")
    }

    /// What GPKit does with the example's input: the first refusal, thrown or among a file's records.
    static func refusal(for example: Example) throws -> Refusal? {
        let words = example.operation.split(separator: " ")
        let format = try #require(Format(rawValue: words[2].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ","))))
        do {
            let file = try ElementSets.read(example.input, as: format)
            if example.operation.hasSuffix("and written as a TLE") {
                _ = try TLE.write(try #require(file.elementSets.first))
                return nil
            }
            return file.refusals.first
        } catch let refusal as Refusal {
            return refusal
        }
    }

    @Test(.enabled(if: theSourceTreeIsHere, "reads the refusal pages, which are not on the device"))
    func everyKindHasAPage() throws {
        let written = try FileManager.default.contentsOfDirectory(atPath: RefusalPagesTests.pages.path).filter { $0.hasSuffix(".md") }
        #expect(Set(written) == Set(Refusal.Kind.allCases.map { "\($0.rawValue).md" }))
        #expect(Refusal.Kind.allCases.count == 19)
    }

    @Test(.enabled(if: theSourceTreeIsHere, "reads the refusal pages, which are not on the device"), arguments: Refusal.Kind.allCases)
    func eachPageSaysWhatGPKitDoes(_ kind: Refusal.Kind) throws {
        let example = try RefusalPagesTests.example(of: kind)
        let refusal = try #require(try RefusalPagesTests.refusal(for: example), "\(kind): the page's input is not refused")
        #expect(refusal.kind == kind)
        #expect("\(refusal)" == example.says)
    }
}
