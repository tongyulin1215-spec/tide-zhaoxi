import Foundation

/// How a planning group appears in the day view.
public enum TodayDisplay: String, Codable, Sendable, CaseIterable {
    case hidden, oneLine, expanded
}

/// 模块组类型：循环 / 清单 / 阶段 / 未分组。
public enum GroupKind: Equatable, Sendable {
    case cycle
    /// 清单：每次的标准由用户自由填写，如"1 小时""两篇"。
    case list(standard: String)
    case phase
    case ungrouped

    /// A list whose standard is a duration.
    public static func list(minutes: Int) -> GroupKind { .list(standard: durationLabel(minutes: minutes)) }

    /// Cycle and list groups carry their schedule on an anchor todo.
    public var hasAnchor: Bool {
        switch self {
        case .cycle, .list: true
        case .phase, .ungrouped: false
        }
    }
}

extension GroupKind: Codable {
    private enum Keys: String, CodingKey { case kind, minutes, standard }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "cycle": self = .cycle
        case "list":
            if let s = try c.decodeIfPresent(String.self, forKey: .standard) {
                self = .list(standard: s)
            } else {
                self = .list(minutes: try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 60)
            }
        case "phase": self = .phase
        default: self = .ungrouped
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .cycle: try c.encode("cycle", forKey: .kind)
        case .list(let standard): try c.encode("list", forKey: .kind); try c.encode(standard, forKey: .standard)
        case .phase: try c.encode("phase", forKey: .kind)
        case .ungrouped: try c.encode("ungrouped", forKey: .kind)
        }
    }
}

/// "1 小时" / "30 分钟" / "1 小时 30 分钟".
public func durationLabel(minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return "\(m) 分钟" }
    return m == 0 ? "\(h) 小时" : "\(h) 小时 \(m) 分钟"
}

/// 规划里的模块组（目标 / 方向）。
public struct TodoGroup: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: GroupKind
    public var isPinned: Bool = false
    public var isArchived: Bool = false
    public var collapsed: Bool
    public var todayDisplay: TodayDisplay
    public var sortOrder: Double
    public var createdAt: Date
    /// Last change, for sync.
    public var modifiedAt: Date? = nil

    public init(id: UUID = UUID(), name: String, kind: GroupKind = .ungrouped, collapsed: Bool = false,
                todayDisplay: TodayDisplay = .expanded, sortOrder: Double = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.collapsed = collapsed
        self.todayDisplay = todayDisplay
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    private enum Keys: String, CodingKey { case id, name, kind, isPinned, isArchived, collapsed, todayDisplay, sortOrder, createdAt, modifiedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(GroupKind.self, forKey: .kind) ?? .ungrouped
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        todayDisplay = try c.decodeIfPresent(TodayDisplay.self, forKey: .todayDisplay) ?? .expanded
        sortOrder = try c.decodeIfPresent(Double.self, forKey: .sortOrder) ?? 0
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt)
    }
}

/// 一条待办的时间方式。
public enum Schedule: Equatable, Sendable {
    case none
    case day(DayKey)
    case deadline(DayKey)
    case span(start: DayKey, end: DayKey)
    case repeating(Repeat)
}

extension Schedule: Codable {
    private enum Kind: String, Codable { case none, day, deadline, span, repeating }
    private enum Keys: String, CodingKey { case kind, day, start, end, rule }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .none: self = .none
        case .day: self = .day(try c.decode(DayKey.self, forKey: .day))
        case .deadline: self = .deadline(try c.decode(DayKey.self, forKey: .day))
        case .span: self = .span(start: try c.decode(DayKey.self, forKey: .start), end: try c.decode(DayKey.self, forKey: .end))
        case .repeating: self = .repeating(try c.decode(Repeat.self, forKey: .rule))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .none: try c.encode(Kind.none, forKey: .kind)
        case .day(let d): try c.encode(Kind.day, forKey: .kind); try c.encode(d, forKey: .day)
        case .deadline(let d): try c.encode(Kind.deadline, forKey: .kind); try c.encode(d, forKey: .day)
        case .span(let s, let e):
            try c.encode(Kind.span, forKey: .kind); try c.encode(s, forKey: .start); try c.encode(e, forKey: .end)
        case .repeating(let r): try c.encode(Kind.repeating, forKey: .kind); try c.encode(r, forKey: .rule)
        }
    }
}

/// 每日重复。`weekdays` 为空表示每天；否则为 1（周日）…7（周六）。
public struct Repeat: Codable, Equatable, Sendable {
    public var weekdays: Set<Int>
    public var start: DayKey
    public var plan: DayPlan?
    public var completions: [DayKey: Date]
    public var itemCompletions: [DayKey: Set<UUID>]

    public init(weekdays: Set<Int> = [], start: DayKey, plan: DayPlan? = nil,
                completions: [DayKey: Date] = [:], itemCompletions: [DayKey: Set<UUID>] = [:]) {
        self.weekdays = weekdays
        self.start = start
        self.plan = plan
        self.completions = completions
        self.itemCompletions = itemCompletions
    }

