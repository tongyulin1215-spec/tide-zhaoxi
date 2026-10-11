import CreCore
import SwiftUI

/// 首页：日期、总结 / 整理拖延、未完成 · DDL 折叠 · 已完成，底部输入条。
struct HomeScreen: View {
    @ObservedObject var state: MobileState
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var sync: SyncCoordinator
    @State private var draft = ""
    @State private var editing: UUID?
    @State private var newWithTime = false
    @State private var picking = false
    @State private var showTriage = false
    @State private var showSummary = false
    @State private var showSettings = false
    @State private var openCollapsed = false
    @State private var doneCollapsed = false
    @State private var foldOpen = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        let agenda = state.agendaForViewingDay()
        let open = agenda.entries.filter { !$0.isDone }
        let done = agenda.entries.filter(\.isDone)
        NavigationStack {
            List {
                Section { header(agenda).daySwipe(state) }
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 12))
                if let hint = syncHint(isPaired: sync.isPaired, failed: sync.lastTryFailed, lastSync: sync.lastSync, now: Date()) {
                    Section {
                        Button { showSettings = true } label: {
                            Label(hint, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 16))
                }
                if state.isViewingToday && state.triageCount > 0 {
                    Section { triageBanner }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                if agenda.entries.isEmpty && agenda.foldedDeadlines.isEmpty {
                    // Blank page to swipe on; the 「今天还空着」 label itself sits centred on the screen (overlay below).
                    Section { Color.clear.frame(height: 560).daySwipe(state) }
                        .listRowInsets(EdgeInsets())
                }
                if !open.isEmpty || !agenda.foldedDeadlines.isEmpty {
                    Section(isExpanded: Binding(get: { !openCollapsed }, set: { openCollapsed = !$0 })) {
                        ForEach(open) { HomeRow(state: state, entry: $0, editing: $editing).id("open-\($0.id)") }
                        if !agenda.foldedDeadlines.isEmpty {
                            DisclosureGroup(isExpanded: $foldOpen) {
                                ForEach(agenda.foldedDeadlines) { HomeRow(state: state, entry: $0, editing: $editing).id("fold-\($0.id)") }
                            } label: {
                                Text("DDL 待办（\(agenda.foldedDeadlines.count)）").foregroundStyle(Theme.color(for: .deadline))
                            }
                            .listRowSeparator(.hidden)
                        }
                    } header: { Text("未完成 \(open.count + agenda.foldedDeadlines.count)").daySwipe(state) }
                }
                if !done.isEmpty {
                    Section(isExpanded: Binding(get: { !doneCollapsed }, set: { doneCollapsed = !$0 })) {
                        ForEach(done) { HomeRow(state: state, entry: $0, editing: $editing).id("done-\($0.id)") }
                    } header: { Text("已完成 \(done.count)").daySwipe(state) }
                }
                if !agenda.entries.isEmpty && state.isViewingToday {
                    Section {
                        Button { state.summarizeToday(); showSummary = true } label: {
                            Label("总结今天", systemImage: "sparkles")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .foregroundStyle(Color.accentColor)
                                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("summarize-today")
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 8, trailing: 16))
                }
                if !agenda.entries.isEmpty || !agenda.foldedDeadlines.isEmpty {
                    // Blank space under the list, for swiping to another day.
                    Section { Color.clear.frame(height: 260).daySwipe(state) }
                        .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemBackground))
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if agenda.entries.isEmpty && agenda.foldedDeadlines.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "sun.horizon").font(.system(size: 34, weight: .light)).foregroundStyle(.quaternary)
                        Text(state.isViewingToday ? "今天还空着" : "这天还空着").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .toolbar(.hidden, for: .navigationBar)
            .contentMargins(.top, 0, for: .scrollContent)
            .listSectionSpacing(.compact)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: Binding(get: { editing.map(EditTarget.init) }, set: { editing = $0?.id })) { t in
                if let todo = state.todo(t.id) { EditSheet(state: state, todo: todo) { editing = nil } }
            }
            .sheet(isPresented: $newWithTime) {
                NavigationStack {
                    EditCard(title: nil, today: state.today,
                             initial: TimeChoice(schedule: .day(state.viewingDay), priority: nil),
                             onSave: { choice in
                                 if state.add(draft, override: choice) { draft = "" }
                                 newWithTime = false
                             },
                             onCancel: { newWithTime = false }, knownTags: state.data.allTags)
                    .navigationTitle(draft.isEmpty ? "新待办" : draft).navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $picking) {
                MonthCalendar(day: $state.viewingDay, today: state.today) { picking = false }
                    .phoneCalendarSheet()
            }
            .sheet(isPresented: $showTriage) { MobileTriageSheet(state: state) { showTriage = false } }
            .navigationDestination(isPresented: $showSummary) { DailySummaryScreen(state: state, day: state.today) }
            .onChange(of: router.openTodo) {
                // A tap on an item in the widget: today, with that item open.
                if let id = router.openTodo {
                    state.viewingDay = state.today
                    if state.todo(id) != nil { editing = id }
                    router.openTodo = nil
                }
            }
            .onChange(of: router.today) {
                if router.today { state.viewingDay = state.today; router.today = false }
            }
            .onChange(of: router.todaySummary) {
                // The nightly reminder: generate today's summary and show it.
                if router.todaySummary { state.summarizeToday(); showSummary = true; router.todaySummary = false }
            }
            .sheet(isPresented: $showSettings) { MobileSettingsSheet(state: state) { showSettings = false } }
        }
    }

    /// 大标题「今天」, below it ‹ 日期 › and the done count; a completion ring on the right.
    private func header(_ agenda: Agenda) -> some View {
        let title = DayTitle(state.viewingDay, today: state.today)
        let p = agenda.progress
        return VStack(alignment: .leading, spacing: 2) {
            PageTitleRow {
                HStack(alignment: .center, spacing: 8) {
                        Text(title.big)
                        if let tag = title.tag {
                            Text(tag).font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .foregroundStyle(title.isToday ? Color.white : Color.secondary)
                                .background(title.isToday ? Color.accentColor : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                        }
                }
                .fixedSize().layoutPriority(1)
                // A tap, not a Button: a swipe across the title must change the day, not open the calendar.
                .onTapGesture { picking = true }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("pick-day")
            } trailing: {
                HomeMenu(state: state).frame(width: 40, height: 40)
                Button { showSettings = true } label: { Image(systemName: "gearshape").frame(width: 40, height: 40) }
                    .accessibilityLabel("设置")
            }
            HStack(spacing: 2) {
                Button { state.viewingDay = state.viewingDay.adding(days: -1) } label: { stepIcon("chevron.left") }
                    .accessibilityLabel("前一天").accessibilityIdentifier("prev-day")
                Text(title.small).onTapGesture { picking = true }
                Button { state.viewingDay = state.viewingDay.adding(days: 1) } label: { stepIcon("chevron.right") }
                    .accessibilityLabel("后一天").accessibilityIdentifier("next-day")
                if p.total > 0 {
                    Text("· \(p.done)/\(p.total)").monospacedDigit().padding(.leading, 4)
                }
                Spacer()
                if !state.isViewingToday {
                    Button("回今天") { state.viewingDay = state.today }
                        .font(.subheadline.weight(.medium)).foregroundStyle(Color.accentColor).padding(.trailing, 10)
                }
                if p.total > 0 { ProgressRing(done: p.done, total: p.total).padding(.trailing, 8) }
            }
            .font(.subheadline).foregroundStyle(.secondary)
            .padding(.leading, -6)
        }
        .buttonStyle(.plain)
    }

    private func stepIcon(_ name: String) -> some View {
        Image(systemName: name).font(.footnote.weight(.semibold)).frame(width: 26, height: 26).contentShape(Rectangle())
    }

    private var triageBanner: some View {
        Button { showTriage = true } label: {
            HStack {
                Text("\(state.triageCount) 项拖延")
                Spacer()
                Text("整理").fontWeight(.medium)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
            }
            .font(.subheadline).foregroundStyle(Theme.overdue)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.overdue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var inputBar: some View {
        BottomInputBar(placeholder: "记录想法或安排", text: $draft, focus: $inputFocused, onSubmit: { if state.add(draft) { draft = "" } }) {
            Button { newWithTime = true } label: { Image(systemName: "calendar") }
                .foregroundStyle(.secondary)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("选时间")
        }
    }
}

struct EditTarget: Identifiable { let id: UUID }

/// 「…」：筛选、按标签拉入、排序.
struct HomeMenu: View {
    @ObservedObject var state: MobileState

    var body: some View {
        let pulled = state.data.pulledTags[state.viewingDay] ?? []
        Menu {
            Picker("排序", selection: $state.sortMode) {
                Text("按优先级").tag(SortMode.priority)
                Text("按类别").tag(SortMode.category)
                Text("按标签").tag(SortMode.tag)
            }
            Menu("筛选") {
                Picker("筛选", selection: $state.filter) {
                    Text("全部").tag(AgendaFilter.all)
                    ForEach(state.data.allTags, id: \.self) { Text("#\($0)").tag(AgendaFilter.tag($0)) }
                    ForEach(state.data.visibleGroups) { Text($0.name).tag(AgendaFilter.group($0.id)) }
                }
            }
            Menu("按标签拉入") {
                if state.data.allTags.isEmpty { Text("暂无标签，输入时用 #标签") }
                ForEach(state.data.allTags, id: \.self) { tag in
                    Toggle("#\(tag)", isOn: Binding(get: { pulled.contains(tag) }, set: { _ in state.togglePulledTag(tag) }))
                }
            }
        } label: {
            Image(systemName: state.filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }
}

/// Full edit: name, time, tags, priority — from a tap on a row. A group's own repeat only renames (with its group).
struct EditSheet: View {
    @ObservedObject var state: MobileState
    let todo: Todo
    let onClose: () -> Void
    @State private var name = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("名称", text: $name).font(.body)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16).padding(.top, 12)
                    if !todo.isGroupAnchor {
                        EditCard(title: nil, today: state.today,
                                 initial: TimeChoice(schedule: todo.schedule, priority: todo.priority, tags: todo.tags),
                                 onSave: { choice in
                                     state.data.rename(todo.id, name)
                                     state.data.setTime(todo.id, choice)
                                     onClose()
                                 },
                                 onCancel: onClose, knownTags: state.data.allTags)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("编辑").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if todo.isGroupAnchor {
                    ToolbarItem(placement: .cancellationAction) { Button("取消", action: onClose) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { renameGroup(); onClose() }.fontWeight(.semibold)
                    }
                } else {
                    ToolbarItem(placement: .bottomBar) {
                        Button("删除", role: .destructive) { state.data.deleteTodo(todo.id); onClose() }
                    }
                }
            }
        }
        .presentationDetents(todo.isGroupAnchor ? [.height(200)] : [.medium, .large])
        .onAppear { name = todo.isGroupAnchor ? (state.data.group(todo.groupID)?.name ?? todo.text) : todo.text }
    }

    /// Same as renaming the card in 规划: group and its repeat share the name.
    private func renameGroup() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let g = state.data.group(todo.groupID) else { return }
        state.data.updateGroup(g.id) { $0.name = n }
        let text: String
        if case .list(let st) = g.kind { text = "\(n) \(st)" } else { text = n }
        state.data.update(todo.id) { $0.text = text }
    }
}

