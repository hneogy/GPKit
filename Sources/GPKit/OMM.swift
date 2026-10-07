/// The Orbit Mean-Elements Message: what its keywords must hold, shared by the four readers.
public enum OMM {

    /// Reads a `NORAD_CAT_ID`: an integer of up to nine digits, leading zeros and a plus sign allowed (CCSDS
    /// 502.0-B-3, table 4-3 and 7.5.4). Alpha-5 is a TLE encoding and is refused here, as are ten digits, a
    /// decimal point and the empty string.
    public static func catalogNumber(_ text: String) throws(Refusal) -> Int {
        try catalogNumber(Array(text.utf8)[...])
    }

    static func catalogNumber(_ text: ArraySlice<UInt8>) throws(Refusal) -> Int {
        guard let value = unsignedInteger(text, plusAllowed: true, maxDigits: 9) else {
            throw Refusal(.catalogNumber, "NORAD_CAT_ID \"\(string(text))\" is not an integer of up to nine digits", field: "NORAD_CAT_ID",
                          text: string(text), catalogField: string(text))
        }
        return value
    }

    static let decimalKeywords: Set<String> = ["MEAN_MOTION", "ECCENTRICITY", "INCLINATION", "RA_OF_ASC_NODE", "ARG_OF_PERICENTER",
                                               "MEAN_ANOMALY", "BSTAR", "MEAN_MOTION_DOT", "MEAN_MOTION_DDOT", "SEMI_MAJOR_AXIS", "GM",
                                               "MASS", "SOLAR_RAD_AREA", "SOLAR_RAD_COEFF", "DRAG_AREA", "DRAG_COEFF", "BTERM", "AGOM"]

    /// One record's keywords and their text, in the order the source gave them.
    struct Fields {
        private(set) var order: [String] = []
        private(set) var values: [String: ArraySlice<UInt8>] = [:]

        /// Adds a keyword. False when the record already has it.
        mutating func add(_ keyword: String, _ value: ArraySlice<UInt8>) -> Bool {
            guard values[keyword] == nil else { return false }
            order.append(keyword)
            values[keyword] = trimmed(value)
            return true
        }

        /// The keyword's text, nil when the keyword is absent or empty.
        subscript(_ keyword: String) -> ArraySlice<UInt8>? {
            values[keyword].flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// The element set a record's keywords describe, or the first thing that keeps them from being one.
    static func elementSet(from fields: Fields, format: Format) throws(Refusal) -> ElementSet {
        let catalogField = fields["NORAD_CAT_ID"].map { string($0) }
        func refuse(_ kind: Refusal.Kind, _ message: String, _ keyword: String, _ text: ArraySlice<UInt8>? = nil) -> Refusal {
            Refusal(kind, message, field: keyword, text: text.map { string($0) }, catalogField: catalogField)
        }
        func decimal(_ keyword: String) throws(Refusal) -> ExactDecimal {
            guard let text = fields[keyword] else { throw refuse(.missingKeyword, "\(keyword) is missing or empty", keyword) }
            guard let value = ExactDecimal(utf8: text) else { throw refuse(.notANumber, "\(keyword) \"\(string(text))\" is not a number", keyword, text) }
            return value
        }
        func counter(_ keyword: String) throws(Refusal) -> Int? {
            guard let text = fields[keyword] else { return nil }
            guard let value = unsignedInteger(text, plusAllowed: true) else {
                throw refuse(.notAnInteger, "\(keyword) \"\(string(text))\" is not a non-negative integer", keyword, text)
            }
            return value
        }
        func text(_ keyword: String) -> String? {
            fields[keyword].map { string($0) }
        }

        var catalogNumber: Int?
        if let text = fields["NORAD_CAT_ID"] { catalogNumber = try OMM.catalogNumber(text) }
        guard let epochText = fields["EPOCH"] else { throw refuse(.missingKeyword, "EPOCH is missing or empty", "EPOCH") }
        let epoch: Epoch
        do throws(Refusal) {
            epoch = try Epoch(ccsds: epochText)
        } catch {
            throw error.located(record: nil, line: nil, catalogField: catalogField)
        }
        var set = ElementSet(
            catalogNumber: catalogNumber,
            objectName: text("OBJECT_NAME"),
            objectID: text("OBJECT_ID"),
            classification: text("CLASSIFICATION_TYPE"),
            epoch: epoch,
            meanMotion: try decimal("MEAN_MOTION"),
            eccentricity: try decimal("ECCENTRICITY"),
            inclination: try decimal("INCLINATION"),
            rightAscension: try decimal("RA_OF_ASC_NODE"),
            argumentOfPericenter: try decimal("ARG_OF_PERICENTER"),
            meanAnomaly: try decimal("MEAN_ANOMALY"),
            bstar: try decimal("BSTAR"),
            meanMotionDot: try decimal("MEAN_MOTION_DOT"),
            meanMotionDDot: try decimal("MEAN_MOTION_DDOT"),
            ephemerisType: try counter("EPHEMERIS_TYPE"),
            elementSetNumber: try counter("ELEMENT_SET_NO"),
            revolutionAtEpoch: try counter("REV_AT_EPOCH"),
            centerName: text("CENTER_NAME"),
            referenceFrame: text("REF_FRAME"),
            timeSystem: text("TIME_SYSTEM"),
            meanElementTheory: text("MEAN_ELEMENT_THEORY"))
        set.source = format
        let read: Set<String> = ["NORAD_CAT_ID", "OBJECT_NAME", "OBJECT_ID", "CLASSIFICATION_TYPE", "EPOCH", "MEAN_MOTION", "ECCENTRICITY",
                                 "INCLINATION", "RA_OF_ASC_NODE", "ARG_OF_PERICENTER", "MEAN_ANOMALY", "BSTAR", "MEAN_MOTION_DOT",
                                 "MEAN_MOTION_DDOT", "EPHEMERIS_TYPE", "ELEMENT_SET_NO", "REV_AT_EPOCH", "CENTER_NAME", "REF_FRAME",
                                 "TIME_SYSTEM", "MEAN_ELEMENT_THEORY"]
        for keyword in fields.order where !read.contains(keyword) {
            if let value = fields[keyword] { set.otherKeywords[keyword] = string(value) }
        }
        return set
    }

    /// A record's entry: the element set, or its refusal placed in the file.
    static func entry(_ fields: Fields, format: Format, record: Int, line: Int?) -> ElementSetFile.Entry {
        do throws(Refusal) {
            return .elementSet(try elementSet(from: fields, format: format))
        } catch {
            return .refusal(error.located(record: record, line: line, catalogField: fields["NORAD_CAT_ID"].map { string($0) }))
        }
    }
}
