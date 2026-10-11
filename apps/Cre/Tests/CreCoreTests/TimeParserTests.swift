import Foundation
import Testing
@testable import CreCore

private func p(_ s: String, _ t: DayKey = today) -> ParsedInput { parseInput(s, today: t) }

private func weekdays(_ r: ParsedInput) -> Set<Int>? {
    if case .repeating(let rep) = r.schedule { return rep.weekdays }
    return nil
}

@Test func dayWithChineseDate() {
    #expect(p("10月8日 买香蕉") == ParsedInput(text: "买香蕉", schedule: .day(d(10, 8))))
}

@Test func deadlineKeyword() {
    #expect(p("买香蕉 ddl 10月8日") == ParsedInput(text: "买香蕉", schedule: .deadline(d(10, 8))))
    #expect(p("买香蕉 10.8 截止") == ParsedInput(text: "买香蕉", schedule: .deadline(d(10, 8))))
    #expect(p("买香蕉 DDL10/8") == ParsedInput(text: "买香蕉", schedule: .deadline(d(10, 8))))
}

@Test func spanWithDash() {
    #expect(p("学习 10.5–10.11") == ParsedInput(text: "学习", schedule: .span(start: d(10, 5), end: d(10, 11))))
    #expect(p("学习 10月5日至10月11日").schedule == .span(start: d(10, 5), end: d(10, 11)))
}

@Test func everyDay() {
    let r = p("健身 每天")
    #expect(r.text == "健身")
    #expect(weekdays(r) == [])
}

@Test func weekdaysList() {
    let r = p("健身 每周一三五")
    #expect(r.text == "健身")
    #expect(weekdays(r) == [2, 4, 6])
}

@Test func weekdayRange() {
    #expect(weekdays(p("健身 周一到周六")) == [2, 3, 4, 5, 6, 7])
    #expect(weekdays(p("健身 每周一至五")) == [2, 3, 4, 5, 6])
}

@Test func relativeDays() {
    #expect(p("明天 交表") == ParsedInput(text: "交表", schedule: .day(d(10, 6))))
    #expect(p("后天交表").schedule == .day(d(10, 7)))
    #expect(p("下周三 开会").schedule == .day(d(10, 14)))
}

@Test func noDate() {
    #expect(p("买香蕉") == ParsedInput(text: "买香蕉", schedule: .none))
}

@Test func numbersThatAreNotDates() {
    for s in ["买 2 斤香蕉", "读 10.5 页", "跑 3.5 公里", "iPhone 15", "花了 12.30 元"] {
        #expect(p(s) == ParsedInput(text: s, schedule: .none))
    }
}

@Test func invalidMonthDayIsNotADate() {
    #expect(p("版本 13.40").schedule == .none)
}

@Test func pastMonthDayMeansNextYear() {
    #expect(p("1月3日 交房租", d(12, 20)).schedule == .day(d(1, 3, 2027)))
}

@Test func spanAcrossYearEnd() {
    #expect(p("放假 12.28–1.3", d(12, 1)).schedule == .span(start: d(12, 28), end: d(1, 3, 2027)))
}

@Test func repeatStartsToday() {
    guard case .repeating(let r) = p("健身 每天").schedule else { Issue.record("not repeating"); return }
    #expect(r.start == today)
}
