/// OMM as JSON: an array of objects, one a record, the keywords as keys. A value is a number or a string, both of
/// which providers use, or null, which is read as an empty value. Numbers are kept as the text the file has:
/// nothing passes through a `Double`. A single object is read as one record.
enum JSON {

    indirect enum Value {
        case object([(key: String, value: Value)])
        case array([Value])
        case string([UInt8])
        case number(ArraySlice<UInt8>)
        case bool(Bool)
        case null
    }

    static func readFile(_ bytes: [UInt8]) throws(Refusal) -> [ElementSetFile.Entry] {
        var scanner = Scanner(bytes: bytes)
        let document = try scanner.document()
        let records: [Value]
        switch document {
        case .array(let items): records = items
        case .object: records = [document]
        default: throw Refusal(.malformedFile, "the JSON is neither an array of records nor one record")
        }
        var entries: [ElementSetFile.Entry] = []
        var storage: [[UInt8]] = []
        for (record, value) in records.enumerated() {
            guard case .object(let members) = value else {
                entries.append(.refusal(Refusal(.malformedRecord, "the array's element is not an object", record: record)))
                continue
            }
            var fields = OMM.Fields()
            var problem: Refusal?
            for (key, member) in members where problem == nil {
                let text: ArraySlice<UInt8>
                switch member {
                case .string(let s):
                    storage.append(s)
                    text = storage[storage.count - 1][...]
                case .number(let n): text = n
                case .null: text = []
                default:
                    problem = Refusal(.malformedRecord, "the value of \(key) is neither a number, a string nor null", field: key, record: record)
                    continue
                }
                if !fields.add(key, text) {
                    problem = Refusal(.duplicateKeyword, "\(key) appears twice in one record", field: key, record: record)
                }
            }
            if let problem {
                entries.append(.refusal(problem.located(record: record, line: nil, catalogField: fields["NORAD_CAT_ID"].map { string($0) })))
            } else {
                entries.append(OMM.entry(fields, format: .json, record: record, line: nil))
            }
        }
        return entries
    }

    /// A JSON reader that keeps a number as the bytes it was written with.
    struct Scanner {
        let bytes: [UInt8]
        var i = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        func malformed(_ what: String) -> Refusal {
            i >= bytes.count ? Refusal(.cutShort, "the JSON ends \(what)") : Refusal(.malformedFile, "not JSON at byte \(i + 1): \(what)")
        }

        mutating func skipWhitespace() {
            while i < bytes.count, bytes[i].isWhitespace { i += 1 }
        }

        mutating func document() throws(Refusal) -> Value {
            skipWhitespace()
            let value = try value(depth: 0)
            skipWhitespace()
            guard i == bytes.count else { throw Refusal(.malformedFile, "not JSON at byte \(i + 1): text after the document's end") }
            return value
        }

        mutating func value(depth: Int) throws(Refusal) -> Value {
            guard depth < 32 else { throw Refusal(.malformedFile, "the JSON is nested more than 32 deep") }
            guard i < bytes.count else { throw malformed("where a value should be") }
            switch bytes[i] {
            case 0x7B:
                i += 1
                var members: [(key: String, value: Value)] = []
                skipWhitespace()
                if i < bytes.count, bytes[i] == 0x7D {
                    i += 1
                    return .object(members)
                }
                while true {
                    skipWhitespace()
                    guard i < bytes.count, bytes[i] == 0x22 else { throw malformed("where a key should be") }
                    let key = string(try stringBody())
                    skipWhitespace()
                    guard i < bytes.count, bytes[i] == 0x3A else { throw malformed("where a colon should follow a key") }
                    i += 1
                    skipWhitespace()
                    members.append((key, try value(depth: depth + 1)))
                    skipWhitespace()
                    guard i < bytes.count else { throw malformed("inside an object") }
                    if bytes[i] == 0x2C { i += 1; continue }
                    if bytes[i] == 0x7D { i += 1; return .object(members) }
                    throw malformed("where a comma or a closing brace should be")
                }
            case 0x5B:
                i += 1
                var items: [Value] = []
                skipWhitespace()
                if i < bytes.count, bytes[i] == 0x5D {
                    i += 1
                    return .array(items)
                }
                while true {
                    skipWhitespace()
                    items.append(try value(depth: depth + 1))
                    skipWhitespace()
                    guard i < bytes.count else { throw malformed("before the array is closed") }
                    if bytes[i] == 0x2C { i += 1; continue }
                    if bytes[i] == 0x5D { i += 1; return .array(items) }
                    throw malformed("where a comma or a closing bracket should be")
                }
            case 0x22:
                return .string(try stringBody())
            case 0x74:
                try literal("true")
                return .bool(true)
            case 0x66:
                try literal("false")
                return .bool(false)
            case 0x6E:
                try literal("null")
                return .null
            default:
                return .number(try number())
            }
        }

