import Testing
import GPKit

@Suite struct OMMReadingTests {

    /// What every format must read from the sample.
    func expectSample(_ set: ElementSet) {
        #expect(set.catalogNumber == 25_544)
        #expect(set.objectName == "ISS (ZARYA)")
        #expect(set.objectID == "1998-067A")
        #expect(set.classification == "U")
        #expect(set.epoch.description == "1998-11-20T06:49:59.999808")
        #expect(set.meanMotion.description == "16.05064833")
        #expect(set.eccentricity.description == "0.0125362")
        #expect(set.inclination.description == "51.5908")
        #expect(set.rightAscension.description == "168.3788")
        #expect(set.argumentOfPericenter.description == "86.4185")
        #expect(set.meanAnomaly.description == "359.7454")
        #expect(set.bstar.isZero)
        #expect(set.meanMotionDot.description == "-0.00003657")
        #expect(set.meanMotionDDot.description == "0.000011563")
        #expect(set.ephemerisType == 0)
        #expect(set.elementSetNumber == 1)
        #expect(set.revolutionAtEpoch == 0)
    }

    @Test func theFourFormatsAndTheTLEAgree() throws {
        let csv = try only(Sample.csv, .csv)
        let json = try only(Sample.json, .json)
        let xml = try only(Sample.xml(), .xml)
        let kvn = try only(Sample.kvn, .kvn)
        let tle = try only(Sample.tle, .tle)
        for set in [csv, json, xml, kvn, tle] { expectSample(set) }
        #expect([csv, json, xml, kvn, tle].map(\.source) == [.csv, .json, .xml, .kvn, .tle])
        // what the written TLE of each OMM record is: the TLE itself
        for set in [csv, json, xml, kvn] {
            let lines = try TLE.write(set)
            #expect(lines.line1 == Sample.line1)
            #expect(lines.line2 == Sample.line2)
        }
    }

    @Test func omittedMetadataIsDefaultedAndSaidToBe() throws {
        let csv = try only(Sample.csv, .csv)
        #expect(csv.centerName == "EARTH" && csv.referenceFrame == "TEME" && csv.timeSystem == "UTC" && csv.meanElementTheory == "SGP4")
        #expect(csv.defaulted == ["CENTER_NAME", "REF_FRAME", "TIME_SYSTEM", "MEAN_ELEMENT_THEORY"])
        #expect(try only(Sample.json, .json).defaulted.count == 4)
        let kvn = try only(Sample.kvn, .kvn)
        #expect(kvn.defaulted.isEmpty)
        #expect(kvn.meanElementTheory == "SGP/SGP4")
        #expect(kvn.isSGP4)
        #expect(kvn.otherKeywords["CCSDS_OMM_VERS"] == "2.0")
        let xml = try only(Sample.xml(), .xml)
        #expect(xml.meanElementTheory == "SGP4" && xml.defaulted.isEmpty)
        #expect(xml.otherKeywords == ["CCSDS_OMM_VERS": "2.0", "USER_DEFINED_NOTE": "a & b"])
    }

    @Test func sixAndNineDigitCatalogNumbersArePlainIntegers() throws {
        for number in [100_000, 270_449, 799_501_621, 999_999_999] {
            #expect(try only("[" + Sample.jsonRecord(catalog: String(number)) + "]", .json).catalogNumber == number)
            #expect(try only(Sample.csv.replacingFirst(",25544,", with: ",\(number),"), .csv).catalogNumber == number)
            #expect(try only(Sample.kvn.replacingFirst("= 25544", with: "= \(number)"), .kvn).catalogNumber == number)
            #expect(try only(Sample.xml().replacingFirst(">25544<", with: ">\(number)<"), .xml).catalogNumber == number)
        }
        for text in ["\"A0000\"", "1000000000", "25544.0", "-5"] {
            let file = try ElementSets.read("[" + Sample.jsonRecord(catalog: text) + "]", as: .json)
            #expect(file.refusals.first?.kind == .catalogNumber, "\(text)")
            #expect(file.elementSets.isEmpty)
        }
    }

    @Test func anEmptyObjectIDStaysEmpty() throws {
        #expect(try only("[" + Sample.jsonRecord(objectID: "\"\"") + "]", .json).objectID == nil)
        #expect(try only("[" + Sample.jsonRecord(objectID: "null") + "]", .json).objectID == nil)
        #expect(try only(Sample.csv.replacingFirst("ISS (ZARYA),1998-067A,", with: "UNKNOWN,,"), .csv).objectID == nil)
        #expect(try only(Sample.csv.replacingFirst("ISS (ZARYA),1998-067A,", with: "UNKNOWN,,"), .csv).objectName == "UNKNOWN")
        #expect(try only(Sample.xml(objectID: "<OBJECT_ID></OBJECT_ID>"), .xml).objectID == nil)
        #expect(try only(Sample.xml(objectID: "<OBJECT_ID/>"), .xml).objectID == nil)
        #expect(try only(Sample.kvn.replacingFirst("= 1998-067A", with: "="), .kvn).objectID == nil)
    }

