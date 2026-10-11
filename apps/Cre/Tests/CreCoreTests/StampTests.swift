import Foundation
import Testing
@testable import CreCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let now = t0.addingTimeInterval(3600)

@Test func onlyTheEditedTodoIsStamped() {
    var old = PlanData()
    let g = old.addGroup("读书", kind: .list(standard: "1 小时"), now: t0)
    let a = old.addTodo("人类简史", schedule: .none, groupID: g, tags: [], now: t0)!
    let b = old.addTodo("三体", schedule: .none, groupID: g, tags: [], now: t0)!
    old = old.stamped(since: PlanData(), now: t0)      // first save: everything new
    var new = old
    new.update(a) { $0.text = "人类简史（重读）" }
    let s = new.stamped(since: old, now: now)
    #expect(s.todos.first { $0.id == a }?.modifiedAt == now)
    #expect(s.todos.first { $0.id == b }?.modifiedAt == t0)
    #expect(s.groups.first { $0.id == g }?.modifiedAt == t0)
}

@Test func untouchedRecordsKeepNoStamp() throws {
    let json = #"{"version":1,"groups":[],"todos":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"a","createdAt":0,"schedule":{"kind":"none"}},{"id":"6F9619FF-8B86-D011-B42D-00C04FC964F0","text":"b","createdAt":0,"schedule":{"kind":"none"}}]}"#
    let old = try JSONDecoder().decode(PlanData.self, from: Data(json.utf8))
    #expect(old.todos.allSatisfy { $0.modifiedAt == nil })
    var new = old
    new.update(old.todos[0].id) { $0.text = "a2" }
    let s = new.stamped(since: old, now: now)
    #expect(s.todos[0].modifiedAt == now)
    #expect(s.todos[1].modifiedAt == nil)
}

@Test func deletingWritesAMark() {
    var old = PlanData()
    let a = old.addTodo("x", schedule: .none, groupID: nil, tags: [], now: t0)!
    var new = old
    new.deleteTodo(a)
    #expect(new.stamped(since: old, now: now).deletions["todo:\(a.uuidString)"] == now)
}

@Test func restoringRemovesDeletionMark() {
    var old = PlanData()
    let a = old.addTodo("x", schedule: .none, groupID: nil, tags: [], now: t0)!
    var deleted = old
    deleted.deleteTodo(a)
    deleted = deleted.stamped(since: old, now: now)
    var restored = old
    restored.deletions = deleted.deletions                // undo puts the todo back
    let s = restored.stamped(since: deleted, now: now.addingTimeInterval(5))
    #expect(s.deletions["todo:\(a.uuidString)"] == nil)
    #expect(s.todos.count == 1)
}

@Test func noteChangeStampsThatDay() {
    var old = PlanData()
    old.notes[d(10, 4)] = "旧"
    var new = old
    new.notes[d(10, 5)] = "新的一天"
    let s = new.stamped(since: old, now: now)
    #expect(s.noteStamps[d(10, 5)] == now)
    #expect(s.noteStamps[d(10, 4)] == nil)
}

@Test func ledgerAndScheduleStampLikewise() {
    var lo = LedgerData()
    lo.add(LedgerEntry(amount: 3500, isIncome: false, category: "餐饮", note: "午饭", day: d(10, 5)), now: t0)
    lo.add(LedgerEntry(amount: 600, isIncome: false, category: "交通", note: "地铁", day: d(10, 5)), now: t0)
    var ln = lo
    ln.update(lo.entries[0].id) { $0.amount = 3800 }
    ln.delete(lo.entries[1].id)
    ln.opening = OpeningBalance(amount: 100_00, day: d(10, 1))
    let ls = ln.stamped(since: lo, now: now)
    #expect(ls.entries[0].modifiedAt == now)
    #expect(ls.deletions["entry:\(lo.entries[1].id.uuidString)"] == now)
    #expect(ls.openingModifiedAt == now)
    #expect(ls.settingsModifiedAt == nil)

    var so = ScheduleData()
    let id = so.add(title: "读书", day: d(10, 5), start: 420, end: 480)
    var sn = so
    sn.move(id, from: d(10, 5), to: d(10, 5), start: 540, end: 600, scope: .all)
    #expect(sn.stamped(since: so, now: now).items[0].modifiedAt == now)
    var sd = so
    sd.delete(id, on: d(10, 5), scope: .all)
    #expect(sd.stamped(since: so, now: now).deletions["schedule:\(id.uuidString)"] == now)
}

@Test func stampsSurviveSaveAndOldFilesLoad() throws {
    var old = PlanData()
    let a = old.addTodo("x", schedule: .none, groupID: nil, tags: [], now: t0)!
    old.notes[d(10, 5)] = "n"
    var new = old
    new.deleteTodo(a)
    new.notes[d(10, 5)] = "m"
    let s = new.stamped(since: old, now: now)
    let back = try JSONDecoder().decode(PlanData.self, from: JSONEncoder().encode(s))
    #expect(back == s)
    let empty = try JSONDecoder().decode(PlanData.self, from: Data(#"{"version":1}"#.utf8))
    #expect(empty.deletions.isEmpty && empty.noteStamps.isEmpty && empty.pulledTagStamps.isEmpty)
}

@Test func summaryDeletionKeyIsZeroPadded() {
    var old = PlanData()
    old.generateSummary(day: d(10, 9), now: t0)
    var new = old
    new.deleteSummary(day: d(10, 9))
    #expect(new.stamped(since: old, now: now).deletions["summary:2026-10-09"] == now)
}
