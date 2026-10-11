import AppIntents
import CreCore
import SwiftUI
import WidgetKit

// MARK: Data

struct TodayEntry: TimelineEntry {
    let date: Date
    let today: DayKey
    let content: WidgetContent
    let largeContent: WidgetContent
    let filter: AgendaFilter
    /// Chips: (filter, label), 全部 first.
    let choices: [(AgendaFilter, String)]
    /// Where the small widget's button goes next.
    let next: AgendaFilter
    var filterLabel: String { choices.first { $0.0 == filter }?.1 ?? "全部" }
}

private func loadData() -> PlanData {
    guard let url = PlanStore.sharedURL() else { return PlanData() }
    return PlanStore(fileURL: url).load()
}

private func entry(at date: Date, limit: Int, data: PlanData, filter: AgendaFilter) -> TodayEntry {
    let today = logicalDay(date, startHour: loadDayStartHour())
    var choices = widgetFilterChoices(data: data)
    if !choices.contains(filter) { choices[choices.count - 1] = filter }  // keep the active one visible
    return TodayEntry(date: date, today: today,
                      content: widgetContent(today: today, data: data, limit: limit, filter: filter),
                      largeContent: widgetContent(today: today, data: data, limit: 6, filter: filter),
                      filter: filter,
                      choices: choices.map { ($0, widgetFilterLabel($0, data: data)) },
                      next: nextWidgetFilter(after: filter, data: data))
}

// MARK: Filter (buttons inside the widget)

/// "all", "tag:<name>", "group:<uuid>" — AppIntent parameters must be simple values.
private func encode(_ f: AgendaFilter) -> String {
    switch f {
    case .all: "all"
    case .tag(let t): "tag:" + t
    case .group(let g): "group:" + g.uuidString
    }
}

private func decode(_ s: String) -> AgendaFilter {
    if s.hasPrefix("tag:") { return .tag(String(s.dropFirst(4))) }
    if s.hasPrefix("group:"), let u = UUID(uuidString: String(s.dropFirst(6))) { return .group(u) }
    return .all
}

/// The saved filter, or 全部 when its tag/group no longer exists.
private func currentFilter(_ data: PlanData) -> AgendaFilter {
    let f = loadWidgetFilter()
    return widgetFilterChoices(data: data, max: .max).contains(f) ? f : .all
}

struct SetWidgetFilterIntent: AppIntent {
    static var title: LocalizedStringResource = "筛选"
    static var isDiscoverable = false

    @Parameter(title: "筛选") var filter: String

    init() {}
    init(_ f: AgendaFilter) { filter = encode(f) }

    func perform() async throws -> some IntentResult {
        saveWidgetFilter(decode(filter))
        return .result()
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        entry(at: Date(), limit: 4, data: PlanData(), filter: .all)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let data = loadData()
        completion(entry(at: Date(), limit: limit(context.family), data: data, filter: currentFilter(data)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let data = loadData()
        let e = entry(at: now, limit: limit(context.family), data: data, filter: currentFilter(data))
        completion(Timeline(entries: [e], policy: .after(nextRefresh(after: now, startHour: loadDayStartHour()))))
    }

    private func limit(_ family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 2
        case .systemMedium: 3
        default: 6
        }
    }
}

// MARK: Intent

struct ToggleTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "勾选待办"

    @Parameter(title: "ID") var id: String
    @Parameter(title: "Kind") var kind: String

    init() {}

    init(entry: AgendaEntry) {
        id = entry.id.uuidString
        kind = entry.isGroupRow ? "group" : (entry.kind == .repeating ? "repeat" : "item")
    }

    func perform() async throws -> some IntentResult {
        guard let url = PlanStore.sharedURL(), let uuid = UUID(uuidString: id) else { return .result() }
        let store = PlanStore(fileURL: url)
        let before = store.load()
        var data = before
        guard !store.isReadOnly else { return .result() }
        let today = logicalDay(Date(), startHour: loadDayStartHour())
        switch kind {
        case "group": data.toggleGroupRow(groupID: uuid, on: today, today: today, now: Date())
        case "repeat": data.toggleRepeat(todoID: uuid, on: today, now: Date())
        default: data.toggle(todoID: uuid, on: today, today: today, now: Date())
        }
        try store.save(data.stamped(since: before, now: Date()))  // so sync sees the tick as new
        return .result()
    }
}

// MARK: Views

enum WTheme {
    static func color(_ kind: EntryKind) -> Color {
        switch kind {
        case .day: Color(red: 0.184, green: 0.435, blue: 0.929)
        case .deadline: Color(red: 0.941, green: 0.541, blue: 0.141)
        case .repeating: Color(red: 0.122, green: 0.643, blue: 0.388)
        case .span: Color(red: 0.557, green: 0.357, blue: 0.847)
        }
    }

