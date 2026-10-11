import Foundation

/// 看什么。
public enum SummaryScope: Codable, Equatable, Hashable, Sendable {
    case all
    case group(UUID)
    case tag(String)
}

/// 看多久。
public enum SummaryPeriod: Codable, Equatable, Hashable, Sendable {
    case today, thisWeek, thisMonth
    case custom(DayKey, DayKey)

    /// Concrete days; weeks start on Monday; "this week / month" run up to today.
    public func range(today: DayKey) -> (DayKey, DayKey) {
        switch self {
        case .today: return (today, today)
        case .thisWeek: return (today.adding(days: -((today.weekday + 5) % 7)), today)
        case .thisMonth: return (DayKey(year: today.year, month: today.month, day: 1)!, today)
        case .custom(let a, let b): return (min(a, b), max(a, b))
        }
    }
}

/// 统计什么。
public enum SummaryMetric: String, Codable, CaseIterable, Sendable {
    case count, rate, duration, missed, byGroup, daily

    public var label: String {
        switch self {
        case .count: "完成数"
        case .rate: "完成率"
        case .duration: "平均用时"
        case .missed: "未完成的日子"
        case .byGroup: "按模块组"
        case .daily: "每日完成"
        }
    }
}

public struct SummaryTemplate: Identifiable, Codable, Equatable, Sendable {
    /// Last change, for sync.
    public var modifiedAt: Date? = nil
    public var id: UUID = UUID()
    public var name: String
    public var scope: SummaryScope
    public var period: SummaryPeriod
    public var metrics: [SummaryMetric]
    public var createdAt: Date
}

public struct MissedLine: Codable, Equatable, Sendable {
    public var name: String
    public var days: [DayKey]
}

public struct RepeatLine: Codable, Equatable, Sendable {
    public var name: String
    public var done: Int
    public var total: Int
}

public struct GroupLine: Codable, Equatable, Sendable {
    public var name: String
    public var done: Int
    public var total: Int
}

public struct DailyLine: Codable, Equatable, Sendable {
    public var day: DayKey
    public var done: Int
}

/// 一份自选维度的总结报告（生成时刻的快照）。
public struct SummaryReport: Identifiable, Codable, Equatable, Sendable {
    /// Last change, for sync.
    public var modifiedAt: Date? = nil
    public var id: UUID = UUID()
    public var name: String
    public var templateID: UUID?
    public var scope: SummaryScope
    public var from: DayKey
    public var to: DayKey
    public var createdAt: Date
    public var metrics: [SummaryMetric]
    public var done: Int
    public var total: Int
    public var avgMinutes: Int?
    public var missed: [MissedLine]
    public var repeatLines: [RepeatLine]
    public var byGroup: [GroupLine]
    public var daily: [DailyLine]
    public var doneItems: [SummaryItem]
    public var openItems: [SummaryItem]

    public var rate: Int { total == 0 ? 0 : Int((Double(done) / Double(total) * 100).rounded()) }
}

private func inScope(_ t: Todo, _ scope: SummaryScope) -> Bool {
    switch scope {
    case .all: true
    case .group(let id): t.groupID == id
    case .tag(let tag): t.tags.contains(tag)
    }
}

