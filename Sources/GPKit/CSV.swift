/// OMM as comma-separated values: a header row naming the keywords, one record a row. Fields may be quoted, a
/// quote inside a quoted field doubled. Columns GPKit has no property for are kept in `otherKeywords`.
enum CSV {

    static func readFile(_ bytes: [UInt8]) throws(Refusal) -> [ElementSetFile.Entry] {
        // rows of fields, each row with the line it began on and whether a line ending closed it
        var rows: [(fields: [ArraySlice<UInt8>], line: Int, closed: Bool)] = []
        var fields: [ArraySlice<UInt8>] = []
        var unquoted: [UInt8]? = nil        // the field's bytes when quoting changed them
        var start = 0, i = 0, line = 1, rowLine = 1
        var inQuotes = false, wasQuoted = false
        var storage: [[UInt8]] = []
        func finishField(_ end: Int) -> ArraySlice<UInt8> {
            if let unquoted {
                storage.append(unquoted)
                return storage[storage.count - 1][...]
            }
            return bytes[start..<end]
        }
        while i < bytes.count {
            let c = bytes[i]
            if inQuotes {
                if c == 0x22 {
                    if i + 1 < bytes.count && bytes[i + 1] == 0x22 {
                        unquoted!.append(0x22)
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    if c == 0x0A { line += 1 }
                    unquoted!.append(c)
                }
                i += 1
                continue
            }
            switch c {
            case 0x22 where i == start && !wasQuoted:
                inQuotes = true
                wasQuoted = true
                unquoted = []
            case 0x2C:
                fields.append(finishField(i))
                unquoted = nil
                wasQuoted = false
                start = i + 1
            case 0x0A, 0x0D:
                if c == 0x0D && !(i + 1 < bytes.count && bytes[i + 1] == 0x0A) {
                    throw Refusal(.malformedFile, "a carriage return with no line feed after it", line: line)
                }
                fields.append(finishField(i))
                unquoted = nil
                wasQuoted = false
                if !(fields.count == 1 && fields[0].isEmpty) { rows.append((fields, rowLine, true)) }
                fields = []
                if c == 0x0D { i += 1 }
                line += 1
                rowLine = line
                start = i + 1
            default:
                if wasQuoted {
                    throw Refusal(.malformedFile, "text after a closing quote", line: line)
                }
            }
            i += 1
        }
        if inQuotes { throw Refusal(.cutShort, "the file ends inside a quoted field", line: rowLine) }
        if start < bytes.count || !fields.isEmpty || wasQuoted {
            fields.append(finishField(bytes.count))
            rows.append((fields, rowLine, false))
        }

        guard let header = rows.first else { throw Refusal(.malformedFile, "no header row") }
        let keywords = header.fields.map { string(trimmed($0)) }
        guard keywords.allSatisfy({ !$0.isEmpty }), Set(keywords).count == keywords.count else {
            throw Refusal(.malformedFile, "the header row has an empty or a repeated column name", line: header.line)
        }
        guard keywords.contains("EPOCH") else {
            throw Refusal(.malformedFile, "the first row names no EPOCH column: not an OMM CSV header", line: header.line)
        }
        var entries: [ElementSetFile.Entry] = []
        for row in rows.dropFirst() {
            let record = entries.count
            guard row.fields.count == keywords.count else {
                if !row.closed && row.fields.count < keywords.count {
                    throw Refusal(.cutShort, "the file ends inside its last row: \(row.fields.count) of \(keywords.count) fields, and no line ending",
                                  record: record, line: row.line)
                }
                let catalog = keywords.firstIndex(of: "NORAD_CAT_ID").flatMap { $0 < row.fields.count ? string(trimmed(row.fields[$0])) : nil }
                entries.append(.refusal(Refusal(.malformedRecord, "the row has \(row.fields.count) fields and the header \(keywords.count)",
                                                catalogField: catalog, record: record, line: row.line)))
                continue
            }
            var fields = OMM.Fields()
            for (keyword, value) in zip(keywords, row.fields) { _ = fields.add(keyword, value) }
            entries.append(OMM.entry(fields, format: .csv, record: record, line: row.line))
        }
        return entries
    }
}
