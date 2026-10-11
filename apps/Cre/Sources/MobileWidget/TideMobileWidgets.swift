import CreCore
import SwiftUI
import WidgetKit

/// iPhone widgets: the same 今日待办 as the Mac desktop (small / medium / large), plus the lock screen.
@main
struct TideMobileWidgets: WidgetBundle {
    var body: some Widget {
        CreTodayWidget()
        LockWidget()
        if #available(iOS 18.0, *) { QuickAddControl() }
    }
}

struct LockEntry: TimelineEntry {
    let date: Date
    let summary: LockSummary
}

struct LockProvider: TimelineProvider {
    private func make(_ now: Date) -> LockEntry {
        let data = PlanStore.sharedURL().map { PlanStore(fileURL: $0).load() } ?? PlanData()
        let today = logicalDay(now, startHour: loadDayStartHour())
        return LockEntry(date: now, summary: lockScreenSummary(today: today, data: data))
    }

    func placeholder(in context: Context) -> LockEntry { LockEntry(date: Date(), summary: LockSummary(done: 2, total: 5, next: "交周报")) }
    func getSnapshot(in context: Context, completion: @escaping (LockEntry) -> Void) { completion(make(Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LockEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [make(now)], policy: .after(nextRefresh(after: now, startHour: loadDayStartHour()))))
    }
}

/// Lock screen: 「完成 2/5」 and the next item (rectangular), or a completion ring (circular). Tap opens the app.
struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TideLock", provider: LockProvider()) { LockView(entry: $0) }
            .configurationDisplayName("今日进度")
            .description("完成数与下一条待办。")
            .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

struct LockView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LockEntry

    var body: some View {
        let s = entry.summary
        Group {
            if family == .accessoryCircular {
                Gauge(value: Double(s.done), in: 0...Double(max(s.total, 1))) {
                    Text("今日")
                } currentValueLabel: {
                    Text("\(s.done)/\(s.total)").monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("完成 \(s.done)/\(s.total)").font(.headline).monospacedDigit()
                    Text(s.next ?? (s.total > 0 ? "今天都做完了" : "今天还空着")).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: "tide://today"))
        .containerBackground(.clear, for: .widget)
    }
}
