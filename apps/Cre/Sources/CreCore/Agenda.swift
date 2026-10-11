import Foundation

public enum EntryKind: String, Codable, Sendable {
    case day, deadline, span, repeating
}

public enum SortMode: String, Codable, Sendable, CaseIterable {
    case priority, category, tag
}

/// 筛选今日待办：全部、某个标签、某个模块组。
public enum AgendaFilter: Codable, Equatable, Hashable, Sendable {
    case all
    case tag(String)
    case group(UUID)
}

public struct Progress: Equatable, Sendable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

/// One row in the day view.
public struct AgendaEntry: Identifiable, Equatable, Sendable {
    /// The todo's id, or the group's id for a one-line group row.
    public var id: UUID
    public var kind: EntryKind
    public var text: String
    public var groupName: String?
    public var deadline: DayKey?
    public var overdueDays: Int = 0
    /// Text after ▶ ("today, specifically").
    public var detail: String?
    public var progress: Progress?
    public var isCheckable: Bool
    public var isDone: Bool
    public var isGroupRow: Bool = false
    /// Past view only: not done that day, moved on afterwards.
    public var movedLater: Bool = false
    /// Past view only: a DDL finished on this later day. Shown done, but not counted for the viewed day.
    public var doneLater: DayKey?
    /// Done on the viewed day itself (what progress and summaries count).
    public var countsAsDone: Bool { isDone && doneLater == nil }
    /// For a group row: the entries it stands for.
    public var children: [AgendaEntry] = []
    public var priority: Priority?
    /// Set when the item is in the list only because its tag was pulled in for this day.
    public var pulledBy: String?
    public var tags: [String] = []
    var createdAt: Date
    var completedAt: Date?
}

public struct Agenda: Equatable, Sendable {
    public var entries: [AgendaEntry]
    public var foldedDeadlines: [AgendaEntry]
    /// "今天 3/7": checkable items in `entries` (group rows count their children).
    public var progress: Progress
}

/// Days left at or below this stay in the main list; others fold into "DDL 待办（N）".
public let deadlineFoldThreshold = 3

public func ddlLabel(_ day: DayKey) -> String { "DDL \(day.month)月\(day.day)日" }

public func agenda(for day: DayKey, today: DayKey, data: PlanData, sort: SortMode = .priority) -> Agenda {
    var main: [AgendaEntry] = []
    var folded: [AgendaEntry] = []
    var groupRows: [UUID: [AgendaEntry]] = [:]

    for todo in data.todos {
        let group = data.group(todo.groupID)
        if group?.todayDisplay == .hidden || group?.isArchived == true { continue }
        guard var entry = entry(for: todo, on: day, today: today, data: data) else { continue }
        entry.groupName = group?.name

        if entry.kind == .deadline, let due = entry.deadline, !entry.countsAsDone,
           day.days(until: due) > deadlineFoldThreshold {
            folded.append(entry)
        } else if let group, group.todayDisplay == .oneLine {
            groupRows[group.id, default: []].append(entry)
        } else {
            main.append(entry)
        }
    }

    // Items pulled in by tag for this day: open, not already listed, not repeats or phases.
    let listed = Set(main.map(\.id) + folded.map(\.id) + groupRows.values.flatMap { $0.map(\.id) })
    for tag in data.pulledTags[day] ?? [] {
        for todo in data.todos where todo.tags.contains(tag) && !listed.contains(todo.id) && !todo.isRepeating {
            if case .span = todo.schedule { continue }
            if data.group(todo.groupID)?.isArchived == true { continue }
            // Open items, plus ones already checked off on this very day (so ticking doesn't make them vanish).
            let doneHere = todo.completedDay == day
            guard !todo.isDone || doneHere else { continue }
            if main.contains(where: { $0.id == todo.id }) { continue }
            var e = AgendaEntry(id: todo.id, kind: kindOf(todo.schedule), text: todo.text, isCheckable: true, isDone: doneHere,
                                priority: todo.priority, createdAt: todo.createdAt, completedAt: todo.completedAt)
            e.groupName = data.group(todo.groupID)?.name
            e.tags = todo.tags
            e.pulledBy = tag
            if case .deadline(let due) = todo.schedule {
                e.deadline = due
                // Far-off deadlines fold away even when pulled in.
                if !doneHere, day.days(until: due) > deadlineFoldThreshold {
                    if !folded.contains(where: { $0.id == todo.id }) { folded.append(e) }
                    continue
                }
            }
            main.append(e)
        }
    }

    for group in data.groups where groupRows[group.id] != nil {
        let children = sorted(groupRows[group.id]!, by: sort)
        let checkable = children.filter(\.isCheckable)
        let done = checkable.filter(\.countsAsDone).count
        main.append(AgendaEntry(
            id: group.id,
            kind: children.contains { $0.kind == .repeating } ? .repeating : children[0].kind,
            text: group.name,
            progress: Progress(done: done, total: checkable.count),
            isCheckable: !checkable.isEmpty,
            isDone: !checkable.isEmpty && done == checkable.count,
            isGroupRow: true,
            children: children,
            priority: children.compactMap(\.priority).min(),
            createdAt: group.createdAt
        ))
    }

    let countable = main.flatMap { $0.isGroupRow ? $0.children : [$0] }.filter(\.isCheckable)
    return Agenda(
        entries: sorted(main, by: sort),
        foldedDeadlines: sorted(folded, by: sort),
        progress: Progress(done: countable.filter(\.countsAsDone).count, total: countable.count)
    )
}

