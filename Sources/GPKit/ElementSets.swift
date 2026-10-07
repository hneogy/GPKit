/// The formats GPKit reads.
public enum Format: String, Sendable, Hashable, CaseIterable {
    /// OMM as comma-separated values, a header row naming the keywords.
    case csv
    /// OMM as a JSON array of objects.
    case json
    /// OMM in NDM/XML: an `ndm` element holding `omm` elements, or one `omm`.
    case xml
    /// OMM as `KEYWORD = value` lines.
    case kvn
    /// Two-line element sets, with or without name lines.
    case tle
}

/// What reading one file gave: its records in the file's order, each read or refused.
public struct ElementSetFile: Sendable, Hashable {

    public enum Entry: Sendable, Hashable {
        case elementSet(ElementSet)
        case refusal(Refusal)
    }

    /// Every record of the file, in order.
    public let entries: [Entry]
    /// The provider's own answer when it had no data, such as CelesTrak's `No GP data found`. A file that is this
    /// answer has no entries, and reading it is not an error: nothing to load is a result.
    public let providerMessage: String?

    /// The element sets that were read.
    public var elementSets: [ElementSet] {
        entries.compactMap { if case .elementSet(let set) = $0 { set } else { nil } }
    }

    /// The records that were refused, each with its reason.
    public var refusals: [Refusal] {
        entries.compactMap { if case .refusal(let refusal) = $0 { refusal } else { nil } }
    }
}

/// Reading GP data.
public enum ElementSets {

    /// The plain-text answers a provider gives in place of data, in any format, when it has none.
    public static let emptyAnswers = ["No GP data found", "No SupGP data found"]

    /// Reads a file of element sets.
    ///
    /// Each record comes back read or refused, so one bad record costs one record. The call itself throws only
    /// when the input as a whole cannot be taken for what it is said to be: bytes that are not UTF-8, an empty
    /// input, JSON or XML that does not parse, a file that ends inside a record.
    ///
    /// `checksum` is for `.tle` and says what is done with each line's checksum digit: verified, which is the
    /// default, or ignored. The other formats have no checksum, and the argument does nothing for them.
    public static func read<Bytes: Collection>(_ input: Bytes, as format: Format, checksum: TLE.Checksum = .verify) throws(Refusal) -> ElementSetFile where Bytes.Element == UInt8 {
        let bytes = try validatedInput(input)
        let answer = string(trimmed(bytes[...]))
        if emptyAnswers.contains(answer) {
            return ElementSetFile(entries: [], providerMessage: answer)
        }
        let entries: [ElementSetFile.Entry]
        switch format {
        case .tle: entries = TLE.readFile(bytes, checksum: checksum)
        case .csv: entries = try CSV.readFile(bytes)
        case .json: entries = try JSON.readFile(bytes)
        case .xml: entries = try XML.readFile(bytes)
        case .kvn: entries = try KVN.readFile(bytes)
        }
        return ElementSetFile(entries: entries, providerMessage: nil)
    }

    /// Reads a file of element sets from text.
    public static func read(_ text: String, as format: Format, checksum: TLE.Checksum = .verify) throws(Refusal) -> ElementSetFile {
        try read(Array(text.utf8), as: format, checksum: checksum)
    }
}
