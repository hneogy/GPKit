import Testing
import GPKit

@Suite struct TLEReadingTests {

    @Test func aSetIsReadAsTheRecordItCarries() throws {
        let set = try TLE.parse(name: Sample.name, line1: Sample.line1, line2: Sample.line2)
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
        #expect(set.source == .tle)
        #expect(set.defaulted == ["CENTER_NAME", "REF_FRAME", "TIME_SYSTEM", "MEAN_ELEMENT_THEORY"])
        #expect(set.isSGP4)
    }

    @Test func alpha5InTheCatalogFieldIsAnInteger() throws {
        for (field, number) in [("A0000", 100_000), ("T0449", 270_449), ("Z9999", 339_999), ("00005", 5)] {
            let line1 = withChecksum(replacing(Sample.line1, 2..<7, with: field))
            let line2 = withChecksum(replacing(Sample.line2, 2..<7, with: field))
            #expect(try TLE.parse(line1: line1, line2: line2).catalogNumber == number)
        }
    }

    @Test func aBlankDesignatorIsNoObjectID() throws {
        let line1 = withChecksum(replacing(Sample.line1, 9..<17, with: "        "))
        let set = try TLE.parse(line1: line1, line2: Sample.line2)
        #expect(set.objectID == nil)
        #expect(set.objectName == nil)
    }

    @Test func twoDigitYearsPivotAt57() throws {
        #expect(TLE.fullYear(twoDigit: 57) == 1957)
        #expect(TLE.fullYear(twoDigit: 99) == 1999)
        #expect(TLE.fullYear(twoDigit: 0) == 2000)
        #expect(TLE.fullYear(twoDigit: 56) == 2056)
        let line1 = withChecksum(replacing(Sample.line1, 18..<20, with: "26"))
        #expect(try TLE.parse(line1: line1, line2: Sample.line2).epoch.year == 2026)
    }

    @Test func aCorruptSetIsRefusedWithItsReason() {
        func kind(_ line1: String, _ line2: String) -> Refusal.Kind? {
            refusal { _ = try TLE.parse(line1: line1, line2: line2) }?.kind
        }
        // a wrong checksum digit
        #expect(kind(replacing(Sample.line1, 68..<69, with: "1"), Sample.line2) == .checksum)
        // a line one character short
        #expect(kind(Sample.line1, replacing(Sample.line2, 29..<30, with: "")) == .lineLength)
        // a letter in a numeric field: the checksum catches it here, and with the checksum made right the field does
        #expect(kind(replacing(Sample.line1, 26..<27, with: "O"), Sample.line2) == .checksum)
        #expect(kind(withChecksum(replacing(Sample.line1, 26..<27, with: "O")), Sample.line2) == .notAnEpoch)
        #expect(kind(Sample.line1, withChecksum(replacing(Sample.line2, 10..<11, with: "l"))) == .notANumber)
        // catalog fields that differ, lowercase, a letter Alpha-5 never uses
        #expect(kind(Sample.line1, withChecksum(replacing(Sample.line2, 2..<7, with: "25545"))) == .catalogNumber)
        #expect(kind(withChecksum(replacing(Sample.line1, 2..<7, with: "a0000")), withChecksum(replacing(Sample.line2, 2..<7, with: "a0000"))) == .catalogNumber)
        #expect(kind(withChecksum(replacing(Sample.line1, 2..<7, with: "I0000")), withChecksum(replacing(Sample.line2, 2..<7, with: "I0000"))) == .catalogNumber)
        // a field moved out of its columns
        #expect(kind(withChecksum(replacing(Sample.line1, 32..<34, with: "- ")), Sample.line2) == .layout)
        // day 000 and day 366 of a year that has 365
        #expect(kind(withChecksum(replacing(Sample.line1, 20..<23, with: "000")), Sample.line2) == .notAnEpoch)
        #expect(kind(withChecksum(replacing(Sample.line1, 20..<23, with: "366")), Sample.line2) == .notAnEpoch)
    }

