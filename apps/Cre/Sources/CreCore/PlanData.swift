import Foundation

/// Everything the todo & planning side stores.
public struct PlanData: Equatable, Sendable {
    public var version: Int = 1
    public var groups: [TodoGroup] = []
    public var todos: [Todo] = []
    /// The Friday (as a day) whose triage was last handled.
    public var lastTriagedWeek: DayKey?
    /// 每日总结的历史报告。
    public var summaries: [DailySummary] = []
    /// 随笔 / 感想，按天。
    public var notes: [DayKey: String] = [:]
    /// Tags whose items are pulled into a given day's list.
    public var pulledTags: [DayKey: [String]] = [:]
    /// 自选总结的模板与报告。
    public var templates: [SummaryTemplate] = []
    public var reports: [SummaryReport] = []
    /// 感想 on finished list items.
    public var reflections: [Reflection] = []
    /// Sync bookkeeping: when a record was deleted (key "todo:<uuid>", "summary:<day>" …),
    /// and when each day's 随笔 / pulled tags last changed.
    public var deletions: [String: Date] = [:]
    public var noteStamps: [DayKey: Date] = [:]
    public var pulledTagStamps: [DayKey: Date] = [:]

    public init() {}

    @discardableResult
    public mutating func addGroup(_ name: String, kind: GroupKind = .ungrouped, schedule: Repeat? = nil, now: Date) -> UUID {
        let order = (groups.map(\.sortOrder).max() ?? 0) + 1
        let g = TodoGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, sortOrder: order, createdAt: now)
        groups.append(g)
        if kind.hasAnchor {
            addAnchor(for: g, schedule: schedule ?? Repeat(start: DayKey.from(now)), now: now)
        }
        return g.id
    }

    /// The hidden repeat carrying a cycle / list group's schedule.
    public func anchor(of groupID: UUID) -> Todo? {
        todos.first { $0.groupID == groupID && $0.isGroupAnchor }
    }

    /// Changes a group's kind. Leaving cycle/list turns the anchor into a plain repeat; nothing is deleted.
    public mutating func setGroupKind(_ groupID: UUID, _ kind: GroupKind, today: DayKey, now: Date) {
        setGroupSchedule(groupID, kind: kind, rule: nil, now: now, today: today)
    }

    /// Sets a group's kind and (for cycle / list) its schedule, start included. Keeps the anchor's history;
    /// a day plan survives only for cycle groups. Nothing in the group is deleted.
    public mutating func setGroupSchedule(_ groupID: UUID, kind: GroupKind, rule: Repeat?, now: Date, today: DayKey? = nil) {
        guard let group = group(groupID) else { return }
        updateGroup(groupID) { $0.kind = kind }
        let text = anchorText(name: group.name, kind: kind)
        if let a = anchor(of: groupID) {
            guard kind.hasAnchor else {
                update(a.id) { $0.isGroupAnchor = false }
                return
            }
            update(a.id) { t in
                t.text = text
                guard case .repeating(var r) = t.schedule else { return }
                if let rule {
                    r.weekdays = rule.weekdays
                    r.plan = rule.plan
                    r.start = rule.start
                }
                if kind != .cycle { r.plan = nil }
                t.schedule = .repeating(r)
            }
        } else if kind.hasAnchor, let g = self.group(groupID) {
            var r = rule ?? Repeat(start: today ?? DayKey.from(now))
            if kind != .cycle { r.plan = nil }
            addAnchor(for: g, schedule: r, now: now)
        }
    }

    private mutating func addAnchor(for g: TodoGroup, schedule: Repeat, now: Date) {
        var t = Todo(text: anchorText(name: g.name, kind: g.kind), groupID: g.id, schedule: .repeating(schedule), createdAt: now)
        t.isGroupAnchor = true
        todos.append(t)
    }

    private func anchorText(name: String, kind: GroupKind) -> String {
        if case .list(let standard) = kind {
            let t = standard.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? name : "\(name) \(t)"
        }
        return name
    }

    /// Returns nil (and adds nothing) when the text is blank.
    public mutating func addTodo(_ text: String, schedule: Schedule, groupID: UUID?, tags: [String], now: Date) -> UUID? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let todo = Todo(text: t, groupID: groupID, tags: tags, schedule: schedule, createdAt: now)
        todos.append(todo)
        return todo.id
    }

    /// Deletes the group together with every todo in it.
    public mutating func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        todos.removeAll { $0.groupID == id }
    }

    public mutating func deleteTodo(_ id: UUID) {
        todos.removeAll { $0.id == id }
        reflections.removeAll { $0.todoID == id }
    }

    public mutating func setOngoing(_ todoID: UUID, _ on: Bool) {
        update(todoID) { $0.isOngoing = on }
    }

    /// Every tag in use, sorted.
    public var allTags: [String] { Array(Set(todos.flatMap(\.tags))).sorted() }

    /// Not archived; pinned first, then by order.
    public var visibleGroups: [TodoGroup] {
        groups.filter { !$0.isArchived }.sorted { ($0.isPinned ? 0 : 1, $0.sortOrder) < ($1.isPinned ? 0 : 1, $1.sortOrder) }
    }

    public var archivedGroups: [TodoGroup] { groups.filter(\.isArchived).sorted { $0.sortOrder < $1.sortOrder } }

    /// Moves a todo into a group (or out of all groups with nil). Anchors stay put.
    public mutating func moveTodo(_ id: UUID, toGroup groupID: UUID?) {
        update(id) { t in if !t.isGroupAnchor { t.groupID = groupID } }
    }

    public func todos(in groupID: UUID?) -> [Todo] {
        todos.filter { $0.groupID == groupID }
    }

    public func group(_ id: UUID?) -> TodoGroup? {
        guard let id else { return nil }
        return groups.first { $0.id == id }
    }

    public mutating func update(_ todoID: UUID, _ change: (inout Todo) -> Void) {
        guard let i = todos.firstIndex(where: { $0.id == todoID }) else { return }
        change(&todos[i])
    }

    public mutating func updateGroup(_ groupID: UUID, _ change: (inout TodoGroup) -> Void) {
        guard let i = groups.firstIndex(where: { $0.id == groupID }) else { return }
        change(&groups[i])
    }
}

