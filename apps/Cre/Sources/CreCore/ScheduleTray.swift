import Foundation

/// A todo offered in the schedule's 待办 tray.
public struct TrayItem: Equatable, Sendable {
    public var title: String
    public var kind: EntryKind

    public init(title: String, kind: EntryKind) {
        self.title = title
        self.kind = kind
    }
}

/// The day's open todos for placing on the schedule: group rows opened up into their items, one per name.
public func trayItems(on day: DayKey, today: DayKey, data: PlanData) -> [TrayItem] {
    let a = agenda(for: day, today: today, data: data)
    var out: [TrayItem] = []
    for e in a.entries + a.foldedDeadlines {
        for x in (e.isGroupRow ? e.children : [e]) where !x.isDone && !out.contains(where: { $0.title == x.text }) {
            out.append(TrayItem(title: x.text, kind: x.kind))
        }
    }
    return out
}

/// Already over: an earlier day, or today with its end passed (`minuteNow` = minutes since midnight).
public func scheduleIsPast(_ o: ScheduleOccurrence, minuteNow: Int, today: DayKey) -> Bool {
    if o.day != today { return o.day < today }
    return o.end <= minuteNow
}

/// "09:05".
public func clock(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

/// Minutes since midnight for `date` in the current calendar.
public func minuteOfDay(_ date: Date) -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}
