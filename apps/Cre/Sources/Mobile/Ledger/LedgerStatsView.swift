import Charts
import CreCore
import SwiftUI

/// 统计: category share for the month (or a chosen range) and the last six months.
struct LedgerStatsView: View {
    @ObservedObject var state: MobileState
    let year: Int
    let month: Int
    @State private var income = false
    @State private var custom = false
    @State private var from = DayKey.from(Date())
    @State private var to = DayKey.from(Date())

    private static let palette: [Color] = [
        Color(red: 0.184, green: 0.435, blue: 0.929), Color(red: 0.941, green: 0.541, blue: 0.141),
        Color(red: 0.122, green: 0.643, blue: 0.388), Color(red: 0.557, green: 0.357, blue: 0.847),
        Color(red: 0.898, green: 0.282, blue: 0.302), Color(red: 0.0, green: 0.62, blue: 0.70),
        Color(red: 0.75, green: 0.6, blue: 0.1), Color.gray,
    ]

    private var monthRange: (DayKey, DayKey) {
        let first = DayKey(year: year, month: month, day: 1)!
        let next = DayKey(year: month == 12 ? year + 1 : year, month: month == 12 ? 1 : month + 1, day: 1)!
        return (first, next.adding(days: -1))
    }

    private var range: (DayKey, DayKey) { custom ? (min(from, to), max(from, to)) : monthRange }

    var body: some View {
        let (a, b) = range
        let share = categoryShare(state.ledger, from: a, to: b, income: income)
        let total = max(share.reduce(0) { $0 + $1.amount }, 1)
        let trend = monthlyTrend(state.ledger, endingYear: year, month: month, months: 6)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("范围", selection: $custom) { Text("本月").tag(false); Text("自选").tag(true) }.pickerStyle(.segmented)
                Picker("类型", selection: $income) { Text("支出").tag(false); Text("收入").tag(true) }.pickerStyle(.segmented)
            }
            if custom { RangeField(label: "范围", from: $from, to: $to, latest: state.today) }
            if share.isEmpty {
                Text("无记录").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                Chart(share) { c in
                    SectorMark(angle: .value("金额", c.amount), innerRadius: .ratio(0.6), angularInset: 1.5)
                        .cornerRadius(3)
                        .foregroundStyle(color(for: c, in: share))
                }
                .chartBackground { _ in
                    VStack(spacing: 2) {
                        Text(income ? "收入" : "支出").font(.caption).foregroundStyle(.secondary)
                        Text(money(total)).font(.headline).monospacedDigit()
                    }
                }
                .frame(height: 200)
                VStack(spacing: 10) {
                    ForEach(share) { c in
                        HStack(spacing: 10) {
                            Circle().fill(color(for: c, in: share)).frame(width: 9, height: 9)
                            Text(c.category).accessibilityIdentifier("share-\(c.category)")
                            Spacer()
                            Text(money(c.amount)).monospacedDigit()
                            Text("\(Int((Double(c.amount) / Double(total) * 100).rounded()))%")
                                .foregroundStyle(.secondary).monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                        .font(.subheadline)
                    }
                }
            }
            Text("每天").font(.headline).padding(.top, 8)
            let days = dailyTotals(state.ledger, year: year, month: month)
            Chart(days) { d in
                BarMark(x: .value("日", d.day.day), y: .value("金额", Double(income ? d.income : d.expense) / 100))
                    .foregroundStyle(income ? LedgerColors.income : Theme.color(for: .day))
                    .cornerRadius(2)
            }
            .chartXScale(domain: 1...max(days.count, 1))
            .chartXAxis { AxisMarks(values: [1, 5, 10, 15, 20, 25, days.count]) { v in AxisValueLabel { if let d = v.as(Int.self) { Text("\(d)") } } } }
            .frame(height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("每天\(income ? "收入" : "支出")")
            .accessibilityIdentifier("daily-chart")
            Text("近 6 个月").font(.headline).padding(.top, 8)
            Chart {
                ForEach(trend) { p in
                    BarMark(x: .value("月", "\(p.month)月"), y: .value("金额", Double(p.totals.income) / 100))
                        .foregroundStyle(by: .value("类型", "收入"))
                        .position(by: .value("类型", "收入"))
                    BarMark(x: .value("月", "\(p.month)月"), y: .value("金额", Double(p.totals.expense) / 100))
                        .foregroundStyle(by: .value("类型", "支出"))
                        .position(by: .value("类型", "支出"))
                }
                ForEach(trend) { p in
                    LineMark(x: .value("月", "\(p.month)月"), y: .value("金额", Double(p.totals.net) / 100))
                        .foregroundStyle(by: .value("类型", "净收入"))
                        .symbol(.circle)
                }
            }
            .chartForegroundStyleScale(["收入": LedgerColors.income, "支出": Theme.color(for: .day), "净收入": Color.orange])
            .frame(height: 220)
        }
        .onAppear { (from, to) = monthRange }
    }

    /// Expenses match the flow list's icon colours; income (all green there) goes by rank.
    private func color(for c: CategoryAmount, in list: [CategoryAmount]) -> Color {
        if !income { return CategoryIcon.tint(c.category, isIncome: false, data: state.ledger) }
        let i = list.firstIndex { $0.category == c.category } ?? 0
        return Self.palette[i % Self.palette.count]
    }
}
