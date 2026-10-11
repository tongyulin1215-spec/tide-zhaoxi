import Charts
import CreCore
import SwiftUI

/// 新建总结：看什么 / 看多久 / 统计什么 / 保存为模板。
struct NewSummarySheet: View {
    @ObservedObject var state: AppState
    let onClose: () -> Void

    enum ScopeKind: String, CaseIterable, Identifiable { case all = "全部", group = "模块组", tag = "标签"; var id: String { rawValue } }
    enum PeriodKind: String, CaseIterable, Identifiable { case today = "今天", week = "本周", month = "本月", custom = "自选"; var id: String { rawValue } }

    @State private var name = ""
    @State private var scopeKind: ScopeKind = .all
    @State private var groupID: UUID?
    @State private var tag = ""
    @State private var periodKind: PeriodKind = .week
    @State private var from = Date()
    @State private var to = Date()
    @State private var metrics: Set<SummaryMetric> = Set(SummaryMetric.allCases)
    @State private var saveTemplate = false
    @State private var pickingRange = false

    enum Mode: Hashable { case summary, reflection }
    @State private var mode: Mode = .summary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SoftSegments(selection: $mode, options: [(.summary, "总结"), (.reflection, "感想")])
                .padding(.horizontal, 20).padding(.top, 16)
            switch mode {
            case .summary: summaryForm
            case .reflection:
                ReflectionEditor(state: state, onClose: onClose).padding(20).frame(width: 440)
            }
        }
    }

    private var summaryForm: some View {
        Form {
            TextField("名称", text: $name)
            Picker("看什么", selection: $scopeKind) { ForEach(ScopeKind.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
            if scopeKind == .group {
                Picker("模块组", selection: $groupID) {
                    ForEach(state.data.visibleGroups + state.data.archivedGroups) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if scopeKind == .tag {
                Picker("标签", selection: $tag) {
                    ForEach(state.data.allTags, id: \.self) { Text("#\($0)").tag($0) }
                }
            }
            HStack {
                Picker("看多久", selection: $periodKind) { ForEach(PeriodKind.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                Button {
                    // Start from what's selected now, so 本周 opens showing this week.
                    let (a, b) = period.range(today: state.today)
                    from = a.date(); to = b.date()
                    pickingRange = true
                } label: { Image(systemName: "calendar") }
                    .buttonStyle(.borderless).help("选日期范围")
                    .popover(isPresented: $pickingRange, arrowEdge: .trailing) {
                        MonthCalendar(from: dayBinding($from), to: dayBinding($to), range: true, latest: state.today, today: state.today) {
                            periodKind = .custom
                            pickingRange = false
                        }
                    }
            }
            if periodKind == .custom {
                LabeledContent("范围") {
                    Text(Fmt.range(DayKey.from(min(from, to)), DayKey.from(max(from, to))))
                        .buttonStyle(.link)
                }
            }
            Section("统计什么") {
                ForEach(SummaryMetric.allCases, id: \.self) { m in
                    Toggle(m.label, isOn: Binding(get: { metrics.contains(m) },
                                                  set: { if $0 { metrics.insert(m) } else { metrics.remove(m) } }))
                }
            }
            Toggle("保存为模板", isOn: $saveTemplate)
            HStack {
                Spacer()
                Button("取消", action: onClose).keyboardShortcut(.cancelAction)
                Button("生成", action: create).keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear {
            groupID = state.data.visibleGroups.first?.id
            tag = state.data.allTags.first ?? ""
            from = state.today.adding(days: -6).date()
            to = state.today.date()
        }
    }

    private var scope: SummaryScope? {
        switch scopeKind {
        case .all: return .all
        case .group: return groupID.map { .group($0) }
        case .tag: return tag.isEmpty ? nil : .tag(tag)
        }
    }

    private var period: SummaryPeriod {
        switch periodKind {
        case .today: .today
        case .week: .thisWeek
        case .month: .thisMonth
        case .custom: .custom(DayKey.from(from), DayKey.from(to))
        }
    }

    private var valid: Bool { scope != nil && !metrics.isEmpty }

    private var defaultName: String {
        let what: String
        switch scopeKind {
        case .all: what = ""
        case .group: what = state.data.group(groupID)?.name ?? ""
        case .tag: what = "#" + tag
        }
        return (what.isEmpty ? "" : what + " · ") + periodKind.rawValue + "总结"
    }

    private func create() {
        guard let scope else { return }
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? defaultName : name
        let ordered = SummaryMetric.allCases.filter(metrics.contains)
        let report: SummaryReport?
        if saveTemplate {
            let t = state.data.addTemplate(name: title, scope: scope, period: period, metrics: ordered, now: Date())
            report = state.data.generate(templateID: t, today: state.today, now: Date())
        } else {
            let (a, b) = period.range(today: state.today)
            let r = makeReport(name: title, templateID: nil, scope: scope, from: a, to: b, metrics: ordered,
                               data: state.data, today: state.today, now: Date())
            state.data.reports.append(r)
            report = r
        }
        state.summaryReportID = report?.id
        onClose()
    }
}

/// 一份自选总结报告。
struct ReportView: View {
    @ObservedObject var state: AppState
    let report: SummaryReport
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.name).font(.title3.weight(.semibold))
                        Text(Fmt.range(report.from, report.to)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let t = report.templateID, state.data.templates.contains(where: { $0.id == t }) {
                        Button("重新生成") {
                            if let r = state.data.generate(templateID: t, today: state.today, now: Date()) { state.summaryReportID = r.id }
                        }
                        .controlSize(.small)
                    }
                    Button("删除", role: .destructive) { confirmDelete = true }.controlSize(.small)
                }

                ReportContent(report: report)
                Text("生成于 \(report.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(24)
        }
        .alert("删除「\(report.name)」？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { state.data.deleteReport(report.id); state.summaryReportID = nil }
            Button("取消", role: .cancel) {}
        }
    }
}
