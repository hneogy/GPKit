/// The two-line element set: a reader and a writer for the fixed-column format, with Alpha-5 in the catalog field.
///
/// Reading is strict. A set is read only when both lines are 69 printable ASCII characters, both checksums are
/// right, the two catalog fields agree, every separator column is a space and every field is what its columns are
/// for. Anything else is refused with the reason, and the sets around it are read.
public enum TLE {

    /// What the reader does with the checksum digit in column 69 of each line.
    public enum Checksum: Sendable, Hashable {
        /// The digit must be the one the line computes to; a set whose digit is another is refused. The default.
        case verify
        /// The digit is not looked at, whatever character is there. For lines from a source known to write wrong
        /// or blank checksums. Every other check is made as before: the length, the columns, each field's form.
        /// A wrong digit is then no warning that a line was altered, so a changed digit elsewhere in the line is
        /// read as the value it now spells.
        case ignore
    }

    /// Two-digit years 57 to 99 are 1957 to 1999, and 00 to 56 are 2000 to 2056.
    public static let yearPivot = 57

    public static func fullYear(twoDigit year: Int) -> Int {
        year >= yearPivot ? 1900 + year : 2000 + year
    }

    /// The checksum of a line: its first 68 characters summed, a digit counting its value and a minus sign 1,
    /// modulo 10.
    public static func checksum(of line: String) -> Int {
        checksum(Array(line.utf8)[...])
    }

    static func checksum(_ line: ArraySlice<UInt8>) -> Int {
        line.prefix(68).reduce(0) { $0 + ($1.isDigit ? $1.digitValue : ($1 == 0x2D ? 1 : 0)) } % 10
    }

    // MARK: - Reading

    /// Reads one element set from its two lines, with the name line if there is one. The checksums are verified
    /// unless `checksum` is `.ignore`.
    public static func parse(name: String? = nil, line1: String, line2: String, checksum: Checksum = .verify) throws(Refusal) -> ElementSet {
        try parse(name: name.map { Array($0.utf8)[...] }, line1: Array(line1.utf8)[...], line2: Array(line2.utf8)[...], checksum: checksum)
    }

    static func parse(name: ArraySlice<UInt8>?, line1: ArraySlice<UInt8>, line2: ArraySlice<UInt8>, checksum: Checksum) throws(Refusal) -> ElementSet {
        let l1 = Array(line1), l2 = Array(line2)
        let catalogField = l1.count >= 7 ? string(l1[2..<7]) : nil
        func refuse(_ kind: Refusal.Kind, _ message: String, field: String? = nil, text: ArraySlice<UInt8>? = nil) -> Refusal {
            Refusal(kind, message, field: field, text: text.map { string($0) }, catalogField: catalogField)
        }
        for (n, line) in [(1, l1), (2, l2)] {
            guard line.count == 69 else { throw refuse(.lineLength, "line \(n) is \(line.count) characters, not 69") }
            guard line.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) else { throw refuse(.lineLength, "line \(n) holds a character outside printable ASCII") }
            guard line[0] == 0x30 + UInt8(n), line[1] == 0x20 else { throw refuse(.layout, "line \(n) does not begin \"\(n) \"") }
            let computed = TLE.checksum(line[...])
            guard checksum == .ignore || line[68] == 0x30 + UInt8(computed) else {
                throw refuse(.checksum, "line \(n)'s checksum is \(string(line[68...])), and the line computes to \(computed)", field: "checksum", text: line[68...])
            }
        }
        // a refusal from a helper, with this set's catalog field added
        func placed<T>(_ body: () throws(Refusal) -> T) throws(Refusal) -> T {
            do throws(Refusal) {
                return try body()
            } catch {
                throw error.located(record: nil, line: nil, catalogField: catalogField)
            }
        }
        let catalogNumber = try placed { () throws(Refusal) -> Int in try Alpha5.decode(l1[2..<7]) }
        guard try placed({ () throws(Refusal) -> Int in try Alpha5.decode(l2[2..<7]) }) == catalogNumber else {
            throw refuse(.catalogNumber, "the catalog fields differ: \"\(string(l1[2..<7]))\" on line 1, \"\(string(l2[2..<7]))\" on line 2",
                         field: "catalog number", text: l2[2..<7])
        }
        for column in [8, 17, 32, 43, 52, 61, 63] where l1[column] != 0x20 {
            throw refuse(.layout, "line 1 column \(column + 1) is \"\(string(l1[column...column]))\", where the format has a space", field: "separator", text: l1[column...column])
        }
        for column in [7, 16, 25, 33, 42, 51] where l2[column] != 0x20 {
            throw refuse(.layout, "line 2 column \(column + 1) is \"\(string(l2[column...column]))\", where the format has a space", field: "separator", text: l2[column...column])
        }
        guard l1[7].isUppercaseLetter else {
            throw refuse(.notText, "the classification \"\(string(l1[7...7]))\" is not an uppercase letter", field: "classification", text: l1[7...7])
        }

