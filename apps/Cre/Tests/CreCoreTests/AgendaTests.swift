import Foundation
import Testing
@testable import CreCore

func d(_ m: Int, _ day: Int, _ y: Int = 2026) -> DayKey { DayKey(year: y, month: m, day: day)! }
let today = d(10, 5) // Monday

/// Builds data where each todo is created at noon of `created`.
func make(_ text: String, _ schedule: Schedule, created: DayKey = d(10, 1), group: UUID? = nil,
          into data: inout PlanData) -> UUID {
    data.addTodo(text, schedule: schedule, groupID: group, tags: [], now: created.date())!
}

func texts(_ a: Agenda) -> [String] { a.entries.map(\.text) }

@Test func dayTodoOnlyOnItsDay() {
    var data = PlanData()
    _ = make("买香蕉", .day(d(10, 8)), into: &data)
    #expect(texts(agenda(for: d(10, 7), today: today, data: data)).isEmpty)
    #expect(texts(agenda(for: d(10, 8), today: today, data: data)) == ["买香蕉"])
}

@Test func overdueDayTodoRollsToToday() {
    var data = PlanData()
    _ = make("交表", .day(d(10, 2)), into: &data)
    let e = agenda(for: today, today: today, data: data).entries
    #expect(e.count == 1)
    #expect(e[0].overdueDays == 3)
}

@Test func overdueNotShownOnFutureView() {
    var data = PlanData()
    _ = make("交表", .day(d(10, 2)), into: &data)
    #expect(texts(agenda(for: d(10, 7), today: today, data: data)).isEmpty)
}

@Test func pastViewMarksMovedLater() {
    var data = PlanData()
    _ = make("交表", .day(d(10, 2)), into: &data)
    let e = agenda(for: d(10, 2), today: today, data: data).entries
    #expect(e.count == 1)
    #expect(e[0].movedLater)
}

@Test func deadlineShowsEveryDayUntilDue() {
    var data = PlanData()
    _ = make("交报告", .deadline(d(10, 20)), into: &data)
    let early = agenda(for: today, today: today, data: data)
    #expect(early.entries.isEmpty)
    #expect(early.foldedDeadlines.map(\.text) == ["交报告"])
    #expect(texts(agenda(for: d(10, 18), today: today, data: data)) == ["交报告"])
    #expect(agenda(for: d(10, 21), today: today, data: data).foldedDeadlines.isEmpty)
}

@Test func deadlineFoldThresholdIsThreeDays() {
    var data = PlanData()
    _ = make("三天后", .deadline(d(10, 8)), into: &data)
    _ = make("四天后", .deadline(d(10, 9)), into: &data)
    let a = agenda(for: today, today: today, data: data)
    #expect(texts(a) == ["三天后"])
    #expect(a.foldedDeadlines.map(\.text) == ["四天后"])
    #expect(a.entries[0].deadline == d(10, 8))
}

@Test func overdueDeadlineStaysWithOverdueDays() {
    var data = PlanData()
    _ = make("过期", .deadline(d(10, 3)), into: &data)
    let e = agenda(for: today, today: today, data: data).entries
    #expect(e.map(\.overdueDays) == [2])
}

@Test func ddlLabelFormat() {
    #expect(ddlLabel(d(10, 8)) == "DDL 10月8日")
}

@Test func spanIsNotCheckable() {
    var data = PlanData()
    _ = make("学习", .span(start: d(10, 5), end: d(10, 11)), into: &data)
    let a = agenda(for: d(10, 7), today: d(10, 7), data: data)
    #expect(a.entries.count == 1)
    #expect(a.entries[0].isCheckable == false)
    #expect(a.progress == Progress(done: 0, total: 0))
}

@Test func repeatOnSelectedWeekdaysOnly() {
    var data = PlanData()
    _ = make("健身", .repeating(Repeat(weekdays: [2, 4, 6], start: d(10, 1))), into: &data)
    #expect(texts(agenda(for: d(10, 5), today: today, data: data)) == ["健身"])
    #expect(texts(agenda(for: d(10, 6), today: today, data: data)).isEmpty)
}

@Test func repeatDoesNotRollOver() {
    var data = PlanData()
    _ = make("健身", .repeating(Repeat(weekdays: [2], start: d(10, 1))), into: &data)
    #expect(texts(agenda(for: d(10, 6), today: d(10, 6), data: data)).isEmpty)
}

@Test func hiddenGroupShowsNothing() {
    var data = PlanData()
    let g = data.addGroup("读书", now: Date())
    data.updateGroup(g) { $0.todayDisplay = .hidden }
    _ = make("读书 1 小时", .repeating(Repeat(start: d(10, 1))), group: g, into: &data)
    _ = make("还书", .deadline(d(10, 6)), group: g, into: &data)
    let a = agenda(for: today, today: today, data: data)
    #expect(a.entries.isEmpty)
    #expect(a.foldedDeadlines.isEmpty)
}

@Test func oneLineGroupCollapsesToOneRow() {
    var data = PlanData()
    let g = data.addGroup("家务", now: Date())
    data.updateGroup(g) { $0.todayDisplay = .oneLine }
    let a1 = make("洗衣服", .day(today), group: g, into: &data)
    _ = make("拖地", .day(today), group: g, into: &data)
    data.update(a1) { $0.completedDay = today; $0.completedAt = Date() }
    let e = agenda(for: today, today: today, data: data).entries
    #expect(e.count == 1)
    #expect(e[0].isGroupRow)
    #expect(e[0].text == "家务")
    #expect(e[0].progress == Progress(done: 1, total: 2))
}

@Test func progressCountsCheckableOnly() {
    var data = PlanData()
    let a = make("买香蕉", .day(today), into: &data)
    _ = make("交表", .day(today), into: &data)
    _ = make("学习", .span(start: d(10, 1), end: d(10, 9)), into: &data)
    _ = make("远期", .deadline(d(10, 30)), into: &data)
    data.update(a) { $0.completedDay = today; $0.completedAt = Date() }
    #expect(agenda(for: today, today: today, data: data).progress == Progress(done: 1, total: 2))
}

@Test func doneItemsSortAfterOpenOnes() {
    var data = PlanData()
    let a = make("先建的", .day(today), into: &data)
    _ = make("后建的", .day(today), created: d(10, 2), into: &data)
    data.update(a) { $0.completedDay = today; $0.completedAt = Date() }
    #expect(texts(agenda(for: today, today: today, data: data)) == ["后建的", "先建的"])
}

@Test func todayAdvancesAtMidnight() {
    #expect(advanceViewing(viewing: d(10, 5), oldToday: d(10, 5), newToday: d(10, 6)) == d(10, 6))
    #expect(advanceViewing(viewing: d(10, 1), oldToday: d(10, 5), newToday: d(10, 6)) == d(10, 1))
}
