import CreCore
import SwiftUI

struct GroupCard: View {
    @ObservedObject var state: AppState
    let group: TodoGroup

    @FocusState private var inputFocused: Bool
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
        CardShell {
            Button { state.data.updateGroup(group.id) { $0.collapsed.toggle() } } label: {
                Image(systemName: group.collapsed ? "chevron.right" : "chevron.down").font(.caption)
            }
            .buttonStyle(.borderless)
            if group.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
            Text(group.name).font(.headline).lineLimit(1)
            if let badge { Text(badge).font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 1)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5)) }
            if let anchor, case .repeating = anchor.schedule {
                let n = state.data.streak(for: anchor.id, on: state.today)
                if n > 1 { Text("连续 \(n) 次").font(.caption).foregroundStyle(Theme.color(for: .repeating)) }
            }
            Spacer()
            menu
        } content: {
            if !group.collapsed { content }
        }
        .alert("删除「\(group.name)」及其中 \(items.count) 条待办？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { state.data.deleteGroup(group.id) }
            Button("取消", role: .cancel) {}
        }
        .alert("重命名", isPresented: $renaming) {
            TextField("名称", text: $newName)
            Button("保存") { rename() }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $editingSchedule) {
            NewGroupSheet(state: state, editing: group) { editingSchedule = false }
        }
        .sheet(isPresented: $editingPlan) {
            if let anchor, let r = repeatRule {
                DayPlanEditor(state: state, anchorID: anchor.id, rule: r) { editingPlan = false }
            }
        }
    }

    // MARK: Header

    private var badge: String? { groupBadge(group, data: state.data, today: state.today) }

    private var menu: some View {
        Menu {
            Button(group.isPinned ? "取消置顶" : "置顶") { state.data.updateGroup(group.id) { $0.isPinned.toggle() } }
            Button("重命名") { newName = group.name; renaming = true }
            if case .cycle = group.kind { Button("编辑安排") { editingPlan = true } }
            Button("编辑排期") { editingSchedule = true }
            Picker("今日显示", selection: Binding(
                get: { group.todayDisplay },
                set: { v in state.data.updateGroup(group.id) { $0.todayDisplay = v } }
            )) {
                Text("展开").tag(TodayDisplay.expanded)
                Text("一行").tag(TodayDisplay.oneLine)
                Text("不显示").tag(TodayDisplay.hidden)
            }
            Divider()
            Button("归档") { state.data.updateGroup(group.id) { $0.isArchived = true } }
            Button("删除", role: .destructive) { confirmDelete = true }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
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

    // MARK: Body

    @ViewBuilder private var content: some View {
        switch group.kind {
        case .cycle:
            cycleRows
            ForEach(sortedForPlanning(items)) { PlanRow(state: state, todo: $0) }
        case .list:
            ForEach(sortedForPlanning(items)) { PlanRow(state: state, todo: $0, showOngoing: true) }
            InlineAdd(state: state, groupID: group.id, placeholder: "加一项", undated: true)
        case .phase:
            ForEach(sortedPhases) { PlanRow(state: state, todo: $0) }
            InlineAdd(state: state, groupID: group.id, placeholder: "加一个阶段", undated: false, nextPhase: nextPhaseRange)
        case .ungrouped:
            ForEach(sortedForPlanning(items)) { PlanRow(state: state, todo: $0) }
            InlineAdd(state: state, groupID: group.id, placeholder: "加一条", undated: true)
        }
    }

    private var sortedPhases: [Todo] { CreCore.sortedPhases(items) }

    /// New phase starts the day after the last one ends and lasts a week.
    private var nextPhaseRange: (DayKey, DayKey) { CreCore.nextPhaseRange(items: items, today: state.today) }

    @ViewBuilder private var cycleRows: some View {
        if let anchor, let r = repeatRule, let plan = r.plan, !plan.days.isEmpty {
            ForEach(cycleSlots(r, plan), id: \.day.id) { slot in
                CycleRow(state: state, anchorID: anchor.id, slot: slot)
            }
        } else {
            Button("编辑安排") { editingPlan = true }
                .buttonStyle(.link)
                .padding(.vertical, 4)
        }
    }

    private func cycleSlots(_ r: Repeat, _ plan: DayPlan) -> [CycleSlot] { CreCore.cycleSlots(r, plan, today: state.today) }
}

struct CycleRow: View {
    @ObservedObject var state: AppState
    let anchorID: UUID
    let slot: CycleSlot

    private let color = Theme.color(for: .repeating)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                Button { state.data.toggleRepeat(todoID: anchorID, on: slot.date, now: Date()) } label: {
                    Ring(color: color, filled: slot.isDone, size: 14)
                }
                .buttonStyle(.plain)
                .disabled(!slot.checkable)
                Text(slot.day.name.isEmpty ? slot.label : "\(slot.label) · \(slot.day.name)").lineLimit(1)
                Spacer()
                if slot.isToday { Tag(text: "今天", color: color) }
            }
            if !slot.day.items.isEmpty {
                Text(slot.day.items.map(\.text).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .padding(.leading, 23)
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: Theme.barWidth).padding(.vertical, 3)
        }
        .opacity(slot.isDone ? Theme.doneOpacity : 1)
        .rowHover()
    }
}

/// "＋ 加一项" at the end of a card: a faint row until clicked, then a field that stays open for the next item.
struct InlineAdd: View {
    @ObservedObject var state: AppState
    let groupID: UUID
    let placeholder: String
    /// When true, a line without a recognized time stays undated.
    let undated: Bool
    var nextPhase: (DayKey, DayKey)? = nil

    @State private var text = ""
    @State private var active = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 14)
            if active {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand(perform: close)
                    .onChange(of: focused) { if !focused && text.isEmpty { close() } }
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.accentColor).frame(height: 1.5).offset(y: 3) }
            } else {
                Text(placeholder)
                Spacer()
            }
        }
        .foregroundStyle(active ? Color.primary : Color.secondary.opacity(0.7))
        .padding(.leading, 13)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { if !active { active = true; focused = true } }
    }

    private func submit() {
        let parsed = parseInput(text, today: state.today)
        var choice: TimeChoice? = nil
        if parsed.schedule == .none, let (s, e) = nextPhase {
            choice = TimeChoice(schedule: .span(start: s, end: e), priority: parsed.priority)
        }
        if state.add(text, override: choice, groupID: groupID, defaultToViewingDay: !undated && nextPhase == nil) {
            text = ""
            focused = true  // ready for the next one
        }
    }

    private func close() {
        text = ""
        active = false
    }
}
