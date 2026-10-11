import Foundation
import Testing
@testable import CreCore

func chestPlan() -> (DayPlan, PlanDay) {
    let chest = PlanDay(name: "练胸", weekday: 2, items: [
        PlanItem(text: "卧推 4×8"), PlanItem(text: "上斜哑铃推举 3×10"), PlanItem(text: "飞鸟 3×12"),
    ])
    let back = PlanDay(name: "练背", weekday: 3, items: [PlanItem(text: "引体向上 4×6")])
    return (DayPlan(mode: .fixedWeekday, days: [chest, back]), chest)
}

func repeatOf(_ data: PlanData, _ id: UUID) -> Repeat {
    guard case .repeating(let r) = data.todos.first(where: { $0.id == id })!.schedule else { fatalError() }
    return r
}

@Test func backfillCountsForThatDay() {
    var data = PlanData()
    let id = make("交表", .day(d(10, 3)), into: &data)
    data.toggle(todoID: id, on: d(10, 3), now: Date())
    #expect(data.todos[0].completedDay == d(10, 3))
    #expect(agenda(for: today, today: today, data: data).entries.isEmpty)
    #expect(agenda(for: d(10, 3), today: today, data: data).entries.map(\.isDone) == [true])
}

@Test func untoggleClearsCompletion() {
    var data = PlanData()
    let id = make("交表", .day(today), into: &data)
    data.toggle(todoID: id, on: today, now: Date())
    data.toggle(todoID: id, on: today, now: Date())
    #expect(data.todos[0].completedDay == nil)
    #expect(data.todos[0].completedAt == nil)
}

@Test func allItemsDoneAutoCompletesRepeat() {
    var data = PlanData()
    let (plan, chest) = chestPlan()
    let id = make("健身", .repeating(Repeat(weekdays: [2, 3], start: d(10, 1), plan: plan)), into: &data)
    for item in chest.items { data.toggleRepeatItem(todoID: id, itemID: item.id, on: today, now: Date()) }
    let r = repeatOf(data, id)
    #expect(r.completions[today] != nil)
    #expect(r.itemCompletions[today] == Set(chest.items.map(\.id)))
}

@Test func oneTapCompletesRepeatAndItems() {
    var data = PlanData()
    let (plan, chest) = chestPlan()
    let id = make("健身", .repeating(Repeat(weekdays: [2, 3], start: d(10, 1), plan: plan)), into: &data)
    data.toggleRepeat(todoID: id, on: today, now: Date())
    let r = repeatOf(data, id)
    #expect(r.completions[today] != nil)
    #expect(r.itemCompletions[today] == Set(chest.items.map(\.id)))
}

@Test func uncheckingItemReopensRepeat() {
    var data = PlanData()
    let (plan, chest) = chestPlan()
    let id = make("健身", .repeating(Repeat(weekdays: [2, 3], start: d(10, 1), plan: plan)), into: &data)
    data.toggleRepeat(todoID: id, on: today, now: Date())
    data.toggleRepeatItem(todoID: id, itemID: chest.items[0].id, on: today, now: Date())
    let r = repeatOf(data, id)
    #expect(r.completions[today] == nil)
    #expect(r.itemCompletions[today]?.count == 2)
}

@Test func groupRowTogglesAll() {
    var data = PlanData()
    let g = data.addGroup("家务", now: Date())
    data.updateGroup(g) { $0.todayDisplay = .oneLine }
    let a = make("洗衣服", .day(today), group: g, into: &data)
    _ = make("拖地", .day(today), group: g, into: &data)
    _ = make("倒垃圾", .repeating(Repeat(start: d(10, 1))), group: g, into: &data)
    data.toggle(todoID: a, on: today, now: Date())
    data.toggleGroupRow(groupID: g, on: today, today: today, now: Date())
    #expect(agenda(for: today, today: today, data: data).progress == Progress(done: 3, total: 3))
    data.toggleGroupRow(groupID: g, on: today, today: today, now: Date())
    #expect(agenda(for: today, today: today, data: data).progress == Progress(done: 0, total: 3))
}
