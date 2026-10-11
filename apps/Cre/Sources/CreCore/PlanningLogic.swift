import Foundation

/// Open first, then by priority and creation; done items last, newest first.
public func sortedForPlanning(_ todos: [Todo]) -> [Todo] {
    todos.sorted { a, b in
        if a.isDone != b.isDone { return !a.isDone }
        if a.isDone { return (a.completedAt ?? .distantPast) > (b.completedAt ?? .distantPast) }
        let pa = a.priority?.rawValue ?? 3, pb = b.priority?.rawValue ?? 3
        if pa != pb { return pa < pb }
        return a.createdAt < b.createdAt
    }
}

/// A phase group's phases in date order.
public func sortedPhases(_ items: [Todo]) -> [Todo] {
    items.sorted { a, b in
        if case .span(let sa, _) = a.schedule, case .span(let sb, _) = b.schedule { return sa < sb }
        return a.createdAt < b.createdAt
    }
}

/// New phase starts the day after the last one ends and lasts a week.
public func nextPhaseRange(items: [Todo], today: DayKey) -> (DayKey, DayKey) {
    let lastEnd = items.compactMap { t -> DayKey? in
        if case .span(_, let e) = t.schedule { return e }
        return nil
    }.max()
    let start = lastEnd?.adding(days: 1) ?? today
    return (start, start.adding(days: 6))
}

/// One day of a cycle group as listed on its card.
public struct CycleSlot: Sendable {
    public let day: PlanDay
    public let label: String
    public let date: DayKey
    public let isToday: Bool
    public let isDone: Bool
    public let checkable: Bool
}

private let weekdayNames = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]

/// The cycle's days for this week (fixed weekdays) or in rotation order, with what's done.
public func cycleSlots(_ r: Repeat, _ plan: DayPlan, today: DayKey) -> [CycleSlot] {
    switch plan.mode {
    case .fixedWeekday:
        let monday = today.adding(days: -((today.weekday + 5) % 7))
        return plan.days
            .sorted { (($0.weekday ?? 1) + 5) % 7 < (($1.weekday ?? 1) + 5) % 7 }
            .map { day in
                let date = monday.adding(days: ((day.weekday ?? 1) + 5) % 7)
                return CycleSlot(day: day, label: weekdayNames[day.weekday ?? 1], date: date, isToday: date == today,
                                 isDone: r.completions[date] != nil, checkable: date <= today)
            }
    case .rotate:
        let current = planDay(for: r, on: today)
        let k = r.completions.keys.filter { $0 >= r.start && $0 < today }.count
        let doneToday = r.completions[today] != nil
        let position = current.flatMap { c in plan.days.firstIndex { $0.id == c.id } }
        return plan.days.enumerated().map { i, day in
            let finished = position.map { i < $0 } ?? false || (doneToday && i == (k % plan.days.count))
            return CycleSlot(day: day, label: "第 \(i + 1) 天", date: today,
                             isToday: i == position, isDone: finished, checkable: i == position)
        }
    }
}