    @Test func aRefusalSaysWhatWhereAndWith() throws {
        let bad = withChecksum(replacing(Sample.line1, 26..<27, with: "O"))
        let file = try ElementSets.read([Sample.name, bad, Sample.line2].joined(separator: "\n"), as: .tle)
        let refusal = try #require(file.refusals.first)
        #expect(refusal.kind == .notAnEpoch)
        #expect(refusal.field == "epoch")
        #expect(refusal.text == "98324.28O72222")
        #expect(refusal.catalogField == "25544")
        #expect(refusal.line == 2)
        #expect(refusal.record == 0)
        #expect(refusal.message.contains("98324.28O72222"))
    }

    @Test func readingGoesOnAfterARefusal() throws {
        let second1 = withChecksum(replacing(Sample.line1, 2..<7, with: "A0000"))
        let second2 = withChecksum(replacing(Sample.line2, 2..<7, with: "A0000"))
        // three sets; the middle one has lost its line 2
        let text = [Sample.name, Sample.line1, Sample.line2, "ORPHAN", Sample.line1, "SARAMAGO", second1, second2].joined(separator: "\r\n") + "\r\n"
        let file = try ElementSets.read(text, as: .tle)
        #expect(file.entries.count == 3)
        #expect(file.elementSets.map(\.catalogNumber) == [25_544, 100_000])
        #expect(file.elementSets.map(\.objectName) == ["ISS (ZARYA)", "SARAMAGO"])
        #expect(file.refusals.map(\.kind) == [.missingLine2])
        #expect(file.refusals.first?.line == 5)
    }

    @Test func nothingIsPassedOverInSilence() throws {
        let text = ["# a comment", Sample.line2, "", Sample.line1, Sample.line2, "trailing text"].joined(separator: "\n")
        let file = try ElementSets.read(text, as: .tle)
        #expect(file.elementSets.count == 1)
        #expect(file.refusals.map(\.kind) == [.strayLine, .missingLine1, .strayLine])
    }

    @Test func namesWithAndWithoutTheZeroPrefixAndNoNamesAtAll() throws {
        #expect(try only("0 ISS (ZARYA)\n\(Sample.line1)\n\(Sample.line2)\n", .tle).objectName == "ISS (ZARYA)")
        let two = try ElementSets.read("\(Sample.line1)\n\(Sample.line2)\n\(Sample.line1)\n\(Sample.line2)", as: .tle)
        #expect(two.elementSets.count == 2)
        #expect(two.elementSets.allSatisfy { $0.objectName == nil })
    }

    @Test func theProvidersEmptyAnswerIsNoRecordsAndNoError() throws {
        for format in Format.allCases {
            for answer in ElementSets.emptyAnswers {
                let file = try ElementSets.read(answer, as: format)
                #expect(file.entries.isEmpty)
                #expect(file.providerMessage == answer)
            }
        }
        #expect(refusal { _ = try ElementSets.read("", as: .tle) }?.kind == .emptyInput)
        #expect(refusal { _ = try ElementSets.read(" \r\n", as: .json) }?.kind == .emptyInput)
        #expect(refusal { _ = try ElementSets.read([0xFF, 0xFE, 0x31], as: .tle) }?.kind == .notUTF8)
    }
}

@Suite struct TLEWritingTests {

    @Test func whatWasReadIsWrittenBackByteForByte() throws {
        let set = try TLE.parse(name: Sample.name, line1: Sample.line1, line2: Sample.line2)
        let lines = try TLE.write(set)
        #expect(lines.line1 == Sample.line1)
        #expect(lines.line2 == Sample.line2)
        #expect(lines.name == "ISS (ZARYA)")
        #expect(lines.text == "ISS (ZARYA)\n\(Sample.line1)\n\(Sample.line2)")
    }

