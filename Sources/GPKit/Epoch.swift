/// The instant an element set is for, as its source wrote it: a calendar date and a time of day, with the fraction
/// of the second kept as a whole number of attoseconds.
///
/// An epoch is kept as integers, never as a `Double` of days or seconds. A TLE's eight-decimal day is an exact
/// number of microseconds (one hundred-millionth of a day is 864 of them), and an OMM writes its fraction in
/// digits; both arrive here unchanged. The time system is the record's (`ElementSet.timeSystem`), UTC for every GP
/// element set a provider serves. Second 60, a leap second, is accepted at 23:59 and kept.
public struct Epoch: Sendable, Hashable, Comparable, CustomStringConvertible {

    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    /// 0 to 59, or 60 for a leap second.
    public let second: Int
    /// The fraction of the second, in attoseconds: 0 to 999,999,999,999,999,999.
    public let attosecond: UInt64

    static let attosecondsPerSecond: UInt64 = 1_000_000_000_000_000_000

    public init(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, attosecond: UInt64 = 0) throws(Refusal) {
        func refuse(_ what: String) -> Refusal { Refusal(.notAnEpoch, "the epoch's \(what)", field: "EPOCH") }
        guard (1...9999).contains(year) else { throw refuse("year \(year) is not 1 to 9999") }
        guard (1...12).contains(month) else { throw refuse("month \(month) is not 1 to 12") }
        guard (1...Epoch.days(inMonth: month, of: year)).contains(day) else { throw refuse("day \(day) is not a day of month \(month) of \(year)") }
        guard (0...23).contains(hour) else { throw refuse("hour \(hour) is not 0 to 23") }
        guard (0...59).contains(minute) else { throw refuse("minute \(minute) is not 0 to 59") }
        guard (0...59).contains(second) || (second == 60 && hour == 23 && minute == 59) else {
            throw refuse("second \(second) is not 0 to 59, or 60 at 23:59")
        }
        guard attosecond < Epoch.attosecondsPerSecond else { throw refuse("fraction is a second or more") }
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.attosecond = attosecond
    }

    /// The same, with the day counted from 1 January.
    public init(year: Int, dayOfYear: Int, hour: Int, minute: Int, second: Int, attosecond: UInt64 = 0) throws(Refusal) {
        guard (1...9999).contains(year) else { throw Refusal(.notAnEpoch, "the epoch's year \(year) is not 1 to 9999", field: "EPOCH") }
        guard (1...Epoch.days(in: year)).contains(dayOfYear) else {
            throw Refusal(.notAnEpoch, "the epoch's day \(dayOfYear) is not a day of \(year)", field: "EPOCH")
        }
        var month = 1
        var day = dayOfYear
        while day > Epoch.days(inMonth: month, of: year) {
            day -= Epoch.days(inMonth: month, of: year)
            month += 1
        }
        try self.init(year: year, month: month, day: day, hour: hour, minute: minute, second: second, attosecond: attosecond)
    }

    /// Reads a CCSDS time code (502.0-B-3, 7.5.10): `YYYY-MM-DDThh:mm:ss[.d...][Z]` or `YYYY-DDDThh:mm:ss[.d...][Z]`.
    /// Every part has its full width; the `T` is required; `Z` is the only terminator. Up to eighteen fraction
    /// digits are kept, and any further ones must be zeros.
    public init(ccsds text: String) throws(Refusal) {
        try self.init(ccsds: Array(text.utf8)[...])
    }

