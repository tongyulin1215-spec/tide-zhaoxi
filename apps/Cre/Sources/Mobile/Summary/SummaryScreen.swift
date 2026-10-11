import CreCore
import SwiftUI

/// 总结 list: 每日总结, 模板, 感想, reports by type → detail pages. 「新建」 (总结 / 感想) top right.
struct SummaryScreen: View {
    @ObservedObject var state: MobileState
    @State private var path = NavigationPath()
    @State private var creatingSummary = false
    @State private var creatingReflection = false
    @State private var dayToDelete: DayKey?
    @State private var templateToDelete: SummaryTemplate?
    @State private var reportToDelete: SummaryReport?
    @State private var reflectionOpen: UUID?

    enum Route: Hashable { case day(DayKey), report(UUID) }

    /// Today and every day with a summary or a note; newest first.
    private var listedDays: [DayKey] {
        var days = Set(state.data.summaries.map(\.day))
        days.formUnion(state.data.notes.filter { !$0.value.isEmpty }.keys)
        days.insert(state.today)
        return days.sorted(by: >)
    }

    /// Reports listed by type: each template's history, then one-off reports by name.
    private var reportGroups: [(title: String, reports: [SummaryReport])] {
        let sorted = state.data.reports.sorted { $0.createdAt > $1.createdAt }
        var order: [String] = []
        var map: [String: [SummaryReport]] = [:]
        for r in sorted {
            let key = r.templateID.flatMap { id in state.data.templates.first { $0.id == id }?.name } ?? r.name
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(r)
        }
        return order.map { ($0, map[$0]!) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    PageTitleRow { Text("总结") } trailing: {
                        Menu {
                            Button("总结") { creatingSummary = true }.accessibilityIdentifier("new-summary")
                            Button("感想") { creatingReflection = true }.accessibilityIdentifier("new-reflection")
                        } label: { Image(systemName: "plus").frame(width: 40, height: 40) }
                        .accessibilityLabel("新建")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0))

                Section("每日总结") {
                    ForEach(listedDays, id: \.self) { d in
                        let s = state.data.summaries.first { $0.day == d }
                        NavigationLink(value: Route.day(d)) {
                            row(Fmt.title(d, today: state.today), s.map { "\($0.rate)%" } ?? "未生成")
                        }
                        .accessibilityIdentifier("day-\(d.string)")
                        .swipeActions { if s != nil { Button("删除", role: .destructive) { dayToDelete = d } } }
                    }
                }
                if !state.data.templates.isEmpty {
                    Section("模板") {
                        ForEach(state.data.templates) { t in
                            Button {
                                if let r = state.data.generate(templateID: t.id, today: state.today, now: Date()) { path.append(Route.report(r.id)) }
                            } label: { row(t.name, "生成") }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("template-\(t.name)")
                            .swipeActions { Button("删除", role: .destructive) { templateToDelete = t } }
                        }
                    }
                }
                if !state.data.reflections.isEmpty {
                    Section("感想") {
                        ForEach(state.data.reflections.sorted { $0.finishedOn > $1.finishedOn }) { r in
                            let title = state.data.reflectionTitle(r)
                            Button { reflectionOpen = r.id } label: { row(title, Fmt.date(r.finishedOn)) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("reflection-\(title)")
                                .swipeActions { Button("删除", role: .destructive) { state.data.deleteReflection(id: r.id) } }
                        }
                    }
                }
                ForEach(reportGroups, id: \.title) { g in
                    Section(g.title) {
                        ForEach(g.reports) { r in
                            NavigationLink(value: Route.report(r.id)) { row(Fmt.range(r.from, r.to), "\(r.rate)%") }
                                .swipeActions { Button("删除", role: .destructive) { reportToDelete = r } }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 0, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .day(let d): DailySummaryScreen(state: state, day: d)
                case .report(let id): ReportScreen(state: state, reportID: id)
                }
            }
            .sheet(isPresented: $creatingSummary) {
                NewSummaryScreen(state: state) { id in
                    creatingSummary = false
                    if let id { path.append(Route.report(id)) }
                }
            }
            .sheet(isPresented: $creatingReflection) { ReflectionScreen(state: state) { creatingReflection = false } }
            .sheet(item: Binding(get: { reflectionOpen.map(EditTarget.init) }, set: { reflectionOpen = $0?.id })) { t in
                ReflectionScreen(state: state, reflectionID: t.id) { reflectionOpen = nil }
            }
            .alert("删除 \(dayToDelete.map(Fmt.date) ?? "") 的总结？", isPresented: Binding(get: { dayToDelete != nil }, set: { if !$0 { dayToDelete = nil } })) {
                Button("删除", role: .destructive) { if let d = dayToDelete { state.data.deleteSummary(day: d) }; dayToDelete = nil }
                Button("取消", role: .cancel) { dayToDelete = nil }
            } message: { Text("随笔会保留。") }
            .alert("删除模板「\(templateToDelete?.name ?? "")」？", isPresented: Binding(get: { templateToDelete != nil }, set: { if !$0 { templateToDelete = nil } })) {
                Button("删除", role: .destructive) { if let t = templateToDelete { state.data.deleteTemplate(t.id) }; templateToDelete = nil }
                Button("取消", role: .cancel) { templateToDelete = nil }
            } message: { Text("已生成的报告会保留。") }
            .alert("删除这份报告？", isPresented: Binding(get: { reportToDelete != nil }, set: { if !$0 { reportToDelete = nil } })) {
                Button("删除", role: .destructive) { if let r = reportToDelete { state.data.deleteReport(r.id) }; reportToDelete = nil }
                Button("取消", role: .cancel) { reportToDelete = nil }
            }
        }
    }

    private func row(_ title: String, _ trailing: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary).lineLimit(1)
            Spacer()
            Text(trailing).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

/// One day: generated summary (完成 x/y · z%), its items, and the day's 随笔 (saved as you pause, and on leaving).
struct DailySummaryScreen: View {
    @ObservedObject var state: MobileState
    @State var day: DayKey
    @State private var draft = ""
    @State private var draftDay: DayKey?
    @State private var commitTask: Task<Void, Never>?
    @State private var picking = false

    private var report: DailySummary? { state.data.summaries.first { $0.day == day } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 6) {
                    Button { day = day.adding(days: -1) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("前一天")
                    Button { picking = true } label: { Text(Fmt.title(day, today: state.today)).font(.title2.bold()).foregroundStyle(.primary) }
                    Button { day = day.adding(days: 1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30) }
                        .foregroundStyle(day >= state.today ? Color.secondary.opacity(0.4) : .secondary)
                        .disabled(day >= state.today).accessibilityLabel("后一天")
                    Spacer()
                }
                .buttonStyle(.plain)
                .padding(.leading, -8)
                if let r = report {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("完成 \(r.done)/\(r.total) · \(r.rate)%").font(.headline).monospacedDigit()
                        ProgressView(value: Double(r.done), total: Double(max(r.total, 1))).tint(Theme.color(for: .repeating))
                    }
                    itemSection("已完成", r.doneItems, done: true)
                    itemSection("未完成", r.openItems, done: false)
                    HStack {
                        Text("生成于 \(r.createdAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        if day == state.today { Button("重新生成") { state.data.generateSummary(day: day, now: Date()) }.font(.subheadline) }
                    }
                } else {
                    Button { state.data.generateSummary(day: day, now: Date()) } label: { Label("生成总结", systemImage: "sparkles") }
                        .buttonStyle(.borderedProminent)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("随笔").font(.headline)
                    TextEditor(text: $draft)
                        .frame(minHeight: 160)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("随笔")
                        .onChange(of: draft) { scheduleCommit() }
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picking) {
            MonthCalendar(day: $day, latest: state.today, today: state.today) { picking = false }.phoneCalendarSheet()
        }
        .onAppear(perform: loadDraft)
        .onChange(of: day) { commitDraft(); loadDraft() }
        .onDisappear(perform: commitDraft)
    }

    private func loadDraft() {
        draftDay = day
        draft = state.data.notes[day] ?? ""
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { commitDraft() }
        }
    }

    private func commitDraft() {
        guard let d = draftDay else { return }
        let value: String? = draft.isEmpty ? nil : draft
        if state.data.notes[d] != value { state.data.notes[d] = value }
    }

    @ViewBuilder private func itemSection(_ title: String, _ items: [SummaryItem], done: Bool) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(title) \(items.count)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done ? Theme.color(for: .repeating) : .secondary)
                        Text(item.text)
                        Spacer()
                        if let g = item.group { Tag(text: g, color: .gray) }
                    }
                }
            }
        }
    }
}

/// One report, with 重新生成 for template reports.
struct ReportScreen: View {
    @ObservedObject var state: MobileState
    @State var reportID: UUID

    private var report: SummaryReport? { state.data.reports.first { $0.id == reportID } }

    var body: some View {
        ScrollView {
            if let report {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.name).font(.title2.bold())
                        Text(Fmt.range(report.from, report.to)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    ReportContent(report: report)
                    Text("生成于 \(report.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let t = report?.templateID, state.data.templates.contains(where: { $0.id == t }) {
                Button("重新生成") {
                    if let r = state.data.generate(templateID: t, today: state.today, now: Date()) { reportID = r.id }
                }
            }
        }
    }
}
