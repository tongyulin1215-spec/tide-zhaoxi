import Foundation
import Testing
@testable import CreCore

private func entry(_ data: PlanData, on day: DayKey, _ text: String) -> AgendaEntry? {
    agenda(for: day, today: day, data: data).entries.first { $0.text == text }
}

private func rotatePlan() -> DayPlan {
    DayPlan(mode: .rotate, days: [PlanDay(name: "练胸"), PlanDay(name: "练背"), PlanDay(name: "练腿")])
}

@Test func fixedShowsMondayPlan() {
    var data = PlanData()
    let (plan, _) = chestPlan()
    _ = make("健身", .repeating(Repeat(weekdays: [2, 3], start: d(10, 1), plan: plan)), into: &data)
    let e = entry(data, on: d(10, 5), "健身")!
    #expect(e.detail == "练胸")
    #expect(e.progress == Progress(done: 0, total: 3))
}

@Test func fixedSkipsMissedDay() {
    var data = PlanData()
    let (plan, _) = chestPlan()
    _ = make("健身", .repeating(Repeat(weekdays: [2, 3], start: d(10, 1), plan: plan)), into: &data)
    #expect(entry(data, on: d(10, 6), "健身")?.detail == "练背")
}

@Test func rotateShiftsAfterMissedDay() {
    var data = PlanData()
    let id = make("健身", .repeating(Repeat(start: d(10, 5), plan: rotatePlan())), into: &data)
    #expect(entry(data, on: d(10, 6), "健身")?.detail == "练胸")
    data.toggleRepeat(todoID: id, on: d(10, 6), now: Date())
    #expect(entry(data, on: d(10, 7), "健身")?.detail == "练背")
}

@Test func rotationSurvivesPlanDayRemoval() {
    var data = PlanData()
    var plan = rotatePlan()
    let id = make("健身", .repeating(Repeat(start: d(10, 1), plan: plan)), into: &data)
    for day in 1...4 { data.toggleRepeat(todoID: id, on: d(10, day), now: Date()) }
    plan.days.removeLast()
    data.updateRepeat(id) { $0.plan = plan }
    #expect(entry(data, on: d(10, 5), "健身")?.detail == "练胸")
}

@Test func ongoingShownWhenNoPlan() {
    var data = PlanData()
    let g = data.addGroup("读书", now: Date())
    _ = make("读书 1 小时", .repeating(Repeat(start: d(10, 1))), group: g, into: &data)
    let book = make("人类简史", .none, group: g, into: &data)
    data.setOngoing(book, true)
    #expect(entry(data, on: today, "读书 1 小时")?.detail == "人类简史")
}

@Test func multipleOngoingJoined() {
    var data = PlanData()
    let g = data.addGroup("读书", now: Date())
    _ = make("读书 1 小时", .repeating(Repeat(start: d(10, 1))), group: g, into: &data)
    data.setOngoing(make("人类简史", .none, group: g, into: &data), true)
    data.setOngoing(make("三体", .none, created: d(10, 2), group: g, into: &data), true)
    #expect(entry(data, on: today, "读书 1 小时")?.detail == "人类简史 | 三体")
}

@Test func ongoingClearedWhenDone() {
    var data = PlanData()
    let g = data.addGroup("读书", now: Date())
    _ = make("读书 1 小时", .repeating(Repeat(start: d(10, 1))), group: g, into: &data)
    let book = make("人类简史", .none, group: g, into: &data)
    data.setOngoing(book, true)
    data.toggle(todoID: book, on: today, now: Date())
    #expect(entry(data, on: today, "读书 1 小时")?.detail == nil)
}
