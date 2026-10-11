import Foundation

// MARK: - Merging two copies (sync)
// Record by record: the later `modifiedAt` wins (no stamp = oldest). A deletion mark later than the surviving
// record removes it; an edit after the mark brings the record back. Marks from both sides are kept.

private func later(_ a: Date?, _ b: Date?) -> Bool { (a ?? .distantPast) > (b ?? .distantPast) }

private func unionMarks(_ a: [String: Date], _ b: [String: Date]) -> [String: Date] {
    a.merging(b) { max($0, $1) }
}

/// `mine` wins ties. `keepLocal` copies device-only fields from my copy onto the winner.
private func mergeList<T: Stampable>(_ mine: [T], _ theirs: [T], marks: inout [String: Date],
                                     keepLocal: (inout T, T) -> Void = { _, _ in }) -> [T] {
    let other = Dictionary(theirs.map { ($0.stampKey, $0) }, uniquingKeysWith: { a, _ in a })
    var out: [T] = []
    var seen = Set<String>()
    func place(_ r: T) {
        if let mark = marks[r.stampKey] {
            if mark >= (r.modifiedAt ?? .distantPast) { return }  // deleted after its last edit
            marks[r.stampKey] = nil                                // edited after the delete: back again
        }
        out.append(r)
    }
    for m in mine {
        seen.insert(m.stampKey)
        guard let t = other[m.stampKey] else { place(m); continue }
        var winner = later(t.modifiedAt, m.modifiedAt) ? t : m
        keepLocal(&winner, m)
        place(winner)
    }
    for t in theirs where !seen.contains(t.stampKey) { place(t) }
    return out
}

/// Per-day values (随笔, pulled tags): the later stamp wins; unstamped days keep whichever side has a value.
private func mergeDays<V: Equatable>(_ mine: [DayKey: V], _ myStamps: [DayKey: Date],
                                     _ theirs: [DayKey: V], _ theirStamps: [DayKey: Date]) -> ([DayKey: V], [DayKey: Date]) {
    var values: [DayKey: V] = [:]
    var stamps: [DayKey: Date] = [:]
    let days = Set(mine.keys).union(theirs.keys).union(myStamps.keys).union(theirStamps.keys)
    for day in days {
        let ms = myStamps[day], ts = theirStamps[day]
        if later(ts, ms) {
            values[day] = theirs[day]
        } else if ms == nil && ts == nil {
            values[day] = mine[day] ?? theirs[day]
        } else {
            values[day] = mine[day]
        }
        stamps[day] = [ms, ts].compactMap { $0 }.max()
    }
    return (values, stamps)
}

extension PlanData {
    /// This copy and another (from the other device) as one; run on both sides, the result is the same.
    public func merged(with other: PlanData) -> PlanData {
        var m = self
        var marks = unionMarks(deletions, other.deletions)
        m.todos = mergeList(todos, other.todos, marks: &marks)
        m.groups = mergeList(groups, other.groups, marks: &marks) { winner, mine in winner.collapsed = mine.collapsed }
        m.summaries = mergeList(summaries, other.summaries, marks: &marks)
        m.templates = mergeList(templates, other.templates, marks: &marks)
        m.reports = mergeList(reports, other.reports, marks: &marks)
        m.reflections = mergeList(reflections, other.reflections, marks: &marks)
        m.deletions = marks
        (m.notes, m.noteStamps) = mergeDays(notes, noteStamps, other.notes, other.noteStamps)
        (m.pulledTags, m.pulledTagStamps) = mergeDays(pulledTags, pulledTagStamps, other.pulledTags, other.pulledTagStamps)
        m.lastTriagedWeek = [lastTriagedWeek, other.lastTriagedWeek].compactMap { $0 }.max()
        m.version = max(version, other.version)
        return m
    }
}

extension LedgerData {
    public func merged(with other: LedgerData) -> LedgerData {
        var m = self
        var marks = unionMarks(deletions, other.deletions)
        m.entries = mergeList(entries, other.entries, marks: &marks)
        m.deletions = marks
        // Categories and the opening balance each go by their own stamp.
        if later(other.settingsModifiedAt, settingsModifiedAt) {
            m.expenseCategories = other.expenseCategories
            m.incomeCategories = other.incomeCategories
            m.settingsModifiedAt = other.settingsModifiedAt
        }
        // Before it had its own stamp, an opening balance was stamped with the categories.
        let mine = openingModifiedAt ?? (opening != nil ? settingsModifiedAt : nil)
        let theirs = other.openingModifiedAt ?? (other.opening != nil ? other.settingsModifiedAt : nil)
        if later(theirs, mine) {
            m.opening = other.opening
            m.openingModifiedAt = theirs
        } else if mine == nil && theirs == nil {
            m.opening = opening ?? other.opening
        }
        return m
    }
}

extension ScheduleData {
    public func merged(with other: ScheduleData) -> ScheduleData {
        var m = self
        var marks = unionMarks(deletions, other.deletions)
        m.items = mergeList(items, other.items, marks: &marks)
        m.deletions = marks
        return m
    }
}

/// Drops deletion marks older than `days`, once both sides have seen them.
public func pruneDeletions(_ marks: inout [String: Date], olderThan days: Int, now: Date) {
    let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
    marks = marks.filter { $0.value >= cutoff }
}

// MARK: - 新的一天开始时间, synced with a stamp

public struct DayStartSetting: Codable, Equatable, Sendable {
    public var hour: Int
    public var modifiedAt: Date?

    public init(hour: Int, modifiedAt: Date?) {
        self.hour = hour
        self.modifiedAt = modifiedAt
    }

    public func merged(with other: DayStartSetting) -> DayStartSetting {
        later(other.modifiedAt, modifiedAt) ? other : self
    }
}

/// day-start.json: a bare number (older) or {hour, modifiedAt}.
public func loadDayStart(_ url: URL? = dayStartURL()) -> DayStartSetting {
    guard let url, let d = try? Data(contentsOf: url) else { return DayStartSetting(hour: 0, modifiedAt: nil) }
    if let s = try? JSONDecoder().decode(DayStartSetting.self, from: d), (0...6).contains(s.hour) { return s }
    if let h = try? JSONDecoder().decode(Int.self, from: d), (0...6).contains(h) { return DayStartSetting(hour: h, modifiedAt: nil) }
    return DayStartSetting(hour: 0, modifiedAt: nil)
}

public func saveDayStart(_ s: DayStartSetting, to url: URL? = dayStartURL()) {
    guard let url, let d = try? JSONEncoder().encode(s) else { return }
    try? d.write(to: url, options: .atomic)
}
