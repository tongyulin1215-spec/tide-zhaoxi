import Foundation

/// The day plan (e.g. "练胸") a repeat uses on `day`, or nil when it has none that day.
public func planDay(for r: Repeat, on day: DayKey) -> PlanDay? {
    guard let plan = r.plan, !plan.days.isEmpty else { return nil }
    switch plan.mode {
    case .fixedWeekday:
        return plan.days.first { $0.weekday == day.weekday }
    case .rotate:
        // Only completed occurrences advance the rotation; a missed day shows the same item next time.
        // After a full round, `gap` days pause before the next round. Weeks play no part.
        let done = r.completions.keys.filter { $0 >= r.start && $0 < day && r.occurs(on: $0) }.sorted()
        let k = done.count, n = plan.days.count
        if k > 0, k % n == 0, plan.gap > 0, let last = done.last, last.days(until: day) <= plan.gap {
            return nil
        }
        return plan.days[k % n]
    }
}

extension PlanData {
    /// Check / uncheck a one-off todo as done on `day` (a past day when back-filling).
    /// When `today` is given, a tick on a future day counts for today.
    public mutating func toggle(todoID: UUID, on day: DayKey, today: DayKey? = nil, now: Date) {
        let day = today.map { min(day, $0) } ?? day
        update(todoID) { t in
            if t.isDone {
                t.completedDay = nil
                t.completedAt = nil
            } else {
                t.completedDay = day
                t.completedAt = now
            }
        }
    }

    /// Check / uncheck a repeat's whole row for `day`; checking also marks every item of that day.
    public mutating func toggleRepeat(todoID: UUID, on day: DayKey, now: Date) {
        updateRepeat(todoID) { r in
            if r.completions[day] != nil {
                r.completions[day] = nil
                r.itemCompletions[day] = nil
            } else {
                r.completions[day] = now
                if let items = planDay(for: r, on: day)?.items, !items.isEmpty {
                    r.itemCompletions[day] = Set(items.map(\.id))
                }
            }
        }
    }

    /// Check / uncheck one item of the day's plan; finishing all items completes the row, unchecking reopens it.
    public mutating func toggleRepeatItem(todoID: UUID, itemID: UUID, on day: DayKey, now: Date) {
        updateRepeat(todoID) { r in
            let items = Set(planDay(for: r, on: day)?.items.map(\.id) ?? [])
            var done = r.itemCompletions[day] ?? []
            if done.contains(itemID) { done.remove(itemID) } else { done.insert(itemID) }
            r.itemCompletions[day] = done.isEmpty ? nil : done
            if !items.isEmpty && items.isSubset(of: done) {
                if r.completions[day] == nil { r.completions[day] = now }
            } else {
                r.completions[day] = nil
            }
        }
    }

    /// Check every checkable item of a one-line group for `day`, or uncheck all when all are already done.
    public mutating func toggleGroupRow(groupID: UUID, on day: DayKey, today: DayKey, now: Date) {
        guard let row = agenda(for: day, today: today, data: self).entries
            .first(where: { $0.isGroupRow && $0.id == groupID }) else { return }
        let targets = row.children.filter(\.isCheckable)
        let markDone = !targets.allSatisfy(\.isDone)
        for child in targets where child.isDone != markDone {
            if child.kind == .repeating {
                toggleRepeat(todoID: child.id, on: day, now: now)
            } else {
                toggle(todoID: child.id, on: day, today: today, now: now)
            }
        }
    }

    public mutating func updateRepeat(_ todoID: UUID, _ change: (inout Repeat) -> Void) {
        update(todoID) { t in
            guard case .repeating(var r) = t.schedule else { return }
            change(&r)
            t.schedule = .repeating(r)
        }
    }
}

extension PlanData {
    /// Consecutive scheduled occurrences done up to `day` (today counts once done; days off don't break it).
    public func streak(for todoID: UUID, on day: DayKey) -> Int {
        guard let todo = todos.first(where: { $0.id == todoID }), case .repeating(let r) = todo.schedule else { return 0 }
        func scheduled(_ d: DayKey) -> Bool {
            guard r.occurs(on: d) else { return false }
            if r.plan?.mode == .rotate { return r.completions[d] != nil || planDay(for: r, on: d) != nil }
            return true
        }
        var n = 0
        var d = day
        if r.completions[d] == nil { d = d.adding(days: -1) }
        while d >= r.start {
            if scheduled(d) {
                guard r.completions[d] != nil else { break }
                n += 1
            }
            d = d.adding(days: -1)
        }
        return n
    }
}
