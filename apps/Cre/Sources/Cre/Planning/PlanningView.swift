import CreCore
import SwiftUI

struct PlanningView: View {
    @ObservedObject var state: AppState
    @FocusState private var inputFocused: Bool
    @State private var creating = false

    private var groups: [TodoGroup] { state.data.visibleGroups }
    @State private var showArchived = false
    @State private var archivedToDelete: TodoGroup?
    private var loose: [Todo] { state.data.todos.filter { $0.groupID == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                InputBar(state: state, defaultToViewingDay: false, placeholder: "记一条零散待办", focus: $inputFocused)
                Button { creating = true } label: { Label("新建模块组", systemImage: "plus.rectangle.on.rectangle") }
                    .controlSize(.large)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(groups) { GroupCard(state: state, group: $0) }
                    LooseCard(state: state, todos: loose)
                }
                if !state.data.archivedGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Button { withAnimation { showArchived.toggle() } } label: {
                            Label("已归档 \(state.data.archivedGroups.count)", systemImage: showArchived ? "chevron.down" : "chevron.right")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        if showArchived {
                            ForEach(state.data.archivedGroups) { g in
                                HStack {
                                    Text(g.name)
                                    Text("\(state.data.todos(in: g.id).filter { !$0.isGroupAnchor }.count) 条").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("恢复") { state.data.updateGroup(g.id) { $0.isArchived = false } }.controlSize(.small)
                                    Button("删除", role: .destructive) { archivedToDelete = g }.controlSize(.small)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                    .padding(.top, 14)
                }
            }
        }
        .padding(22)
        .sheet(isPresented: $creating) { NewGroupSheet(state: state) { creating = false } }
        .alert("删除「\(archivedToDelete?.name ?? "")」及其中 \(archivedToDelete.map { g in state.data.todos(in: g.id).filter { !$0.isGroupAnchor }.count } ?? 0) 条待办？",
               isPresented: Binding(get: { archivedToDelete != nil }, set: { if !$0 { archivedToDelete = nil } })) {
            Button("删除", role: .destructive) { if let g = archivedToDelete { state.data.deleteGroup(g.id) }; archivedToDelete = nil }
            Button("取消", role: .cancel) { archivedToDelete = nil }
        }
    }
}

/// 规划页下方的零散待办。
struct LooseCard: View {
    @ObservedObject var state: AppState
    let todos: [Todo]

    var body: some View {
        CardShell {
            Text("零散待办").font(.headline)
        } content: {
            ForEach(sortedForPlanning(todos)) { PlanRow(state: state, todo: $0) }
            if todos.isEmpty {
                Text("无").foregroundStyle(.tertiary).padding(.vertical, 6)
            }
        }
    }
}

struct CardShell<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) { header }
            content
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.09)))
    }
}

/// A plain todo row in planning: ring, priority, text (tap to edit), time tag (tap to edit), ongoing toggle.
struct PlanRow: View {
    @ObservedObject var state: AppState
    let todo: Todo
    var showOngoing = false

    @State private var editing = false
    @State private var draft = ""
    @State private var editingTime = false
    @State private var hovering = false
    @State private var writing = false
    @FocusState private var focused: Bool

    /// 感想 can be written on finished items of a list group.
    private var canReflect: Bool {
        guard todo.isDone, let g = state.data.group(todo.groupID), case .list = g.kind else { return false }
        return true
    }

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

    var body: some View {
        HStack(spacing: 9) {
            Button { state.data.toggle(todoID: todo.id, on: state.today, now: Date()) } label: {
                Ring(color: color, filled: todo.isDone, size: 14)
            }
            .buttonStyle(.plain)
            .disabled(todo.isRepeating)
            if let p = todo.priority {
                PriorityChip(priority: p)
            }
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { if !focused { commit() } }
            } else {
                Text(todo.text).lineLimit(1)
                    .onTapGesture { draft = todo.text; editing = true; focused = true }
            }
            Spacer(minLength: 4)
            if showOngoing && !todo.isDone {
                if todo.isOngoing {
                    Button { state.data.setOngoing(todo.id, false) } label: { Tag(text: "▶ 进行中", color: Theme.color(for: .repeating)) }
                        .buttonStyle(.plain)
                } else if hovering {
                    Button { state.data.setOngoing(todo.id, true) } label: { Tag(text: "▶ 设为进行中", color: .gray) }
                        .buttonStyle(.plain)
                }
            }
            ForEach(todo.tags, id: \.self) { Tag(text: "#\($0)", color: .teal) }
            if canReflect {
                // Written: a quote mark that stays. Not yet: a pen while the pointer is on the row.
                if state.data.reflection(for: todo.id) != nil {
                    Button { writing = true } label: { Image(systemName: "text.quote").font(.caption) }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("查看感想")
                } else if hovering {
                    Button { writing = true } label: { Image(systemName: "square.and.pencil").font(.caption) }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("写感想")
                }
            }
            if todo.isDone, let d = todo.completedDay {
                Tag(text: Fmt.date(state.data.reflection(for: todo.id)?.finishedOn ?? d), color: .gray)
            } else if let label = timeLabel {
                Tag(text: label, color: kind == .deadline ? Theme.color(for: .deadline) : .gray)
            }
            if hovering {
                Menu {
                    Button("零散待办") { state.data.moveTodo(todo.id, toGroup: nil) }.disabled(todo.groupID == nil)
                    Divider()
                    ForEach(state.data.visibleGroups) { g in
                        Button(g.name) { state.data.moveTodo(todo.id, toGroup: g.id) }.disabled(todo.groupID == g.id)
                    }
                } label: { Image(systemName: "arrow.right.square") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("移到")
                Button { state.data.deleteTodo(todo.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: Theme.barWidth).padding(.vertical, 3)
        }
        .opacity(todo.isDone ? Theme.doneOpacity : 1)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.045 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { editingTime = true }  // text = rename, blank = full edit
        .onHover { hovering = $0 }
        .contextMenu {
            if canReflect {
                Button(state.data.reflection(for: todo.id) == nil ? "写感想" : "查看感想") { writing = true }
                Divider()
            }
            Button("删除", role: .destructive) { state.data.deleteTodo(todo.id) }
        }
        .sheet(isPresented: $writing) {
            ReflectionEditor(state: state, fixedTodoID: todo.id) { writing = false }.padding(20).frame(width: 440)
        }
        .popover(isPresented: $editingTime) {
            EditCard(title: todo.text, today: state.today,
                     initial: TimeChoice(schedule: todo.schedule, priority: todo.priority, tags: todo.tags),
                     onSave: { state.setTime(todo.id, $0); editingTime = false },
                     onCancel: { editingTime = false }, knownTags: state.data.allTags)
        }
    }

    private var timeLabel: String? {
        if case .deadline(let d) = todo.schedule { return ddlLabel(d) }
        return Fmt.schedule(todo.schedule)
    }

    private func commit() {
        guard editing else { return }
        editing = false
        state.editText(todo.id, draft)
    }
}
