import Foundation
import Testing
@testable import CreCore

private let t9 = d(10, 9).date(hour: 9), t10 = d(10, 9).date(hour: 10), t11 = d(10, 9).date(hour: 11)

/// One todo, saved once (stamped) at `at`.
private func base(_ text: String = "交周报", at: Date = t9) -> (PlanData, UUID) {
    var p = PlanData()
    let id = p.addTodo(text, schedule: .none, groupID: nil, tags: [], now: at)!
    return (p.stamped(since: PlanData(), now: at), id)
}

private func edited(_ p: PlanData, _ id: UUID, _ text: String, at: Date) -> PlanData {
    var n = p
    n.update(id) { $0.text = text }
    return n.stamped(since: p, now: at)
}

private func deleted(_ p: PlanData, _ id: UUID, at: Date) -> PlanData {
    var n = p
    n.deleteTodo(id)
    return n.stamped(since: p, now: at)
}

@Test func laterEditWins() {
    let (p, id) = base()
    let a = edited(p, id, "甲", at: t10), b = edited(p, id, "乙", at: t11)
    #expect(a.merged(with: b).todos.first { $0.id == id }?.text == "乙")
    #expect(b.merged(with: a).todos.first { $0.id == id }?.text == "乙")
}

@Test func editAfterDeleteRevives() {
    let (p, id) = base(at: d(10, 8).date())
    let a = deleted(p, id, at: t9), b = edited(p, id, "改过", at: t10)
    let m = a.merged(with: b)
    #expect(m.todos.first { $0.id == id }?.text == "改过")
    #expect(m.deletions["todo:\(id.uuidString)"] == nil)
    #expect(b.merged(with: a) == m)
}

@Test func deleteAfterEditRemoves() {
    let (p, id) = base(at: d(10, 8).date())
    let a = deleted(p, id, at: t10), b = edited(p, id, "改过", at: t9)
    let m = a.merged(with: b)
    #expect(!m.todos.contains { $0.id == id })
    #expect(m.deletions["todo:\(id.uuidString)"] == t10)
    #expect(!b.merged(with: a).todos.contains { $0.id == id })
}

@Test func emptyPhoneDoesNotEraseMac() {
    var mac = PlanData()
    for i in 0..<5 { mac.addTodo("待办\(i)", schedule: .none, groupID: nil, tags: [], now: t9) }
    mac.notes[d(10, 8)] = "随笔"
    var ledger = LedgerData()
    for i in 1...3 { ledger.add(LedgerEntry(amount: i * 100, isIncome: false, category: "餐饮", note: "", day: d(10, 9)), now: t9) }
    var schedule = ScheduleData()
    schedule.add(title: "组会", day: d(10, 9), start: 600, end: 660)
    schedule.add(title: "健身", day: d(10, 9), start: 1140, end: 1200)
    #expect(mac.merged(with: PlanData()).todos.count == 5)
    #expect(PlanData().merged(with: mac).todos.count == 5)
    #expect(PlanData().merged(with: mac).notes[d(10, 8)] == "随笔")
    #expect(LedgerData().merged(with: ledger).entries.count == 3)
    #expect(ScheduleData().merged(with: schedule).items.count == 2)
}

@Test func mergedKeepsTheWinnersStamp() {
    let (p, id) = base()
    let a = edited(p, id, "甲", at: t10), b = edited(p, id, "乙", at: t11)
    #expect(a.merged(with: b).todos.first { $0.id == id }?.modifiedAt == t11)
}

@Test func collapsedIsLocal() {
    var p = PlanData()
    let g = p.addGroup("读书", now: t9)
    p = p.stamped(since: PlanData(), now: t9)
    var folded = p
    folded.updateGroup(g) { $0.collapsed = true }
    let s = folded.stamped(since: p, now: t10)
    #expect(s.groups.first { $0.id == g }?.modifiedAt == t9)
    var renamed = p
    renamed.updateGroup(g) { $0.name = "阅读" }
    renamed = renamed.stamped(since: p, now: t11)
    let m = s.merged(with: renamed)
    #expect(m.groups.first { $0.id == g }?.name == "阅读")
    #expect(m.groups.first { $0.id == g }?.collapsed == true)
}

@Test func notesMergePerDay() {
    var a = PlanData(), b = PlanData()
    a.notes[d(10, 8)] = "旧"; a.noteStamps[d(10, 8)] = t9
    b.notes[d(10, 8)] = "新"; b.noteStamps[d(10, 8)] = t10
    b.notes[d(10, 7)] = nil; b.noteStamps[d(10, 7)] = t10
    a.notes[d(10, 7)] = "要删的"; a.noteStamps[d(10, 7)] = t9
    let m = a.merged(with: b)
    #expect(m.notes[d(10, 8)] == "新")
    #expect(m.notes[d(10, 7)] == nil)
}

@Test func ledgerSettingsByStamp() {
    var a = LedgerData(), b = LedgerData()
    a.expenseCategories += ["宠物"]; a.settingsModifiedAt = t9
    b.opening = OpeningBalance(amount: 100_000, day: d(10, 1)); b.settingsModifiedAt = t10
    let m = a.merged(with: b)
    #expect(m.opening?.amount == 100_000)
    #expect(!m.expenseCategories.contains("宠物"))
}

@Test func pruneDropsOldMarks() {
    let now = d(10, 31).date()
    var marks = ["todo:a": d(9, 30).date(), "todo:b": d(10, 2).date()]
    pruneDeletions(&marks, olderThan: 30, now: now)
    #expect(marks["todo:a"] == nil)
    #expect(marks["todo:b"] != nil)
}

@Test func dayStartOldFormatLoads() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ds-\(UUID()).json")
    try JSONEncoder().encode(3).write(to: url)
    #expect(loadDayStart(url) == DayStartSetting(hour: 3, modifiedAt: nil))
    saveDayStart(DayStartSetting(hour: 4, modifiedAt: t10), to: url)
    #expect(loadDayStart(url) == DayStartSetting(hour: 4, modifiedAt: t10))
    #expect(loadDayStartHour(url) == 4)
    #expect(DayStartSetting(hour: 1, modifiedAt: t9).merged(with: DayStartSetting(hour: 5, modifiedAt: t10)).hour == 5)
}

@Test func ledgerOpeningAndCategoriesMergeSeparately() {
    var mac = LedgerData()
    mac.opening = OpeningBalance(amount: 500_000, day: d(10, 1))
    mac = mac.stamped(since: LedgerData(), now: t9)
    var phone = LedgerData()
    var added = phone
    added.expenseCategories += ["宠物"]
    phone = added.stamped(since: phone, now: t10)
    let m = mac.merged(with: phone)
    #expect(m.opening?.amount == 500_000)
    #expect(m.expenseCategories.contains("宠物"))
    #expect(phone.merged(with: mac) == m)
}