/// Builds a report over `from...to` (days after `today` are not counted).
/// One-off todos count when dated or completed in the range; repeats count each scheduled day; phases are left out.
public func makeReport(name: String, templateID: UUID?, scope: SummaryScope, from: DayKey, to: DayKey,
                       metrics: [SummaryMetric], data: PlanData, today: DayKey, now: Date) -> SummaryReport {
    let last = min(to, today)
    let days: [DayKey] = from <= last ? (0...from.days(until: last)).map { from.adding(days: $0) } : []
    var done = 0, total = 0
    var minutes: [Int] = []
    var missed: [MissedLine] = []
    var repeats: [RepeatLine] = []
    var groupCounts: [String: (Int, Int)] = [:]
    var groupOrder: [String] = []
    var daily = Dictionary(uniqueKeysWithValues: days.map { ($0, 0) })
    var doneItems: [SummaryItem] = []
    var openItems: [SummaryItem] = []

    func count(_ group: String, isDone: Bool, n: Int = 1, d: Int = 1) {
        if groupCounts[group] == nil { groupOrder.append(group) }
        let c = groupCounts[group] ?? (0, 0)
        groupCounts[group] = (c.0 + (isDone ? d : 0), c.1 + n)
    }

    for t in data.todos where inScope(t, scope) {
        let groupName = data.group(t.groupID)?.name ?? "零散"
        let item = SummaryItem(text: t.text, group: t.isGroupAnchor ? nil : data.group(t.groupID)?.name)
        switch t.schedule {
        case .span:
            continue
        case .repeating(let r):
            func scheduled(_ d: DayKey) -> Bool {
                guard r.occurs(on: d) else { return false }
                if r.plan?.mode == .rotate { return r.completions[d] != nil || planDay(for: r, on: d) != nil }
                return true
            }
            let occ = days.filter(scheduled)
            guard !occ.isEmpty else { continue }
            let hit = occ.filter { r.completions[$0] != nil }
            done += hit.count
            total += occ.count
            hit.forEach { daily[$0, default: 0] += 1 }
            repeats.append(RepeatLine(name: t.text, done: hit.count, total: occ.count))
            let miss = occ.filter { r.completions[$0] == nil }
            if !miss.isEmpty { missed.append(MissedLine(name: t.text, days: miss)) }
            count(groupName, isDone: true, n: occ.count, d: hit.count)
        case .none, .day, .deadline:
            let completedInRange = t.completedDay.map { from <= $0 && $0 <= last } ?? false
            var dated: DayKey?
            if case .day(let d) = t.schedule { dated = d }
            if case .deadline(let d) = t.schedule { dated = d }
            let datedInRange = dated.map { from <= $0 && $0 <= to } ?? false
            guard completedInRange || (datedInRange && !t.isDone) else { continue }
            total += 1
            if completedInRange {
                done += 1
                daily[t.completedDay!, default: 0] += 1
                doneItems.append(item)
                if let c = t.completedAt { minutes.append(max(0, Int(c.timeIntervalSince(t.createdAt) / 60))) }
            } else {
                openItems.append(item)
            }
            count(groupName, isDone: completedInRange)
        }
    }

    return SummaryReport(
        name: name, templateID: templateID, scope: scope, from: from, to: to, createdAt: now, metrics: metrics,
        done: done, total: total,
        avgMinutes: minutes.isEmpty ? nil : minutes.reduce(0, +) / minutes.count,
        missed: missed, repeatLines: repeats,
        byGroup: groupOrder.sorted { a, b in a == "零散" ? false : (b == "零散" ? true : a < b) }
            .map { GroupLine(name: $0, done: groupCounts[$0]!.0, total: groupCounts[$0]!.1) },
        daily: days.map { DailyLine(day: $0, done: daily[$0] ?? 0) },
        doneItems: doneItems, openItems: openItems
    )
}

extension PlanData {
    @discardableResult
    public mutating func addTemplate(name: String, scope: SummaryScope, period: SummaryPeriod,
                                     metrics: [SummaryMetric], now: Date) -> UUID {
        let t = SummaryTemplate(name: name, scope: scope, period: period, metrics: metrics, createdAt: now)
        templates.append(t)
        return t.id
    }

    /// Generates a report from a template for its period as of `today`.
    @discardableResult
    public mutating func generate(templateID: UUID, today: DayKey, now: Date) -> SummaryReport? {
        guard let t = templates.first(where: { $0.id == templateID }) else { return nil }
        let (a, b) = t.period.range(today: today)
        let r = makeReport(name: t.name, templateID: t.id, scope: t.scope, from: a, to: b,
                           metrics: t.metrics, data: self, today: today, now: now)
        reports.append(r)
        return r
    }

    /// Deleting a template keeps the reports it produced.
    public mutating func deleteTemplate(_ id: UUID) { templates.removeAll { $0.id == id } }
    public mutating func deleteReport(_ id: UUID) { reports.removeAll { $0.id == id } }
}