    @Test func catalogNumbersFrom100000AreAlpha5() throws {
        var set = try TLE.parse(line1: Sample.line1, line2: Sample.line2)
        for (number, field) in [(99_999, "99999"), (100_000, "A0000"), (270_449, "T0449"), (339_999, "Z9999")] {
            set.catalogNumber = number
            let lines = try TLE.write(set)
            #expect(lines.line1.dropFirst(2).prefix(5) == field)
            #expect(lines.line2.dropFirst(2).prefix(5) == field)
            #expect(lines.name == nil)
            #expect(try TLE.parse(line1: lines.line1, line2: lines.line2).catalogNumber == number)
        }
    }

    @Test func whatTheFormatCannotCarryIsRefused() throws {
        let set = try TLE.parse(line1: Sample.line1, line2: Sample.line2)
        func kind(_ change: (inout ElementSet) -> Void) -> Refusal.Kind? {
            var copy = set
            change(&copy)
            return refusal { _ = try TLE.write(copy) }?.kind
        }
        #expect(kind { $0.catalogNumber = 340_000 } == .cannotEncode)
        #expect(kind { $0.catalogNumber = 799_501_621 } == .cannotEncode)
        #expect(kind { $0.catalogNumber = -1 } == .cannotEncode)
        #expect(kind { $0.catalogNumber = nil } == .cannotEncode)
        #expect(kind { $0.epoch = try! Epoch(ccsds: "2057-01-01T00:00:00") } == .cannotEncode)
        #expect(kind { $0.meanMotion = ExactDecimal("100.5")! } == .cannotEncode)
        #expect(kind { $0.inclination = ExactDecimal("-1")! } == .cannotEncode)
        #expect(kind { $0.eccentricity = ExactDecimal("1")! } == .cannotEncode)
        #expect(kind { $0.bstar = ExactDecimal("1e12")! } == .cannotEncode)
        #expect(kind { $0.elementSetNumber = 10_000 } == .cannotEncode)
        #expect(kind { $0.revolutionAtEpoch = 100_000 } == .cannotEncode)
        #expect(kind { $0.objectID = "UNKNOWN" } == .cannotEncode)
    }

    @Test func valuesAreBroughtToTheFieldsResolutionInDecimal() throws {
        var set = try only(Sample.csv, .csv)
        set.eccentricity = ExactDecimal("0.00048259")!
        set.bstar = ExactDecimal("0.00015975118")!
        set.inclination = ExactDecimal("51.63085")!
        set.epoch = try Epoch(ccsds: "2026-09-20T12:42:37.141056")
        let rounded = try TLE.write(set)
        #expect(columns(rounded.line2, 26..<33) == "0004826")
        #expect(columns(rounded.line1, 53..<61) == " 15975-3")
        #expect(columns(rounded.line2, 8..<16) == " 51.6309")
        #expect(columns(rounded.line1, 18..<32) == "26263.52959654")
        #expect(columns(try TLE.write(set, eccentricity: .truncated).line2, 26..<33) == "0004825")
        // a mantissa that rounds up into the next power of ten
        set.bstar = ExactDecimal("0.000999996")!
        #expect(columns(try TLE.write(set).line1, 53..<61) == " 10000-2")
        set.bstar = ExactDecimal("-0.0000027414")!
        #expect(columns(try TLE.write(set).line1, 53..<61) == "-27414-5")
    }

    @Test func anEpochThatRoundsUpToMidnightMovesToTheNextDay() throws {
        var set = try TLE.parse(line1: Sample.line1, line2: Sample.line2)
        set.epoch = try Epoch(ccsds: "2026-12-31T23:59:59.999999")
        #expect(columns(try TLE.write(set).line1, 18..<32) == "27001.00000000")
        set.epoch = try Epoch(ccsds: "2026-09-20T00:00:00")
        #expect(columns(try TLE.write(set).line1, 18..<32) == "26263.00000000")
    }

    @Test func aWrittenLineHasItsChecksum() throws {
        let lines = try TLE.write(try TLE.parse(line1: Sample.line1, line2: Sample.line2))
        #expect(lines.line1.count == 69 && lines.line2.count == 69)
        #expect(String(TLE.checksum(of: lines.line1)) == String(lines.line1.last!))
        #expect(String(TLE.checksum(of: lines.line2)) == String(lines.line2.last!))
    }
}