    @Test func kvnVariants() throws {
        // a day-of-year epoch with Z; units in brackets; signs on integers; a lowercase exponent
        var text = Sample.kvn.replacingFirst("1998-11-20T06:49:59.999808", with: "1998-324T06:49:59.999808Z")
        text = text.replacingFirst("= 16.05064833", with: "= 16.05064833 [rev/day]").replacingFirst("= 51.5908", with: "= 51.5908 [deg]")
        text = text.replacingFirst("= 25544", with: "= +25544").replacingFirst("= .11563E-4", with: "= 1.15630e-5")
        expectSample(try only(text, .kvn))
        // comments, blank lines, no spaces, spaces and a tab
        text = "CCSDS_OMM_VERS=2.0\nCOMMENT a comment = with an equals sign\nCOMMENT\n" + Sample.kvn.split(separator: "\n").dropFirst().joined(separator: "\n\n")
        text = text.replacingFirst("MEAN_MOTION         = ", with: "  MEAN_MOTION =\t").replacingFirst("EPOCH               = ", with: "EPOCH=")
        expectSample(try only(text, .kvn))
        // version 3.0, the optional TLE parameters left out: the record has no catalog number, and none is invented
        var lines = Sample.kvn.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.removeAll { $0.hasPrefix("EPHEMERIS_TYPE") || $0.hasPrefix("CLASSIFICATION_TYPE") || $0.hasPrefix("NORAD_CAT_ID") || $0.hasPrefix("ELEMENT_SET_NO") || $0.hasPrefix("REV_AT_EPOCH") }
        lines[0] = "CCSDS_OMM_VERS = 3.0"
        let bare = try only(lines.joined(separator: "\n"), .kvn)
        #expect(bare.catalogNumber == nil && bare.ephemerisType == nil && bare.classification == nil && bare.elementSetNumber == nil && bare.revolutionAtEpoch == nil)
        #expect(bare.meanMotion.description == "16.05064833")
        // two messages in one file, and a keyword twice in the second
        let two = try ElementSets.read(Sample.kvn + Sample.kvn + "BSTAR = 1\n", as: .kvn)
        #expect(two.elementSets.count == 1)
        #expect(two.refusals.map(\.kind) == [.duplicateKeyword])
        #expect(refusal { _ = try ElementSets.read("OBJECT_NAME = X\n", as: .kvn) }?.kind == .malformedFile)
    }

    @Test func aRecordThatCannotBeReadCostsOneRecord() throws {
        let good = Sample.jsonRecord()
        let noEpoch = good.replacingFirst("\"EPOCH\":\"1998-11-20T06:49:59.999808\",", with: "")
        let badNumber = good.replacingFirst("16.05064833", with: "\"fast\"")
        let badEpoch = good.replacingFirst("1998-11-20T06:49:59.999808", with: "98324.28472222")
        let twice = good.replacingFirst("{", with: "{\"BSTAR\":1,")
        let file = try ElementSets.read("[\(good),\(noEpoch),\(badNumber),7,\(badEpoch),\(twice),\(good)]", as: .json)
        #expect(file.entries.count == 7)
        #expect(file.elementSets.count == 2)
        #expect(file.refusals.map(\.kind) == [.missingKeyword, .notANumber, .malformedRecord, .notAnEpoch, .duplicateKeyword])
        #expect(file.refusals.map(\.record) == [1, 2, 3, 4, 5])
        #expect(file.refusals[1].field == "MEAN_MOTION" && file.refusals[1].text == "fast" && file.refusals[1].catalogField == "25544")
    }

    @Test func aFileCutShortIsRefusedWhole() {
        #expect(refusal { _ = try ElementSets.read(String(Sample.json.dropLast()), as: .json) }?.kind == .cutShort)
        #expect(refusal { _ = try ElementSets.read(String(Sample.json.dropLast(20)), as: .json) }?.kind == .cutShort)
        #expect(refusal { _ = try ElementSets.read(Sample.csv + String(Sample.csvRow.dropLast(12)), as: .csv) }?.kind == .cutShort)
        #expect(refusal { _ = try ElementSets.read(String(Sample.xml().dropLast(8)), as: .xml) }?.kind == .cutShort)
    }

