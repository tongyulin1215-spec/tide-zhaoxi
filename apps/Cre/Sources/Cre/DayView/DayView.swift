import AppKit
import CreCore
import SwiftUI

/// One day's todos. Home page (`compact: false`) and widget (`compact: true`).
struct DayView: View {
    @ObservedObject var state: AppState
    let compact: Bool
    var trailingHeader: AnyView? = nil

    @FocusState private var inputFocused: Bool
    @State private var showFolded = false
    @AppStorage("openCollapsed") private var openCollapsed = false
    @AppStorage("doneCollapsed") private var doneCollapsed = false

    var body: some View {
        let agenda = state.agendaForViewingDay()
        let open = agenda.entries.filter { !$0.isDone }
        let done = agenda.entries.filter(\.isDone)

        VStack(alignment: .leading, spacing: 10) {
            InputBar(state: state, focus: $inputFocused)

            if state.triageOffered {
                TriageBanner(state: state) {
                    if compact { state.openMainWindow?(); NSApp.activate(ignoringOtherApps: true) }
                    state.showTriage = true
                }
            }

            HStack(spacing: 10) {
                Text(Fmt.title(state.viewingDay, today: state.today))
                    .font(compact ? .headline : .title3.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                if state.isViewingToday && agenda.progress.total > 0 {
                    Text(compact ? "\(agenda.progress.done)/\(agenda.progress.total)" : "今天 \(agenda.progress.done)/\(agenda.progress.total)")
                        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let label = state.filterLabel {
                    Button { state.filter = .all } label: {
                        HStack(spacing: 3) { Text(label); Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                            .font(.caption).padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain).help("清除筛选")
                }
                FilterMenu(state: state)
                TagPullMenu(state: state)
                SortMenu(state: state)
                Divider().frame(height: 14).padding(.horizontal, 2)
                CalendarButton(state: state)
                if let trailingHeader { trailingHeader }
            }

            if !compact { QuickActions(state: state) }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if agenda.entries.isEmpty && agenda.foldedDeadlines.isEmpty {
                        EmptyDay(isToday: state.isViewingToday)
                    }
                    if !open.isEmpty || !agenda.foldedDeadlines.isEmpty {
                        SectionHeader(title: "未完成", count: open.count + agenda.foldedDeadlines.count, collapsed: $openCollapsed)
                        if !openCollapsed {
                            ForEach(open) { AgendaRow(state: state, entry: $0).id("open-\($0.id)") }
                            if !agenda.foldedDeadlines.isEmpty { folded(agenda.foldedDeadlines) }
                        }
                    }
                    if !done.isEmpty {
                        SectionHeader(title: "已完成", count: done.count, collapsed: $doneCollapsed)
                        if !doneCollapsed {
                            ForEach(done) { AgendaRow(state: state, entry: $0).id("done-\($0.id)") }
                        }
                    }
                }
            }
        }
        .padding(compact ? 12 : 22)
        .celebration(state.celebrateToken)
    }

    @ViewBuilder private func folded(_ entries: [AgendaEntry]) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { showFolded.toggle() } } label: {
            HStack(spacing: 6) {
                Image(systemName: showFolded ? "chevron.down" : "chevron.right").font(.caption)
                Text("DDL 待办（\(entries.count)）")
                Spacer()
            }
            .foregroundStyle(Theme.color(for: .deadline))
            .padding(.vertical, 7)
            .padding(.leading, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if showFolded {
            ForEach(entries) { AgendaRow(state: state, entry: $0, indent: 14).id("fold-\($0.id)") }
        }
    }
}

/// Nothing on the viewed day.
struct EmptyDay: View {
    let isToday: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 50, height: 50)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
            Text(isToday ? "今天还空着" : "这天还空着").foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("随时按")
                Key("⌥")
                Key("Space")
                Text("记一条")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct Key: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.caption.monospaced())
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.12)))
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int
    @Binding var collapsed: Bool

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { collapsed.toggle() } } label: {
            HStack(spacing: 6) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.system(size: 10, weight: .semibold))
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary.opacity(0.75))
                Text("\(count)").font(.subheadline).foregroundStyle(.tertiary)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.top, 18)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Home-only shortcuts.
struct QuickActions: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Button { state.summarizeToday() } label: { Label("总结一下今天", systemImage: "note.text") }
            if state.triageCount > 0 {
                Button { state.showTriage = true } label: {
                    Label("整理拖延（\(state.triageCount)）", systemImage: "tray.full")
                }
                .tint(Theme.overdue)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct HomeView: View {
    @ObservedObject var state: AppState
    var body: some View { DayView(state: state, compact: false) }
}

/// 按标签检索：把带某个标签的事项拉进当天。
struct TagPullMenu: View {
    @ObservedObject var state: AppState

    var body: some View {
        let pulled = state.data.pulledTags[state.viewingDay] ?? []
        Menu {
            if state.data.allTags.isEmpty { Text("暂无标签，输入时用 #标签") }
            ForEach(state.data.allTags, id: \.self) { tag in
                Toggle("#\(tag)", isOn: Binding(get: { pulled.contains(tag) }, set: { _ in state.togglePulledTag(tag) }))
            }
        } label: {
            ToolbarIcon(name: pulled.isEmpty ? "number" : "number.circle.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("按标签拉入")
    }
}
