import Testing
import GPKit

@Suite struct ExactDecimalTests {

    @Test func theSameNumberInAnyFormIsEqual() {
        #expect(ExactDecimal(".15975118E-3") == ExactDecimal("0.00015975118"))
        #expect(ExactDecimal("8.422e-5") == ExactDecimal(".00008422"))
        #expect(ExactDecimal("1.15630e-5") == ExactDecimal(".11563E-4"))
        #expect(ExactDecimal("51.6300") == ExactDecimal("51.63"))
        #expect(ExactDecimal("+0") == ExactDecimal.zero)
        #expect(ExactDecimal("-0.0") == ExactDecimal.zero)
        #expect(ExactDecimal("5.") == ExactDecimal(5))
    }

    @Test func writtenPlainlyWithoutLosingADigit() {
        #expect(ExactDecimal(".15975118E-3")?.description == "0.00015975118")
        #expect(ExactDecimal("-.3657E-4")?.description == "-0.00003657")
        #expect(ExactDecimal("16.05064833")?.description == "16.05064833")
        #expect(ExactDecimal("1E3")?.description == "1000")
        #expect(ExactDecimal("0")?.description == "0")
        #expect(ExactDecimal("0.1234567890123456789012345")?.description == "0.1234567890123456789012345")
    }

    @Test func whatIsNotANumberIsNotRead() {
        for text in ["", " ", ".", "-", "1,5", "0x10", "NaN", "inf", "1 2", "1e", "1e+", "--1", "1.2.3", "A0000", " 1", "1 "] {
            #expect(ExactDecimal(text) == nil, "\(text)")
        }
    }

    @Test func nearestDouble() {
        #expect(ExactDecimal("16.05064833")?.double == 16.05064833)
        #expect(ExactDecimal("-.3657E-4")?.double == -0.00003657)
        #expect(ExactDecimal(0.1)?.description == "0.1")
        #expect(ExactDecimal(Double.nan) == nil)
    }
}

@Suite struct EpochTests {

    @Test func bothCCSDSFormsAreRead() throws {
        let calendar = try Epoch(ccsds: "2020-03-04T10:34:41.4264")
        #expect(try Epoch(ccsds: "2020-064T10:34:41.4264") == calendar)
        #expect(calendar.description == "2020-03-04T10:34:41.426400")
        #expect(calendar.dayOfYear == 64)
        #expect(try Epoch(ccsds: "2002-204T15:56:23Z").description == "2002-07-23T15:56:23.000000")
        #expect(try Epoch(ccsds: "2001-11-06T11:17:33").microsecond == 0)
        #expect(try Epoch(ccsds: "2026-09-20T12:42:37.141056").microsecond == 141_056)
        #expect(try Epoch(ccsds: "1998-11-20T06:49:59.999808Z").description == "1998-11-20T06:49:59.999808")
    }

    @Test func everyFractionDigitIsKept() throws {
        let epoch = try Epoch(ccsds: "2026-09-20T12:42:37.123456789012345678")
        #expect(epoch.attosecond == 123_456_789_012_345_678)
        #expect(epoch.nanosecond == 123_456_789)
        #expect(epoch.description == "2026-09-20T12:42:37.123456789012345678")
        #expect(refusal { _ = try Epoch(ccsds: "2026-09-20T12:42:37.1234567890123456789") }?.kind == .notAnEpoch)
    }

    @Test func aLeapSecondIsKept() throws {
        let leap = try Epoch(ccsds: "2016-12-31T23:59:60")
        #expect(leap.second == 60)
        #expect(leap.description == "2016-12-31T23:59:60.000000")
        #expect(try Epoch(ccsds: "2016-12-31T23:59:59.5") < leap)
        #expect(refusal { _ = try Epoch(ccsds: "2016-12-31T12:00:60") }?.kind == .notAnEpoch)
    }

    @Test func whatIsNotACCSDSEpochIsRefused() {
        for text in ["2026-9-20T12:42:37", "2026-09-20 12:42:37", "26263.52959654", "2026-09-20T12:42:37.141056+00:00", "20260920T124237",
                     "2026-13-01T00:00:00", "2026-02-30T00:00:00", "2025-366T00:00:00", "2026-000T00:00:00", "2026-09-20T24:00:00",
                     "2026-09-20T12:42:37.", "2026-09-20T12:42", "", "2026-09-20T12:42:37Zjunk"] {
            #expect(refusal { _ = try Epoch(ccsds: text) }?.kind == .notAnEpoch, "\(text)")
        }
    }

    @Test func leapYears() throws {
        #expect(try Epoch(ccsds: "2024-366T00:00:00").description == "2024-12-31T00:00:00.000000")
        #expect(try Epoch(ccsds: "2000-02-29T00:00:00").dayOfYear == 60)
        #expect(refusal { _ = try Epoch(ccsds: "1900-02-29T00:00:00") } != nil)
    }
}

@Suite struct Alpha5Tests {

    @Test func spaceTracksExamples() throws {
        for (number, field) in [(100_000, "A0000"), (148_493, "E8493"), (182_931, "J2931"), (234_018, "P4018"), (301_928, "W1928"),
                                (339_999, "Z9999"), (179_999, "H9999"), (180_000, "J0000"), (229_999, "N9999"), (230_000, "P0000"),
                                (5, "00005"), (25_544, "25544"), (99_999, "99999"), (0, "00000")] {
            #expect(try Alpha5.decode(field) == number)
            #expect(try Alpha5.encode(number) == field)
        }
    }

    @Test func whatIsNotAlpha5IsRefused() {
        for field in ["I0000", "O1234", "a0000", "AA000", "A000", "1A000", "A00000", " 5544", "+1234", "A-001", "A 000", ""] {
            #expect(refusal { _ = try Alpha5.decode(field) }?.kind == .catalogNumber, "\(field)")
        }
    }

    @Test func whatTheFieldCannotCarryIsRefused() {
        for number in [340_000, 799_501_621, -1] {
            #expect(refusal { _ = try Alpha5.encode(number) }?.kind == .cannotEncode, "\(number)")
        }
    }

    @Test func ommCatalogNumbersArePlainIntegers() throws {
        for (text, number) in [("25544", 25_544), ("00964", 964), ("+25544", 25_544), ("100000", 100_000), ("799501621", 799_501_621), ("999999999", 999_999_999)] {
            #expect(try OMM.catalogNumber(text) == number)
        }
        for text in ["A0000", "1000000000", "25544.0", "", "-1", "25 544"] {
            #expect(refusal { _ = try OMM.catalogNumber(text) }?.kind == .catalogNumber, "\(text)")
        }
    }
}
