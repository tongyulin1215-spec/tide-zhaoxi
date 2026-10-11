import Foundation
import Testing
@testable import CreCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return c
}()

private func at(_ day: DayKey, _ h: Int, _ m: Int) -> Date {
    cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: h, minute: m))!
}

@Test func offeredFridayEvening() {
    #expect(shouldOfferTriage(now: at(d(10, 9), 19, 5), lastTriagedWeek: nil, calendar: cal))
}

@Test func notBeforeSeven() {
    #expect(!shouldOfferTriage(now: at(d(10, 9), 18, 59), lastTriagedWeek: nil, calendar: cal))
}

@Test func notTwiceSameWeek() {
    #expect(!shouldOfferTriage(now: at(d(10, 9), 21, 0), lastTriagedWeek: d(10, 9), calendar: cal))
    #expect(shouldOfferTriage(now: at(d(10, 16), 19, 30), lastTriagedWeek: d(10, 9), calendar: cal))
}

@Test func notOnSaturday() {
    #expect(!shouldOfferTriage(now: at(d(10, 10), 20, 0), lastTriagedWeek: nil, calendar: cal))
}

@Test func candidatesAreOverdueOnly() {
    var data = PlanData()
    _ = make("过期指定日", .day(d(10, 7)), into: &data)
    _ = make("过期DDL", .deadline(d(10, 8)), into: &data)
    _ = make("今天的", .day(d(10, 9)), into: &data)
    _ = make("未到期DDL", .deadline(d(10, 20)), into: &data)
    let done = make("已完成", .day(d(10, 6)), into: &data)
    data.toggle(todoID: done, on: d(10, 6), now: Date())
    _ = make("学习", .span(start: d(10, 1), end: d(10, 4)), into: &data)
    #expect(triageCandidates(today: d(10, 9), data: data).map(\.text) == ["过期指定日", "过期DDL"])
}

@Test func doTodayMovesToToday() {
    var data = PlanData()
    let id = make("过期DDL", .deadline(d(10, 8)), into: &data)
    data.doToday(id, today: d(10, 9))
    #expect(data.todos[0].schedule == .day(d(10, 9)))
}

@Test func rescheduleKeepsKind() {
    var data = PlanData()
    let a = make("过期DDL", .deadline(d(10, 8)), into: &data)
    let b = make("过期指定日", .day(d(10, 7)), into: &data)
    data.reschedule(a, to: d(10, 12))
    data.reschedule(b, to: d(10, 11))
    #expect(data.todos.map(\.schedule) == [.deadline(d(10, 12)), .day(d(10, 11))])
}
