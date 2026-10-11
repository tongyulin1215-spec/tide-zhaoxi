import Foundation
import Testing
@testable import CreCore

// Final review, Important 1: decimals are not dates.
@Test func decimalsAreNotDates() {
    let t = d(10, 4)
    for s in ["喝水 1.5L", "1.5倍速看课", "跑了3.5", "app 2.1 版本发布", "下午3.30开会"] {
        #expect(parseInput(s, today: t).schedule == .none, "\(s)")
    }
}

@Test func nearbyDotDatesStillWork() {
    let t = d(10, 4)
    #expect(parseInput("买香蕉 10.8", today: t).schedule == .day(d(10, 8)))
    #expect(parseInput("交表 10.3", today: t).schedule == .day(d(10, 3))) // yesterday stays this year
    #expect(parseInput("放假 12.28–1.3", today: d(12, 1)).schedule == .span(start: d(12, 28), end: d(1, 3, 2027)))
}

// Important 2: a span already under way stays in this year.
@Test func spanInProgressStaysThisYear() {
    #expect(parseInput("学习 10.1–10.7", today: d(10, 4)).schedule == .span(start: d(10, 1), end: d(10, 7)))
    #expect(parseInput("放假 12.28–1.3", today: d(1, 1, 2027)).schedule == .span(start: d(12, 28), end: d(1, 3, 2027)))
}

// Important 3: ticking on a future day counts for today.
@Test func tickingOnFutureDayCountsToday() {
    var data = PlanData()
    let id = make("交报告", .deadline(d(10, 20)), into: &data)
    data.toggle(todoID: id, on: d(10, 10), today: today, now: Date())
    #expect(data.todos[0].completedDay == today)
    let e = agenda(for: today, today: today, data: data)
    #expect(e.entries.map(\.isDone) == [true])
}

// Important 4/5/6: schedule can be set and changed after creation; kind changes keep content.
@Test func switchingToCycleGetsEditablePlan() {
    var data = PlanData()
    let g = data.addGroup("跑步", now: Date())
    _ = make("买跑鞋", .none, group: g, into: &data)
    data.setGroupSchedule(g, kind: .cycle, rule: Repeat(weekdays: [2, 4, 6], start: today,
        plan: DayPlan(mode: .fixedWeekday, days: [2, 4, 6].map { PlanDay(name: "", weekday: $0) })), now: Date())
    guard case .repeating(let r)? = data.anchor(of: g)?.schedule else { Issue.record("no anchor"); return }
    #expect(r.plan?.days.count == 3)
    #expect(data.todos.contains { $0.text == "买跑鞋" })
}

@Test func switchingCycleToListDropsPlanAndKeepsMinutes() {
    var data = PlanData()
    let g = data.addGroup("读书", kind: .list(minutes: 90), schedule: Repeat(start: d(10, 1)), now: Date())
    data.setGroupSchedule(g, kind: .cycle, rule: Repeat(start: d(10, 1), plan: DayPlan(mode: .rotate, days: [PlanDay(name: "A")], gap: 1)), now: Date())
    data.setGroupSchedule(g, kind: .list(minutes: 90), rule: Repeat(start: d(10, 1)), now: Date())
    let book = make("人类简史", .none, group: g, into: &data)
    data.setOngoing(book, true)
    let e = agenda(for: today, today: today, data: data).entries
    #expect(e.map(\.text) == ["读书 1 小时 30 分钟"])
    #expect(e[0].detail == "人类简史")
}

@Test func editingScheduleKeepsHistory() {
    var data = PlanData()
    let g = data.addGroup("健身", kind: .cycle, schedule: Repeat(weekdays: [2], start: d(9, 28),
        plan: DayPlan(mode: .fixedWeekday, days: [PlanDay(name: "练胸", weekday: 2)])), now: Date())
    let id = data.anchor(of: g)!.id
    data.toggleRepeat(todoID: id, on: d(9, 28), now: Date())
    // The edit sheet passes the group's own start back unless the user changes it.
    data.setGroupSchedule(g, kind: .cycle, rule: Repeat(weekdays: [2, 4], start: d(9, 28),
        plan: DayPlan(mode: .fixedWeekday, days: [PlanDay(name: "练胸", weekday: 2), PlanDay(name: "练背", weekday: 4)])), now: Date())
    guard case .repeating(let r)? = data.anchor(of: g)?.schedule else { Issue.record("no anchor"); return }
    #expect(r.completions[d(9, 28)] != nil)
    #expect(r.start == d(9, 28))
    #expect(r.weekdays == [2, 4])
}

// Important 7: an unreadable file is reported, and never overwritten.
@Test func corruptFileIsReported() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cre-r7-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("data.json")
    try "not json".write(to: url, atomically: true, encoding: .utf8)
    let store = PlanStore(fileURL: url)
    _ = store.load()
    guard case .movedAside(let backup)? = store.loadIssue else { Issue.record("no issue"); return }
    #expect(FileManager.default.fileExists(atPath: backup.path))
}

@Test func unmovableCorruptFileMakesStoreReadOnly() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cre-r7b-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("data.json")
    try "not json".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
    let store = PlanStore(fileURL: url)
    _ = store.load()
    #expect(store.loadIssue == .unreadable)
    #expect(throws: (any Error).self) { try store.save(PlanData()) }
    #expect(try String(contentsOf: url, encoding: .utf8) == "not json")
}

// Minor 2: "下周一到周三" is a span next week, not a weekly repeat.
@Test func nextWeekRangeIsSpan() {
    let r = parseInput("下周一到周三出差", today: d(10, 4)) // Sunday
    #expect(r.text == "出差")
    #expect(r.schedule == .span(start: d(10, 5), end: d(10, 7)))
    let r2 = parseInput("下周一到周三出差", today: d(10, 7)) // Wednesday
    #expect(r2.schedule == .span(start: d(10, 12), end: d(10, 14)))
}

// Minor 3: an unnamed day shows no "▶".
@Test func unnamedDayHasNoDetail() {
    var data = PlanData()
    _ = make("健身", .repeating(Repeat(weekdays: [2], start: d(10, 1),
        plan: DayPlan(mode: .fixedWeekday, days: [PlanDay(name: "", weekday: 2)]))), into: &data)
    #expect(agenda(for: d(10, 5), today: d(10, 5), data: data).entries[0].detail == nil)
}

// Minor 4: duplicate action lines get their own ids; unchanged lines keep theirs.
@Test func duplicateActionLinesGetOwnIds() {
    let old = [PlanItem(text: "卧推"), PlanItem(text: "飞鸟")]
    let merged = mergePlanItems(old: old, lines: ["卧推", "卧推", "飞鸟"])
    #expect(merged.map(\.text) == ["卧推", "卧推", "飞鸟"])
    #expect(Set(merged.map(\.id)).count == 3)
    #expect(merged[0].id == old[0].id)
    #expect(merged[2].id == old[1].id)
}