    public func occurs(on day: DayKey) -> Bool {
        day >= start && (weekdays.isEmpty || weekdays.contains(day.weekday))
    }

    private enum Keys: String, CodingKey { case weekdays, start, plan, completions, itemCompletions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? []
        start = try c.decode(DayKey.self, forKey: .start)
        plan = try c.decodeIfPresent(DayPlan.self, forKey: .plan)
        completions = try c.decodeIfPresent([DayKey: Date].self, forKey: .completions) ?? [:]
        itemCompletions = try c.decodeIfPresent([DayKey: Set<UUID>].self, forKey: .itemCompletions) ?? [:]
    }
}

public enum PlanMode: String, Codable, Sendable, CaseIterable {
    case fixedWeekday, rotate
}

/// 按天安排当天内容（如健身：周一练胸、周二练背）。
public struct DayPlan: Codable, Equatable, Sendable {
    public var mode: PlanMode
    /// Fixed: one per weekday. Rotate: the period, in order.
    public var days: [PlanDay]
    /// Rotate only: days to pause after each full round.
    public var gap: Int

    public init(mode: PlanMode, days: [PlanDay] = [], gap: Int = 0) {
        self.mode = mode
        self.days = days
        self.gap = gap
    }

    private enum Keys: String, CodingKey { case mode, days, gap }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        mode = try c.decode(PlanMode.self, forKey: .mode)
        days = try c.decodeIfPresent([PlanDay].self, forKey: .days) ?? []
        gap = try c.decodeIfPresent(Int.self, forKey: .gap) ?? 0
    }
}

public struct PlanDay: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var weekday: Int?
    public var items: [PlanItem]

    public init(id: UUID = UUID(), name: String, weekday: Int? = nil, items: [PlanItem] = []) {
        self.id = id
        self.name = name
        self.weekday = weekday
        self.items = items
    }

    private enum Keys: String, CodingKey { case id, name, weekday, items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        weekday = try c.decodeIfPresent(Int.self, forKey: .weekday)
        items = try c.decodeIfPresent([PlanItem].self, forKey: .items) ?? []
    }
}

public struct PlanItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

public enum Priority: Int, Codable, Comparable, Sendable, CaseIterable {
    case p0 = 0, p1 = 1, p2 = 2

    public static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    public var label: String { "P\(rawValue)" }
}

/// 一条待办：就是一句话。
public struct Todo: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var groupID: UUID?
    public var tags: [String]
    public var schedule: Schedule
    public var isOngoing: Bool
    public var createdAt: Date
    public var completedAt: Date?
    /// The day the todo counts as done on (a past day when back-filled). Unused for `.repeating`.
    public var completedDay: DayKey?
    public var priority: Priority?
    /// The hidden repeat that carries a cycle / list group's schedule.
    public var isGroupAnchor: Bool = false
    /// Last change, for sync (nil in files written before stamping existed).
    public var modifiedAt: Date? = nil

    public init(id: UUID = UUID(), text: String, groupID: UUID? = nil, tags: [String] = [],
                schedule: Schedule = .none, isOngoing: Bool = false, createdAt: Date = Date(),
                completedAt: Date? = nil, completedDay: DayKey? = nil, priority: Priority? = nil) {
        self.id = id
        self.text = text
        self.groupID = groupID
        self.tags = tags
        self.schedule = schedule
        self.isOngoing = isOngoing
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.completedDay = completedDay
        self.priority = priority
    }

    public var isDone: Bool { completedDay != nil }

    private enum Keys: String, CodingKey {
        case id, text, groupID, tags, schedule, isOngoing, createdAt, completedAt, completedDay, priority, isGroupAnchor, modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        schedule = try c.decodeIfPresent(Schedule.self, forKey: .schedule) ?? .none
        isOngoing = try c.decodeIfPresent(Bool.self, forKey: .isOngoing) ?? false
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        completedDay = try c.decodeIfPresent(DayKey.self, forKey: .completedDay)
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority)
        isGroupAnchor = try c.decodeIfPresent(Bool.self, forKey: .isGroupAnchor) ?? false
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt)
    }

    public var isRepeating: Bool {
        if case .repeating = schedule { return true }
        return false
    }
}

extension DayKey: CodingKeyRepresentable {
    public var codingKey: CodingKey { DayCodingKey(stringValue: string) }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(string: codingKey.stringValue)
    }
}

private struct DayCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Rebuilds a day's actions from edited lines. Each unchanged line keeps the id of one old item
/// (so past check marks survive); duplicates and new lines get fresh ids.
public func mergePlanItems(old: [PlanItem], lines: [String]) -> [PlanItem] {
    var pool = old
    return lines.map { line in
        if let i = pool.firstIndex(where: { $0.text == line }) {
            return pool.remove(at: i)
        }
        return PlanItem(text: line)
    }
}
