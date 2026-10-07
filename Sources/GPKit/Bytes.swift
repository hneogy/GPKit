// Byte-level helpers shared by the readers. Everything GPKit reads is UTF-8, and every format it reads keeps its
// structure in ASCII, so the readers work on bytes and make a String only of what they keep.

extension UInt8 {
    var isDigit: Bool { self >= 0x30 && self <= 0x39 }
    var digitValue: Int { Int(self) - 0x30 }
    var isUppercaseLetter: Bool { self >= 0x41 && self <= 0x5A }
    /// Space or tab.
    var isBlank: Bool { self == 0x20 || self == 0x09 }
    /// Space, tab, carriage return or line feed.
    var isWhitespace: Bool { self == 0x20 || self == 0x09 || self == 0x0D || self == 0x0A }
}

func string(_ bytes: some Collection<UInt8>) -> String {
    String(decoding: bytes, as: UTF8.self)
}

func trimmed(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
    var slice = bytes
    while let first = slice.first, first.isWhitespace { slice = slice.dropFirst() }
    while let last = slice.last, last.isWhitespace { slice = slice.dropLast() }
    return slice
}

/// The lines of a file: split at each line feed, one carriage return before it removed. A last line without a line
/// feed is a line; the empty piece after a final line feed is not.
func splitLines(_ bytes: [UInt8]) -> [ArraySlice<UInt8>] {
    var lines: [ArraySlice<UInt8>] = []
    var start = bytes.startIndex
    for i in bytes.indices where bytes[i] == 0x0A {
        var end = i
        if end > start && bytes[end - 1] == 0x0D { end -= 1 }
        lines.append(bytes[start..<end])
        start = i + 1
    }
    if start < bytes.endIndex {
        var end = bytes.endIndex
        if bytes[end - 1] == 0x0D { end -= 1 }
        lines.append(bytes[start..<end])
    }
    return lines
}

/// The input as validated UTF-8, without a byte-order mark. Refuses input that is not UTF-8 and input that holds
/// nothing but whitespace.
func validatedInput(_ input: some Collection<UInt8>) throws(Refusal) -> [UInt8] {
    var bytes = Array(input)
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
    // String(decoding:) repairs what is not UTF-8, so bytes that come back changed were not UTF-8
    guard String(decoding: bytes, as: UTF8.self).utf8.elementsEqual(bytes) else {
        throw Refusal(.notUTF8, "the input is not UTF-8")
    }
    guard bytes.contains(where: { !$0.isWhitespace }) else {
        throw Refusal(.emptyInput, "the input is empty")
    }
    return bytes
}

/// A non-negative integer as text: digits, with an optional plus sign when `plusAllowed`. nil for anything else,
/// and for more digits than `maxDigits`.
func unsignedInteger(_ bytes: ArraySlice<UInt8>, plusAllowed: Bool, maxDigits: Int = 18) -> Int? {
    var slice = bytes
    if plusAllowed, slice.first == 0x2B { slice = slice.dropFirst() }
    guard !slice.isEmpty, slice.count <= maxDigits, slice.allSatisfy(\.isDigit) else { return nil }
    return slice.reduce(0) { $0 * 10 + $1.digitValue }
}

func padded(_ value: Int, width: Int, with pad: Character = "0") -> String {
    let digits = String(value)
    return digits.count >= width ? digits : String(repeating: pad, count: width - digits.count) + digits
}
