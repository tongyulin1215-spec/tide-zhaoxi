import Foundation
import Testing
@testable import CreCore

@Test func fixedCycleSlotsRunMondayToSunday() {
    let today = d(10, 9)  // Friday
    let plan = DayPlan(mode: .fixedWeekday, days: [PlanDay(name: "练背", weekday: 3), PlanDay(name: "练胸", weekday: 2)])
    var r = Repeat(weekdays: [2, 3], start: d(10, 1), plan: plan)
    r.completions[d(10, 5)] = Date()
    let slots = cycleSlots(r, plan, today: today)
    #expect(slots.map(\.label) == ["周一", "周二"])
    #expect(slots[0].date == d(10, 5) && slots[0].isDone)
    #expect(slots[1].date == d(10, 6) && !slots[1].isDone && slots[1].checkable)
}

@Test func nextPhaseStartsAfterTheLastOne() {
    let now = d(10, 1).date()
    var data = PlanData()
    let g = data.addGroup("游戏", kind: .phase, now: now)
    data.addTodo("学习", schedule: .span(start: d(10, 1), end: d(10, 7)), groupID: g, tags: [], now: now)
    let (s, e) = nextPhaseRange(items: data.todos(in: g), today: d(10, 3))
    #expect(s == d(10, 8) && e == d(10, 14))
    let (s2, _) = nextPhaseRange(items: [], today: d(10, 3))
    #expect(s2 == d(10, 3))
}

@Test func planningSortPutsOpenFirst() {
    let now = d(10, 1).date()
    var data = PlanData()
    let a = data.addTodo("甲", schedule: .none, groupID: nil, tags: [], now: now)!
    data.addTodo("乙", schedule: .none, groupID: nil, tags: [], now: now.addingTimeInterval(1))
    data.update(a) { $0.priority = .p0 }
    let c = data.addTodo("丙", schedule: .none, groupID: nil, tags: [], now: now.addingTimeInterval(2))!
    data.toggle(todoID: c, on: d(10, 1), now: now)
    #expect(sortedForPlanning(data.todos).map(\.text) == ["甲", "乙", "丙"])
}