        mutating func literal(_ word: String) throws(Refusal) {
            let w = Array(word.utf8)
            guard i + w.count <= bytes.count, Array(bytes[i..<(i + w.count)]) == w else { throw malformed("where a value should be") }
            i += w.count
        }

        /// `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`, returned as written.
        mutating func number() throws(Refusal) -> ArraySlice<UInt8> {
            let start = i
            if i < bytes.count, bytes[i] == 0x2D { i += 1 }
            guard i < bytes.count, bytes[i].isDigit else { throw malformed("where a value should be") }
            if bytes[i] == 0x30 {
                i += 1
            } else {
                while i < bytes.count, bytes[i].isDigit { i += 1 }
            }
            if i < bytes.count, bytes[i] == 0x2E {
                i += 1
                guard i < bytes.count, bytes[i].isDigit else { throw malformed("in a number, after its decimal point") }
                while i < bytes.count, bytes[i].isDigit { i += 1 }
            }
            if i < bytes.count, bytes[i] == 0x45 || bytes[i] == 0x65 {
                i += 1
                if i < bytes.count, bytes[i] == 0x2B || bytes[i] == 0x2D { i += 1 }
                guard i < bytes.count, bytes[i].isDigit else { throw malformed("in a number, after its exponent mark") }
                while i < bytes.count, bytes[i].isDigit { i += 1 }
            }
            return bytes[start..<i]
        }

        /// The string that starts at the quote under the cursor, its escapes resolved, as UTF-8.
        mutating func stringBody() throws(Refusal) -> [UInt8] {
            i += 1
            var out: [UInt8] = []
            while true {
                guard i < bytes.count else { throw malformed("inside a string") }
                let c = bytes[i]
                if c == 0x22 {
                    i += 1
                    return out
                }
                guard c >= 0x20 else { throw malformed("a control character inside a string") }
                if c != 0x5C {
                    out.append(c)
                    i += 1
                    continue
                }
                i += 1
                guard i < bytes.count else { throw malformed("inside a string") }
                switch bytes[i] {
                case 0x22: out.append(0x22)
                case 0x5C: out.append(0x5C)
                case 0x2F: out.append(0x2F)
                case 0x62: out.append(0x08)
                case 0x66: out.append(0x0C)
                case 0x6E: out.append(0x0A)
                case 0x72: out.append(0x0D)
                case 0x74: out.append(0x09)
                case 0x75:
                    var scalar = try hex4()
                    if (0xD800...0xDBFF).contains(scalar) {
                        guard i + 2 < bytes.count, bytes[i + 1] == 0x5C, bytes[i + 2] == 0x75 else { throw malformed("half of a surrogate pair in a string") }
                        i += 2
                        let low = try hex4()
                        guard (0xDC00...0xDFFF).contains(low) else { throw malformed("half of a surrogate pair in a string") }
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let unicode = Unicode.Scalar(scalar) else { throw malformed("half of a surrogate pair in a string") }
                    out.append(contentsOf: Array(String(Character(unicode)).utf8))
                default:
                    throw malformed("an escape JSON does not have")
                }
                i += 1
            }
        }

        /// The four hex digits after the `u` under the cursor; leaves the cursor on the last of them.
        mutating func hex4() throws(Refusal) -> UInt32 {
            guard i + 4 < bytes.count else { throw malformed("inside a string") }
            var value: UInt32 = 0
            for k in 1...4 {
                let c = bytes[i + k]
                let digit: UInt32
                switch c {
                case 0x30...0x39: digit = UInt32(c) - 0x30
                case 0x41...0x46: digit = UInt32(c) - 0x41 + 10
                case 0x61...0x66: digit = UInt32(c) - 0x61 + 10
                default: throw malformed("an escape JSON does not have")
                }
                value = value * 16 + digit
            }
            i += 4
            return value
        }
    }
}
