/// The five-character catalog field of a TLE, as Space-Track defines it.
///
/// Numbers below 100000 are five digits. From 100000 to 339999 the first character is a letter standing for 10 to
/// 33, `A` to `Z` without `I` and `O`, and the last four digits follow. Nothing above 339999 fits; such an object
/// has no TLE and is read from an OMM. Alpha-5 exists only in those five columns: in GPKit a catalog number is an
/// `Int` everywhere else.
public enum Alpha5 {

    /// The largest catalog number the field can carry.
    public static let ceiling = 339_999

    static let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ".utf8)

    /// Decodes a catalog field. It must be exactly five characters: a digit, or an uppercase letter other than
    /// `I` and `O`, then four digits. Lowercase, a space, a sign, a letter in another place and any other length
    /// are refused.
    public static func decode(_ field: String) throws(Refusal) -> Int {
        try decode(Array(field.utf8)[...])
    }

    static func decode(_ field: ArraySlice<UInt8>) throws(Refusal) -> Int {
        func refuse(_ why: String) -> Refusal {
            Refusal(.catalogNumber, "the catalog field \"\(string(field))\" \(why)", field: "catalog number", text: string(field), catalogField: string(field))
        }
        guard field.count == 5 else { throw refuse("is not five characters") }
        guard field.dropFirst().allSatisfy(\.isDigit) else { throw refuse("is neither five digits nor a letter and four digits") }
        let first = field[field.startIndex]
        let low = field.dropFirst().reduce(0) { $0 * 10 + $1.digitValue }
        if first.isDigit { return first.digitValue * 10_000 + low }
        if first == 0x49 || first == 0x4F { throw refuse("begins with \(string([first])), which Alpha-5 never uses") }
        guard let index = letters.firstIndex(of: first) else { throw refuse("is neither five digits nor a letter and four digits") }
        return (index + 10) * 10_000 + low
    }

    /// Encodes a catalog number, 0 to 339999. Anything else is refused: the field cannot carry it.
    public static func encode(_ catalogNumber: Int) throws(Refusal) -> String {
        guard catalogNumber >= 0 else {
            throw Refusal(.cannotEncode, "catalog number \(catalogNumber) is negative", field: "catalog number", text: String(catalogNumber))
        }
        guard catalogNumber <= ceiling else {
            throw Refusal(.cannotEncode, "catalog number \(catalogNumber) is above \(ceiling), the most a TLE's five columns can carry; it needs an OMM",
                          field: "catalog number", text: String(catalogNumber))
        }
        if catalogNumber < 100_000 { return padded(catalogNumber, width: 5) }
        return string([letters[catalogNumber / 10_000 - 10]]) + padded(catalogNumber % 10_000, width: 4)
    }
}
