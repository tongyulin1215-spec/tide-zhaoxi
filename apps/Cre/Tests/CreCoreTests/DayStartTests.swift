import Foundation
import Testing
@testable import CreCore

private func at(_ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
}

@Test func beforeDayStartStillCountsAsYesterday() {
    #expect(logicalDay(at(10, 6, 1, 30), startHour: 2) == d(10, 5))
    #expect(logicalDay(at(10, 6, 2, 0), startHour: 2) == d(10, 6))
    #expect(logicalDay(at(10, 6, 0, 10), startHour: 0) == d(10, 6))
}

@Test func widgetRefreshesAtDayStart() {
    #expect(nextRefresh(after: at(10, 6, 1, 0), startHour: 2) == at(10, 6, 2))
    #expect(nextRefresh(after: at(10, 6, 3, 0), startHour: 2) == at(10, 7, 2))
    #expect(nextRefresh(after: at(10, 6, 3, 0)) == at(10, 7, 0))
}

@Test func dayStartHourRoundTripsThroughFile() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ds-\(UUID()).json")
    #expect(loadDayStartHour(url) == 0)
    saveDayStartHour(2, to: url)
    #expect(loadDayStartHour(url) == 2)
}

@Test func todayRollsOverWhileOpen() {
    #expect(nextRefresh(after: at(10, 9, 23, 59), startHour: 0) == at(10, 10, 0))
    #expect(nextRefresh(after: at(10, 9, 23, 59), startHour: 4) == at(10, 10, 4))
}
