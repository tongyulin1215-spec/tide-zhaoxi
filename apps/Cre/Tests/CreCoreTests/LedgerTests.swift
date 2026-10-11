import Foundation
import Testing
@testable import CreCore

private let t = d(10, 4)

// L1
@Test func ledgerSaveThenLoad() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cre-l-\(UUID().uuidString)")
    let url = dir.appendingPathComponent("ledger.json")
    var data = LedgerData()
    data.add(LedgerEntry(amount: 3500, isIncome: false, category: "餐饮", note: "午饭", day: t), now: Date(timeIntervalSince1970: 1_791_000_000))
    let store = LedgerStore(fileURL: url)
    try store.save(data)
    #expect(store.load() == data)
}

@Test func ledgerDefaultsHavePresetCategories() {
    let data = LedgerData()
    #expect(data.expenseCategories == ["餐饮", "交通", "购物", "居住", "娱乐", "医疗", "其他"])
    #expect(data.incomeCategories == ["工资", "奖金", "其他"])
}

@Test func deletingCategoryKeepsEntries() {
    var data = LedgerData()
    data.add(LedgerEntry(amount: 600, isIncome: false, category: "交通", note: "地铁", day: t), now: Date())
    data.removeCategory("交通", income: false)
    #expect(!data.expenseCategories.contains("交通"))
    #expect(data.entries[0].category == "交通")
}

// L2
@Test func ledgerBasicExpense() {
    let r = parseLedger("午饭 35", today: t, data: LedgerData())!
    #expect(r.amount == 3500)
    #expect(!r.isIncome)
    #expect(r.category == "餐饮")
    #expect(r.note == "午饭")
    #expect(r.day == t)
}

@Test func ledgerIncomeForms() {
    let a = parseLedger("工资 +12000", today: t, data: LedgerData())!
    #expect(a.isIncome && a.amount == 1_200_000 && a.category == "工资" && a.note == "工资")
    let b = parseLedger("收入 奖金 3000", today: t, data: LedgerData())!
    #expect(b.isIncome && b.category == "奖金" && b.note == "奖金")
}

@Test func ledgerAmountIsLastNumber() {
    let r = parseLedger("买 2 杯咖啡 30", today: t, data: LedgerData())!
    #expect(r.amount == 3000)
    #expect(r.note == "买 2 杯咖啡")
    #expect(parseLedger("打车 23.5", today: t, data: LedgerData())!.amount == 2350)
    #expect(parseLedger("房租 1,200", today: t, data: LedgerData())!.amount == 120_000)
}

@Test func ledgerDayWords() {
    #expect(parseLedger("昨天 打车 23", today: t, data: LedgerData())!.day == d(10, 3))
    #expect(parseLedger("10月1日 电影 60", today: t, data: LedgerData())!.day == d(10, 1))
}

@Test func ledgerNeedsAmount() {
    #expect(parseLedger("午饭", today: t, data: LedgerData()) == nil)
    #expect(parseLedger("   ", today: t, data: LedgerData()) == nil)
}

@Test func ledgerUnknownGoesToOther() {
    #expect(parseLedger("杂项 12", today: t, data: LedgerData())!.category == "其他")
}

@Test func ledgerLearnsCategoryForSameNote() {
    var data = LedgerData()
    data.add(LedgerEntry(amount: 2000, isIncome: false, category: "娱乐", note: "猫粮", day: d(10, 1)), now: Date())
    #expect(parseLedger("猫粮 20", today: t, data: data)!.category == "娱乐")
}

@Test func moneyFormat() {
    #expect(money(3500) == "¥35")
    #expect(money(2350) == "¥23.50")
    #expect(money(1_200_000) == "¥12,000")
}

// L3
@Test func monthTotalsOnlyThisMonth() {
    var data = LedgerData()
    data.add(LedgerEntry(amount: 1_200_000, isIncome: true, category: "工资", note: "工资", day: d(10, 1)), now: Date())
    data.add(LedgerEntry(amount: 3500, isIncome: false, category: "餐饮", note: "午饭", day: d(10, 4)), now: Date())
    data.add(LedgerEntry(amount: 9900, isIncome: false, category: "购物", note: "书", day: d(9, 30)), now: Date())
    let m = monthTotals(data, year: 2026, month: 10)
    #expect(m == MonthTotals(income: 1_200_000, expense: 3500))
    #expect(m.net == 1_196_500)
}

