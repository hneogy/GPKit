/// OMM as `KEYWORD = value` lines (CCSDS 502.0-B-3, section 7). A message begins at `CCSDS_OMM_VERS`, and a file
/// may hold several. Blank lines and `COMMENT` lines are passed over; spaces and tabs around the keyword, the
/// equals sign and the value are not significant; a unit in square brackets after a numeric value is passed over.
enum KVN {

    static func readFile(_ bytes: [UInt8]) throws(Refusal) -> [ElementSetFile.Entry] {
        struct Message {
            var fields = OMM.Fields()
            var line: Int
            var problem: Refusal?
        }
        var messages: [Message] = []
        var before: (count: Int, line: Int)?
        for (index, raw) in splitLines(bytes).enumerated() {
            let line = trimmed(raw)
            if line.isEmpty { continue }
            if line.starts(with: Array("COMMENT".utf8)), line.count == 7 || line[line.startIndex + 7].isBlank { continue }
            var keyword: String?
            var value: ArraySlice<UInt8> = []
            if let equals = line.firstIndex(of: 0x3D) {
                let key = trimmed(line[..<equals])
                if let first = key.first, first.isUppercaseLetter, key.allSatisfy({ $0.isUppercaseLetter || $0.isDigit || $0 == 0x5F }) {
                    keyword = string(key)
                    value = trimmed(line[(equals + 1)...])
                }
            }
            if keyword == "CCSDS_OMM_VERS" { messages.append(Message(line: index + 1)) }
            guard !messages.isEmpty else {
                before = (before.map { $0.count + 1 } ?? 1, before?.line ?? index + 1)
                continue
            }
            let m = messages.count - 1
            guard messages[m].problem == nil else { continue }
            guard let keyword else {
                messages[m].problem = Refusal(.malformedRecord, "a line that is not KEYWORD = value", text: string(line.prefix(80)), line: index + 1)
                continue
            }
            if OMM.decimalKeywords.contains(keyword), value.last == 0x5D, let open = value.lastIndex(of: 0x5B) {
                value = trimmed(value[..<open])
            }
            if !messages[m].fields.add(keyword, value) {
                messages[m].problem = Refusal(.duplicateKeyword, "\(keyword) appears twice in one message", field: keyword, line: index + 1)
            }
        }
        guard !messages.isEmpty else { throw Refusal(.malformedFile, "no CCSDS_OMM_VERS line: not an OMM in KVN") }
        var entries: [ElementSetFile.Entry] = []
        if let before {
            entries.append(.refusal(Refusal(.malformedRecord, "\(before.count) line\(before.count == 1 ? "" : "s") before the first CCSDS_OMM_VERS",
                                            record: 0, line: before.line)))
        }
        for message in messages {
            let record = entries.count
            if let problem = message.problem {
                entries.append(.refusal(problem.located(record: record, line: message.line, catalogField: message.fields["NORAD_CAT_ID"].map { string($0) })))
            } else {
                entries.append(OMM.entry(message.fields, format: .kvn, record: record, line: message.line))
            }
        }
        return entries
    }
}
