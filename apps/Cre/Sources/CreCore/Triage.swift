import Foundation

/// 周五清理从这个钟点起出现。
public let triageHour = 19

/// Friday at or after `triageHour`, and this Friday's triage not yet handled.
public func shouldOfferTriage(now: Date, lastTriagedWeek: DayKey?, calendar: Calendar = .current) -> Bool {
    let friday = 6
    guard calendar.component(.weekday, from: now) == friday,
          calendar.component(.hour, from: now) >= triageHour else { return false }
    return lastTriagedWeek != DayKey.from(now, calendar: calendar)
}

/// Unfinished day todos and deadlines whose date is already past.
public func triageCandidates(today: DayKey, data: PlanData) -> [Todo] {
    data.todos.filter { t in
        guard !t.isDone, data.group(t.groupID)?.isArchived != true else { return false }
        switch t.schedule {
        case .day(let d), .deadline(let d): return d < today
        default: return false
        }
    }
}

extension PlanData {
    /// 今天做：becomes a day todo for today.
    public mutating func doToday(_ id: UUID, today: DayKey) {
        update(id) { $0.schedule = .day(today) }
    }

    /// 改个日期：keeps the kind, changes the date.
    public mutating func reschedule(_ id: UUID, to day: DayKey) {
        update(id) { t in
            switch t.schedule {
            case .day: t.schedule = .day(day)
            case .deadline: t.schedule = .deadline(day)
            default: break
            }
        }
    }
}