/// 整理拖延：今天做 / 改个日期.
struct MobileTriageSheet: View {
    @ObservedObject var state: MobileState
    let onClose: () -> Void
    @State private var picking: UUID?

    var body: some View {
        NavigationStack {
            List {
                ForEach(triageCandidates(today: state.today, data: state.data)) { todo in
                    HStack {
                        Text(todo.text).lineLimit(1)
                        Spacer()
                        Button("今天做") { state.data.doToday(todo.id, today: state.today) }.buttonStyle(.bordered)
                        Button("改日期") { picking = todo.id }.buttonStyle(.bordered)
                    }
                }
            }
            .navigationTitle("整理拖延").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: onClose) } }
            .sheet(item: Binding(get: { picking.map(EditTarget.init) }, set: { picking = $0?.id })) { t in
                MonthCalendar(day: Binding(get: { state.today.adding(days: 1) }, set: { state.data.reschedule(t.id, to: $0) }),
                              earliest: state.today, today: state.today) { picking = nil }
                    .phoneCalendarSheet()
            }
        }
    }
}

/// Home title: the date big, with 「今天」 (filled) or 「明天」「昨天」 (grey) as a tag beside it.
struct DayTitle {
    let big: String
    let small: String
    let tag: String?
    let isToday: Bool

    init(_ day: DayKey, today: DayKey) {
        big = Fmt.date(day)
        small = Fmt.weekdayName(day.weekday)
        let offset = today.days(until: day)
        isToday = offset == 0
        tag = [0: "今天", 1: "明天", -1: "昨天"][offset]
    }
}

extension View {
    /// Swipe left for the next day, right for the previous one. Only on blank parts of the page:
    /// a swipe on a row stays the row's delete.
    func daySwipe(_ state: MobileState) -> some View {
        contentShape(Rectangle()).simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { g in
                let dx = g.translation.width, dy = g.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 2 else { return }
                withAnimation(.easeOut(duration: 0.2)) { state.viewingDay = state.viewingDay.adding(days: dx < 0 ? 1 : -1) }
            }
        )
    }
}

/// Today's completion as a ring with the percentage inside.
struct ProgressRing: View {
    let done: Int
    let total: Int

    var body: some View {
        let f = Double(done) / Double(max(total, 1))
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 3.5)
            Circle().trim(from: 0, to: f).stroke(Theme.color(for: .repeating), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((f * 100).rounded()))").font(.system(size: 10, weight: .semibold)).monospacedDigit()
        }
        .frame(width: 34, height: 34)
        .animation(.easeOut(duration: 0.25), value: done)
    }
}
