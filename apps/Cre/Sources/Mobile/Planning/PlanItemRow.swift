import CreCore
import SwiftUI

/// Long-press menu for a todo, the same on 首页 and 规划: 移到 / 写感想 / 删除.
struct PlanItemMenu: View {
    @ObservedObject var state: MobileState
    let todo: Todo
    @Binding var writing: Bool

    /// 感想 belong to items of a list group (finished or not; saving ticks it).
    static func canReflect(_ todo: Todo, _ data: PlanData) -> Bool {
        guard let g = data.group(todo.groupID), case .list = g.kind, !todo.isGroupAnchor else { return false }
        return true
    }

    var body: some View {
        Menu("移到") {
            Button("零散待办") { state.data.moveTodo(todo.id, toGroup: nil) }.disabled(todo.groupID == nil)
            ForEach(state.data.visibleGroups) { g in
                Button(g.name) { state.data.moveTodo(todo.id, toGroup: g.id) }.disabled(todo.groupID == g.id)
            }
        }
        if Self.canReflect(todo, state.data) {
            Button(state.data.reflection(for: todo.id) == nil ? "写感想" : "查看感想") { writing = true }
        }
        Button("删除", role: .destructive) { state.data.deleteTodo(todo.id) }
    }
}

/// A todo in a 规划 card: ring, priority, text; below it time, tags, 进行中, done date. Tap = edit, swipe = delete.
struct PlanItemRow: View {
    @ObservedObject var state: MobileState
    let todo: Todo
    var showOngoing = false

    @State private var editing = false
    @State private var writing = false

    private var kind: EntryKind? {
        switch todo.schedule {
        case .none: nil
        case .day: .day
        case .deadline: .deadline
        case .span: .span
        case .repeating: .repeating
        }
    }

    private var color: Color { kind.map(Theme.color(for:)) ?? Theme.undated }

    private var timeLabel: String? {
        if case .deadline(let d) = todo.schedule { return ddlLabel(d) }
        return Fmt.schedule(todo.schedule)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { state.data.toggle(todoID: todo.id, on: state.today, now: Date()) } label: {
                Ring(color: color, filled: todo.isDone, size: 20)
            }
            .buttonStyle(.plain)
            .disabled(todo.isRepeating)
            .accessibilityIdentifier("tick-\(todo.text)")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let p = todo.priority { PriorityChip(priority: p) }
                    Text(todo.text)
                }
                details
            }
            Spacer(minLength: 0)
            if state.data.reflection(for: todo.id) != nil {
                Button { writing = true } label: { Image(systemName: "text.quote").font(.footnote) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("查看感想")
            }
        }
        .padding(.vertical, 2)
        .opacity(todo.isDone ? Theme.doneOpacity : 1)
        .contentShape(Rectangle())
        .onTapGesture { editing = true }
        .swipeActions(edge: .trailing) {
            Button("删除", role: .destructive) { state.data.deleteTodo(todo.id) }
        }
        .contextMenu {
            if showOngoing && !todo.isDone {
                Button(todo.isOngoing ? "取消进行中" : "设为进行中") { state.data.setOngoing(todo.id, !todo.isOngoing) }
            }
            PlanItemMenu(state: state, todo: todo, writing: $writing)
        }
        .sheet(isPresented: $editing) { EditSheet(state: state, todo: todo) { editing = false } }
        .sheet(isPresented: $writing) { ReflectionScreen(state: state, fixedTodoID: todo.id) { writing = false } }
    }

    @ViewBuilder private var details: some View {
        let ongoing = showOngoing && !todo.isDone && todo.isOngoing
        if ongoing || !todo.tags.isEmpty || todo.isDone || timeLabel != nil {
            HStack(spacing: 4) {
                if ongoing {
                    Button { state.data.setOngoing(todo.id, false) } label: {
                        Tag(text: "▶ 进行中", color: Theme.color(for: .repeating))
                    }
                    .buttonStyle(.plain)
                }
                if todo.isDone, let d = todo.completedDay {
                    Tag(text: Fmt.date(state.data.reflection(for: todo.id)?.finishedOn ?? d), color: .gray)
                } else if let label = timeLabel {
                    Tag(text: label, color: kind == .deadline ? Theme.color(for: .deadline) : .gray)
                }
                ForEach(todo.tags, id: \.self) { Tag(text: "#\($0)", color: .teal) }
            }
        }
    }
}

/// A day of a cycle group: ring for that day, its name, and its actions.
struct CycleSlotRow: View {
    @ObservedObject var state: MobileState
    let anchorID: UUID
    let slot: CycleSlot

    private let color = Theme.color(for: .repeating)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { state.data.toggleRepeat(todoID: anchorID, on: slot.date, now: Date()) } label: {
                Ring(color: color, filled: slot.isDone, size: 20)
            }
            .buttonStyle(.plain)
            .disabled(!slot.checkable)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(slot.day.name.isEmpty ? slot.label : "\(slot.label) · \(slot.day.name)")
                    if slot.isToday { Tag(text: "今天", color: color) }
                }
                if !slot.day.items.isEmpty {
                    Text(slot.day.items.map(\.text).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(slot.isDone ? Theme.doneOpacity : 1)
    }
}

/// 「＋ 加一项」 at the end of a card: a faint row until tapped, then a field that stays open for the next item.
struct InlineAddRow: View {
    @ObservedObject var state: MobileState
    let group: TodoGroup
    let placeholder: String
    /// A line without a recognized time stays undated.
    let undated: Bool
    var nextPhase: (DayKey, DayKey)? = nil

    @State private var text = ""
    @State private var active = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").font(.footnote.weight(.semibold)).frame(width: 20)
            if active {
                TextField(placeholder, text: $text)
                    .focused($focused)
                    .submitLabel(.next)
                    .onSubmit(submit)
                    .onChange(of: focused) { if !focused && text.isEmpty { active = false } }
            } else {
                Text(placeholder)
                Spacer()
            }
        }
        .foregroundStyle(active ? Color.primary : Color.secondary)
        .contentShape(Rectangle())
        .onTapGesture { if !active { active = true; focused = true } }
        .accessibilityElement(children: active ? .contain : .combine)
        .accessibilityAddTraits(active ? [] : .isButton)
        .accessibilityIdentifier(active ? "" : "add-\(group.name)")
    }

    private func submit() {
        let parsed = parseInput(text, today: state.today)
        var choice: TimeChoice? = nil
        if parsed.schedule == .none, let (s, e) = nextPhase {
            choice = TimeChoice(schedule: .span(start: s, end: e), priority: parsed.priority)
        }
        if state.add(text, override: choice, groupID: group.id, defaultToViewingDay: !undated && nextPhase == nil) {
            text = ""
            focused = true  // ready for the next one
        }
    }
}