private func entry(for todo: Todo, on day: DayKey, today: DayKey, data: PlanData) -> AgendaEntry? {
    var e = AgendaEntry(id: todo.id, kind: .day, text: todo.text, isCheckable: true,
                        isDone: false, priority: todo.priority, createdAt: todo.createdAt, completedAt: todo.completedAt)
    e.tags = todo.tags

    // A finished one-off item shows only on the day it counts for.
    if !todo.isRepeating, let doneDay = todo.completedDay {
        if doneDay < day { return nil }
        if doneDay == day {
            switch todo.schedule {
            case .none: return nil
            case .day(let d) where d > day: return nil
            case .span(let s, _) where s > day: return nil
            default: break
            }
            e.isDone = true
        }
    }

    switch todo.schedule {
    case .none:
        return nil

    case .day(let d):
        e.kind = .day
        if e.isDone { return e }
        if d == day {
            if day < today { e.movedLater = true }
            return e
        }
        if day == today && d < today {
            e.overdueDays = d.days(until: today)
            return e
        }
        return nil

    case .deadline(let due):
        e.kind = .deadline
        e.deadline = due
        if e.isDone { return e }
        let created = DayKey.from(todo.createdAt)
        if created <= day && day <= due {
            if let doneDay = todo.completedDay, doneDay > day {
                e.isDone = true
                e.doneLater = doneDay
            }
            return e
        }
        if day == today && due < today {
            e.overdueDays = due.days(until: today)
            return e
        }
        return nil

    case .span(let s, let end):
        e.kind = .span
        e.isCheckable = false
        if e.isDone { return e }
        return (s <= day && day <= end) ? e : nil

    case .repeating(let r):
        e.kind = .repeating
        guard r.occurs(on: day) else { return nil }
        if r.plan?.mode == .rotate, r.completions[day] == nil, planDay(for: r, on: day) == nil { return nil }
        e.isDone = r.completions[day] != nil
        e.detail = detailText(for: todo, on: day, data: data)
        if let items = planDay(for: r, on: day)?.items, !items.isEmpty {
            let done = r.itemCompletions[day] ?? []
            e.progress = Progress(done: items.filter { done.contains($0.id) }.count, total: items.count)
        }
        return e
    }
}

/// Text after ▶: the day plan's name when the repeat has one, else the group's in-progress todos.
public func detailText(for todo: Todo, on day: DayKey, data: PlanData) -> String? {
    if case .repeating(let r) = todo.schedule, r.plan != nil {
        return planDay(for: r, on: day).map(\.name).flatMap { $0.isEmpty ? nil : $0 }
    }
    guard let groupID = todo.groupID else { return nil }
    let ongoing = data.todos
        .filter { $0.groupID == groupID && $0.isOngoing && !$0.isDone && $0.id != todo.id }
        .sorted { $0.createdAt < $1.createdAt }
        .map(\.text)
    return ongoing.isEmpty ? nil : ongoing.joined(separator: " | ")
}

private func rank(_ e: AgendaEntry) -> Int {
    switch e.kind {
    case .deadline: 0
    case .day: 1
    case .repeating: 2
    case .span: 3
    }
}

/// P0 < P1 < P2 < none.
private func pRank(_ e: AgendaEntry) -> Int { e.priority?.rawValue ?? 3 }

private func sorted(_ entries: [AgendaEntry], by mode: SortMode) -> [AgendaEntry] {
    entries.sorted { a, b in
        if a.isDone != b.isDone { return !a.isDone }
        if a.isDone { return (a.completedAt ?? .distantPast) < (b.completedAt ?? .distantPast) }
        if mode == .tag {
            // By first tag (alphabetical), untagged last; then priority.
            let ta = a.tags.sorted().first, tb = b.tags.sorted().first
            if ta != tb {
                guard let ta else { return false }
                guard let tb else { return true }
                return ta < tb
            }
        }
        let keys: [(Int, Int)] = mode == .category
            ? [(rank(a), rank(b)), (pRank(a), pRank(b))]
            : [(pRank(a), pRank(b)), (rank(a), rank(b))]
        for (x, y) in keys where x != y { return x < y }
        return a.createdAt < b.createdAt
    }
}

func kindOf(_ s: Schedule) -> EntryKind {
    switch s {
    case .deadline: .deadline
    case .span: .span
    case .repeating: .repeating
    case .day, .none: .day
    }
}

/// Keeps only what matches the filter; progress is recounted over what remains.
public func filtered(_ a: Agenda, by filter: AgendaFilter, data: PlanData) -> Agenda {
    guard filter != .all else { return a }
    func match(_ e: AgendaEntry) -> Bool {
        let todo = data.todos.first { $0.id == e.id }
        switch filter {
        case .all: return true
        case .tag(let t): return todo?.tags.contains(t) ?? false
        case .group(let g): return todo?.groupID == g
        }
    }
    var entries: [AgendaEntry] = []
    for e in a.entries {
        if e.isGroupRow {
            if case .group(let g) = filter, e.id == g { entries.append(e); continue }
            var row = e
            row.children = e.children.filter(match)
            guard !row.children.isEmpty else { continue }
            let checkable = row.children.filter(\.isCheckable)
            let done = checkable.filter(\.countsAsDone).count
            row.progress = Progress(done: done, total: checkable.count)
            row.isDone = !checkable.isEmpty && done == checkable.count
            entries.append(row)
        } else if match(e) {
            entries.append(e)
        }
    }
    let countable = entries.flatMap { $0.isGroupRow ? $0.children : [$0] }.filter(\.isCheckable)
    return Agenda(entries: entries, foldedDeadlines: a.foldedDeadlines.filter(match),
                  progress: Progress(done: countable.filter(\.countsAsDone).count, total: countable.count))
}
