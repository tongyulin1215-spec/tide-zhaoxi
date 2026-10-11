import Foundation
import Testing
@testable import CreCore

@Test func dailySummaryCountsAndGroups() {
    var data = PlanData()
    let g = data.addGroup("工作", now: Date())
    let a = make("交周报", .day(today), group: g, into: &data)
    _ = make("回邮件", .day(today), group: g, into: &data)
    let c = make("买香蕉", .day(today), into: &data)
    data.toggle(todoID: a, on: today, now: Date())
    data.toggle(todoID: c, on: today, now: Date())
    let s = makeDailySummary(day: today, data: data, now: Date())
    #expect(s.done == 2 && s.total == 3)
    #expect(s.rate == 67)
    #expect(s.doneItems.map(\.text) == ["交周报", "买香蕉"])
    #expect(s.doneItems.map(\.group) == ["工作", nil])
    #expect(s.openItems.map(\.text) == ["回邮件"])
}

@Test func dailySummaryIncludesRepeatDetail() {
    var data = PlanData()
    let gid = data.addGroup("读书", kind: .list(minutes: 60), schedule: Repeat(start: d(10, 1)), now: Date())
    let book = make("人类简史", .none, group: gid, into: &data)
    data.setOngoing(book, true)
    data.toggleRepeat(todoID: data.anchor(of: gid)!.id, on: today, now: Date())
    let s = makeDailySummary(day: today, data: data, now: Date())
    #expect(s.doneItems.map(\.text) == ["读书 1 小时 ▶ 人类简史"])
}

@Test func generateStoresAndReplacesSameDay() {
    var data = PlanData()
    _ = make("交表", .day(today), into: &data)
    data.generateSummary(day: today, now: Date())
    data.generateSummary(day: today, now: Date())
    #expect(data.summaries.count == 1)
    #expect(data.summaries[0].day == today)
}

@Test func regenerateKeepsNote() {
    var data = PlanData()
    data.notes[today] = "今天效率不错"
    data.generateSummary(day: today, now: Date())
    data.generateSummary(day: today, now: Date())
    #expect(data.notes[today] == "今天效率不错")
}

@Test func summariesNewestFirst() {
    var data = PlanData()
    data.generateSummary(day: d(10, 2), now: Date())
    data.generateSummary(day: d(10, 4), now: Date())
    data.generateSummary(day: d(10, 3), now: Date())
    #expect(data.summariesNewestFirst.map(\.day) == [d(10, 4), d(10, 3), d(10, 2)])
}

@Test func oldPlanFileWithoutSummariesLoads() throws {
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    let p = try dec.decode(PlanData.self, from: Data(#"{"todos":[]}"#.utf8))
    #expect(p.summaries.isEmpty && p.notes.isEmpty)
}

@Test func deletingSummaryKeepsNote() {
    var data = PlanData()
    data.notes[today] = "随笔"
    data.generateSummary(day: today, now: Date())
    data.deleteSummary(day: today)
    #expect(data.summaries.isEmpty)
    #expect(data.notes[today] == "随笔")
}