extension PlanData: Codable {
    private enum Keys: String, CodingKey { case version, groups, todos, lastTriagedWeek, summaries, notes, pulledTags, templates, reports, reflections,
                                         deletions, noteStamps, pulledTagStamps }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        groups = try c.decodeIfPresent([TodoGroup].self, forKey: .groups) ?? []
        todos = try c.decodeIfPresent([Todo].self, forKey: .todos) ?? []
        lastTriagedWeek = try c.decodeIfPresent(DayKey.self, forKey: .lastTriagedWeek)
        summaries = try c.decodeIfPresent([DailySummary].self, forKey: .summaries) ?? []
        notes = try c.decodeIfPresent([DayKey: String].self, forKey: .notes) ?? [:]
        pulledTags = try c.decodeIfPresent([DayKey: [String]].self, forKey: .pulledTags) ?? [:]
        templates = try c.decodeIfPresent([SummaryTemplate].self, forKey: .templates) ?? []
        reports = try c.decodeIfPresent([SummaryReport].self, forKey: .reports) ?? []
        reflections = try c.decodeIfPresent([Reflection].self, forKey: .reflections) ?? []
        deletions = try c.decodeIfPresent([String: Date].self, forKey: .deletions) ?? [:]
        noteStamps = try c.decodeIfPresent([DayKey: Date].self, forKey: .noteStamps) ?? [:]
        pulledTagStamps = try c.decodeIfPresent([DayKey: Date].self, forKey: .pulledTagStamps) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(version, forKey: .version)
        try c.encode(groups, forKey: .groups)
        try c.encode(todos, forKey: .todos)
        try c.encodeIfPresent(lastTriagedWeek, forKey: .lastTriagedWeek)
        try c.encode(summaries, forKey: .summaries)
        try c.encode(notes, forKey: .notes)
        try c.encode(pulledTags, forKey: .pulledTags)
        try c.encode(templates, forKey: .templates)
        try c.encode(reports, forKey: .reports)
        if !reflections.isEmpty { try c.encode(reflections, forKey: .reflections) }
        if !deletions.isEmpty { try c.encode(deletions, forKey: .deletions) }
        if !noteStamps.isEmpty { try c.encode(noteStamps, forKey: .noteStamps) }
        if !pulledTagStamps.isEmpty { try c.encode(pulledTagStamps, forKey: .pulledTagStamps) }
    }
}
