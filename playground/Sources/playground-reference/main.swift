// playground-reference SETS-FILE OUT-FILE: the playground's answers worked out natively, by the same PlaygroundAnswers
// code the WebAssembly module runs, for a fixed list of calls; playground/test/equal.mjs makes the same calls on the
// module under Node's WASI and holds every answer equal to these, byte for byte (so every number with ==).
//
// The calls: every text below read; for each element set in it and each place, where it is at its epoch, an hour
// and a day on, and its passes over the next day above 0° and above 10°. Each number handed to a call is written as
// Swift writes it (shortest form that reads back the same), so the script hands the module the very same Double.
import Foundation
import PlaygroundAnswers

let arguments = CommandLine.arguments
guard arguments.count == 3, let sets = FileManager.default.contents(atPath: arguments[1]) else {
    FileHandle.standardError.write(Data("usage: playground-reference SETS-FILE OUT-FILE\n".utf8))
    exit(2)
}

let texts: [(String, String)] = [
    // the five sets of GPKit's pass comparison (Tests/GPKitTests/Resources/pass-check-sets.tle; NOTICE says whence)
    ("pass-check-sets", String(decoding: sets, as: UTF8.self)),
    // the ISS of the tests' samples as OMM, in CSV and in KVN
    ("iss-csv", """
        OBJECT_NAME,OBJECT_ID,EPOCH,MEAN_MOTION,ECCENTRICITY,INCLINATION,RA_OF_ASC_NODE,ARG_OF_PERICENTER,MEAN_ANOMALY,EPHEMERIS_TYPE,CLASSIFICATION_TYPE,NORAD_CAT_ID,ELEMENT_SET_NO,REV_AT_EPOCH,BSTAR,MEAN_MOTION_DOT,MEAN_MOTION_DDOT
        ISS (ZARYA),1998-067A,1998-11-20T06:49:59.999808,16.05064833,.0125362,51.5908,168.3788,86.4185,359.7454,0,U,25544,1,0,0,-.3657E-4,.11563E-4

        """),
    ("iss-kvn", """
        CCSDS_OMM_VERS      = 2.0
        CREATION_DATE       = 2026-11-10T00:00:00
        ORIGINATOR          = GPKIT

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

        """),
    // the page's refused example: line 1's checksum one off
    ("refused", "ISS (ZARYA)\n1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    11\n2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05\n"),
    ("not-an-element-set", "hello\n"),
]

// the tutorials' place, Skyfield's (the same, 100 m up), one in the south and east, and one far north
let places: [(Double, Double, Double)] = [(40.0, -75.0, 0.0), (40.0, -75.0, 100.0), (-33.8688, 151.2093, 58.0), (64.8378, -147.7164, 136.0)]
let offsets: [Double] = [0, 3_600, 86_400]
let minimums: [Double] = [0, 10]

func n(_ value: Double) -> String { "\(value)" }
var calls: [[String: Any]] = []
for (name, text) in texts {
    calls.append(["call": "read", "text": name, "args": [String](), "answer": Answers.read(text)])
    for (index, epoch) in Answers.epochs(text).enumerated() {
        for (latitude, longitude, height) in places {
            let place = [n(latitude), n(longitude), n(height)]
            for offset in offsets {
                let at = epoch + offset
                calls.append(["call": "now", "text": name, "args": [String(index)] + place + [n(at)],
                              "answer": Answers.now(text, index: Int32(index), latitude: latitude, longitude: longitude, height: height, unixTime: at)])
            }
            for above in minimums {
                calls.append(["call": "passes", "text": name, "args": [String(index)] + place + [n(epoch), n(86_400), n(above)],
                              "answer": Answers.passes(text, index: Int32(index), latitude: latitude, longitude: longitude, height: height,
                                                       unixStart: epoch, seconds: 86_400, above: above)])
            }
        }
    }
}
let out: [String: Any] = ["texts": Dictionary(uniqueKeysWithValues: texts), "calls": calls]
let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
FileManager.default.createFile(atPath: arguments[2], contents: data)
print("\(calls.count) calls written to \(arguments[2])")
