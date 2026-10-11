import Foundation

/// App Group shared by the app and its desktop widget.
#if os(iOS)
public let appGroupID = "group.com.lty.cre.mobile"
#else
public let appGroupID = "XZLHB3F367.cre"
#endif

/// A file inside the App Group container, or nil when the group isn't available.
public func sharedFileURL(_ name: String, groupID: String = appGroupID) -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?.appendingPathComponent(name)
}

extension DataStore where Value == PlanData {
    /// `data.json` inside the App Group container, or nil when the group isn't available.
    public static func sharedURL(groupID: String = appGroupID) -> URL? {
        sharedFileURL("data.json", groupID: groupID)
    }
}

/// Copies the pre-widget data file into the shared location once. Never overwrites existing shared data;
/// the old file is renamed to `data.migrated.json`, not deleted. Returns true when it migrated.
@discardableResult
public func migrateLegacyData(from legacy: URL, to shared: URL) -> Bool {
    let fm = FileManager.default
    guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: shared.path) else { return false }
    do {
        try fm.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: legacy, to: shared)
        try fm.moveItem(at: legacy, to: legacy.deletingLastPathComponent().appendingPathComponent("data.migrated.json"))
        return true
    } catch {
        return false
    }
}

/// What a desktop widget shows: open items by priority (first `limit`), folded DDL count, done items, progress.
public struct WidgetContent: Sendable {
    public var open: [AgendaEntry]
    public var folded: Int
    public var done: [AgendaEntry]
    public var progress: Progress
}

public func widgetContent(today: DayKey, data: PlanData, limit: Int, filter: AgendaFilter = .all) -> WidgetContent {
    let a = filtered(agenda(for: today, today: today, data: data, sort: .priority), by: filter, data: data)
    return WidgetContent(
        open: Array(a.entries.filter { !$0.isDone }.prefix(limit)),
        folded: a.foldedDeadlines.count,
        done: a.entries.filter(\.isDone),
        progress: a.progress
    )
}

/// The lock screen line: today's count and the first open item (nil when all done).
public struct LockSummary: Equatable, Sendable {
    public var done: Int
    public var total: Int
    public var next: String?

    public init(done: Int, total: Int, next: String?) {
        self.done = done
        self.total = total
        self.next = next
    }
}

public func lockScreenSummary(today: DayKey, data: PlanData) -> LockSummary {
    let c = widgetContent(today: today, data: data, limit: 1)
    let first = c.open.first.map { $0.isGroupRow ? ($0.children.first { !$0.isDone }?.text ?? $0.text) : $0.text }
    return LockSummary(done: c.progress.done, total: c.progress.total, next: first)
}

/// The widget's next timeline refresh: when the next day starts (at `startHour`).
public func nextRefresh(after now: Date, startHour: Int = 0, calendar: Calendar = .current) -> Date {
    let today = logicalDay(now, startHour: startHour, calendar: calendar)
    let next = calendar.startOfDay(for: today.adding(days: 1).date(hour: 12, calendar: calendar))
    return calendar.date(byAdding: .hour, value: startHour, to: next)!
}

// MARK: Day start (新的一天从几点开始)

/// The day `now` belongs to when a day starts at `startHour` (0 = midnight): 1:30 with a 2:00 start is still yesterday.
public func logicalDay(_ now: Date, startHour: Int, calendar: Calendar = .current) -> DayKey {
    DayKey.from(calendar.date(byAdding: .hour, value: -startHour, to: now)!, calendar: calendar)
}

/// Shared with the widget; kept apart from data.json.
public func dayStartURL() -> URL? { sharedFileURL("day-start.json") }

public func loadDayStartHour(_ url: URL? = dayStartURL()) -> Int { loadDayStart(url).hour }

/// A change made on this device: stamped now so it wins the next sync.
public func saveDayStartHour(_ hour: Int, to url: URL? = dayStartURL(), now: Date = Date()) {
    saveDayStart(DayStartSetting(hour: hour, modifiedAt: now), to: url)
}

// MARK: Widget filter (in-widget buttons; kept apart from data.json)

/// "全部" first, then tags with the most open todos; at most `max`. Groups stay out to keep the widget uncluttered.
public func widgetFilterChoices(data: PlanData, max: Int = 4) -> [AgendaFilter] {
    var counts: [String: Int] = [:]
    for t in data.todos where !t.isDone { for tag in t.tags { counts[tag, default: 0] += 1 } }
    let tags = data.allTags.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    let all: [AgendaFilter] = [.all] + tags.map { .tag($0) }
    return Array(all.prefix(max))
}

public func widgetFilterLabel(_ f: AgendaFilter, data: PlanData) -> String {
    switch f {
    case .all: "全部"
    case .tag(let t): "#" + t
    case .group(let g): data.group(g)?.name ?? "全部"
    }
}

/// The small widget's single button: steps through every tag, back to 全部.
public func nextWidgetFilter(after f: AgendaFilter, data: PlanData) -> AgendaFilter {
    let all = widgetFilterChoices(data: data, max: .max)
    guard let i = all.firstIndex(of: f), i + 1 < all.count else { return .all }
    return all[i + 1]
}

public func widgetFilterURL() -> URL? { sharedFileURL("widget-filter.json") }

public func loadWidgetFilter(_ url: URL? = widgetFilterURL()) -> AgendaFilter {
    guard let url, let d = try? Data(contentsOf: url),
          let f = try? JSONDecoder().decode(AgendaFilter.self, from: d) else { return .all }
    return f
}

public func saveWidgetFilter(_ f: AgendaFilter, to url: URL? = widgetFilterURL()) {
    guard let url, let d = try? JSONEncoder().encode(f) else { return }
    try? d.write(to: url, options: .atomic)
}