    init(ccsds bytes: ArraySlice<UInt8>) throws(Refusal) {
        let refusal = Refusal(.notAnEpoch, "\"\(string(bytes))\" is not a CCSDS epoch (YYYY-MM-DDThh:mm:ss[.d][Z] or YYYY-DDDThh:mm:ss[.d][Z])",
                              field: "EPOCH", text: string(bytes))
        var i = bytes.startIndex
        let end = bytes.endIndex
        func number(_ width: Int) -> Int? {
            guard i + width <= end, bytes[i..<(i + width)].allSatisfy(\.isDigit) else { return nil }
            return bytes[i..<(i + width)].reduce(0) { $0 * 10 + $1.digitValue }
        }
        func take(_ byte: UInt8) -> Bool {
            i < end && bytes[i] == byte
        }
        guard let year = number(4) else { throw refusal }
        i += 4
        guard take(0x2D) else { throw refusal }
        i += 1
        var month: Int?
        var day: Int
        if i + 3 <= end, bytes[i..<(i + 3)].allSatisfy(\.isDigit), i + 3 < end, bytes[i + 3] == 0x54 {
            day = number(3)!
            i += 3
        } else {
            guard let m = number(2) else { throw refusal }
            i += 2
            guard take(0x2D) else { throw refusal }
            i += 1
            guard let d = number(2) else { throw refusal }
            i += 2
            month = m
            day = d
        }
        guard take(0x54) else { throw refusal }
        i += 1
        guard let hour = number(2) else { throw refusal }
        i += 2
        guard take(0x3A) else { throw refusal }
        i += 1
        guard let minute = number(2) else { throw refusal }
        i += 2
        guard take(0x3A) else { throw refusal }
        i += 1
        guard let second = number(2) else { throw refusal }
        i += 2
        var attosecond: UInt64 = 0
        if take(0x2E) {
            i += 1
            var count = 0
            while i < end, bytes[i].isDigit {
                if count < 18 {
                    attosecond = attosecond * 10 + UInt64(bytes[i].digitValue)
                } else if bytes[i] != 0x30 {
                    throw Refusal(.notAnEpoch, "the epoch \"\(string(bytes))\" has more than eighteen fraction digits", field: "EPOCH", text: string(bytes))
                }
                count += 1
                i += 1
            }
            guard count > 0 else { throw refusal }
            for _ in count..<max(count, 18) { attosecond *= 10 }
        }
        if take(0x5A) { i += 1 }
        guard i == end else { throw refusal }
        do throws(Refusal) {
            if let month {
                try self.init(year: year, month: month, day: day, hour: hour, minute: minute, second: second, attosecond: attosecond)
            } else {
                try self.init(year: year, dayOfYear: day, hour: hour, minute: minute, second: second, attosecond: attosecond)
            }
        } catch {
            throw Refusal(.notAnEpoch, "\(error.message) in \"\(string(bytes))\"", field: "EPOCH", text: string(bytes))
        }
    }

    public var dayOfYear: Int {
        (1..<month).reduce(day) { $0 + Epoch.days(inMonth: $1, of: year) }
    }

    /// The fraction of the second in whole microseconds, anything finer cut off.
    public var microsecond: Int { Int(attosecond / 1_000_000_000_000) }

    /// The fraction of the second in whole nanoseconds, anything finer cut off.
    public var nanosecond: Int { Int(attosecond / 1_000_000_000) }

    /// Microseconds since the day began: 0 to 86,400,999,999 (the last second of a day with a leap second).
    var microsecondOfDay: Int { ((hour * 60 + minute) * 60 + second) * 1_000_000 + microsecond }

    /// `YYYY-MM-DDThh:mm:ss.ffffff`, with more fraction digits where the epoch has them.
    public var description: String {
        var fraction = Array(padded(Int(attosecond / 1_000_000_000), width: 9).utf8) + Array(padded(Int(attosecond % 1_000_000_000), width: 9).utf8)
        while fraction.count > 6, fraction.last == 0x30 { fraction.removeLast() }
        return "\(padded(year, width: 4))-\(padded(month, width: 2))-\(padded(day, width: 2))T\(padded(hour, width: 2)):\(padded(minute, width: 2)):\(padded(second, width: 2)).\(string(fraction))"
    }

    public static func < (a: Epoch, b: Epoch) -> Bool {
        (a.year, a.month, a.day, a.hour, a.minute, a.second) != (b.year, b.month, b.day, b.hour, b.minute, b.second)
            ? (a.year, a.month, a.day, a.hour, a.minute, a.second) < (b.year, b.month, b.day, b.hour, b.minute, b.second)
            : a.attosecond < b.attosecond
    }