    static func color(_ p: Priority) -> Color {
        switch p {
        case .p0: Color(red: 0.898, green: 0.282, blue: 0.302)
        case .p1: Color(red: 0.941, green: 0.541, blue: 0.141)
        case .p2: .gray
        }
    }
}

private let weekdays = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]

struct WidgetRow: View {
    let entry: AgendaEntry
    let today: DayKey

    private var color: Color { WTheme.color(entry.kind) }

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 15)
            if entry.kind == .span && !entry.isGroupRow {
                Circle().fill(color.opacity(0.35)).frame(width: 13, height: 13)
            } else {
                Button(intent: ToggleTodoIntent(entry: entry)) {
                    ZStack {
                        Circle().strokeBorder(color, lineWidth: 2)
                        if entry.isDone { Circle().fill(color) }
                    }
                    .frame(width: 13, height: 13)
                }
                .buttonStyle(.plain)
            }
            if let p = entry.priority {
                Text(p.label).font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 3)
                    .background(WTheme.color(p).opacity(p == .p0 ? 1 : 0.25), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(p == .p0 ? Color.white : WTheme.color(p))
            }
            #if os(iOS)
            // Tapping an item opens it in the app; group rows just open today.
            if entry.isGroupRow {
                Text(entry.text).lineLimit(1)
            } else {
                Link(destination: URL(string: "tide://todo/\(entry.id.uuidString)")!) { Text(entry.text).lineLimit(1) }
            }
            #else
            Text(entry.text).lineLimit(1)
            #endif
            if let detail = entry.detail { Text("▶ \(detail)").foregroundStyle(color).lineLimit(1) }
            Spacer(minLength: 2)
            if entry.overdueDays > 0 {
                tag("拖了 \(entry.overdueDays) 天", .red)
            } else if let due = entry.deadline {
                tag(ddlLabel(due), WTheme.color(.deadline))
            }
        }
        .font(.system(size: 12))
        .opacity(entry.isDone ? 0.45 : 1)
    }

    private func tag(_ text: String, _ c: Color) -> some View {
        Text(text).font(.system(size: 10)).padding(.horizontal, 5).background(c.opacity(0.15), in: Capsule()).foregroundStyle(c)
            .lineLimit(1)
    }
}

struct CreWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var dateText: String { "\(entry.today.month)月\(entry.today.day)日" }
    private var p: CreCore.Progress { entry.content.progress }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemMedium: list(entry.content, showDone: false)
            default: list(entry.largeContent, showDone: true)
            }
        }
        #if os(iOS)
        .widgetURL(URL(string: "tide://today"))
        #else
        .widgetURL(URL(string: "cre://today"))
        #endif
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(dateText).font(.system(size: 13, weight: .semibold))
                Text(weekdays[entry.today.weekday]).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if entry.choices.count > 1 {
                    Button(intent: SetWidgetFilterIntent(entry.next)) { chip(entry.filterLabel, on: entry.filter != .all) }
                        .buttonStyle(.plain)
                }
            }
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 6)
                Circle().trim(from: 0, to: p.total == 0 ? 0 : CGFloat(p.done) / CGFloat(p.total))
                    .stroke(WTheme.color(.repeating), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(p.done)/\(p.total)").font(.system(size: 13, weight: .bold)).monospacedDigit()
            }
            .frame(width: 50, height: 50)
            ForEach(entry.content.open) { WidgetRow(entry: $0, today: entry.today) }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ text: String, on: Bool) -> some View {
        Text(text).font(.system(size: 10.5, weight: on ? .semibold : .regular)).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(on ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.07), in: Capsule())
            .foregroundStyle(on ? Color.accentColor : Color.secondary)
    }

    private func list(_ c: WidgetContent, showDone: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("今天 · \(dateText) \(weekdays[entry.today.weekday])").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(p.done)/\(p.total)").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
            }
            if entry.choices.count > 1 {
                HStack(spacing: 4) {
                    ForEach(Array(entry.choices.enumerated()), id: \.offset) { _, c in
                        Button(intent: SetWidgetFilterIntent(c.0)) { chip(c.1, on: c.0 == entry.filter) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if c.open.isEmpty && c.done.isEmpty && c.folded == 0 {
                Text("今日无待办").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(c.open) { WidgetRow(entry: $0, today: entry.today) }
            if showDone {
                if c.folded > 0 {
                    Text("DDL 待办（\(c.folded)）").font(.system(size: 11)).foregroundStyle(WTheme.color(.deadline))
                }
                if !c.done.isEmpty {
                    Text("已完成 \(c.done.count)").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 2)
                    ForEach(c.done.prefix(2)) { WidgetRow(entry: $0, today: entry.today) }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#if os(macOS)
@main
#endif
struct CreTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TideToday", provider: Provider()) { CreWidgetView(entry: $0) }
            .configurationDisplayName("今日待办")
            .description("今日待办，可勾选、筛选。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
