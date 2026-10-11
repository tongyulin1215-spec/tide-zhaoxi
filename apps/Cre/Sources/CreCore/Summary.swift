import Foundation

public struct SummaryItem: Codable, Equatable, Sendable {
    public var text: String
    public var group: String?
}

/// 每日总结：生成时刻的快照（待办与规划数据，不含记账）。
public struct DailySummary: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var day: DayKey
    public var createdAt: Date
    public var done: Int
    public var total: Int
    public var doneItems: [SummaryItem]
    public var openItems: [SummaryItem]
    /// Last change, for sync.
    public var modifiedAt: Date? = nil

    /// Completion rate in percent, rounded.
    public var rate: Int { total == 0 ? 0 : Int((Double(done) / Double(total) * 100).rounded()) }
}

public func makeDailySummary(day: DayKey, data: PlanData, now: Date) -> DailySummary {
    let a = agenda(for: day, today: day, data: data, sort: .priority)
    let rows = a.entries.flatMap { $0.isGroupRow ? $0.children : [$0] }.filter(\.isCheckable)
    func item(_ e: AgendaEntry) -> SummaryItem {
        let anchor = data.todos.first { $0.id == e.id }?.isGroupAnchor ?? false
        return SummaryItem(text: e.detail.map { "\(e.text) ▶ \($0)" } ?? e.text, group: anchor ? nil : e.groupName)
    }
    let done = rows.filter(\.countsAsDone)
    return DailySummary(day: day, createdAt: now, done: done.count, total: rows.count,
                        doneItems: done.map(item), openItems: rows.filter { !$0.countsAsDone }.map(item))
}

extension PlanData {
    /// Creates (or replaces) the day's summary. The day's note is kept as is.
    @discardableResult
    public mutating func generateSummary(day: DayKey, now: Date) -> DailySummary {
        let s = makeDailySummary(day: day, data: self, now: now)
        summaries.removeAll { $0.day == day }
        summaries.append(s)
        return s
    }

    /// Removes the day's report; the day's note stays.
    public mutating func deleteSummary(day: DayKey) {
        summaries.removeAll { $0.day == day }
    }

    public var summariesNewestFirst: [DailySummary] {
        summaries.sorted { $0.day > $1.day }
    }
}
