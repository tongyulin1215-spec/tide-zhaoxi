import Foundation

// MARK: - 日程 (a planning aid: no ticking, no stats, independent of todos)

public enum ScheduleRepeat: Codable, Equatable, Hashable, Sendable {
    case none
    case daily
    /// Weekdays, 1 = Sunday … 7 = Saturday.
    case weekly(Set<Int>)
}

public struct ScheduleItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    /// The day it happens, or a repeat's first day.
    public var day: DayKey
    /// Minutes from midnight, 0…1440.
    public var start: Int
    public var end: Int
    public var repeats: ScheduleRepeat
    /// Days a repeat skips (deleted or moved just that once).
    public var skipped: Set<DayKey>
    /// The kind of todo it came from (for its colour); nil when made here.
    public var kind: EntryKind?
    /// Last change, for sync.
    public var modifiedAt: Date? = nil

    public init(id: UUID = UUID(), title: String, day: DayKey, start: Int, end: Int,
                repeats: ScheduleRepeat = .none, skipped: Set<DayKey> = [], kind: EntryKind? = nil) {
        self.id = id
        self.title = title
        self.day = day
        self.start = start
        self.end = end
        self.repeats = repeats
        self.skipped = skipped
        self.kind = kind
    }

    public var isRepeating: Bool { repeats != .none }

    public func occurs(on d: DayKey) -> Bool {
        switch repeats {
        case .none: return d == day
        case .daily: return d >= day && !skipped.contains(d)
        case .weekly(let w): return d >= day && w.contains(d.weekday) && !skipped.contains(d)
        }
    }
}

/// One appearance of an item on a day.
public struct ScheduleOccurrence: Identifiable, Equatable, Sendable {
    public var itemID: UUID
    public var day: DayKey
    public var title: String
    public var start: Int
    public var end: Int
    public var isRepeating: Bool
    public var kind: EntryKind?
    public var id: String { "\(itemID)-\(day)" }
}

/// Where an occurrence sits among overlapping ones: column `column` of `columns`.
public struct ScheduleSlot: Equatable, Sendable {
    public var occurrence: ScheduleOccurrence
    public var column: Int
    public var columns: Int
}

public enum ScheduleScope: Sendable { case one, all }

public struct ScheduleData: StoredValue, Sendable {
    public var version = 1
    public var items: [ScheduleItem] = []
    /// Sync bookkeeping: deleted items ("schedule:<uuid>").
    public var deletions: [String: Date] = [:]

    public init() {}

    private enum Keys: String, CodingKey { case version, items, deletions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        items = try c.decodeIfPresent([ScheduleItem].self, forKey: .items) ?? []
        deletions = try c.decodeIfPresent([String: Date].self, forKey: .deletions) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(version, forKey: .version)
        try c.encode(items, forKey: .items)
        if !deletions.isEmpty { try c.encode(deletions, forKey: .deletions) }
    }

