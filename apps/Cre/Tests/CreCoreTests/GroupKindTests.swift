import Foundation
import Testing
@testable import CreCore

private func sixDays(gap: Int) -> DayPlan {
    DayPlan(mode: .rotate, days: ["练胸", "练背", "练腿", "练肩", "练臂", "核心"].map { PlanDay(name: $0) }, gap: gap)
}

/// A rotating cycle group "健身" starting 10-05; returns (data, anchor id).
private func cycleGroup(_ plan: DayPlan) -> (PlanData, UUID) {
    var data = PlanData()
    let g = data.addGroup("健身", kind: .cycle, schedule: Repeat(start: d(10, 5), plan: plan), now: d(10, 5).date())
    return (data, data.anchor(of: g)!.id)
}

private func shown(_ data: PlanData, _ day: DayKey) -> String? {
    agenda(for: day, today: day, data: data).entries.first { $0.text == "健身" }?.detail
}

@Test func rotateGapStopsAfterRound() {
    var (data, id) = cycleGroup(sixDays(gap: 1))
    for i in 0..<6 { data.toggleRepeat(todoID: id, on: d(10, 5).adding(days: i), now: Date()) }
    #expect(agenda(for: d(10, 11), today: d(10, 11), data: data).entries.isEmpty)
    #expect(shown(data, d(10, 12)) == "练胸")
}

@Test func rotateMissedDayCarriesAcrossWeeks() {
    var (data, id) = cycleGroup(sixDays(gap: 1))
    // Mon 10-05 done; Tue/Wed missed; Thu–Sun done.
    for day in [5, 8, 9, 10, 11] { data.toggleRepeat(todoID: id, on: d(10, day), now: Date()) }
    #expect(shown(data, d(10, 6)) == "练背")
    #expect(shown(data, d(10, 7)) == "练背")
    #expect(shown(data, d(10, 12)) == "核心") // next Monday continues
    data.toggleRepeat(todoID: id, on: d(10, 12), now: Date())
    #expect(agenda(for: d(10, 13), today: d(10, 13), data: data).entries.isEmpty) // gap
    #expect(shown(data, d(10, 14)) == "练胸")
}

@Test func rotateGapZeroNeverStops() {
    var (data, id) = cycleGroup(sixDays(gap: 0))
    for i in 0..<6 { data.toggleRepeat(todoID: id, on: d(10, 5).adding(days: i), now: Date()) }
    #expect(shown(data, d(10, 11)) == "练胸")
}

@Test func rotateLongPeriodAllowed() {
    let plan = DayPlan(mode: .rotate, days: (1...10).map { PlanDay(name: "第\($0)项") }, gap: 2)
    var (data, id) = cycleGroup(plan)
    for i in 0..<9 { data.toggleRepeat(todoID: id, on: d(10, 5).adding(days: i), now: Date()) }
    #expect(shown(data, d(10, 14)) == "第10项")
}

@Test func cycleAnchorIsNamedAfterGroup() {
    let (data, _) = cycleGroup(sixDays(gap: 1))
    #expect(data.todos.count == 1)
    #expect(data.todos[0].text == "健身")
    #expect(data.todos[0].isGroupAnchor)
}

@Test func listAnchorShowsDurationAndOngoing() {
    var data = PlanData()
    let g = data.addGroup("读书", kind: .list(minutes: 60), schedule: Repeat(start: d(10, 1)), now: Date())
    let book = make("人类简史", .none, group: g, into: &data)
    data.setOngoing(book, true)
    let e = agenda(for: today, today: today, data: data).entries
    #expect(e.map(\.text) == ["读书 1 小时"])
    #expect(e[0].detail == "人类简史")
}

@Test func durationText() {
    #expect(durationLabel(minutes: 30) == "30 分钟")
    #expect(durationLabel(minutes: 120) == "2 小时")
    #expect(durationLabel(minutes: 90) == "1 小时 30 分钟")
}

@Test func listWeeklyOnlyOnChosenDays() {
    var data = PlanData()
    _ = data.addGroup("网课", kind: .list(minutes: 120), schedule: Repeat(weekdays: [2, 4, 6], start: d(10, 1)), now: Date())
    #expect(texts(agenda(for: d(10, 5), today: d(10, 5), data: data)) == ["网课 2 小时"])
    #expect(texts(agenda(for: d(10, 6), today: d(10, 6), data: data)).isEmpty)
}

@Test func changingKindKeepsTodos() {
    var data = PlanData()
    let g = data.addGroup("读书", kind: .list(minutes: 60), schedule: Repeat(start: d(10, 1)), now: Date())
    _ = make("人类简史", .none, group: g, into: &data)
    data.setGroupKind(g, .ungrouped, today: today, now: Date())
    #expect(data.todos.count == 2)
    #expect(data.todos.allSatisfy { !$0.isGroupAnchor })
    #expect(data.group(g)?.kind == .ungrouped)
}

@Test func changingToCycleCreatesAnchor() {
    var data = PlanData()
    let g = data.addGroup("跑步", now: Date())
    data.setGroupKind(g, .cycle, today: today, now: Date())
    #expect(data.anchor(of: g)?.text == "跑步")
}

@Test func oldGroupsDecodeAsUngrouped() throws {
    let json = #"{"id":"6E6790BC-4504-4244-A262-0EC5211FACD4","name":"x","collapsed":false,"todayDisplay":"expanded","sortOrder":1,"createdAt":"2026-10-01T04:00:00Z"}"#
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    #expect(try dec.decode(TodoGroup.self, from: Data(json.utf8)).kind == .ungrouped)
}
