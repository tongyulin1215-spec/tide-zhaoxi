import CreCore
import SwiftUI

/// One line of the home list. Circle = tick; rest of the row = edit sheet; swipe left = delete.
struct HomeRow: View {
    @ObservedObject var state: MobileState
    let entry: AgendaEntry
    var indent: CGFloat = 0
    @Binding var editing: UUID?
    @State private var expanded = false
    @State private var writing = false

    private var color: Color { Theme.color(for: entry.kind) }
    private var todo: Todo? { entry.isGroupRow ? nil : state.todo(entry.id) }
    private var canEdit: Bool { todo != nil }
    /// Delete and the context menu stay off a group's own repeat; it belongs to the group.
    private var canDelete: Bool { todo != nil && !(todo?.isGroupAnchor ?? false) }

    /// The repeat's items for the viewed day, with their done state.
    private var planItems: [(PlanItem, Bool)] {
        guard let todo, case .repeating(let r) = todo.schedule,
              let items = planDay(for: r, on: state.viewingDay)?.items else { return [] }
        let done = r.itemCompletions[state.viewingDay] ?? []
        return items.map { ($0, done.contains($0.id)) }
    }

    private var canExpand: Bool { entry.isGroupRow || !planItems.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 20)
                marker
                if let p = entry.priority, !entry.isGroupRow { PriorityChip(priority: p) }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.text).lineLimit(1)
                        if let p = entry.progress, p.total > 0 {
                            Text("\(p.done)/\(p.total)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    if let detail = entry.detail {
                        Text("▶ \(detail)").font(.caption).foregroundStyle(color).lineLimit(1)
                    }
                    tags
                }
                Spacer(minLength: 4)
                if canExpand {
                    Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary).frame(width: 36, height: 36).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expanded ? "收起" : "展开")
                    .accessibilityIdentifier("expand-\(entry.text)")
                }
            }
            .padding(.leading, indent)
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("row-\(entry.text)")
            .opacity(entry.isDone || entry.movedLater ? Theme.doneOpacity : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                // The arrow expands; the rest of the row edits. A group row has nothing to edit, so it expands.
                if canEdit { editing = entry.id }
                else if canExpand { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } }
            }
            if expanded {
                if entry.isGroupRow {
                    ForEach(entry.children) { HomeRow(state: state, entry: $0, indent: indent + 18, editing: $editing) }
                } else {
                    ForEach(planItems, id: \.0.id) { item, done in
                        HStack(spacing: 8) {
                            Button { state.toggleItem(todoID: entry.id, itemID: item.id) } label: { Ring(color: color, filled: done, size: 14) }
                                .buttonStyle(.plain)
                            Text(item.text).foregroundStyle(done ? .secondary : .primary)
                        }
                        .padding(.leading, indent + 34).padding(.vertical, 4)
                    }
                }
            }
        }
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            if canDelete { Button("删除", role: .destructive) { state.data.deleteTodo(entry.id) } }
        }
        .contextMenu {
            if canDelete, let todo { PlanItemMenu(state: state, todo: todo, writing: $writing) }
        }
        .sheet(isPresented: $writing) { ReflectionScreen(state: state, fixedTodoID: entry.id) { writing = false } }
    }

    @ViewBuilder private var marker: some View {
        if entry.kind == .span && !entry.isGroupRow {
            Circle().fill(color.opacity(0.25)).frame(width: 18, height: 18)
        } else if entry.isCheckable {
            Button { withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { state.toggle(entry) } } label: {
                Ring(color: color, filled: entry.isDone, size: 20)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tick-\(entry.text)")
        } else {
            Color.clear.frame(width: 20, height: 20)
        }
    }

    /// Time and grouping tags, under the text (a phone row is too narrow for them on the right).
    @ViewBuilder private var tags: some View {
        let groupName = entry.isGroupRow || (todo?.isGroupAnchor ?? false) ? nil : entry.groupName
        let hasAny = entry.overdueDays > 0 || entry.deadline != nil || entry.doneLater != nil || entry.movedLater
            || entry.kind == .span || !(todo?.tags ?? []).isEmpty || groupName != nil
        if hasAny {
            HStack(spacing: 4) {
                if entry.overdueDays > 0 { Tag(text: "拖了 \(entry.overdueDays) 天", color: Theme.overdue) }
                if entry.movedLater { Tag(text: "已顺延", color: .gray) }
                if let d = entry.doneLater { Tag(text: "\(d.month)月\(d.day)日完成", color: .gray) }
                if let due = entry.deadline { Tag(text: ddlLabel(due), color: Theme.color(for: .deadline)) }
                if let todo, case .span(let s, let e) = todo.schedule {
                    Tag(text: "第 \(s.days(until: state.viewingDay) + 1)/\(s.days(until: e) + 1) 天", color: color)
                }
                ForEach(todo?.tags ?? [], id: \.self) { Tag(text: "#\($0)", color: .teal) }
                if let g = groupName { Tag(text: g, color: .gray) }
            }
            .lineLimit(1)
        }
    }
}
