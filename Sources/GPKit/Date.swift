// The one file of GPKit that uses Foundation. Every other file builds without it (tools/check-no-foundation.sh
// compiles them so), and where there is no Foundation this file is empty.
#if canImport(Foundation)
import Foundation

extension Epoch {

    /// 2001 January 1, the day a `Date` counts its seconds from, as a count of days from 1970 January 1.
    static let dateReferenceDay = 11_323

    /// The instant a `Date` holds, as UTC, to the microsecond. Refuses a date outside the years 1 to 9999.
    public init(_ date: Date) throws(Refusal) {
        try self.init(seconds: date.timeIntervalSinceReferenceDate, fromUnixDay: Epoch.dateReferenceDay)
    }

    /// This instant as a `Date`.
    ///
    /// A `Date` is a `Double` of seconds from 2001, every day counted as 86,400 of them. It holds a microsecond
    /// for about 140 years either side of 2001 and less beyond, so an epoch finer than that, or further off, comes
    /// back from a `Date` as the nearest instant the `Date` could hold. A leap second, which a `Date` has no count
    /// for, becomes the second after it.
    public var date: Date {
        Date(timeIntervalSinceReferenceDate: Double(unixDay - Epoch.dateReferenceDay) * 86_400.0 + secondOfDay)
    }
}
#endif
