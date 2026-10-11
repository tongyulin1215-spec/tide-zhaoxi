import Foundation
import Testing
@testable import CreCore

@Test func invalidDateIsNil() {
    #expect(DayKey(year: 2026, month: 2, day: 30) == nil)
}

@Test func addingAcrossMonthAndYear() {
    #expect(DayKey(year: 2026, month: 12, day: 30)!.adding(days: 3) == DayKey(year: 2027, month: 1, day: 2)!)
}

@Test func daysUntil() {
    #expect(DayKey(year: 2026, month: 10, day: 5)!.days(until: DayKey(year: 2026, month: 10, day: 11)!) == 6)
}

@Test func weekdayOfKnownMonday() {
    #expect(DayKey(year: 2026, month: 10, day: 5)!.weekday == 2)
}

@Test func codableAsString() throws {
    let data = try JSONEncoder().encode(DayKey(year: 2026, month: 10, day: 8)!)
    #expect(String(data: data, encoding: .utf8) == "\"2026-10-08\"")
}
