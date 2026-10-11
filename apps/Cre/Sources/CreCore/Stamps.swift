import Foundation

// MARK: - Sync stamps
// Every save compares the new value with the previous one: changed records get `modifiedAt = now`,
// removed ones leave a deletion mark, and a record that comes back (undo) loses its mark.

protocol Stampable: Equatable {
    var modifiedAt: Date? { get set }
    /// Identity across saves, also the deletion-mark key ("todo:<uuid>").
    var stampKey: String { get }
    /// Equal apart from the stamp (and anything that stays on one device).
    func sameContent(as other: Self) -> Bool
}

extension Stampable {
    func sameContent(as other: Self) -> Bool {
        var a = self, b = other
        a.modifiedAt = nil
        b.modifiedAt = nil
        return a == b
    }
}

extension Todo: Stampable { var stampKey: String { "todo:\(id.uuidString)" } }
extension TodoGroup: Stampable {
    var stampKey: String { "group:\(id.uuidString)" }

    /// Folding a card is a view preference on one device, not a change to sync.
    func sameContent(as other: TodoGroup) -> Bool {
        var a = self, b = other
        a.modifiedAt = nil; b.modifiedAt = nil
        b.collapsed = a.collapsed
        return a == b
    }
}
extension DailySummary: Stampable { var stampKey: String { "summary:\(day.string)" } }
extension SummaryTemplate: Stampable { var stampKey: String { "template:\(id.uuidString)" } }
extension SummaryReport: Stampable { var stampKey: String { "report:\(id.uuidString)" } }
extension Reflection: Stampable { var stampKey: String { "reflection:\(id.uuidString)" } }
extension LedgerEntry: Stampable { var stampKey: String { "entry:\(id.uuidString)" } }
extension ScheduleItem: Stampable { var stampKey: String { "schedule:\(id.uuidString)" } }

private func stampList<T: Stampable>(_ new: inout [T], old: [T], deletions: inout [String: Date], now: Date) {
    let before = Dictionary(old.map { ($0.stampKey, $0) }, uniquingKeysWith: { a, _ in a })
    var seen = Set<String>()
    for i in new.indices {
        let key = new[i].stampKey
        seen.insert(key)
        if let o = before[key] {
            if !new[i].sameContent(as: o) { new[i].modifiedAt = now }
        } else {
            new[i].modifiedAt = now
            deletions[key] = nil
        }
    }
    for key in before.keys where !seen.contains(key) { deletions[key] = now }
}

private func stampDays<V: Equatable>(_ new: [DayKey: V], old: [DayKey: V], stamps: inout [DayKey: Date], now: Date) {
    for day in Set(new.keys).union(old.keys) where new[day] != old[day] { stamps[day] = now }
}

extension PlanData {
    /// This value with sync stamps updated against what was saved before.
    public func stamped(since old: PlanData, now: Date) -> PlanData {
        var s = self
        stampList(&s.todos, old: old.todos, deletions: &s.deletions, now: now)
        stampList(&s.groups, old: old.groups, deletions: &s.deletions, now: now)
        stampList(&s.summaries, old: old.summaries, deletions: &s.deletions, now: now)
        stampList(&s.templates, old: old.templates, deletions: &s.deletions, now: now)
        stampList(&s.reports, old: old.reports, deletions: &s.deletions, now: now)
        stampList(&s.reflections, old: old.reflections, deletions: &s.deletions, now: now)
        stampDays(s.notes, old: old.notes, stamps: &s.noteStamps, now: now)
        stampDays(s.pulledTags, old: old.pulledTags, stamps: &s.pulledTagStamps, now: now)
        return s
    }
}

extension LedgerData {
    public func stamped(since old: LedgerData, now: Date) -> LedgerData {
        var s = self
        stampList(&s.entries, old: old.entries, deletions: &s.deletions, now: now)
        if s.expenseCategories != old.expenseCategories || s.incomeCategories != old.incomeCategories { s.settingsModifiedAt = now }
        if s.opening != old.opening { s.openingModifiedAt = now }
        return s
    }
}

extension ScheduleData {
    public func stamped(since old: ScheduleData, now: Date) -> ScheduleData {
        var s = self
        stampList(&s.items, old: old.items, deletions: &s.deletions, now: now)
        return s
    }
}
