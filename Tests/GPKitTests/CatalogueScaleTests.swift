import Testing
import GPKit

/// The article "Working with a whole catalogue" (GPKit.docc/Articles/CatalogueScale.md): its code, compiled as it is
/// printed there, gives what reading the whole file gives.
@Suite struct CatalogueScaleTests {

    // as the article prints it
    /// Propagators for every element set of a CSV, read a thousand records at a time from its lines (the header first),
    /// so that neither the whole text nor every record is held at once. `expected`, the number of records if known (count
    /// the lines first), makes the array at its full size: one that grows by doubling can hold up to twice what it keeps.
    /// Records GPKit refuses, and sets it will not propagate, are counted in `refused`.
    func propagators(fromCSVLines lines: some Sequence<String>, expected: Int = 0, piece: Int = 1000) throws -> (propagators: [Propagator], refused: Int) {
        var header: String?
        var rows: [String] = []
        var propagators: [Propagator] = []
        propagators.reserveCapacity(expected)
        var refused = 0
        func read() throws {
            guard let header, !rows.isEmpty else { return }
            let file = try ElementSets.read(([header] + rows).joined(separator: "\n"), as: .csv)
            refused += file.refusals.count
            for set in file.elementSets {
                do { propagators.append(try Propagator(set)) } catch { refused += 1 }
            }
            rows.removeAll(keepingCapacity: true)
        }
        for line in lines where !line.isEmpty {
            if header == nil { header = line; continue }
            rows.append(line)
            if rows.count == piece { try read() }
        }
        try read()
        return (propagators, refused)
    }

    /// 2,503 rows: the Space Station's 1998 set under 2,500 catalog numbers, one row GPKit refuses, and two type-4
    /// rows it reads and will not propagate.
    static func lines() -> [String] {
        var lines = [Sample.csvHeader]
        for i in 0..<2_500 {
            lines.append(Sample.csvRow.replacingOccurrences(of: ",25544,", with: ",\(100_000 + i),"))
            if i == 1_200 { lines.append(Sample.csvRow.replacingOccurrences(of: ",25544,", with: ",A0000,")) }
            if i == 10 || i == 2_499 { lines.append(Sample.csvRow.replacingOccurrences(of: ",25544,", with: ",\(900_000 + i),").replacingOccurrences(of: ",359.7454,0,U,", with: ",359.7454,4,U,")) }
        }
        return lines
    }

    @Test func readInPiecesItGivesWhatTheWholeFileGives() throws {
        let lines = Self.lines()
        let whole = try ElementSets.read(lines.joined(separator: "\r\n") + "\r\n", as: .csv)
        let expected = whole.elementSets.filter { (try? Propagator($0)) != nil }
        #expect(whole.refusals.count == 1 && whole.elementSets.count == 2_502 && expected.count == 2_500)
        // pieces of 1,000 (the last one short), of 7, and of more than the file
        // with the array made at the records' count, at none, and too small
        for (piece, reserved) in [(1_000, 2_503), (7, 0), (10_000, 10)] {
            let (propagators, refused) = try propagators(fromCSVLines: lines, expected: reserved, piece: piece)
            #expect(propagators.map(\.elementSet) == expected, "pieces of \(piece)")
            #expect(refused == 3, "pieces of \(piece)")
        }
        // nothing but a header, or nothing at all
        #expect(try propagators(fromCSVLines: [Sample.csvHeader]).propagators.isEmpty)
        #expect(try propagators(fromCSVLines: [String]()).propagators.isEmpty)
    }
}
