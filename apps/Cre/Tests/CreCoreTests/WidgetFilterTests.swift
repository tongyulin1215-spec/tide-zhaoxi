import Foundation
import Testing
@testable import CreCore

@Test func widgetFilterChoicesPutBusiestTagsFirst() {
    var data = PlanData()
    _ = data.addTodo("a", schedule: .day(today), groupID: nil, tags: ["读书"], now: today.date())
    _ = data.addTodo("b", schedule: .day(today), groupID: nil, tags: ["秋招"], now: today.date())
    _ = data.addTodo("c", schedule: .day(today), groupID: nil, tags: ["秋招"], now: today.date())
    let choices = widgetFilterChoices(data: data)
    #expect(choices == [.all, .tag("秋招"), .tag("读书")])
    #expect(widgetFilterLabel(.tag("秋招"), data: data) == "#秋招")
    #expect(widgetFilterLabel(.all, data: data) == "全部")
}

@Test func widgetFilterChoicesAreCapped() {
    var data = PlanData()
    for t in ["a", "b", "c", "d", "e"] {
        _ = data.addTodo(t, schedule: .day(today), groupID: nil, tags: [t], now: today.date())
    }
    #expect(widgetFilterChoices(data: data, max: 4).count == 4)
}

@Test func widgetFilterNextCycles() {
    var data = PlanData()
    _ = data.addTodo("a", schedule: .day(today), groupID: nil, tags: ["x"], now: today.date())
    #expect(nextWidgetFilter(after: .all, data: data) == .tag("x"))
    #expect(nextWidgetFilter(after: .tag("x"), data: data) == .all)
    #expect(nextWidgetFilter(after: .tag("gone"), data: data) == .all)
}

@Test func widgetFilterRoundTripsThroughFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-\(UUID()).json")
    #expect(loadWidgetFilter(url) == .all)
    saveWidgetFilter(.tag("秋招"), to: url)
    #expect(loadWidgetFilter(url) == .tag("秋招"))
}

@Test func widgetFilterChoicesSkipGroups() {
    var data = PlanData()
    let g = data.addGroup("阅读", kind: .list(standard: "1 小时"), now: today.date())
    _ = data.addTodo("a", schedule: .day(today), groupID: nil, tags: ["秋招"], now: today.date())
    #expect(widgetFilterChoices(data: data) == [.all, .tag("秋招")])
    #expect(nextWidgetFilter(after: .tag("秋招"), data: data) == .all)
    _ = g
}

@Test func lockLineShowsNextOpen() {
    let today = d(10, 9)
    var data = PlanData()
    let a = data.addTodo("寄快递", schedule: .day(today), groupID: nil, tags: [], now: today.date())!
    data.addTodo("交周报", schedule: .day(today), groupID: nil, tags: [], now: today.date())
    data.toggle(todoID: a, on: today, today: today, now: today.date())
    let s = lockScreenSummary(today: today, data: data)
    #expect(s.done == 1 && s.total == 2)
    #expect(s.next == "交周报")
    let b = data.todos.first { $0.text == "交周报" }!.id
    data.toggle(todoID: b, on: today, today: today, now: today.date())
    #expect(lockScreenSummary(today: today, data: data).next == nil)
}