    @Test func csvRowsAndQuoting() throws {
        // a quoted name with a comma and a doubled quote; an extra column kept; a row of the wrong width refused, the next read
        let header = Sample.csvHeader + ",DATA_SOURCE"
        let quoted = Sample.csvRow.replacingFirst("ISS (ZARYA)", with: "\"ISS, \"\"ZARYA\"\"\"") + ",operator"
        let file = try ElementSets.read([header, quoted, Sample.csvRow, Sample.csvRow + ",x"].joined(separator: "\n") + "\n", as: .csv)
        #expect(file.elementSets.map(\.objectName) == ["ISS, \"ZARYA\"", "ISS (ZARYA)"])
        #expect(file.elementSets[0].otherKeywords == ["DATA_SOURCE": "operator"])
        #expect(file.refusals.map(\.kind) == [.malformedRecord])
        #expect(file.refusals.first?.catalogField == "25544" && file.refusals.first?.line == 3)
        #expect(refusal { _ = try ElementSets.read("just some text\n", as: .csv) }?.kind == .malformedFile)
    }

    @Test func jsonForms() throws {
        // numbers as strings, as Space-Track writes them; a single object; whitespace and escapes
        let strings = Sample.jsonRecord().replacingFirst(":16.05064833", with: ":\"16.05064833\"").replacingFirst("\"NORAD_CAT_ID\":25544", with: "\"NORAD_CAT_ID\":\"25544\"")
        expectSample(try only(strings, .json))
        let spaced = "\n[ " + Sample.jsonRecord().replacingFirst("ISS (ZARYA)", with: "ISS \\u0028ZARYA\\u0029") + " ]\n"
        expectSample(try only(spaced, .json))
        for bad in ["[", "{", "[{]", "[{\"A\":}]", "[{\"A\":1,}]", "[1 2]", "nul", "[\"\\x\"]", "[] []", "[01]"] {
            #expect(refusal { _ = try ElementSets.read(bad, as: .json) } != nil, "\(bad)")
        }
        #expect(try ElementSets.read("[]", as: .json).entries.isEmpty)
    }

    @Test func xmlForms() throws {
        expectSample(try only(Sample.xml(root: "omm", omm: "inner").replacingFirst("<inner id=\"CCSDS_OMM_VERS\" version=\"2.0\">", with: "").replacingFirst("</inner>", with: ""), .xml))
        expectSample(try only(Sample.xml(root: "ndm:ndm", omm: "ndm:omm"), .xml))
        expectSample(try only(Sample.xml().replacingFirst("<OBJECT_NAME>ISS (ZARYA)</OBJECT_NAME>", with: "<OBJECT_NAME><![CDATA[ISS (ZARYA)]]></OBJECT_NAME>"), .xml))
        expectSample(try only(Sample.xml().replacingFirst("ISS (ZARYA)", with: "ISS &#40;ZARYA&#x29;"), .xml))
        #expect(refusal { _ = try ElementSets.read("<!DOCTYPE ndm [<!ENTITY a \"b\">]>" + Sample.xml(), as: .xml) }?.kind == .malformedFile)
        #expect(refusal { _ = try ElementSets.read("<html><body>503</body></html>", as: .xml) }?.kind == .malformedFile)
        #expect(refusal { _ = try ElementSets.read("<ndm><omm></ndm></omm>", as: .xml) }?.kind == .malformedFile)
        #expect(refusal { _ = try ElementSets.read(Sample.xml().replacingFirst("&amp;", with: "&nbsp;"), as: .xml) }?.kind == .malformedFile)
        let two = try ElementSets.read(Sample.xml().replacingFirst("</body></omm>", with: "</body></omm><omm version=\"2.0\"><body/></omm>"), as: .xml)
        #expect(two.elementSets.count == 1)
        #expect(two.refusals.map(\.kind) == [.missingKeyword])
    }

    @Test func aByteOrderMarkIsPassedOver() throws {
        expectSample(try ElementSets.read([0xEF, 0xBB, 0xBF] + Array(Sample.csv.utf8), as: .csv).elementSets[0])
    }
}

extension String {
    /// The string with the first occurrence of `target` replaced; the tests fail loudly when there is none.
    func replacingFirst(_ target: String, with replacement: String) -> String {
        let haystack = Array(utf8), needle = Array(target.utf8)
        var i = 0
        while i + needle.count <= haystack.count {
            if Array(haystack[i..<(i + needle.count)]) == needle {
                return String(decoding: haystack[..<i] + Array(replacement.utf8) + haystack[(i + needle.count)...], as: UTF8.self)
            }
            i += 1
        }
        fatalError("\"\(target)\" is not in the text")
    }
}
