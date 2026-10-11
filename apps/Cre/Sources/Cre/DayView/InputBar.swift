import CreCore
import SwiftUI

/// Top input: one line; a faint hint shows what was recognized; the date button picks time by hand.
struct InputBar: View {
    @ObservedObject var state: AppState
    var groupID: UUID? = nil
    /// Undated lines become todos for the viewed day (day view) or stay undated (planning).
    var defaultToViewingDay = true
    var placeholder = "记录想法或安排"
    var focus: FocusState<Bool>.Binding

    @State private var text = ""
    @State private var picked: TimeChoice?
    @State private var picking = false

    private var hint: String? {
        let parsed = parseInput(text, today: state.today)
        let schedule = picked?.schedule ?? parsed.schedule
        let priority = picked?.priority ?? parsed.priority
        let parts = [priority?.label, Fmt.schedule(schedule)].compactMap { $0 }
        return parts.isEmpty || text.isEmpty ? nil : "→ " + parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused(focus)
                .onSubmit(submit)
            if let hint {
                Text(hint).foregroundStyle(.tertiary).lineLimit(1)
            }
            Button { picking = true } label: { Image(systemName: "calendar.badge.plus") }
                .buttonStyle(.borderless)
                .foregroundStyle(picked == nil ? Color.secondary : Color.accentColor)
                .help("选择日期")
                .popover(isPresented: $picking) {
                    EditCard(title: nil, today: state.today,
                             initial: picked ?? TimeChoice(schedule: .day(state.viewingDay), priority: nil),
                             onSave: { picked = $0; picking = false; focus.wrappedValue = true },
                             onCancel: { picking = false }, knownTags: state.data.allTags)
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
    }

    private func submit() {
        if state.add(text, override: picked, groupID: groupID, defaultToViewingDay: defaultToViewingDay) {
            text = ""
            picked = nil
        }
        focus.wrappedValue = true
    }
}

/// Previous / next day around the calendar jump, plus "回到今天".
struct CalendarButton: View {
    @ObservedObject var state: AppState
    @State private var open = false

    var body: some View {
        HStack(spacing: 6) {
            if !state.isViewingToday {
                Button("回到今天") { state.viewingDay = state.today }
                    .controlSize(.small)
            }
            Button { state.viewingDay = state.viewingDay.adding(days: -1) } label: { ToolbarIcon(name: "chevron.left") }
                .buttonStyle(.borderless)
                .help("前一天")
            Button { open = true } label: { ToolbarIcon(name: "calendar") }
                .buttonStyle(.borderless)
                .help("跳到某天")
                .popover(isPresented: $open) {
                    MonthCalendar(day: $state.viewingDay, today: state.today) { open = false }
                }
            Button { state.viewingDay = state.viewingDay.adding(days: 1) } label: { ToolbarIcon(name: "chevron.right") }
                .buttonStyle(.borderless)
                .help("后一天")
        }
    }
}


/// 按优先级 / 按类别 / 按标签.
struct SortMenu: View {
    @ObservedObject var state: AppState

    private static let options: [(SortMode, String)] = [(.priority, "按优先级"), (.category, "按类别"), (.tag, "按标签")]
    private var current: String { Self.options.first { $0.0 == state.sortMode }?.1 ?? "按优先级" }

    var body: some View {
        Menu {
            ForEach(Self.options, id: \.0) { mode, title in
                Button { state.sortMode = mode } label: {
                    if state.sortMode == mode { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            ToolbarIcon(name: "arrow.up.arrow.down")
        }
        .help("排序：\(current)")
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// 筛选：只看某个标签或某个模块组。
struct FilterMenu: View {
    @ObservedObject var state: AppState

    var body: some View {
        Menu {
            item("全部", .all)
            if !state.data.allTags.isEmpty {
                Section("标签") { ForEach(state.data.allTags, id: \.self) { item("#\($0)", .tag($0)) } }
            }
            if !state.data.visibleGroups.isEmpty {
                Section("模块组") { ForEach(state.data.visibleGroups) { item($0.name, .group($0.id)) } }
            }
        } label: {
            ToolbarIcon(name: state.filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("筛选")
    }

    private func item(_ title: String, _ f: AgendaFilter) -> some View {
        Button { state.filter = f } label: {
            if state.filter == f { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }
}
