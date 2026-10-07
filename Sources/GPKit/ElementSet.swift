/// One GP element set: the record an OMM carries, whichever format it arrived in.
///
/// The properties are the OMM's keywords, in the OMM's units, holding what the source wrote. A set read from a TLE
/// has the same shape: the TLE is a way in, not the model.
public struct ElementSet: Sendable, Hashable {

    // MARK: Identity

    /// `NORAD_CAT_ID`: a plain integer, 0 to 999,999,999, whatever its width. A TLE's Alpha-5 field is decoded on
    /// the way in and never kept. nil only for an OMM that omits the keyword, which the standard allows.
    public var catalogNumber: Int?
    /// `OBJECT_NAME`. nil when the source has none or leaves it empty.
    public var objectName: String?
    /// `OBJECT_ID`, the international designator in the OMM's form, `1998-067A`. nil when the source has none or
    /// leaves it empty, as analyst objects do.
    public var objectID: String?
    /// `CLASSIFICATION_TYPE`: `U`, or what the source wrote.
    public var classification: String?

    // MARK: Mean elements

    /// `EPOCH`.
    public var epoch: Epoch
    /// `MEAN_MOTION`, revolutions per day, as written: the Kozai mean motion of the TLE.
    public var meanMotion: ExactDecimal
    /// `ECCENTRICITY`.
    public var eccentricity: ExactDecimal
    /// `INCLINATION`, degrees.
    public var inclination: ExactDecimal
    /// `RA_OF_ASC_NODE`, degrees.
    public var rightAscension: ExactDecimal
    /// `ARG_OF_PERICENTER`, degrees.
    public var argumentOfPericenter: ExactDecimal
    /// `MEAN_ANOMALY`, degrees.
    public var meanAnomaly: ExactDecimal

    // MARK: TLE parameters

    /// `BSTAR`, per Earth radius.
    public var bstar: ExactDecimal
    /// `MEAN_MOTION_DOT`, revolutions per day squared: the value a TLE prints, which is half the first derivative.
    public var meanMotionDot: ExactDecimal
    /// `MEAN_MOTION_DDOT`, revolutions per day cubed: the value a TLE prints, a sixth of the second derivative.
    public var meanMotionDDot: ExactDecimal
    /// `EPHEMERIS_TYPE`. nil for an OMM that omits it.
    public var ephemerisType: Int?
    /// `ELEMENT_SET_NO`. nil for an OMM that omits it.
    public var elementSetNumber: Int?
    /// `REV_AT_EPOCH`. nil for an OMM that omits it.
    public var revolutionAtEpoch: Int?

    // MARK: Metadata

    /// `CENTER_NAME`. `EARTH` when the source does not say.
    public var centerName: String
    /// `REF_FRAME`. `TEME` when the source does not say.
    public var referenceFrame: String
    /// `TIME_SYSTEM`. `UTC` when the source does not say.
    public var timeSystem: String
    /// `MEAN_ELEMENT_THEORY`, as written: providers use both `SGP4` and `SGP/SGP4`. `SGP4` when the source does
    /// not say.
    public var meanElementTheory: String
    /// Which of the four keywords above the source did not carry, so that the value here is GPKit's default and
    /// not the source's word. CelesTrak's CSV and JSON omit all four, and so does every TLE.
    public var defaulted: Set<String>
    /// Every other keyword the record carried with a value, as text: `CCSDS_OMM_VERS`, `CREATION_DATE`, a
    /// supplemental file's extra columns, an XML record's `USER_DEFINED_` parameters.
    public var otherKeywords: [String: String]
    /// The format the set was read from. nil for a set built in code.
    public var source: Format?

    public static let defaultCenterName = "EARTH"
    public static let defaultReferenceFrame = "TEME"
    public static let defaultTimeSystem = "UTC"
    public static let defaultMeanElementTheory = "SGP4"
    static let metadataDefaults = ["CENTER_NAME": defaultCenterName, "REF_FRAME": defaultReferenceFrame,
                                   "TIME_SYSTEM": defaultTimeSystem, "MEAN_ELEMENT_THEORY": defaultMeanElementTheory]

    /// True when the record is for SGP4, under either spelling.
    public var isSGP4: Bool { meanElementTheory == "SGP4" || meanElementTheory == "SGP/SGP4" }

    public init(catalogNumber: Int?, objectName: String? = nil, objectID: String? = nil, classification: String? = nil,
                epoch: Epoch, meanMotion: ExactDecimal, eccentricity: ExactDecimal, inclination: ExactDecimal,
                rightAscension: ExactDecimal, argumentOfPericenter: ExactDecimal, meanAnomaly: ExactDecimal,
                bstar: ExactDecimal = .zero, meanMotionDot: ExactDecimal = .zero, meanMotionDDot: ExactDecimal = .zero,
                ephemerisType: Int? = nil, elementSetNumber: Int? = nil, revolutionAtEpoch: Int? = nil,
                centerName: String? = nil, referenceFrame: String? = nil, timeSystem: String? = nil,
                meanElementTheory: String? = nil, otherKeywords: [String: String] = [:]) {
        self.catalogNumber = catalogNumber
        self.objectName = objectName
        self.objectID = objectID
        self.classification = classification
        self.epoch = epoch
        self.meanMotion = meanMotion
        self.eccentricity = eccentricity
        self.inclination = inclination
        self.rightAscension = rightAscension
        self.argumentOfPericenter = argumentOfPericenter
        self.meanAnomaly = meanAnomaly
        self.bstar = bstar
        self.meanMotionDot = meanMotionDot
        self.meanMotionDDot = meanMotionDDot
        self.ephemerisType = ephemerisType
        self.elementSetNumber = elementSetNumber
        self.revolutionAtEpoch = revolutionAtEpoch
        self.centerName = centerName ?? ElementSet.defaultCenterName
        self.referenceFrame = referenceFrame ?? ElementSet.defaultReferenceFrame
        self.timeSystem = timeSystem ?? ElementSet.defaultTimeSystem
        self.meanElementTheory = meanElementTheory ?? ElementSet.defaultMeanElementTheory
        var defaulted: Set<String> = []
        if centerName == nil { defaulted.insert("CENTER_NAME") }
        if referenceFrame == nil { defaulted.insert("REF_FRAME") }
        if timeSystem == nil { defaulted.insert("TIME_SYSTEM") }
        if meanElementTheory == nil { defaulted.insert("MEAN_ELEMENT_THEORY") }
        self.defaulted = defaulted
        self.otherKeywords = otherKeywords
    }
}
