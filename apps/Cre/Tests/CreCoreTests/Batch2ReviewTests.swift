import Foundation
import Testing
@testable import CreCore

// I1: a pulled item that is checked stays (as done) and counts.
@Test func pulledItemStaysWhenChecked() {
    var data = PlanData()
    let a = make("整理文档", .none, into: &data)
    data.update(a) { $0.tags = ["工作"] }
    data.pulledTags[today] = ["工作"]
    data.toggle(todoID: a, on: today, today: today, now: Date())
    let ag = agenda(for: today, today: today, data: data)
    #expect(ag.entries.map(\.isDone) == [true])
    #expect(ag.progress == Progress(done: 1, total: 1))
    #expect(makeDailySummary(day: today, data: data, now: Date()).done == 1)
}

// I3: archived groups stay out of pulls and Friday cleanup.
@Test func archivedGroupNotPulledNorTriaged() {
    var data = PlanData()
    let g = data.addGroup("旧项目", now: Date())
    let a = make("收尾", .none, group: g, into: &data)
    data.update(a) { $0.tags = ["工作"] }
    _ = make("过期", .day(d(10, 1)), group: g, into: &data)
    data.updateGroup(g) { $0.isArchived = true }
    data.pulledTags[today] = ["工作"]
    #expect(agenda(for: today, today: today, data: data).entries.isEmpty)
    #expect(triageCandidates(today: today, data: data).isEmpty)
}

// I5: a tag stops before a time word or number.
@Test func tagStopsBeforeTimeWords() {
    let r = parseInput("开会#工作明天下午", today: today)
    #expect(r.tags == ["工作"])
    #expect(r.schedule == .day(d(10, 6)))
    let r2 = parseInput("交报告#工作p0", today: today)
    #expect(r2.tags == ["工作"] && r2.priority == .p0)
    let r3 = parseInput("整理#工作，周五前", today: today)
    #expect(r3.tags == ["工作"])
}

// I7: rows split into label and value lines.
@Test func rowsGroupedByHeight() {
    let boxes = [
        TextBox(text: "实付款", minX: 0.05, midY: 0.50, height: 0.03),
        TextBox(text: "¥45.00", minX: 0.70, midY: 0.505, height: 0.03),
        TextBox(text: "订单金额", minX: 0.05, midY: 0.55, height: 0.03),
        TextBox(text: "¥58.00", minX: 0.70, midY: 0.548, height: 0.03),
        TextBox(text: "87", minX: 0.9, midY: 0.98, height: 0.02),
    ]
    #expect(groupRows(boxes) == ["87", "订单金额 ¥58.00", "实付款 ¥45.00"])
}

@Test func labelOnItsOwnLineTakesNextNumber() {
    let p = extractPayment(lines: ["9:41", "87", "账单详情", "美团外卖", "实付款", "¥45.00", "订单金额 ¥58.00"])
    #expect(p.amount == 4500)
}

@Test func fallbackPrefersMoneyLooking() {
    let p = extractPayment(lines: ["87", "瑞幸咖啡", "-23.50", "支付成功"])
    #expect(p.amount == 2350)
    #expect(p.merchant == "瑞幸咖啡")
}

@Test func plusAmountIsIncome() {
    let p = extractPayment(lines: ["收款到账", "张三", "+100.00"])
    #expect(p.amount == 10000 && p.isIncome)
}