    public func occurrences(on day: DayKey) -> [ScheduleOccurrence] {
        items.filter { $0.occurs(on: day) }
            .map { ScheduleOccurrence(itemID: $0.id, day: day, title: $0.title, start: $0.start, end: $0.end,
                                     isRepeating: $0.isRepeating, kind: $0.kind) }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// Overlapping items share the width side by side.
    public func layout(on day: DayKey) -> [ScheduleSlot] {
        var result: [ScheduleSlot] = []
        var cluster: [ScheduleSlot] = []
        var clusterEnd = -1
        var columnEnds: [Int] = []
        func flush() {
            let n = columnEnds.count
            result += cluster.map { var s = $0; s.columns = n; return s }
            cluster = []; columnEnds = []
        }
        for o in occurrences(on: day) {
            if o.start >= clusterEnd { flush(); clusterEnd = -1 }
            let col = columnEnds.firstIndex { $0 <= o.start } ?? columnEnds.count
            if col == columnEnds.count { columnEnds.append(o.end) } else { columnEnds[col] = o.end }
            cluster.append(ScheduleSlot(occurrence: o, column: col, columns: 0))
            clusterEnd = max(clusterEnd, o.end)
        }
        flush()
        return result
    }

    @discardableResult
    public mutating func add(title: String, day: DayKey, start: Int, end: Int, repeats: ScheduleRepeat = .none,
                             kind: EntryKind? = nil) -> UUID {
        let item = ScheduleItem(title: title, day: day, start: start, end: max(end, start + 15), repeats: repeats, kind: kind)
        items.append(item)
        return item.id
    }

    /// Drag result: the occurrence on `from` now sits on `to` at `start`–`end`.
    public mutating func move(_ id: UUID, from: DayKey, to: DayKey, start: Int, end: Int, scope: ScheduleScope) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if items[i].isRepeating && scope == .one {
            items[i].skipped.insert(from)
            add(title: items[i].title, day: to, start: start, end: end, kind: items[i].kind)
            return
        }
        items[i].start = start
        items[i].end = end
        let shift = from.days(until: to)
        switch items[i].repeats {
        case .none: items[i].day = to
        case .daily: break
        case .weekly(let w):
            items[i].repeats = .weekly(Set(w.map { (($0 - 1 + shift) % 7 + 7) % 7 + 1 }))
            if to < items[i].day { items[i].day = to }
        }
    }

    /// Editor result. For one occurrence of a repeat, that day is split off as its own item.
    public mutating func update(_ id: UUID, on occurrenceDay: DayKey, title: String, day: DayKey, start: Int, end: Int,
                                repeats: ScheduleRepeat, scope: ScheduleScope) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if items[i].isRepeating && scope == .one {
            items[i].skipped.insert(occurrenceDay)
            add(title: title, day: day, start: start, end: end, kind: items[i].kind)
            return
        }
        let wasRepeating = items[i].isRepeating
        items[i].title = title
        items[i].start = start
        items[i].end = max(end, start + 15)
        items[i].repeats = repeats
        if !wasRepeating { items[i].day = day }
    }

    public mutating func delete(_ id: UUID, on day: DayKey, scope: ScheduleScope) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if items[i].isRepeating && scope == .one {
            items[i].skipped.insert(day)
        } else {
            items.remove(at: i)
        }
    }
}

// MARK: - Helpers

/// Nearest quarter hour, kept within the day.
public func snapMinute(_ m: Int) -> Int {
    min(24 * 60, max(0, Int((Double(m) / 15).rounded()) * 15))
}

private let cnHour: [Character: Double] = ["一": 1, "两": 2, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
private let hourRe = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?|[一两二三四五六七八九十])?\s*个?\s*(半)?\s*小时"#)
private let minuteRe = try! NSRegularExpression(pattern: #"(\d+)\s*分钟"#)

/// "读书 1 小时" → 60, "半小时" → 30, "1 小时 30 分钟" → 90; nil when the title names no duration.
public func minutesInTitle(_ title: String) -> Int? {
    let ns = title as NSString
    var total = 0.0
    var found = false
    if let m = hourRe.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)) {
        let numRange = m.range(at: 1), half = m.range(at: 2).location != NSNotFound
        if numRange.location != NSNotFound {
            let s = ns.substring(with: numRange)
            total += (Double(s) ?? s.first.flatMap { cnHour[$0] } ?? 0) * 60
            if half { total += 30 }
            found = true
        } else if half {
            total += 30
            found = true
        }
    }
    if let m = minuteRe.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)) {
        total += Double(ns.substring(with: m.range(at: 1))) ?? 0
        found = true
    }
    return found && total > 0 ? Int(total) : nil
}

public typealias ScheduleStore = DataStore<ScheduleData>

extension DataStore where Value == ScheduleData {
    /// `schedule.json` in the App Group container.
    public static func sharedURL(groupID: String = appGroupID) -> URL? {
        sharedFileURL("schedule.json", groupID: groupID)
    }
}
