import Charts
import CreCore
import SwiftUI

/// A report's figures: completion, time, repeats, missed days, by group, daily chart, items. Same on Mac and phone.
struct ReportContent: View {
    let report: SummaryReport

    private func has(_ m: SummaryMetric) -> Bool { report.metrics.contains(m) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if has(.count) || has(.rate) {
                VStack(alignment: .leading, spacing: 6) {
                    Text([has(.count) ? "完成 \(report.done)/\(report.total)" : nil, has(.rate) ? "\(report.rate)%" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.headline).monospacedDigit()
                    ProgressView(value: Double(report.done), total: Double(max(report.total, 1)))
                        .tint(Theme.color(for: .repeating))
                }
            }
            if has(.duration) {
                row("平均用时", report.avgMinutes.map(durationLabel(minutes:)) ?? "—")
            }
            if !report.repeatLines.isEmpty && (has(.count) || has(.rate)) {
                section("重复") {
                    ForEach(Array(report.repeatLines.enumerated()), id: \.offset) { _, l in
                        row(l.name, "\(l.done)/\(l.total) 次")
                    }
                }
            }
            if has(.missed) && !report.missed.isEmpty {
                section("未完成的日子") {
                    ForEach(Array(report.missed.enumerated()), id: \.offset) { _, l in
                        row(l.name, l.days.map(Fmt.date).joined(separator: "、"))
                    }
                }
            }
            if has(.byGroup) && !report.byGroup.isEmpty {
                section("按模块组") {
                    ForEach(Array(report.byGroup.enumerated()), id: \.offset) { _, g in
                        HStack(spacing: 10) {
                            Text(g.name).frame(width: 90, alignment: .leading)
                            ProgressView(value: Double(g.done), total: Double(max(g.total, 1))).tint(Theme.color(for: .day))
                            Text("\(g.done)/\(g.total)").monospacedDigit().foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                        }
                    }
                }
            }
            if has(.daily) && report.daily.count > 1 {
                section("每日完成") {
                    Chart(report.daily, id: \.day) { l in
                        BarMark(x: .value("日", "\(l.day.month)/\(l.day.day)"), y: .value("完成", l.done))
                            .foregroundStyle(Theme.color(for: .repeating))
                    }
                    .frame(height: 160)
                }
            }
            if has(.count) {
                items("已完成", report.doneItems, done: true)
                items("未完成", report.openItems, done: false)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder private func items(_ title: String, _ list: [SummaryItem], done: Bool) -> some View {
        if !list.isEmpty {
            section("\(title) \(list.count)") {
                ForEach(Array(list.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done ? Theme.color(for: .repeating) : .secondary)
                        Text(item.text)
                        Spacer()
                        if let g = item.group { Tag(text: g, color: .gray) }
                    }
                }
            }
        }
    }
}