    // MARK: - As a count

    /// Whole days from 1970 January 1 to the date (Howard Hinnant's days_from_civil).
    var unixDay: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Seconds since the day began, with the fraction. A leap second runs from 86,400 to 86,401.
    var secondOfDay: Double {
        Double((hour * 60 + minute) * 60 + second) + Double(attosecond) / 1.0e18
    }

    /// Days from 1950 January 0.0 UTC, the count SGP4 keeps its epoch in: 1949 December 31 at 00:00 is 0.
    var daysSince1950: Double {
        Double(unixDay + 7_306) + secondOfDay / 86_400.0
    }

    /// The Julian date, UTC.
    var julianDate: Double {
        daysSince1950 + 2_433_281.5
    }

    /// Seconds from 1970 January 1 at 00:00 UTC, every day counted as 86,400 seconds: Unix time, which is what
    /// Foundation's `Date.timeIntervalSince1970` holds. A leap second has the count of the second after it.
    public var unixTime: Double {
        Double(unixDay) * 86_400.0 + secondOfDay
    }

    /// The instant a count of Unix time stands for, to the microsecond.
    public init(unixTime: Double) throws(Refusal) {
        guard unixTime.isFinite, abs(unixTime) < 2.5e11 else {
            throw Refusal(.notAnEpoch, "\(unixTime) seconds from 1970 is not a date this type holds", field: "EPOCH")
        }
        let day = (unixTime / 86_400.0).rounded(.down)
        let microseconds = ((unixTime - day * 86_400.0) * 1.0e6).rounded()
        self.init(unixDay: Int(day), microsecondOfDay: Int(microseconds))
    }

    /// The seconds from `other` to this instant, every day counted as 86,400 seconds. The days are subtracted as
    /// whole numbers, so two instants years apart still differ to well under a microsecond.
    public func seconds(since other: Epoch) -> Double {
        Double(unixDay - other.unixDay) * 86_400.0 + (secondOfDay - other.secondOfDay)
    }

    /// This instant moved by a number of seconds, to the microsecond.
    public func advanced(by seconds: Double) throws(Refusal) -> Epoch {
        guard seconds.isFinite, abs(seconds) < 2.5e11 else {
            throw Refusal(.notAnEpoch, "\(seconds) seconds is not an interval this type moves by", field: "EPOCH")
        }
        let total = secondOfDay + seconds
        let days = (total / 86_400.0).rounded(.down)
        let moved = Epoch(unixDay: unixDay + Int(days), microsecondOfDay: Int(((total - days * 86_400.0) * 1.0e6).rounded()))
        guard (1...9999).contains(moved.year) else {
            throw Refusal(.notAnEpoch, "\(seconds) seconds from \(self) is outside the years 1 to 9999", field: "EPOCH")
        }
        return moved
    }

    /// A day counted from 1970 January 1 and a number of microseconds into it, which may run past the day's end.
    init(unixDay: Int, microsecondOfDay: Int) {
        var day = unixDay + microsecondOfDay / 86_400_000_000
        var micro = microsecondOfDay % 86_400_000_000
        if micro < 0 {
            micro += 86_400_000_000
            day -= 1
        }
        // Howard Hinnant's civil_from_days
        let z = day + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let m = mp < 10 ? mp + 3 : mp - 9
        self.year = (m <= 2 ? 1 : 0) + yoe + era * 400
        self.month = m
        self.day = doy - (153 * mp + 2) / 5 + 1
        self.hour = micro / 3_600_000_000
        self.minute = micro / 60_000_000 % 60
        self.second = micro / 1_000_000 % 60
        self.attosecond = UInt64(micro % 1_000_000) * 1_000_000_000_000
    }

    static func isLeap(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    static func days(in year: Int) -> Int {
        isLeap(year) ? 366 : 365
    }

    static func days(inMonth month: Int, of year: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}
