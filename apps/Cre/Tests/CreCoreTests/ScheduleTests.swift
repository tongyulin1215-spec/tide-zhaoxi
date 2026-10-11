import Foundation
import Testing
@testable import CreCore

// today = 10/5 (Monday); this week = 10/5 … 10/11
private let week = (0..<7).map { today.adding(days: $0) }

private func titles(_ s: ScheduleData, _ day: DayKey) -> [String] {
    s.occurrences(on: day).map { "\($0.title) \($0.start)-\($0.end)" }
}

@Test func durationFromTitle() {
    #expect(minutesInTitle("读书 1 小时") == 60)
    #expect(minutesInTitle("Apex练枪半小时") == 30)
    #expect(minutesInTitle("阅读 1 小时 30 分钟") == 90)
    #expect(minutesInTitle("背单词 45分钟") == 45)
    #expect(minutesInTitle("跑步1.5小时") == 90)
    #expect(minutesInTitle("两小时复盘") == 120)
    #expect(minutesInTitle("买香蕉") == nil)
}

@Test func snapsToQuarterHour() {
    #expect(snapMinute(7 * 60 + 7) == 7 * 60)
    #expect(snapMinute(7 * 60 + 8) == 7 * 60 + 15)
    #expect(snapMinute(-20) == 0)
    #expect(snapMinute(24 * 60 + 30) == 24 * 60)
}

@Test func singleItemShowsOnItsDayOnly() {
    var s = ScheduleData()
    s.add(title: "测试", day: d(10, 8), start: 180, end: 240)
    #expect(titles(s, d(10, 8)) == ["测试 180-240"])
    #expect(titles(s, d(10, 9)).isEmpty)
}

@Test func dailyAndWeeklyRepeatFromTheirStart() {
    var s = ScheduleData()
    s.add(title: "读书", day: d(10, 6), start: 420, end: 480, repeats: .daily)
    s.add(title: "游泳", day: d(10, 5), start: 1140, end: 1200, repeats: .weekly([4, 6]))  // 周三、周五
    #expect(titles(s, d(10, 5)).isEmpty)
    #expect(titles(s, d(10, 7)) == ["读书 420-480", "游泳 1140-1200"])
    #expect(titles(s, d(10, 9)) == ["读书 420-480", "游泳 1140-1200"])
    #expect(titles(s, d(10, 10)) == ["读书 420-480"])
}

@Test func movingOneOccurrenceLeavesTheRest() {
    var s = ScheduleData()
    let id = s.add(title: "读书", day: d(10, 5), start: 420, end: 480, repeats: .daily)
    s.move(id, from: d(10, 6), to: d(10, 6), start: 540, end: 600, scope: .one)
    #expect(titles(s, d(10, 6)) == ["读书 540-600"])
    #expect(titles(s, d(10, 7)) == ["读书 420-480"])
}

@Test func movingAllChangesEveryDay() {
    var s = ScheduleData()
    let id = s.add(title: "读书", day: d(10, 5), start: 420, end: 480, repeats: .daily)
    s.move(id, from: d(10, 6), to: d(10, 6), start: 540, end: 600, scope: .all)
    #expect(titles(s, d(10, 5)) == ["读书 540-600"])
    #expect(titles(s, d(10, 9)) == ["读书 540-600"])
}

@Test func movingAllWeeklyToAnotherDayShiftsTheWeekday() {
    var s = ScheduleData()
    let id = s.add(title: "游泳", day: d(10, 5), start: 1140, end: 1200, repeats: .weekly([4]))  // 周三
    s.move(id, from: d(10, 7), to: d(10, 8), start: 1140, end: 1200, scope: .all)
    #expect(titles(s, d(10, 7)).isEmpty)
    #expect(titles(s, d(10, 8)) == ["游泳 1140-1200"])
}

@Test func movingSingleItemToAnotherDay() {
    var s = ScheduleData()
    let id = s.add(title: "测试", day: d(10, 8), start: 180, end: 240)
    s.move(id, from: d(10, 8), to: d(10, 9), start: 600, end: 660, scope: .all)
    #expect(titles(s, d(10, 8)).isEmpty)
    #expect(titles(s, d(10, 9)) == ["测试 600-660"])
}

@Test func deletingOneOccurrenceOrAll() {
    var s = ScheduleData()
    let id = s.add(title: "读书", day: d(10, 5), start: 420, end: 480, repeats: .daily)
    s.delete(id, on: d(10, 6), scope: .one)
    #expect(titles(s, d(10, 6)).isEmpty)
    #expect(titles(s, d(10, 7)) == ["读书 420-480"])
    s.delete(id, on: d(10, 7), scope: .all)
    #expect(s.items.isEmpty)
}

@Test func overlappingItemsSitSideBySide() {
    var s = ScheduleData()
    s.add(title: "A", day: today, start: 540, end: 660)
    s.add(title: "B", day: today, start: 600, end: 720)
    s.add(title: "C", day: today, start: 780, end: 840)
    let lay = s.layout(on: today)
    #expect(lay.map { "\($0.occurrence.title) \($0.column)/\($0.columns)" } == ["A 0/2", "B 1/2", "C 0/1"])
}

@Test func scheduleSurvivesSaveAndLoad() throws {
    var s = ScheduleData()
    s.add(title: "游泳", day: d(10, 5), start: 1140, end: 1200, repeats: .weekly([4, 6]))
    let back = try JSONDecoder().decode(ScheduleData.self, from: JSONEncoder().encode(s))
    #expect(back == s)
    _ = week
}

@Test func sourceKindTravelsWithTheItem() throws {
    var s = ScheduleData()
    let id = s.add(title: "读书", day: d(10, 5), start: 420, end: 480, repeats: .daily, kind: .repeating)
    s.move(id, from: d(10, 6), to: d(10, 6), start: 540, end: 600, scope: .one)
    #expect(s.occurrences(on: d(10, 6)).first?.kind == .repeating)
    #expect(s.occurrences(on: d(10, 7)).first?.kind == .repeating)
    let back = try JSONDecoder().decode(ScheduleData.self, from: JSONEncoder().encode(s))
    #expect(back == s)
    let old = try JSONDecoder().decode(ScheduleData.self, from: Data(#"{"version":1,"items":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"x","day":"2026-10-05","start":60,"end":120,"repeats":{"none":{}},"skipped":[]}]}"#.utf8))
    #expect(old.items.first?.kind == nil)
}
