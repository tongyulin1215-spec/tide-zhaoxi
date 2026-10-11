import Foundation
import Testing
@testable import CreCore

// B7 screenshot ledger
@Test func paymentFromWeChatStyle() {
    let p = extractPayment(lines: ["支付成功", "瑞幸咖啡", "-23.50", "当前状态 支付成功", "商品 生椰拿铁", "支付时间 2026年10月4日 08:31"])
    #expect(p.amount == 2350)
    #expect(p.merchant == "瑞幸咖啡")
}

@Test func paymentFromLabeledLines() {
    let p = extractPayment(lines: ["订单详情", "商户全称 上海某某餐饮有限公司", "订单金额 ¥58.00", "实付款 ¥45.00", "优惠 ¥13.00"])
    #expect(p.amount == 4500)
    #expect(p.merchant == "上海某某餐饮有限公司")
}

@Test func paymentFromYenSign() {
    let p = extractPayment(lines: ["美团外卖", "￥32", "已完成"])
    #expect(p.amount == 3200)
    #expect(p.merchant == "美团外卖")
}

@Test func paymentNoneFound() {
    #expect(extractPayment(lines: ["你好", "今天天气不错"]).amount == nil)
}

// B9 leftovers
@Test func otherCategoryCannotBeRenamed() {
    var data = LedgerData()
    data.renameCategory("其他", to: "杂项", income: false)
    #expect(data.expenseCategories.contains("其他"))
}

@Test func amountOddForms() {
    let t = d(10, 4)
    #expect(parseLedger("房租 1，200", today: t, data: LedgerData())?.amount == 120_000)
    #expect(parseLedger("午饭 35.", today: t, data: LedgerData())?.amount == 3500)
    let bad = parseLedger("2月30日 午饭 30", today: t, data: LedgerData())
    #expect(bad?.amount == 3000)
    #expect(bad?.note == "午饭")
}

@Test func dayKeyIgnoresNonGregorianSystemCalendar() {
    var buddhist = Calendar(identifier: .buddhist)
    buddhist.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let date = DayKey(year: 2026, month: 10, day: 4)!.date()
    #expect(DayKey.from(date, calendar: buddhist) == DayKey(year: 2026, month: 10, day: 4)!)
}

@Test func oldRepeatAndPlanDecodeWithMissingFields() throws {
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    let r = try dec.decode(Repeat.self, from: Data(#"{"start":"2026-10-01"}"#.utf8))
    #expect(r.weekdays.isEmpty && r.completions.isEmpty && r.plan == nil)
    let pd = try dec.decode(PlanDay.self, from: Data(#"{"id":"6E6790BC-4504-4244-A262-0EC5211FACD4","name":"练胸"}"#.utf8))
    #expect(pd.items.isEmpty && pd.weekday == nil)
}

@Test func paymentFromRealOCROutput() {
    let p = extractPayment(lines: ["支付成功", "瑞幸咖啡", "-23.50", "当前状态 支付成功", "商品生椰拿铁", "支付时间2026年10月4日08:31"])
    #expect(p.amount == 2350 && p.merchant == "瑞幸咖啡")
}
