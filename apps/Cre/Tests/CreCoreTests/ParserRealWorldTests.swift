import Foundation
import Testing
@testable import CreCore

private let t4 = d(10, 4) // Sunday
private func p(_ s: String, _ day: DayKey = today) -> ParsedInput { parseInput(s, today: day) }

@Test func beforeDateMeansDeadline() {
    let r = p("10月8日之前准备第二轮汇报，优先级p1，", t4)
    #expect(r.text == "准备第二轮汇报")
    #expect(r.schedule == .deadline(d(10, 8)))
    #expect(r.priority == .p1)
}

@Test func priorityWordIsRemoved() {
    let r = p("准备汇报 优先级：P0 截止10月12日", t4)
    #expect(r.text == "准备汇报")
    #expect(r.priority == .p0)
    #expect(r.schedule == .deadline(d(10, 12)))
}

@Test func chineseNumeralDates() {
    #expect(p("十月八号前交材料", t4) == ParsedInput(text: "交材料", schedule: .deadline(d(10, 8))))
    #expect(p("十一月二十日 看牙医", t4).schedule == .day(d(11, 20)))
}

@Test func weekdayDeadlines() {
    // today Mon 10-05
    #expect(p("周五前交周报") == ParsedInput(text: "交周报", schedule: .deadline(d(10, 9))))
    #expect(p("下周三之前 提交").schedule == .deadline(d(10, 14)))
    #expect(p("明天之前交表").schedule == .deadline(d(10, 6)))
    #expect(p("周三 开会").schedule == .day(d(10, 7)))
}

@Test func moreDeadlineWords() {
    #expect(p("交材料 截至10月20日", t4).schedule == .deadline(d(10, 20)))
    #expect(p("交材料 deadline 10.20", t4).schedule == .deadline(d(10, 20)))
    #expect(p("交材料，10月20日到期", t4).schedule == .deadline(d(10, 20)))
}

@Test func leftoverPunctuationCleaned() {
    #expect(p("，，买香蕉，明天，", t4).text == "买香蕉")
    #expect(p("买香蕉、苹果 明天", t4).text == "买香蕉、苹果")
}

@Test func weekdayPastThisWeekGoesToNextWeek() {
    // today Sun 10-04: "周五" means the coming Friday 10-09
    #expect(p("周五 交报告", t4).schedule == .day(d(10, 9)))
}

@Test func repeatWithStartDay() {
    let r = p("从10.8开始，每天Apex练枪半小时", d(10, 6))
    #expect(r.text == "Apex练枪半小时")
    #expect(r.schedule == .repeating(Repeat(start: d(10, 8))))
    #expect(p("每天Apex练枪半小时，10月8日起", d(10, 6)).schedule == .repeating(Repeat(start: d(10, 8))))
    let w = p("每周三从下周一开始 游泳")
    #expect(w.text == "游泳")
    #expect(w.schedule == .repeating(Repeat(weekdays: [4], start: d(10, 12))))
}

@Test func startPhraseWithoutRepeatIsThatDay() {
    #expect(p("从10.8开始 Apex练枪", d(10, 6)) == ParsedInput(text: "Apex练枪", schedule: .day(d(10, 8))))
}

@Test func qiInsideAWordIsNotAStart() {
    #expect(p("明天起床跑步") == ParsedInput(text: "起床跑步", schedule: .day(d(10, 6))))
}
