import AppKit
import CreCore
import SwiftUI

struct AgendaRow: View {
    @ObservedObject var state: AppState
    let entry: AgendaEntry
    var indent: CGFloat = 0

    @State private var expanded = false
    @State private var pop = false
    @State private var editing = false
    @State private var draft = ""
    @State private var editingTime = false
    @State private var hovering = false
    @FocusState private var fieldFocused: Bool

    private var color: Color { Theme.color(for: entry.kind) }
    private var todo: Todo? { entry.isGroupRow ? nil : state.todo(entry.id) }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// The repeat's items for the viewed day, with their done state.
    private var planItems: [(PlanItem, Bool)] {
        guard let todo, case .repeating(let r) = todo.schedule,
              let items = planDay(for: r, on: state.viewingDay)?.items else { return [] }
        let done = r.itemCompletions[state.viewingDay] ?? []
        return items.map { ($0, done.contains($0.id)) }
    }

    /// Phase progress: (day n, of m).
    private var spanDay: (Int, Int)? {
        guard let todo, case .span(let s, let e) = todo.schedule else { return nil }
        return (s.days(until: state.viewingDay) + 1, s.days(until: e) + 1)
    }

    private var canExpand: Bool { entry.isGroupRow || !planItems.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                marker
                if let p = entry.priority, !entry.isGroupRow {
                    PriorityChip(priority: p)
                }
                title
                if let detail = entry.detail {
                    Text("▶ \(detail)").foregroundStyle(color).lineLimit(1)
                }
                if let p = entry.progress, p.total > 0 {
                    Text("\(p.done)/\(p.total)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                tags
                if canExpand {
                    Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 7)
            .padding(.leading, 12 + indent)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: Theme.barWidth)
                    .padding(.vertical, 4)
                    .padding(.leading, indent)
            }
            .opacity(entry.isDone || entry.movedLater ? Theme.doneOpacity : 1)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.045 : 0)))
            .contentShape(Rectangle())
            .onTapGesture(perform: rowTapped)  // text = rename, blank = full edit
            .onHover { hovering = $0 }
            .contextMenu {
                if canDelete { Button("删除", role: .destructive) { delete() } }
            }
            .popover(isPresented: $editingTime) { editCard }

            if expanded {
                if entry.isGroupRow {
                    ForEach(entry.children) { AgendaRow(state: state, entry: $0, indent: indent + 20) }
                } else {
                    ForEach(planItems, id: \.0.id) { item, done in
                        HStack(spacing: 8) {
                            Button { tick(wasDone: done) { state.toggleItem(todoID: entry.id, itemID: item.id) } } label: {
                                Ring(color: color, filled: done, size: 12)
                            }
                            .buttonStyle(.plain)
                            Text(item.text).foregroundStyle(done ? .secondary : .primary)
                        }
                        .padding(.vertical, 4)
                        .padding(.leading, indent + 34)
                    }
                }
            }
            Divider().opacity(0.5)
        }
    }

    // MARK: Pieces

    @ViewBuilder private var marker: some View {
        if entry.kind == .span && !entry.isGroupRow {
            ProgressPie(fraction: spanDay.map { Double($0.0) / Double(max($0.1, 1)) } ?? 0, color: color)
        } else if entry.isCheckable {
            Button { tick(wasDone: entry.isDone) { state.toggle(entry) } } label: {
                Ring(color: color, filled: entry.isDone, size: 15).scaleEffect(pop ? 1.3 : 1)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 15, height: 15)
        }
    }

    @ViewBuilder private var title: some View {
        if editing {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .onSubmit(commitText)
                .onExitCommand { editing = false }
                .onChange(of: fieldFocused) { if !fieldFocused { commitText() } }
        } else {
            Text(entry.text)
                .lineLimit(1)
                .onTapGesture {
                    guard !entry.isGroupRow, !(todo?.isGroupAnchor ?? false) else { return }
                    draft = entry.text
                    editing = true
                    fieldFocused = true
                }
        }
    }

    @ViewBuilder private var tags: some View {
        HStack(spacing: 4) {
            if entry.overdueDays > 0 {
                timeTag("拖了 \(entry.overdueDays) 天", Theme.overdue)
            }
            if entry.pulledBy != nil {
                Image(systemName: "arrow.down.right.circle").font(.caption).foregroundStyle(.teal).help("按标签拉入")
            }
            if entry.movedLater {
                Tag(text: "已顺延", color: .gray)
            }
            if let d = entry.doneLater {
                Tag(text: "\(d.month)月\(d.day)日完成", color: .gray)
            }
            if let due = entry.deadline {
                timeTag(ddlLabel(due), Theme.color(for: .deadline))
            }
            if let (n, m) = spanDay {
                timeTag("第 \(n)/\(m) 天", color)
            }
            ForEach(todo?.tags ?? [], id: \.self) { Tag(text: "#\($0)", color: .teal) }
            if let g = entry.groupName, !entry.isGroupRow, !(todo?.isGroupAnchor ?? false) {
                Tag(text: g, color: .gray)
            }
            if entry.kind == .repeating && !entry.isGroupRow && !(todo?.isGroupAnchor ?? false) {
                Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary)
            }
            if hovering && todo != nil && !(todo?.isGroupAnchor ?? false) {
                Button { delete() } label: { Image(systemName: "trash").font(.caption) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("删除")
            }
        }
    }

    /// A click on the row's blank part: the full edit card, or opening a group row.
    private func rowTapped() {
        if entry.isGroupRow {
            if canExpand { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } }
        } else if todo != nil && !(todo?.isGroupAnchor ?? false) {
            editingTime = true
        }
    }

    /// Group rows and a group's own schedule row can't be deleted from here.
    private var canDelete: Bool { todo != nil && !(todo?.isGroupAnchor ?? false) }

    private func delete() {
        guard canDelete else { return }
        state.data.deleteTodo(entry.id)
    }

    private func timeTag(_ text: String, _ color: Color) -> some View {
        Tag(text: text, color: color)
    }

    @ViewBuilder private var editCard: some View {
        if let todo {
            EditCard(title: todo.text, today: state.today,
                     initial: TimeChoice(schedule: todo.schedule, priority: todo.priority, tags: todo.tags),
                     onSave: { state.setTime(todo.id, $0); editingTime = false },
                     onCancel: { editingTime = false }, knownTags: state.data.allTags)
        }
    }

    private func commitText() {
        guard editing else { return }
        editing = false
        state.editText(entry.id, draft)
    }

    /// Runs a check action with a short pop and a sound when checking.
    private func tick(wasDone: Bool, _ action: () -> Void) {
        if reduceMotion {
            action()
        } else {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { action(); pop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { withAnimation { pop = false } }
        }
        if !wasDone { NSSound(named: "Pop")?.play() }
    }
}


/// Fills as a phase's days pass.
struct ProgressPie: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.2))
            PieSlice(fraction: min(max(fraction, 0), 1)).fill(color)
        }
        .frame(width: 15, height: 15)
    }
}

struct PieSlice: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: c)
        p.addArc(center: c, radius: rect.width / 2, startAngle: .degrees(-90),
                 endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
        p.closeSubpath()
        return p
    }
}


