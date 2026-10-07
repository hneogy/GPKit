import GPKit

// The element set the tests read and write: the International Space Station's first record, as the gpconf corpus
// publishes it in its derived files (derived/corrupt-input/unedited-sets.tle and derived/kvn-variants/, MIT).
enum Sample {
    static let name = "ISS (ZARYA)             "
    static let line1 = "1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    10"
    static let line2 = "2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05"
    static let tle = [name, line1, line2].joined(separator: "\r\n") + "\r\n"

    static let kvn = """
    CCSDS_OMM_VERS      = 2.0
    CREATION_DATE       =
    ORIGINATOR          =

    OBJECT_NAME         = ISS (ZARYA)
    OBJECT_ID           = 1998-067A
    CENTER_NAME         = EARTH
    REF_FRAME           = TEME
    TIME_SYSTEM         = UTC
    MEAN_ELEMENT_THEORY = SGP/SGP4

    EPOCH               = 1998-11-20T06:49:59.999808
    MEAN_MOTION         = 16.05064833
    ECCENTRICITY        = .0125362
    INCLINATION         = 51.5908
    RA_OF_ASC_NODE      = 168.3788
    ARG_OF_PERICENTER   = 86.4185
    MEAN_ANOMALY        = 359.7454

    EPHEMERIS_TYPE      = 0
    CLASSIFICATION_TYPE = U
    NORAD_CAT_ID        = 25544
    ELEMENT_SET_NO      = 1
    REV_AT_EPOCH        = 0
    BSTAR               = 0
    MEAN_MOTION_DOT     = -.3657E-4
    MEAN_MOTION_DDOT    = .11563E-4

    """

    static let csvHeader = "OBJECT_NAME,OBJECT_ID,EPOCH,MEAN_MOTION,ECCENTRICITY,INCLINATION,RA_OF_ASC_NODE,ARG_OF_PERICENTER,MEAN_ANOMALY,EPHEMERIS_TYPE,CLASSIFICATION_TYPE,NORAD_CAT_ID,ELEMENT_SET_NO,REV_AT_EPOCH,BSTAR,MEAN_MOTION_DOT,MEAN_MOTION_DDOT"
    static let csvRow = "ISS (ZARYA),1998-067A,1998-11-20T06:49:59.999808,16.05064833,.0125362,51.5908,168.3788,86.4185,359.7454,0,U,25544,1,0,0,-.3657E-4,.11563E-4"
    static let csv = csvHeader + "\r\n" + csvRow + "\r\n"

    static func jsonRecord(catalog: String = "25544", objectID: String = "\"1998-067A\"") -> String {
        """
        {"OBJECT_NAME":"ISS (ZARYA)","OBJECT_ID":\(objectID),"EPOCH":"1998-11-20T06:49:59.999808","MEAN_MOTION":16.05064833,\
        "ECCENTRICITY":0.0125362,"INCLINATION":51.5908,"RA_OF_ASC_NODE":168.3788,"ARG_OF_PERICENTER":86.4185,\
        "MEAN_ANOMALY":359.7454,"EPHEMERIS_TYPE":0,"CLASSIFICATION_TYPE":"U","NORAD_CAT_ID":\(catalog),"ELEMENT_SET_NO":1,\
        "REV_AT_EPOCH":0,"BSTAR":0,"MEAN_MOTION_DOT":-3.657e-5,"MEAN_MOTION_DDOT":1.1563e-5}
        """
    }
    static let json = "[" + jsonRecord() + "]"

    static func xml(root: String = "ndm", omm: String = "omm", objectID: String = "<OBJECT_ID>1998-067A</OBJECT_ID>") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <\(root) xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <!-- one message -->
        <\(omm) id="CCSDS_OMM_VERS" version="2.0">
        <header><CREATION_DATE/><ORIGINATOR/></header><body><segment><metadata><OBJECT_NAME>ISS (ZARYA)</OBJECT_NAME>\(objectID)\
        <CENTER_NAME>EARTH</CENTER_NAME><REF_FRAME>TEME</REF_FRAME><TIME_SYSTEM>UTC</TIME_SYSTEM>\
        <MEAN_ELEMENT_THEORY>SGP4</MEAN_ELEMENT_THEORY></metadata><data><meanElements><EPOCH>1998-11-20T06:49:59.999808</EPOCH>\
        <MEAN_MOTION>16.05064833</MEAN_MOTION><ECCENTRICITY>.0125362</ECCENTRICITY><INCLINATION>51.5908</INCLINATION>\
        <RA_OF_ASC_NODE>168.3788</RA_OF_ASC_NODE><ARG_OF_PERICENTER>86.4185</ARG_OF_PERICENTER><MEAN_ANOMALY>359.7454</MEAN_ANOMALY>\
        </meanElements><tleParameters><EPHEMERIS_TYPE>0</EPHEMERIS_TYPE><CLASSIFICATION_TYPE>U</CLASSIFICATION_TYPE>\
        <NORAD_CAT_ID>25544</NORAD_CAT_ID><ELEMENT_SET_NO>1</ELEMENT_SET_NO><REV_AT_EPOCH>0</REV_AT_EPOCH><BSTAR>0</BSTAR>\
        <MEAN_MOTION_DOT>-.3657E-4</MEAN_MOTION_DOT><MEAN_MOTION_DDOT>.11563E-4</MEAN_MOTION_DDOT></tleParameters>\
        <userDefinedParameters><USER_DEFINED parameter="NOTE">a &amp; b</USER_DEFINED></userDefinedParameters></data></segment></body></\(omm)>
        </\(root)>
        """
    }
}

/// The one element set of a file that holds exactly one, read without a refusal.
func only(_ text: String, _ format: Format) throws -> ElementSet {
    let file = try ElementSets.read(text, as: format)
    guard file.refusals.isEmpty, file.elementSets.count == 1 else { throw Refusal(.malformedFile, "expected one element set and no refusal: \(file)") }
    return file.elementSets[0]
}

/// The refusal a call ends with, or nil when it does not refuse.
func refusal(_ body: () throws -> Void) -> Refusal? {
    do {
        try body()
        return nil
    } catch {
        return error as? Refusal
    }
}

/// A line with its last character replaced by the checksum the rest computes to.
func withChecksum(_ line: String) -> String {
    String(line.dropLast()) + String(TLE.checksum(of: line))
}

func replacing(_ line: String, _ range: Range<Int>, with text: String) -> String {
    let c = Array(line)
    return String(c[..<range.lowerBound]) + text + String(c[range.upperBound...])
}

/// The characters of a line at the given columns, counted from 0.
func columns(_ line: String, _ range: Range<Int>) -> String {
    String(Array(line)[range])
}
