import CreCore
import Foundation

/// 新建 / 编辑模块组的选项：名称 → 类型 → 排期方式 → 具体排期. Shared by the Mac sheet and the phone screen.
struct GroupForm {
    enum Kind: String, CaseIterable, Identifiable {
        case cycle = "循环", list = "清单", phase = "阶段", ungrouped = "未分组"
        var id: String { rawValue }
    }
    enum CycleMode: String, CaseIterable, Identifiable {
        case fixed = "按星期固定", rotate = "按顺序轮换"
        var id: String { rawValue }
    }
    enum ListMode: String, CaseIterable, Identifiable {
        case daily = "每天", weekly = "每周"
        var id: String { rawValue }
    }

    static let order = [2, 3, 4, 5, 6, 7, 1]

    var name = ""
    var kind: Kind = .cycle
    var cycleMode: CycleMode = .fixed
    var listMode: ListMode = .daily
    var weekdays: Set<Int> = [2, 3, 4, 5, 6, 7]
    var period = 6
    var gap = 1
    var standard = ""
    /// 从哪天开始 (cycle / list).
    var start: DayKey

    /// The group's existing schedule, when editing.
    private var existingRule: Repeat?

    init(editing g: TodoGroup?, data: PlanData, today: DayKey) {
        if let g, case .repeating(let r)? = data.anchor(of: g.id)?.schedule { existingRule = r }
        start = existingRule?.start ?? today
        guard let g else { return }
        name = g.name
        switch g.kind {
        case .cycle: kind = .cycle
        case .list(let st): kind = .list; standard = st
        case .phase: kind = .phase
        case .ungrouped: kind = .ungrouped
        }
        if let r = existingRule {
            weekdays = r.weekdays.isEmpty ? Set(Self.order) : r.weekdays
            listMode = r.weekdays.isEmpty ? .daily : .weekly
            if let plan = r.plan {
                cycleMode = plan.mode == .rotate ? .rotate : .fixed
                if plan.mode == .rotate { period = max(1, plan.days.count); gap = plan.gap }
            }
        }
    }

    var needsDays: Bool {
        (kind == .cycle && cycleMode == .fixed) || (kind == .list && listMode == .weekly)
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !(needsDays && weekdays.isEmpty)
    }

    /// Empty field falls back to the shown reference.
    private var listStandard: String {
        let t = standard.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "1 小时" : t
    }

    /// Cycle plan for the chosen settings, keeping names and actions of days that remain.
    private func cyclePlan() -> DayPlan {
        let old = existingRule?.plan
        if cycleMode == .fixed {
            let days = Self.order.filter(weekdays.contains).map { w in
                old?.mode == .fixedWeekday ? (old?.days.first { $0.weekday == w } ?? PlanDay(name: "", weekday: w))
                                            : PlanDay(name: "", weekday: w)
            }
            return DayPlan(mode: .fixedWeekday, days: days)
        }
        let kept = old?.mode == .rotate ? Array(old!.days.prefix(period)) : []
        return DayPlan(mode: .rotate, days: kept + (kept.count..<period).map { _ in PlanDay(name: "") }, gap: gap)
    }

    /// Creates the group, or updates `editing` in place.
    func apply(to data: inout PlanData, editing: TodoGroup?, today: DayKey, now: Date) {
        let days = weekdays.count == 7 ? Set<Int>() : weekdays
        if let g = editing {
            let n = name.trimmingCharacters(in: .whitespaces)
            if n != g.name { data.updateGroup(g.id) { $0.name = n } }
            switch kind {
            case .cycle:
                let plan = cyclePlan()
                let rule = Repeat(weekdays: plan.mode == .fixedWeekday ? days : [], start: start, plan: plan)
                data.setGroupSchedule(g.id, kind: .cycle, rule: rule, now: now, today: today)
            case .list:
                data.setGroupSchedule(g.id, kind: .list(standard: listStandard),
                                      rule: Repeat(weekdays: listMode == .daily ? [] : days, start: start), now: now, today: today)
            case .phase:
                data.setGroupSchedule(g.id, kind: .phase, rule: nil, now: now, today: today)
            case .ungrouped:
                data.setGroupSchedule(g.id, kind: .ungrouped, rule: nil, now: now, today: today)
            }
            return
        }
        switch kind {
        case .cycle:
            let rule: Repeat
            if cycleMode == .fixed {
                let plan = DayPlan(mode: .fixedWeekday, days: Self.order.filter(weekdays.contains).map { PlanDay(name: "", weekday: $0) })
                rule = Repeat(weekdays: days, start: start, plan: plan)
            } else {
                let plan = DayPlan(mode: .rotate, days: (0..<period).map { _ in PlanDay(name: "") }, gap: gap)
                rule = Repeat(start: start, plan: plan)
            }
            data.addGroup(name, kind: .cycle, schedule: rule, now: now)
        case .list:
            data.addGroup(name, kind: .list(standard: listStandard),
                          schedule: Repeat(weekdays: listMode == .daily ? [] : days, start: start), now: now)
        case .phase:
            data.addGroup(name, kind: .phase, now: now)
        case .ungrouped:
            data.addGroup(name, kind: .ungrouped, now: now)
        }
    }
}

/// The small grey badge after a group's name: 循环 · 一三五 / 清单 · 每天 1 小时 / 阶段 · 2/4.
func groupBadge(_ group: TodoGroup, data: PlanData, today: DayKey) -> String? {
    var rule: Repeat? = nil
    if case .repeating(let r)? = data.anchor(of: group.id)?.schedule { rule = r }
    switch group.kind {
    case .cycle:
        guard let r = rule else { return "循环" }
        if let plan = r.plan, plan.mode == .rotate { return "循环 · 周期 \(plan.days.count) · 间隔 \(plan.gap)" }
        return "循环 · " + Fmt.weekdaySet(r.weekdays)
    case .list(let standard):
        return "清单 · \(Fmt.weekdaySet(rule?.weekdays ?? [])) \(standard)"
    case .phase:
        let phases = sortedPhases(data.todos.filter { $0.groupID == group.id && !$0.isGroupAnchor })
        guard !phases.isEmpty else { return "阶段" }
        let current = phases.firstIndex { p in
            if case .span(let s, let e) = p.schedule { return s <= today && today <= e }
            return false
        } ?? phases.lastIndex { $0.isDone } ?? 0
        return "阶段 · \(current + 1)/\(phases.count)"
    case .ungrouped:
        return nil
    }
}

/// Saves a cycle's day names and actions (one action per line).
func saveDayPlan(_ plan: DayPlan, names: [String], actions: [String], anchorID: UUID, in data: inout PlanData) {
    var p = plan
    for i in p.days.indices where names.indices.contains(i) {
        p.days[i].name = names[i].trimmingCharacters(in: .whitespaces)
        let lines = actions[i].split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        p.days[i].items = mergePlanItems(old: p.days[i].items, lines: lines)
    }
    data.updateRepeat(anchorID) { $0.plan = p }
}