        func number<T>(_ value: T?, _ what: String, _ text: ArraySlice<UInt8>) throws(Refusal) -> T {
            guard let value else { throw refuse(.notANumber, "the \(what) field \"\(string(text))\" is not a number in the field's form", field: what, text: text) }
            return value
        }
        let epoch = try placed { () throws(Refusal) -> Epoch in try epochField(l1[18..<32]) }
        let designator = try placed { () throws(Refusal) -> String? in try objectID(fromDesignator: l1[9..<17]) }
        let ephemerisType: Int = l1[62] == 0x20 ? 0 : try number(l1[62].isDigit ? l1[62].digitValue : nil, "ephemeris type", l1[62...62])
        var objectName: String?
        if var bytes = name.map({ trimmed($0) }) {
            if bytes.starts(with: [0x30, 0x20]) { bytes = trimmed(bytes.dropFirst(2)) }
            if !bytes.isEmpty { objectName = string(bytes) }
        }
        var set = ElementSet(
            catalogNumber: catalogNumber,
            objectName: objectName,
            objectID: designator,
            classification: string(l1[7...7]),
            epoch: epoch,
            meanMotion: try number(fixedPoint(l2[52..<63], decimals: 8), "mean motion", l2[52..<63]),
            eccentricity: try number(l2[26..<33].allSatisfy(\.isDigit) ? ExactDecimal(negative: false, digits: l2[26..<33].map { UInt8($0.digitValue) }, exponent: -7) : nil,
                                     "eccentricity", l2[26..<33]),
            inclination: try number(fixedPoint(l2[8..<16], decimals: 4), "inclination", l2[8..<16]),
            rightAscension: try number(fixedPoint(l2[17..<25], decimals: 4), "right ascension", l2[17..<25]),
            argumentOfPericenter: try number(fixedPoint(l2[34..<42], decimals: 4), "argument of pericenter", l2[34..<42]),
            meanAnomaly: try number(fixedPoint(l2[43..<51], decimals: 4), "mean anomaly", l2[43..<51]),
            bstar: try number(exponentField(l1[53..<61]), "BSTAR", l1[53..<61]),
            meanMotionDot: try number(firstDerivative(l1[33..<43]), "first derivative", l1[33..<43]),
            meanMotionDDot: try number(exponentField(l1[44..<52]), "second derivative", l1[44..<52]),
            ephemerisType: ephemerisType,
            elementSetNumber: try number(rightJustified(l1[64..<68]), "element set number", l1[64..<68]),
            revolutionAtEpoch: try number(rightJustified(l2[63..<68]), "revolution number", l2[63..<68]))
        set.source = .tle
        return set
    }

    /// `nnn.nnnn`, right-justified: spaces, digits, a point, exactly `decimals` digits.
    static func fixedPoint(_ field: ArraySlice<UInt8>, decimals: Int) -> ExactDecimal? {
        let body = field.drop(while: { $0 == 0x20 })
        guard let point = body.firstIndex(of: 0x2E) else { return nil }
        let whole = body[..<point], fraction = body[(point + 1)...]
        guard !whole.isEmpty, whole.allSatisfy(\.isDigit), fraction.count == decimals, fraction.allSatisfy(\.isDigit) else { return nil }
        return ExactDecimal(negative: false, digits: (whole + fraction).map { UInt8($0.digitValue) }, exponent: -decimals)
    }

    /// `s.dddddddd`: a sign or a space, a point, eight digits.
    static func firstDerivative(_ field: ArraySlice<UInt8>) -> ExactDecimal? {
        let f = Array(field)
        guard f.count == 10, f[0] == 0x20 || f[0] == 0x2B || f[0] == 0x2D, f[1] == 0x2E, f[2...].allSatisfy(\.isDigit) else { return nil }
        return ExactDecimal(negative: f[0] == 0x2D, digits: f[2...].map { UInt8($0.digitValue) }, exponent: -8)
    }

    /// `sdddddsd`: a sign or a space, five digits with the decimal point implied before them, a signed one-digit
    /// power of ten.
    static func exponentField(_ field: ArraySlice<UInt8>) -> ExactDecimal? {
        let f = Array(field)
        guard f.count == 8, f[0] == 0x20 || f[0] == 0x2B || f[0] == 0x2D, f[1..<6].allSatisfy(\.isDigit),
              f[6] == 0x2B || f[6] == 0x2D, f[7].isDigit else { return nil }
        let power = f[6] == 0x2D ? -f[7].digitValue : f[7].digitValue
        return ExactDecimal(negative: f[0] == 0x2D, digits: f[1..<6].map { UInt8($0.digitValue) }, exponent: power - 5)
    }

    /// Spaces, then digits to the end of the field.
    static func rightJustified(_ field: ArraySlice<UInt8>) -> Int? {
        unsignedInteger(field.drop(while: { $0 == 0x20 }), plusAllowed: false)
    }

    /// `YYDDD.DDDDDDDD`: every digit in place. The eight-decimal day is an exact number of microseconds.
    static func epochField(_ field: ArraySlice<UInt8>) throws(Refusal) -> Epoch {
        let f = Array(field)
        guard f.count == 14, f[0..<5].allSatisfy(\.isDigit), f[5] == 0x2E, f[6...].allSatisfy(\.isDigit) else {
            throw Refusal(.notAnEpoch, "the epoch field \"\(string(field))\" is not YYDDD.DDDDDDDD", field: "epoch", text: string(field))
        }
        let year = fullYear(twoDigit: f[0].digitValue * 10 + f[1].digitValue)
        let day = f[2..<5].reduce(0) { $0 * 10 + $1.digitValue }
        let microseconds = f[6...].reduce(0) { $0 * 10 + $1.digitValue } * 864
        do throws(Refusal) {
            return try Epoch(year: year, dayOfYear: day, hour: microseconds / 3_600_000_000, minute: microseconds / 60_000_000 % 60,
                             second: microseconds / 1_000_000 % 60, attosecond: UInt64(microseconds % 1_000_000) * 1_000_000_000_000)
        } catch {
            throw Refusal(.notAnEpoch, "the epoch field \"\(string(field))\": day \(day) is not a day of \(year)", field: "epoch", text: string(field))
        }
    }

    /// Columns 10 to 17, `YYNNNPPP`, as the OMM's `OBJECT_ID`, `YYYY-NNNPPP`; nil for a blank field.
    static func objectID(fromDesignator field: ArraySlice<UInt8>) throws(Refusal) -> String? {
        var body = field
        while body.last == 0x20 { body = body.dropLast() }
        guard !body.isEmpty else { return nil }
        let b = Array(body)
        guard b.count >= 5, b[0..<5].allSatisfy(\.isDigit), b[5...].allSatisfy(\.isUppercaseLetter) else {
            throw Refusal(.notText, "the international designator \"\(string(field))\" is not a two-digit year, a three-digit launch number and up to three letters",
                          field: "international designator", text: string(field))
        }
        return "\(fullYear(twoDigit: b[0].digitValue * 10 + b[1].digitValue))-\(string(b[2...]))"
    }

    /// Reads a file of element sets, with or without name lines. Each line 1 followed by a line 2 is a set, read
    /// or refused; a line 1 or a line 2 on its own is refused; a line that is neither, and is not the name of the
    /// set after it, is refused as a stray line. Reading goes on after every refusal.
    static func readFile(_ bytes: [UInt8], checksum: Checksum) -> [ElementSetFile.Entry] {
        let lines = splitLines(bytes)
        func kind(_ line: ArraySlice<UInt8>) -> Int {
            line.starts(with: [0x31, 0x20]) ? 1 : (line.starts(with: [0x32, 0x20]) ? 2 : 0)
        }
        func field(_ line: ArraySlice<UInt8>) -> String? {
            line.count >= 7 ? string(line.dropFirst(2).prefix(5)) : nil
        }
        var entries: [ElementSetFile.Entry] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let record = entries.count
            switch kind(line) {
            case 1 where i + 1 < lines.count && kind(lines[i + 1]) == 2:
                let name = i > 0 && kind(lines[i - 1]) == 0 && !trimmed(lines[i - 1]).isEmpty ? lines[i - 1] : nil
                do throws(Refusal) {
                    entries.append(.elementSet(try parse(name: name, line1: line, line2: lines[i + 1], checksum: checksum)))
                } catch {
                    entries.append(.refusal(error.located(record: record, line: i + 1, catalogField: field(line))))
                }
                i += 2
            case 1:
                entries.append(.refusal(Refusal(.missingLine2, "a line 1 with no line 2 after it", catalogField: field(line), record: record, line: i + 1)))
                i += 1
            case 2:
                entries.append(.refusal(Refusal(.missingLine1, "a line 2 with no line 1 before it", catalogField: field(line), record: record, line: i + 1)))
                i += 1
            default:
                let isName = i + 1 < lines.count && kind(lines[i + 1]) == 1
                if !isName && !trimmed(line).isEmpty {
                    entries.append(.refusal(Refusal(.strayLine, "a line that is neither an element line nor the name of the set after it",
                                                    text: string(line.prefix(80)), record: record, line: i + 1)))
                }
                i += 1
            }
        }
        return entries
    }

    // MARK: - Writing

    /// Two lines, or three with a name.
    public struct Lines: Sendable, Hashable {
        public let name: String?
        public let line1: String
        public let line2: String

        /// The lines joined by line feeds, the name first when there is one.
        public var text: String {
            (name.map { [$0] } ?? []).appending(contentsOf: [line1, line2]).joined(separator: "\n")
        }
    }

    /// How a value with more digits than its field is brought to the field's resolution.
    public enum Resolution: Sendable {
        /// Rounded to the nearest, a half going up.
        case rounded
        /// Cut off. CelesTrak writes the eccentricity this way.
        case truncated
    }

    /// Writes an element set as a TLE. The catalog field is five digits below 100000 and Alpha-5 from 100000 to
    /// 339999. Every value is brought to its field's resolution exactly, in decimal: angles and the mean motion
    /// rounded, BSTAR and the second derivative to a five-digit mantissa, the epoch to a hundred-millionth of a day.
    ///
    /// Refused, never approximated: a catalog number that is missing, negative or above 339999; an epoch outside
    /// 1957 to 2056; any value wider than its columns. A missing classification is written `U`, and a missing
    /// ephemeris type, element set number or revolution number as 0.
    public static func write(_ set: ElementSet, eccentricity: Resolution = .rounded) throws(Refusal) -> Lines {
        func refuse(_ message: String, field: String, text: String? = nil) -> Refusal {
            Refusal(.cannotEncode, message, field: field, text: text, catalogField: set.catalogNumber.map { String($0) })
        }
        guard let number = set.catalogNumber else { throw refuse("the element set has no catalog number", field: "catalog number") }
        let catalog = try Alpha5.encode(number)

        let classification = Array((set.classification ?? "U").utf8)
        guard classification.count == 1, classification[0].isUppercaseLetter else {
            throw refuse("the classification \"\(set.classification ?? "")\" is not one uppercase letter", field: "classification", text: set.classification)
        }

        var designator = Array(repeating: UInt8(0x20), count: 8)
        if let id = set.objectID {
            let b = Array(id.utf8)
            guard b.count >= 9, b.count <= 11, b[0..<4].allSatisfy(\.isDigit), b[4] == 0x2D, b[5..<8].allSatisfy(\.isDigit),
                  b[8...].allSatisfy(\.isUppercaseLetter) else {
                throw refuse("the object id \"\(id)\" is not YYYY-NNN and one to three letters", field: "OBJECT_ID", text: id)
            }
            let year = b[0..<4].reduce(0) { $0 * 10 + $1.digitValue }
            guard fullYear(twoDigit: year % 100) == year else {
                throw refuse("the object id's year \(year) is outside 1957 to 2056, the years two digits can stand for", field: "OBJECT_ID", text: id)
            }
            designator = Array(b[2..<4] + b[5...])
            designator += Array(repeating: 0x20, count: 8 - designator.count)
        }

        var year = set.epoch.year
        var day = set.epoch.dayOfYear
        var fraction = (set.epoch.microsecondOfDay + 432) / 864   // hundred-millionths of a day, a half going up
        if fraction >= 100_000_000 {
            fraction -= 100_000_000
            day += 1
            if day > Epoch.days(in: year) {
                day = 1
                year += 1
            }
        }
        guard fullYear(twoDigit: year % 100) == year else {
            throw refuse("the epoch's year \(year) is outside 1957 to 2056, the years two digits can stand for", field: "EPOCH", text: set.epoch.description)
        }

        func fixed(_ value: ExactDecimal, places: Int, width: Int, _ keyword: String) throws(Refusal) -> String {
            guard !value.isNegative else { throw refuse("\(keyword) \(value) is negative, and the field has no sign", field: keyword, text: value.description) }
            var digits = value.scaled(byTenTo: places, .halfUp).map { $0 + 0x30 }
            while digits.count < places + 1 { digits.insert(0x30, at: 0) }
            guard digits.count + 1 <= width else { throw refuse("\(keyword) \(value) is wider than the field's \(width) columns", field: keyword, text: value.description) }
            let text = digits[..<(digits.count - places)] + [0x2E] + digits[(digits.count - places)...]
            return string(Array(repeating: 0x20, count: width - text.count) + text)
        }

        func exponent(_ value: ExactDecimal, _ keyword: String) throws(Refusal) -> String {
            guard !value.isZero else { return " 00000+0" }
            // the value is 0.<digits> times ten to `power`
            var power = value.digits.count + value.exponent
            var mantissa = Array(value.digits.prefix(5))
            mantissa += Array(repeating: 0, count: 5 - mantissa.count)
            if value.digits.count > 5 && value.digits[5] >= 5 {
                var i = 4
                var carried = true
                while carried && i >= 0 {
                    if mantissa[i] == 9 { mantissa[i] = 0 } else { mantissa[i] += 1; carried = false }
                    i -= 1
                }
                if carried {
                    mantissa = [1, 0, 0, 0, 0]
                    power += 1
                }
            }
            guard (-9...9).contains(power) else { throw refuse("\(keyword) \(value) needs a power of ten the field's one digit cannot hold", field: keyword, text: value.description) }
            return (value.isNegative ? "-" : " ") + string(mantissa.map { $0 + 0x30 }) + (power < 0 ? "-" : "+") + String(abs(power))
        }

        let dot = set.meanMotionDot.scaled(byTenTo: 8, .halfUp)
        guard dot.count <= 8 else { throw refuse("MEAN_MOTION_DOT \(set.meanMotionDot) is 1 or more, and the field holds a fraction", field: "MEAN_MOTION_DOT", text: set.meanMotionDot.description) }
        let firstDerivative = (set.meanMotionDot.isNegative ? "-" : " ") + "." + string(Array(repeating: 0x30, count: 8 - dot.count) + dot.map { $0 + 0x30 })

        guard !set.eccentricity.isNegative else { throw refuse("ECCENTRICITY \(set.eccentricity) is negative", field: "ECCENTRICITY", text: set.eccentricity.description) }
        let ecc = set.eccentricity.scaled(byTenTo: 7, eccentricity == .rounded ? .halfUp : .down)
        guard ecc.count <= 7 else { throw refuse("ECCENTRICITY \(set.eccentricity) is 1 or more at the field's seven digits", field: "ECCENTRICITY", text: set.eccentricity.description) }

        let ephemerisType = set.ephemerisType ?? 0
        guard (0...9).contains(ephemerisType) else { throw refuse("EPHEMERIS_TYPE \(ephemerisType) is not one digit", field: "EPHEMERIS_TYPE", text: String(ephemerisType)) }
        let elementSet = set.elementSetNumber ?? 0
        guard (0...9999).contains(elementSet) else { throw refuse("ELEMENT_SET_NO \(elementSet) does not fit the field's four columns", field: "ELEMENT_SET_NO", text: String(elementSet)) }
        let revolution = set.revolutionAtEpoch ?? 0
        guard (0...99999).contains(revolution) else { throw refuse("REV_AT_EPOCH \(revolution) does not fit the field's five columns", field: "REV_AT_EPOCH", text: String(revolution)) }

        var name: String?
        if let objectName = set.objectName {
            guard objectName.utf8.allSatisfy({ $0 >= 0x20 && $0 != 0x7F }) else { throw refuse("the object name holds a control character", field: "OBJECT_NAME", text: objectName) }
            name = objectName
        }

        var line1 = "1 \(catalog)\(string(classification)) \(string(designator)) \(padded(year % 100, width: 2))\(padded(day, width: 3)).\(padded(fraction, width: 8))"
        line1 += " \(firstDerivative) \(try exponent(set.meanMotionDDot, "MEAN_MOTION_DDOT")) \(try exponent(set.bstar, "BSTAR"))"
        line1 += " \(ephemerisType) \(padded(elementSet, width: 4, with: " "))"
        var line2 = "2 \(catalog) \(try fixed(set.inclination, places: 4, width: 8, "INCLINATION")) \(try fixed(set.rightAscension, places: 4, width: 8, "RA_OF_ASC_NODE"))"
        line2 += " \(string(Array(repeating: 0x30, count: 7 - ecc.count) + ecc.map { $0 + 0x30 }))"
        line2 += " \(try fixed(set.argumentOfPericenter, places: 4, width: 8, "ARG_OF_PERICENTER")) \(try fixed(set.meanAnomaly, places: 4, width: 8, "MEAN_ANOMALY"))"
        line2 += " \(try fixed(set.meanMotion, places: 8, width: 11, "MEAN_MOTION"))\(padded(revolution, width: 5, with: " "))"
        line1 += String(checksum(of: line1))
        line2 += String(checksum(of: line2))
        return Lines(name: name, line1: line1, line2: line2)
    }
}

private extension Array {
    func appending(contentsOf other: [Element]) -> [Element] { self + other }
}
