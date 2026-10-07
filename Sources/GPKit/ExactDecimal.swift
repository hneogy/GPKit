/// A decimal number exactly as its source wrote it.
///
/// An element set's values are decimal text: `15.49196792`, `.00048259`, `8.422e-5`, or a TLE field such as
/// ` 15975-3`. Reading one into a `Double` changes it in the last place; this type keeps the digits, so two sources
/// that wrote the same number compare equal, and a value can be written back at any resolution without having
/// passed through binary. `double` is the nearest `Double`, for computing with.
public struct ExactDecimal: Sendable, Hashable, CustomStringConvertible, LosslessStringConvertible {

    public let isNegative: Bool
    /// The significant digits as values 0 to 9, most significant first, with no zero at either end. Empty for zero.
    let digits: [UInt8]
    /// The power of ten the digits, read as an integer, are multiplied by.
    let exponent: Int

    public static let zero = ExactDecimal(negative: false, digits: [], exponent: 0)

    /// The digits read as an integer, times ten to `exponent`. Zeros at either end are removed and counted.
    init(negative: Bool, digits: some Collection<UInt8>, exponent: Int) {
        var all = Array(digits)
        var exponent = exponent
        while all.last == 0 {
            all.removeLast()
            exponent += 1
        }
        all = Array(all.drop(while: { $0 == 0 }))
        self.isNegative = all.isEmpty ? false : negative
        self.digits = all
        self.exponent = all.isEmpty ? 0 : exponent
    }

    /// Reads decimal text: an optional sign, digits with at most one decimal point and at least one digit, and an
    /// optional exponent (`E` or `e`, an optional sign, digits). `.5`, `5.`, `+0`, `-.3657E-4` and `1.15630e-5`
    /// are numbers; `1,5`, `0x10`, `NaN`, the empty string and text with a space inside are not.
    public init?(_ text: String) {
        self.init(utf8: Array(text.utf8)[...])
    }

    init?(utf8 bytes: ArraySlice<UInt8>) {
        var i = bytes.startIndex
        let end = bytes.endIndex
        var negative = false
        if i < end, bytes[i] == 0x2B || bytes[i] == 0x2D {
            negative = bytes[i] == 0x2D
            i += 1
        }
        var mantissa: [UInt8] = []
        var fractionDigits = 0
        var sawDigit = false
        while i < end, bytes[i].isDigit {
            mantissa.append(UInt8(bytes[i].digitValue))
            sawDigit = true
            i += 1
        }
        if i < end, bytes[i] == 0x2E {
            i += 1
            while i < end, bytes[i].isDigit {
                mantissa.append(UInt8(bytes[i].digitValue))
                fractionDigits += 1
                sawDigit = true
                i += 1
            }
        }
        guard sawDigit, mantissa.count <= 64 else { return nil }
        var power = 0
        if i < end, bytes[i] == 0x45 || bytes[i] == 0x65 {
            i += 1
            var negativePower = false
            if i < end, bytes[i] == 0x2B || bytes[i] == 0x2D {
                negativePower = bytes[i] == 0x2D
                i += 1
            }
            guard let value = unsignedInteger(bytes[i..<end], plusAllowed: false, maxDigits: 4) else { return nil }
            power = negativePower ? -value : value
            i = end
        }
        guard i == end else { return nil }
        self.init(negative: negative, digits: mantissa, exponent: power - fractionDigits)
    }

    /// A whole number.
    public init(_ value: Int) {
        let text = Array(String(value.magnitude).utf8).map { UInt8($0.digitValue) }
        self.init(negative: value < 0, digits: text, exponent: 0)
    }

    /// The shortest decimal that reads back to this `Double`. nil for a value that is not finite.
    public init?(_ value: Double) {
        guard value.isFinite else { return nil }
        self.init("\(value)")
    }

    public var isZero: Bool { digits.isEmpty }

    /// Plain notation with no exponent and no zero that is not needed: `0.00015975118`, `-0.00003657`, `15.49196792`, `0`.
    public var description: String {
        guard !digits.isEmpty else { return "0" }
        var out: [UInt8] = isNegative ? [0x2D] : []
        let ascii = digits.map { $0 + 0x30 }
        if exponent >= 0 {
            out += ascii
            out += Array(repeating: 0x30, count: exponent)
        } else {
            let wholeDigits = digits.count + exponent
            if wholeDigits > 0 {
                out += ascii[..<wholeDigits]
                out.append(0x2E)
                out += ascii[wholeDigits...]
            } else {
                out += [0x30, 0x2E]
                out += Array(repeating: 0x30, count: -wholeDigits)
                out += ascii
            }
        }
        return string(out)
    }

    /// The nearest `Double`.
    public var double: Double {
        Double(description) ?? (isNegative ? -Double.infinity : Double.infinity)
    }

    enum Rounding {
        case halfUp, down
    }

    /// The digits (as values 0 to 9, no leading zero, `[0]` for zero) of this number's magnitude times ten to
    /// `places`, made an integer by rounding half away from zero or by cutting. Exact: no binary arithmetic.
    func scaled(byTenTo places: Int, _ rounding: Rounding) -> [UInt8] {
        let shift = exponent + places
        var kept: [UInt8]
        if shift >= 0 {
            kept = digits + Array(repeating: 0, count: shift)
        } else {
            let dropped = -shift
            kept = dropped >= digits.count ? [] : Array(digits[..<(digits.count - dropped)])
            let firstDropped = dropped <= digits.count ? digits[digits.count - dropped] : 0
            if rounding == .halfUp && firstDropped >= 5 {
                var i = kept.count - 1
                var carried = true
                while carried && i >= 0 {
                    if kept[i] == 9 { kept[i] = 0 } else { kept[i] += 1; carried = false }
                    i -= 1
                }
                if carried { kept.insert(1, at: 0) }
            }
        }
        return kept.isEmpty ? [0] : kept
    }
}
