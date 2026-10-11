import Foundation
import Testing
@testable import CreCore

@Test func addLineParsesAndFallsBackToViewingDay() {
    var data = PlanData()
    let id = data.addLine("交周报 p1", override: nil, groupID: nil, viewingDay: d(10, 7), today: today, now: today.date())
    let t = data.todos.first { $0.id == id }
    #expect(t?.text == "交周报")
    #expect(t?.schedule == .day(d(10, 7)))
    #expect(t?.priority == .p1)
}

@Test func addLineKeepsUndatedInGroups() {
    var data = PlanData()
    let g = data.addGroup("读书", kind: .list(standard: "1 小时"), now: today.date())
    let id = data.addLine("三体", override: nil, groupID: g, viewingDay: nil, today: today, now: today.date())
    #expect(data.todos.first { $0.id == id }?.schedule == Schedule.none)
    #expect(data.addLine("   ", override: nil, groupID: nil, viewingDay: today, today: today, now: today.date()) == nil)
}

@Test func addLineOverrideWins() {
    var data = PlanData()
    let id = data.addLine("报告 #工作", override: TimeChoice(schedule: .deadline(d(10, 9)), priority: .p0, tags: ["急"]),
                          groupID: nil, viewingDay: today, today: today, now: today.date())
    let t = data.todos.first { $0.id == id }
    #expect(t?.schedule == .deadline(d(10, 9)))
    #expect(t?.priority == .p0)
    #expect(t?.tags == ["工作", "急"])
}

@Test func renameIgnoresBlank() {
    var data = PlanData()
    let id = data.addTodo("旧", schedule: .none, groupID: nil, tags: [], now: today.date())!
    data.rename(id, "  ")
    #expect(data.todos[0].text == "旧")
    data.rename(id, " 新 ")
    #expect(data.todos[0].text == "新")
}

@Test func setTimeKeepsTagsWhenNil() {
    var data = PlanData()
    let id = data.addTodo("x", schedule: .none, groupID: nil, tags: ["a"], now: today.date())!
    data.setTime(id, TimeChoice(schedule: .day(today), priority: .p2, tags: nil))
    #expect(data.todos[0].tags == ["a"])
    #expect(data.todos[0].schedule == .day(today))
    data.setTime(id, TimeChoice(schedule: .day(today), priority: nil, tags: ["b"]))
    #expect(data.todos[0].tags == ["b"])
}
