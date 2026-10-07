/// Why a file, or one record of a file, was not read, or why an element set was not written.
///
/// Nothing in GPKit drops input without a word and nothing guesses: what cannot be read as it stands is refused,
/// and the refusal says what was wrong, where, and with which text.
public struct Refusal: Error, Sendable, Hashable, CustomStringConvertible {

    public enum Kind: String, Sendable, Hashable, CaseIterable {
        // the whole input
        /// Nothing but whitespace.
        case emptyInput
        /// The bytes are not UTF-8.
        case notUTF8
        /// The file is not what its format requires: JSON that does not parse, XML that is not well formed, a CSV
        /// without a header.
        case malformedFile
        /// The file ends inside a record.
        case cutShort

        // a TLE set
        /// A line that is not 69 characters, or holds a character outside printable ASCII.
        case lineLength
        /// A checksum digit that is not the one the line computes to.
        case checksum
        /// A line 1 with no line 2 after it.
        case missingLine2
        /// A line 2 with no line 1 before it.
        case missingLine1
        /// A line that is neither an element line nor the name of the set that follows.
        case strayLine
        /// A character where the format fixes another: a separator column that is not a space, a field out of place.
        case layout

        // one value
        /// A catalog field that is neither five digits nor Alpha-5, or a `NORAD_CAT_ID` that is not an integer of
        /// up to nine digits, or two catalog fields of one set that differ.
        case catalogNumber
        /// A numeric field or keyword whose text is not a number.
        case notANumber
        /// A counter whose text is not a non-negative integer.
        case notAnInteger
        /// An epoch that is not a CCSDS time code, or not a `YYDDD.DDDDDDDD` field, or not a date.
        case notAnEpoch
        /// An international designator or a classification the TLE's columns cannot hold as written.
        case notText

        // one OMM record
        /// A keyword the record must carry and does not.
        case missingKeyword
        /// A keyword that appears twice in one record.
        case duplicateKeyword
        /// A record whose structure is not the format's: a JSON array element that is not an object, a KVN line
        /// that is not `KEYWORD = value`, a CSV row with more or fewer fields than the header.
        case malformedRecord

        // writing
        /// A value the TLE format cannot carry: a catalog number above 339999, a field wider than its columns.
        case cannotEncode
    }

    public let kind: Kind
    /// The reason, as a sentence.
    public let message: String
    /// The field or keyword at fault, when it is one.
    public let field: String?
    /// The text that was there.
    public let text: String?
    /// The catalog field or `NORAD_CAT_ID` as the input carried it, when the record got that far.
    public let catalogField: String?
    /// Which record of the file, counting from 0; nil for a refusal of the whole input.
    public let record: Int?
    /// The line of the file, counting from 1, where the format has lines.
    public let line: Int?

    public init(_ kind: Kind, _ message: String, field: String? = nil, text: String? = nil, catalogField: String? = nil,
                record: Int? = nil, line: Int? = nil) {
        self.kind = kind
        self.message = message
        self.field = field
        self.text = text
        self.catalogField = catalogField
        self.record = record
        self.line = line
    }

    public var description: String {
        var out = message
        if let line { out += " (line \(line) of the file)" } else if let record { out += " (record \(record + 1) of the file)" }
        return out
    }

    /// The same refusal, placed in its file.
    func located(record: Int?, line: Int?, catalogField: String?) -> Refusal {
        Refusal(kind, message, field: field, text: text, catalogField: self.catalogField ?? catalogField,
                record: self.record ?? record, line: self.line ?? line)
    }
}
