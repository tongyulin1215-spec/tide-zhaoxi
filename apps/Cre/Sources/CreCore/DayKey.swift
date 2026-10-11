import Foundation

/// A calendar day (year-month-day) with no time or time zone.
/// All day arithmetic goes through this type so DST and time zones never shift a day.
public struct DayKey: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    public init?(year: Int, month: Int, day: Int) {
        let comps = DateComponents(year: year, month: month, day: day)
        guard comps.isValidDate(in: Self.utc) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The Gregorian day of `date` in the calendar's time zone (a Buddhist/Japanese/Chinese system calendar can't shift it).
    public static func from(_ date: Date, calendar: Calendar = .current) -> DayKey {
        var g = Calendar(identifier: .gregorian)
        g.timeZone = calendar.timeZone
        let c = g.dateComponents([.year, .month, .day], from: date)
        return DayKey(year: c.year!, month: c.month!, day: c.day!)!
    }

    private var utcDate: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private init(utcDate: Date) {
        let c = Self.utc.dateComponents([.year, .month, .day], from: utcDate)
        year = c.year!
        month = c.month!
        day = c.day!
    }

    public func adding(days: Int) -> DayKey {
        DayKey(utcDate: Self.utc.date(byAdding: .day, value: days, to: utcDate)!)
    }

    /// Positive when `other` is later.
    public func days(until other: DayKey) -> Int {
        Self.utc.dateComponents([.day], from: utcDate, to: other.utcDate).day!
    }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar`.
    public var weekday: Int { Self.utc.component(.weekday, from: utcDate) }

    public func date(hour: Int = 12, calendar: Calendar = .current) -> Date {
        var g = Calendar(identifier: .gregorian)
        g.timeZone = calendar.timeZone
        return g.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var string: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }
}

extension DayKey: Codable {
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let key = DayKey(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad day: \(s)"))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }
}

/// When the real day changes, a view that was showing "today" follows it; a view on another day stays put.
public func advanceViewing(viewing: DayKey, oldToday: DayKey, newToday: DayKey) -> DayKey {
    viewing == oldToday ? newToday : viewing
}
