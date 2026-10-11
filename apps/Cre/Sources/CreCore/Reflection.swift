import Foundation

/// 感想：notes on a list item (a book, a course …), or on something outside any list (`title`).
public struct Reflection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    /// The list item it is about; nil for one written under 其他.
    public var todoID: UUID?
    /// Name for one written under 其他.
    public var title: String?
    /// 完成时间, defaulting to the day it was ticked.
    public var finishedOn: DayKey
    public var text: String
    public var updatedAt: Date
    /// Last change, for sync.
    public var modifiedAt: Date? = nil

    public init(id: UUID = UUID(), todoID: UUID?, title: String? = nil, finishedOn: DayKey, text: String, updatedAt: Date) {
        self.id = id
        self.todoID = todoID
        self.title = title
        self.finishedOn = finishedOn
        self.text = text
        self.updatedAt = updatedAt
    }
}

extension PlanData {
    /// List groups that have at least one finished item.
    public var listGroupsWithFinished: [TodoGroup] {
        (visibleGroups + archivedGroups).filter { g in
            if case .list = g.kind { return !finishedItems(in: g.id).isEmpty }
            return false
        }
    }

    /// Finished items of a list group, most recently finished first.
    public func finishedItems(in groupID: UUID) -> [Todo] {
        todos.filter { $0.groupID == groupID && !$0.isGroupAnchor && $0.isDone }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    public func reflection(for todoID: UUID) -> Reflection? {
        reflections.first { $0.todoID == todoID }
    }

    /// The reflection's date if there is one, else the day the item was ticked.
    public func defaultFinishDay(for todoID: UUID) -> DayKey? {
        reflection(for: todoID)?.finishedOn ?? todos.first { $0.id == todoID }?.completedDay
    }

    /// Creates or replaces the one reflection an item has. An item not yet ticked gets ticked on `finishedOn`.
    public mutating func saveReflection(todoID: UUID, finishedOn: DayKey, text: String, now: Date) {
        if let t = todos.first(where: { $0.id == todoID }), !t.isDone {
            update(todoID) { $0.completedDay = finishedOn; $0.completedAt = finishedOn.date() }
        }
        if let i = reflections.firstIndex(where: { $0.todoID == todoID }) {
            reflections[i].finishedOn = finishedOn
            reflections[i].text = text
            reflections[i].updatedAt = now
        } else {
            reflections.append(Reflection(todoID: todoID, finishedOn: finishedOn, text: text, updatedAt: now))
        }
    }

    public mutating func deleteReflection(todoID: UUID) {
        reflections.removeAll { $0.todoID == todoID }
    }

    /// Removes one reflection (any kind) by its own id.
    public mutating func deleteReflection(id: UUID) {
        reflections.removeAll { $0.id == id }
    }

    /// What a reflection is about: the item's name, or the name typed under 其他.
    public func reflectionTitle(_ r: Reflection) -> String {
        r.todoID.flatMap { id in todos.first { $0.id == id }?.text } ?? r.title ?? ""
    }

    /// Creates (id nil) or updates a reflection written under 其他. Returns its id.
    @discardableResult
    public mutating func saveFreeReflection(id: UUID?, title: String, finishedOn: DayKey, text: String, now: Date) -> UUID {
        if let id, let i = reflections.firstIndex(where: { $0.id == id }) {
            reflections[i].title = title
            reflections[i].finishedOn = finishedOn
            reflections[i].text = text
            reflections[i].updatedAt = now
            return id
        }
        let r = Reflection(todoID: nil, title: title, finishedOn: finishedOn, text: text, updatedAt: now)
        reflections.append(r)
        return r.id
    }

    /// The 哪一项 menu of a list: finished-but-unwritten (latest first), then open items, then written ones.
    public func reflectionChoices(in groupID: UUID) -> [ReflectionChoice] {
        let all = todos.filter { $0.groupID == groupID && !$0.isGroupAnchor }
        let written = all.filter { reflection(for: $0.id) != nil }
            .sorted { (reflection(for: $0.id)?.finishedOn ?? today0) > (reflection(for: $1.id)?.finishedOn ?? today0) }
        let finished = all.filter { $0.isDone && reflection(for: $0.id) == nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let open = all.filter { !$0.isDone && reflection(for: $0.id) == nil }.sorted { $0.createdAt < $1.createdAt }
        return finished.map { ReflectionChoice(todo: $0, status: .finished) }
            + open.map { ReflectionChoice(todo: $0, status: .unfinished) }
            + written.map { ReflectionChoice(todo: $0, status: .written) }
    }

    /// Every list group (pinned order), for the 清单 menu.
    public var listGroups: [TodoGroup] {
        (visibleGroups + archivedGroups).filter { if case .list = $0.kind { return true }; return false }
    }

    /// Where 新建 opens: the latest finish still unwritten; else a list's first open item; nil = write under 其他.
    public func defaultReflectionTarget() -> ReflectionTarget? {
        let candidates = listGroups.flatMap { g in reflectionChoices(in: g.id).filter { $0.status == .finished }.map { (g.id, $0.todo) } }
        if let best = candidates.max(by: { ($0.1.completedAt ?? .distantPast) < ($1.1.completedAt ?? .distantPast) }) {
            return ReflectionTarget(groupID: best.0, todoID: best.1.id)
        }
        for g in listGroups {
            if let first = reflectionChoices(in: g.id).first { return ReflectionTarget(groupID: g.id, todoID: first.todo.id) }
        }
        return nil
    }
}

private let today0 = DayKey(year: 1970, month: 1, day: 1)!

public struct ReflectionChoice: Sendable {
    public enum Status: Sendable { case finished, unfinished, written }
    public var todo: Todo
    public var status: Status
}

public struct ReflectionTarget: Equatable, Sendable {
    public var groupID: UUID
    public var todoID: UUID
}
