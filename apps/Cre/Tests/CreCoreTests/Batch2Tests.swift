import Foundation
import Testing
@testable import CreCore

// B1 tags
@Test func hashtagsParsed() {
    let r = parseInput("买键盘 #工作 #设备 ddl 10月8日", today: today)
    #expect(r.text == "买键盘")
    #expect(r.tags == ["工作", "设备"])
    #expect(r.schedule == .deadline(d(10, 8)))
}

@Test func hashInsideWordIsNotTag() {
    #expect(parseInput("C#入门", today: today).tags.isEmpty)
}

// B2 pulled tags
@Test func pulledTagBringsItemsIntoToday() {
    var data = PlanData()
    let a = make("整理文档", .none, into: &data)
    data.update(a) { $0.tags = ["工作"] }
    let b = make("报销", .day(d(10, 9)), into: &data)
    data.update(b) { $0.tags = ["工作"] }
    let c = make("已做完", .none, into: &data)
    data.update(c) { $0.tags = ["工作"]; $0.completedDay = d(10, 1) }
    data.pulledTags[today] = ["工作"]
    let e = agenda(for: today, today: today, data: data).entries
    #expect(Set(e.map(\.text)) == ["整理文档", "报销"])
    #expect(e.allSatisfy { $0.pulledBy == "工作" })
    #expect(agenda(for: d(10, 6), today: d(10, 6), data: data).entries.isEmpty)
}

@Test func pulledTagDoesNotDuplicate() {
    var data = PlanData()
    let a = make("交周报", .day(today), into: &data)
    data.update(a) { $0.tags = ["工作"] }
    data.pulledTags[today] = ["工作"]
    #expect(agenda(for: today, today: today, data: data).entries.map(\.text) == ["交周报"])
}

@Test func allTagsListed() {
    var data = PlanData()
    let a = make("a", .none, into: &data)
    let b = make("b", .none, into: &data)
    data.update(a) { $0.tags = ["工作", "家"] }
    data.update(b) { $0.tags = ["工作"] }
    #expect(data.allTags == ["家", "工作"].sorted())
}

// B3 groups
@Test func archivedGroupLeavesToday() {
    var data = PlanData()
    let g = data.addGroup("旧项目", now: Date())
    _ = make("收尾", .day(today), group: g, into: &data)
    data.updateGroup(g) { $0.isArchived = true }
    #expect(agenda(for: today, today: today, data: data).entries.isEmpty)
}

@Test func pinnedGroupsComeFirst() {
    var data = PlanData()
    _ = data.addGroup("A", now: Date())
    let b = data.addGroup("B", now: Date())
    data.updateGroup(b) { $0.isPinned = true }
    #expect(data.visibleGroups.map(\.name) == ["B", "A"])
    data.updateGroup(b) { $0.isArchived = true }
    #expect(data.visibleGroups.map(\.name) == ["A"])
    #expect(data.archivedGroups.map(\.name) == ["B"])
}

@Test func movingTodoIntoGroup() {
    var data = PlanData()
    let g = data.addGroup("工作", now: Date())
    let a = make("整理文档", .none, into: &data)
    data.moveTodo(a, toGroup: g)
    #expect(data.todos(in: g).map(\.text) == ["整理文档"])
    data.moveTodo(a, toGroup: nil)
    #expect(data.todos(in: nil).map(\.text) == ["整理文档"])
}

@Test func oldGroupDecodesUnpinnedUnarchived() throws {
    let json = #"{"id":"6E6790BC-4504-4244-A262-0EC5211FACD4","name":"x","createdAt":"2026-10-01T04:00:00Z"}"#
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    let g = try dec.decode(TodoGroup.self, from: Data(json.utf8))
    #expect(!g.isPinned && !g.isArchived)
}

// B8 streak
@Test func streakCountsScheduledDaysOnly() {
    var data = PlanData()
    let id = make("健身", .repeating(Repeat(weekdays: [2, 4, 6], start: d(9, 21))), into: &data)
    // Mon 9-28, Wed 9-30, Fri 10-2 done; Mon 10-5 (today) not yet.
    for day in [d(9, 28), d(9, 30), d(10, 2)] { data.toggleRepeat(todoID: id, on: day, now: Date()) }
    #expect(data.streak(for: id, on: today) == 3)
    data.toggleRepeat(todoID: id, on: today, now: Date())
    #expect(data.streak(for: id, on: today) == 4)
}

@Test func streakBreaksOnMissedDay() {
    var data = PlanData()
    let id = make("读书", .repeating(Repeat(start: d(10, 1))), into: &data)
    for day in [d(10, 1), d(10, 3), d(10, 4)] { data.toggleRepeat(todoID: id, on: day, now: Date()) }
    #expect(data.streak(for: id, on: today) == 2)
}
