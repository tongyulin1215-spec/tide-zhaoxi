import Foundation
import Testing
@testable import CreCore

private func bookData() -> (PlanData, UUID, UUID, UUID) {
    var data = PlanData()
    let g = data.addGroup("读书", kind: .list(standard: "1 小时"), now: today.date())
    let a = data.addTodo("人类简史", schedule: .none, groupID: g, tags: [], now: today.date())!
    let b = data.addTodo("三体", schedule: .none, groupID: g, tags: [], now: today.date())!
    data.toggle(todoID: a, on: d(10, 3), today: d(10, 3), now: d(10, 3).date())
    return (data, g, a, b)
}

@Test func finishedListItemsAreTheChoices() {
    let (data, g, a, _) = bookData()
    #expect(data.listGroupsWithFinished.map(\.id) == [g])
    #expect(data.finishedItems(in: g).map(\.id) == [a])
}

@Test func reflectionDefaultsToTickDayAndCanBeEdited() {
    var (data, _, a, _) = bookData()
    #expect(data.reflection(for: a) == nil)
    #expect(data.defaultFinishDay(for: a) == d(10, 3))
    data.saveReflection(todoID: a, finishedOn: d(10, 4), text: "人类为什么能合作。", now: today.date())
    #expect(data.reflection(for: a)?.finishedOn == d(10, 4))
    data.saveReflection(todoID: a, finishedOn: d(10, 4), text: "改一下。", now: today.date())
    #expect(data.reflections.count == 1)
    #expect(data.reflection(for: a)?.text == "改一下。")
}

@Test func reflectionsSurviveSaveAndOldFilesLoad() throws {
    var (data, _, a, _) = bookData()
    data.saveReflection(todoID: a, finishedOn: d(10, 3), text: "好书", now: today.date())
    let back = try JSONDecoder().decode(PlanData.self, from: JSONEncoder().encode(data))
    #expect(back.reflections == data.reflections)
    let old = try JSONDecoder().decode(PlanData.self, from: Data(#"{"version":1,"groups":[],"todos":[]}"#.utf8))
    #expect(old.reflections.isEmpty)
}

@Test func deletingItemDropsItsReflection() {
    var (data, _, a, _) = bookData()
    data.saveReflection(todoID: a, finishedOn: d(10, 3), text: "好书", now: today.date())
    data.deleteTodo(a)
    #expect(data.reflections.isEmpty)
}

// MARK: 新建感想: every case has somewhere to go

@Test func choicesListUnwrittenThenUnfinishedThenWritten() {
    var (data, g, a, b) = bookData()            // a 人类简史 finished, b 三体 open
    let c = data.addTodo("活着", schedule: .none, groupID: g, tags: [], now: today.date())!
    data.toggle(todoID: c, on: d(10, 4), today: d(10, 4), now: d(10, 4).date())
    data.saveReflection(todoID: a, finishedOn: d(10, 3), text: "好书", now: today.date())
    let ch = data.reflectionChoices(in: g)
    #expect(ch.map(\.todo.id) == [c, b, a])
    #expect(ch.map(\.status) == [.finished, .unfinished, .written])
}

@Test func defaultTargetIsLatestUnwrittenFinish() {
    var (data, g, a, _) = bookData()
    #expect(data.defaultReflectionTarget()?.todoID == a)
    data.saveReflection(todoID: a, finishedOn: d(10, 3), text: "x", now: today.date())
    // nothing finished & unwritten: first open item of a list
    #expect(data.defaultReflectionTarget()?.groupID == g)
    #expect(data.defaultReflectionTarget()?.todoID != a)
    #expect(PlanData().defaultReflectionTarget() == nil)   // no lists: write a free one
}

@Test func savingOnAnOpenItemFinishesIt() {
    var (data, _, _, b) = bookData()
    data.saveReflection(todoID: b, finishedOn: d(10, 2), text: "看完了", now: today.date())
    #expect(data.todos.first { $0.id == b }?.completedDay == d(10, 2))
}

@Test func freeReflectionHasItsOwnTitle() throws {
    var data = PlanData()
    let id = data.saveFreeReflection(id: nil, title: "沙丘2", finishedOn: d(10, 3), text: "画面好", now: today.date())
    _ = data.saveFreeReflection(id: id, title: "沙丘 2", finishedOn: d(10, 3), text: "画面好", now: today.date())
    #expect(data.reflections.count == 1)
    #expect(data.reflectionTitle(data.reflections[0]) == "沙丘 2")
    let back = try JSONDecoder().decode(PlanData.self, from: JSONEncoder().encode(data))
    #expect(back.reflections == data.reflections)
    data.deleteReflection(id: id)
    #expect(data.reflections.isEmpty)
}
