import Foundation
import Testing
@testable import CreCore

private func done(_ data: inout PlanData, _ id: UUID, on day: DayKey, minutesAfterCreate: Double) {
    let created = data.todos.first { $0.id == id }!.createdAt
    data.update(id) { $0.completedDay = day; $0.completedAt = created.addingTimeInterval(minutesAfterCreate * 60) }
}

@Test func periodRanges() {
    #expect(SummaryPeriod.today.range(today: today) == (today, today))
    #expect(SummaryPeriod.thisWeek.range(today: d(10, 7)) == (d(10, 5), d(10, 7)))   // Mon…Wed
    #expect(SummaryPeriod.thisMonth.range(today: d(10, 7)) == (d(10, 1), d(10, 7)))
    #expect(SummaryPeriod.custom(d(9, 1), d(9, 30)).range(today: today) == (d(9, 1), d(9, 30)))
}

@Test func reportCountsOneOffsInRange() {
    var data = PlanData()
    let a = make("交周报", .day(d(10, 2)), into: &data)
    let b = make("回邮件", .day(d(10, 3)), into: &data)
    _ = make("下周的", .day(d(10, 12)), into: &data)
    let c = make("不设时间做完", .none, into: &data)
    done(&data, a, on: d(10, 2), minutesAfterCreate: 60)
    done(&data, c, on: d(10, 4), minutesAfterCreate: 180)
    _ = b
    let r = makeReport(name: "本周", templateID: nil, scope: .all, from: d(9, 28), to: d(10, 4),
                       metrics: SummaryMetric.allCases, data: data, today: d(10, 4), now: Date())
    #expect(r.done == 2 && r.total == 3)
    #expect(r.rate == 67)
    #expect(r.avgMinutes == 120)
    #expect(Set(r.doneItems.map(\.text)) == ["交周报", "不设时间做完"])
    #expect(r.openItems.map(\.text) == ["回邮件"])
}

@Test func reportRepeatsAndMissedDays() {
    var data = PlanData()
    let id = make("健身", .repeating(Repeat(weekdays: [2, 4, 6], start: d(9, 21))), into: &data)
    data.toggleRepeat(todoID: id, on: d(9, 28), now: Date())
    data.toggleRepeat(todoID: id, on: d(10, 2), now: Date())
    let r = makeReport(name: "x", templateID: nil, scope: .all, from: d(9, 28), to: d(10, 4),
                       metrics: SummaryMetric.allCases, data: data, today: d(10, 4), now: Date())
    #expect(r.done == 2 && r.total == 3)
    #expect(r.missed == [MissedLine(name: "健身", days: [d(9, 30)])])
    #expect(r.repeatLines == [RepeatLine(name: "健身", done: 2, total: 3)])
}

@Test func reportFutureDaysNotCounted() {
    var data = PlanData()
    _ = make("读书", .repeating(Repeat(start: d(10, 1))), into: &data)
    let r = makeReport(name: "x", templateID: nil, scope: .all, from: d(10, 1), to: d(10, 31),
                       metrics: SummaryMetric.allCases, data: data, today: d(10, 4), now: Date())
    #expect(r.total == 4)
}

@Test func reportScopeGroupAndTag() {
    var data = PlanData()
    let g = data.addGroup("工作", now: Date())
    let a = make("交周报", .day(d(10, 2)), group: g, into: &data)
    let b = make("买菜", .day(d(10, 2)), into: &data)
    data.update(b) { $0.tags = ["家"] }
    _ = a
    let byGroup = makeReport(name: "x", templateID: nil, scope: .group(g), from: d(10, 1), to: d(10, 4),
                             metrics: SummaryMetric.allCases, data: data, today: d(10, 4), now: Date())
    #expect(byGroup.openItems.map(\.text) == ["交周报"])
    let byTag = makeReport(name: "x", templateID: nil, scope: .tag("家"), from: d(10, 1), to: d(10, 4),
                           metrics: SummaryMetric.allCases, data: data, today: d(10, 4), now: Date())
    #expect(byTag.openItems.map(\.text) == ["买菜"])
}

@Test func reportByGroupAndDaily() {
    var data = PlanData()
    let g = data.addGroup("工作", now: Date())
    let a = make("交周报", .day(d(10, 2)), group: g, into: &data)
    _ = make("买菜", .day(d(10, 3)), into: &data)
    done(&data, a, on: d(10, 2), minutesAfterCreate: 10)
    let r = makeReport(name: "x", templateID: nil, scope: .all, from: d(10, 1), to: d(10, 4),
                       metrics: SummaryMetric.allCases, data: data, today: d(10, 4), now: Date())
    #expect(r.byGroup == [GroupLine(name: "工作", done: 1, total: 1), GroupLine(name: "零散", done: 0, total: 1)])
    #expect(r.daily.map(\.done) == [0, 1, 0, 0])
}

@Test func templatesGenerateAndDelete() {
    var data = PlanData()
    let t = data.addTemplate(name: "健身周报", scope: .all, period: .thisWeek, metrics: [.count, .rate], now: Date())
    let r = data.generate(templateID: t, today: d(10, 7), now: Date())!
    #expect(r.from == d(10, 5) && r.to == d(10, 7) && r.templateID == t)
    #expect(data.reports.count == 1)
    data.deleteTemplate(t)
    #expect(data.templates.isEmpty)
    #expect(data.reports.count == 1) // reports stay
    data.deleteReport(r.id)
    #expect(data.reports.isEmpty)
}
