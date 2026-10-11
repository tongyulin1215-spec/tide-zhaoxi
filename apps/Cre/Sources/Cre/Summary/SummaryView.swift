import CreCore
import SwiftUI

/// 总结：左侧历史，右侧报告与随笔。
struct SummaryView: View {
    @ObservedObject var state: AppState
    /// The note being typed; written to the data after a short pause, on day switch and on leaving.
    @State private var draft = ""
    @State private var draftDay: DayKey?
    @State private var commitTask: Task<Void, Never>?
    @State private var confirmDelete = false
    @State private var creating = false
    @State private var templateToDelete: SummaryTemplate?
    @State private var reportToDelete: SummaryReport?
    /// The item whose 感想 is open on the right.
    @State private var reflectionSel: UUID?

    private var report: DailySummary? { state.data.summaries.first { $0.day == state.summaryDay } }

    var body: some View {
        HStack(spacing: 0) {
            history
                .frame(width: 210)
            Divider()
            Group {
                if let id = reflectionSel, state.data.reflections.contains(where: { $0.id == id }) {
                    ScrollView {
                        ReflectionEditor(state: state, reflectionID: id) { reflectionSel = nil }
                            .id(id)
                            .padding(24)
                    }
                } else if let id = state.summaryReportID, let r = state.data.reports.first(where: { $0.id == id }) {
                    ReportView(state: state, report: r)
                } else {
                    detail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $creating) { NewSummarySheet(state: state) { creating = false } }
        .alert("删除这份报告？", isPresented: Binding(get: { reportToDelete != nil }, set: { if !$0 { reportToDelete = nil } })) {
            Button("删除", role: .destructive) {
                if let r = reportToDelete {
                    state.data.deleteReport(r.id)
                    if state.summaryReportID == r.id { state.summaryReportID = nil }
                }
                reportToDelete = nil
            }
            Button("取消", role: .cancel) { reportToDelete = nil }
        }
        .alert("删除模板「\(templateToDelete?.name ?? "")」？", isPresented: Binding(get: { templateToDelete != nil }, set: { if !$0 { templateToDelete = nil } })) {
            Button("删除", role: .destructive) { if let t = templateToDelete { state.data.deleteTemplate(t.id) }; templateToDelete = nil }
            Button("取消", role: .cancel) { templateToDelete = nil }
        } message: {
            Text("已生成的报告会保留。")
        }
        .alert("删除 \(Fmt.date(state.summaryDay)) 的总结？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { state.data.deleteSummary(day: state.summaryDay) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("随笔会保留。")
        }
        .onAppear(perform: loadDraft)
        .onChange(of: state.summaryDay) { commitDraft(); loadDraft() }
        .onDisappear(perform: commitDraft)
    }

    private func loadDraft() {
        draftDay = state.summaryDay
        draft = state.data.notes[state.summaryDay] ?? ""
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { commitDraft() }
        }
    }

    private func commitDraft() {
        guard let day = draftDay else { return }
        let value: String? = draft.isEmpty ? nil : draft
        if state.data.notes[day] != value { state.data.notes[day] = value }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { state.summarizeToday() } label: { Label("总结一下今天", systemImage: "note.text") }
                Button { creating = true } label: { Label("新建", systemImage: "plus") }
            }
            .buttonStyle(.bordered).controlSize(.small)
            .padding(.horizontal, 12).padding(.top, 18)
            ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                        SectionTitle(text: "每日总结")
                    ForEach(listedDays, id: \.self) { d in
                        let s = state.data.summaries.first { $0.day == d }
                        dayRow(d, rate: s?.rate)
                            .contextMenu {
                                if s != nil { Button("删除", role: .destructive) { selectDay(d); confirmDelete = true } }
                            }
                    }
                }
                if !state.data.templates.isEmpty {
                    Group {
                        SectionTitle(text: "模板")
                        ForEach(state.data.templates) { t in
                            Button {
                                if let r = state.data.generate(templateID: t.id, today: state.today, now: Date()) { reflectionSel = nil; state.summaryReportID = r.id }
                            } label: {
                                HStack { Image(systemName: "doc.on.doc"); Text(t.name).lineLimit(1); Spacer(); Text("生成").font(.caption).foregroundStyle(.secondary) }
                            }
                            .buttonStyle(.plain)
                            .contextMenu { Button("删除模板", role: .destructive) { templateToDelete = t } }
                        }
                    }
                }
                if !state.data.reflections.isEmpty {
                    Group {
                        SectionTitle(text: "感想")
                        ForEach(state.data.reflections.sorted { $0.finishedOn > $1.finishedOn }) { r in
                            Button { reflectionSel = r.id } label: {
                                HStack {
                                    Text(state.data.reflectionTitle(r)).lineLimit(1)
                                    Spacer()
                                    Text(Fmt.date(r.finishedOn)).font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                                .background(reflectionSel == r.id ? Color.accentColor.opacity(0.15) : .clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ForEach(reportGroups, id: \.title) { group in
                    Group {
                        SectionTitle(text: group.title)
                        ForEach(group.reports) { r in
                            Button { reflectionSel = nil; state.summaryReportID = r.id } label: {
                                HistoryRow(title: Fmt.range(r.from, r.to), rate: r.rate)
                                    .padding(.vertical, 2)
                                    .background(reflectionSel == nil && state.summaryReportID == r.id ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .contextMenu { Button("删除", role: .destructive) { reportToDelete = r } }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))  // white like the detail; the divider does the separating
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

    /// Today, the selected day, and every day with a summary or a note; newest first.
    private var listedDays: [DayKey] {
        var days = Set(state.data.summaries.map(\.day))
        days.formUnion(state.data.notes.filter { !$0.value.isEmpty }.keys)
        days.insert(state.today)
        days.insert(state.summaryDay)
        return days.sorted(by: >)
    }

    private func selectDay(_ d: DayKey) {
        reflectionSel = nil
        state.summaryReportID = nil
        state.summaryDay = d
    }

    private func dayRow(_ d: DayKey, rate: Int?) -> some View {
        Button { selectDay(d) } label: {
            HistoryRow(title: Fmt.title(d, today: state.today), rate: rate)
                .padding(.vertical, 2)
                .background(reflectionSel == nil && state.summaryReportID == nil && state.summaryDay == d ? Color.accentColor.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.title(state.summaryDay, today: state.today)).font(.title3.weight(.semibold))
                    DayStepper(day: Binding(get: { state.summaryDay }, set: { selectDay($0) }), latest: state.today)
                    Spacer()
                    if report != nil && state.summaryDay == state.today {
                        Button("重新生成") { state.data.generateSummary(day: state.summaryDay, now: Date()) }.controlSize(.small)
                    }
                    if report != nil {
                        Button("删除", role: .destructive) { confirmDelete = true }.controlSize(.small)
                    }
                }

                if let r = report {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("完成 \(r.done)/\(r.total) · \(r.rate)%").font(.headline).monospacedDigit()
                        ProgressView(value: Double(r.done), total: Double(max(r.total, 1)))
                            .tint(Theme.color(for: .repeating))
                    }
                    itemSection("已完成", r.doneItems, done: true)
                    itemSection("未完成", r.openItems, done: false)
                    Text("生成于 \(r.createdAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    Button { state.data.generateSummary(day: state.summaryDay, now: Date()) } label: {
                        Label("生成总结", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("随笔").font(.headline)
                    TextEditor(text: $draft)
                        .onChange(of: draft) { scheduleCommit() }
                    .font(.body)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder private func itemSection(_ title: String, _ items: [SummaryItem], done: Bool) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
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

/// ‹ 📅 › for picking any day up to `latest`.
struct DayStepper: View {
    @Binding var day: DayKey
    let latest: DayKey
    @State private var open = false

    var body: some View {
        HStack(spacing: 0) {
            Button { day = day.adding(days: -1) } label: { ToolbarIcon(name: "chevron.left") }
                .buttonStyle(.borderless).help("前一天")
            Button { open = true } label: { ToolbarIcon(name: "calendar") }
                .buttonStyle(.borderless).help("选日期")
                .popover(isPresented: $open) {
                    MonthCalendar(day: $day, latest: latest, today: latest) { open = false }
                }
            Button { day = day.adding(days: 1) } label: { ToolbarIcon(name: "chevron.right") }
                .buttonStyle(.borderless).help("后一天").disabled(day >= latest)
        }
    }
}

/// Group title in the summary list (plain text; no system rule under it).
struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.top, 12).padding(.bottom, 2).padding(.leading, 4)
    }
}

struct HistoryRow: View {
    let title: String
    let rate: Int?

    var body: some View {
        HStack {
            Text(title).lineLimit(1)
            Spacer()
            Text(rate.map { "\($0)%" } ?? "未生成").font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
