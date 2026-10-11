import CreCore
import SwiftUI

/// One 模块组 as a card (a list section): header row (tap to fold, 「…」 for the group's actions), then its items.
struct GroupCardView: View {
    @ObservedObject var state: MobileState
    let group: TodoGroup

    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var editingPlan = false
    @State private var editingSchedule = false

    private var anchor: Todo? { state.data.anchor(of: group.id) }
    private var repeatRule: Repeat? {
        if case .repeating(let r)? = anchor?.schedule { return r }
        return nil
    }
    private var items: [Todo] { state.data.todos.filter { $0.groupID == group.id && !$0.isGroupAnchor } }

    var body: some View {
        Section {
            header
            if !group.collapsed { content }
        }
        .alert("删除「\(group.name)」及其中 \(items.count) 条待办？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { state.data.deleteGroup(group.id) }
            Button("取消", role: .cancel) {}
        }
        .alert("重命名", isPresented: $renaming) {
            TextField("名称", text: $newName)
            Button("保存", action: rename)
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $editingSchedule) {
            NavigationStack { NewGroupScreen(state: state, editing: group) { editingSchedule = false } }
        }
        .sheet(isPresented: $editingPlan) {
            if let anchor, let r = repeatRule {
                DayPlanScreen(state: state, anchorID: anchor.id, rule: r) { editingPlan = false }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { withAnimation { state.data.updateGroup(group.id) { $0.collapsed.toggle() } } } label: {
                HStack(spacing: 8) {
                    Image(systemName: group.collapsed ? "chevron.right" : "chevron.down")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.secondary).frame(width: 20)
                    if group.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                    Text(group.name).font(.headline).lineLimit(1)
                    if let badge = groupBadge(group, data: state.data, today: state.today) {
                        Text(badge).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let anchor, case .repeating = anchor.schedule {
                        let n = state.data.streak(for: anchor.id, on: state.today)
                        if n > 1 { Text("连续 \(n) 次").font(.caption).foregroundStyle(Theme.color(for: .repeating)) }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card-\(group.name)")
            menu
        }
    }

    private var menu: some View {
        Menu {
            Button(group.isPinned ? "取消置顶" : "置顶") { state.data.updateGroup(group.id) { $0.isPinned.toggle() } }
            Button("重命名") { newName = group.name; renaming = true }
            if case .cycle = group.kind { Button("编辑安排") { editingPlan = true } }
            Button("编辑排期") { editingSchedule = true }
            Picker("首页显示", selection: Binding(
                get: { group.todayDisplay },
                set: { v in state.data.updateGroup(group.id) { $0.todayDisplay = v } }
            )) {
                Text("展开").tag(TodayDisplay.expanded)
                Text("一行").tag(TodayDisplay.oneLine)
                Text("不显示").tag(TodayDisplay.hidden)
            }
            .pickerStyle(.menu)
            Button("归档") { state.data.updateGroup(group.id) { $0.isArchived = true } }
            Button("删除", role: .destructive) { confirmDelete = true }
        } label: {
            Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 36, height: 30).contentShape(Rectangle())
        }
        .accessibilityIdentifier("menu-\(group.name)")
    }

    @ViewBuilder private var content: some View {
        switch group.kind {
        case .cycle:
            if let anchor, let r = repeatRule, let plan = r.plan, !plan.days.isEmpty {
                ForEach(cycleSlots(r, plan, today: state.today), id: \.day.id) { slot in
                    CycleSlotRow(state: state, anchorID: anchor.id, slot: slot)
                }
            } else {
                Button("编辑安排") { editingPlan = true }
            }
            ForEach(sortedForPlanning(items)) { PlanItemRow(state: state, todo: $0) }
        case .list:
            ForEach(sortedForPlanning(items)) { PlanItemRow(state: state, todo: $0, showOngoing: true) }
            InlineAddRow(state: state, group: group, placeholder: "加一项", undated: true)
        case .phase:
            ForEach(sortedPhases(items)) { PlanItemRow(state: state, todo: $0) }
            InlineAddRow(state: state, group: group, placeholder: "加一个阶段", undated: false,
                         nextPhase: nextPhaseRange(items: items, today: state.today))
        case .ungrouped:
            ForEach(sortedForPlanning(items)) { PlanItemRow(state: state, todo: $0) }
            InlineAddRow(state: state, group: group, placeholder: "加一条", undated: true)
        }
    }

    private func rename() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        state.data.updateGroup(group.id) { $0.name = n }
        if let anchor {
            let text: String
            if case .list(let st) = group.kind { text = "\(n) \(st)" } else { text = n }
            state.data.update(anchor.id) { $0.text = text }
        }
    }
}