@Test func entriesGroupedByDayNewestFirst() {
    var data = LedgerData()
    data.add(LedgerEntry(amount: 100, isIncome: false, category: "其他", note: "a", day: d(10, 3)), now: Date())
    data.add(LedgerEntry(amount: 200, isIncome: false, category: "其他", note: "b", day: d(10, 4)), now: Date())
    data.add(LedgerEntry(amount: 300, isIncome: true, category: "其他", note: "c", day: d(10, 4)), now: Date())
    let g = dayGroups(data.entries)
    #expect(g.map(\.day) == [d(10, 4), d(10, 3)])
    #expect(g[0].expense == 200 && g[0].income == 300)
}

@Test func categoryShareSortedByAmount() {
    var data = LedgerData()
    data.add(LedgerEntry(amount: 100, isIncome: false, category: "交通", note: "", day: t), now: Date())
    data.add(LedgerEntry(amount: 500, isIncome: false, category: "餐饮", note: "", day: t), now: Date())
    data.add(LedgerEntry(amount: 200, isIncome: false, category: "交通", note: "", day: t), now: Date())
    let s = categoryShare(data, year: 2026, month: 10, income: false)
    #expect(s.map(\.category) == ["餐饮", "交通"])
    #expect(s.map(\.amount) == [500, 300])
}

@Test func trendAcrossYear() {
    var data = LedgerData()
    data.add(LedgerEntry(amount: 1000, isIncome: false, category: "其他", note: "", day: d(12, 5, 2025)), now: Date())
    data.add(LedgerEntry(amount: 2000, isIncome: true, category: "其他", note: "", day: d(1, 5)), now: Date())
    let tr = monthlyTrend(data, endingYear: 2026, month: 2, months: 3)
    #expect(tr.map { "\($0.year)-\($0.month)" } == ["2025-12", "2026-1", "2026-2"])
    #expect(tr.map(\.totals.expense) == [1000, 0, 0])
    #expect(tr.map(\.totals.income) == [0, 2000, 0])
}

// Review fixes
@Test func hugeNumberIsNotAnAmount() {
    #expect(parseLedger("退货 订单 123456789012345678", today: t, data: LedgerData()) == nil)
    #expect(parseLedger("退货 订单 99999999999999999", today: t, data: LedgerData()) == nil)
}

@Test func amountFieldParsing() {
    #expect(parseAmount("35") == 3500)
    #expect(parseAmount("23.5") == 2350)
    #expect(parseAmount("1,200") == 120_000)
    #expect(parseAmount("0") == nil)
    #expect(parseAmount("1e20") == nil)
    #expect(parseAmount("inf") == nil)
    #expect(parseAmount("123456789012345678") == nil)
    #expect(parseAmount("abc") == nil)
}

// Pie chart over a period
@Test func categoryShareOverRange() {
    var data = LedgerData()
    data.add(LedgerEntry(amount: 100, isIncome: false, category: "交通", note: "", day: d(9, 28)), now: Date())
    data.add(LedgerEntry(amount: 500, isIncome: false, category: "餐饮", note: "", day: d(10, 2)), now: Date())
    data.add(LedgerEntry(amount: 300, isIncome: false, category: "交通", note: "", day: d(10, 5)), now: Date())
    data.add(LedgerEntry(amount: 999, isIncome: false, category: "购物", note: "", day: d(10, 6)), now: Date())
    let s = categoryShare(data, from: d(9, 28), to: d(10, 5), income: false)
    #expect(s.map(\.category) == ["餐饮", "交通"])
    #expect(s.map(\.amount) == [500, 400])
}

// "35块5" style amounts
@Test func kuaiJiaoAmounts() {
    let p = { (s: String) in parseLedger(s, today: t, data: LedgerData()) }
    #expect(p("午饭 35块5")?.amount == 3550)
    #expect(p("午饭 35块5毛")?.amount == 3550)
    #expect(p("午饭 35元5角")?.amount == 3550)
    #expect(p("矿泉水 3块")?.amount == 300)
    #expect(p("午饭 35块5")?.note == "午饭")
}
