import CreCore
import SwiftUI

/// 新建总结：看什么 / 看多久（含日历自选）/ 统计什么 / 保存为模板.
struct NewSummaryScreen: View {
    @ObservedObject var state: MobileState
    /// The new report's id (nil when cancelled).
    let onClose: (UUID?) -> Void

    enum ScopeKind: String, CaseIterable { case all = "全部", group = "模块组", tag = "标签" }
    enum PeriodKind: String, CaseIterable { case today = "今天", week = "本周", month = "本月", custom = "自选" }

    @State private var name = ""
    @State private var scopeKind: ScopeKind = .all
    @State private var groupID: UUID?
    @State private var tag = ""
    @State private var periodKind: PeriodKind = .week
    @State private var from = DayKey.from(Date())
    @State private var to = DayKey.from(Date())
    @State private var metrics: Set<SummaryMetric> = Set(SummaryMetric.allCases)
    @State private var saveTemplate = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name, prompt: Text(defaultName))
                        .accessibilityIdentifier("名称")
                }
                Section("看什么") {
                    Picker("看什么", selection: $scopeKind) { ForEach(ScopeKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                    if scopeKind == .group {
                        Picker("模块组", selection: $groupID) {
                            ForEach(state.data.visibleGroups + state.data.archivedGroups) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    if scopeKind == .tag {
                        Picker("标签", selection: $tag) { ForEach(state.data.allTags, id: \.self) { Text("#\($0)").tag($0) } }
                    }
                }
                Section("看多久") {
                    Picker("看多久", selection: $periodKind) { ForEach(PeriodKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                    if periodKind == .custom {
                        RangeField(label: "范围", from: $from, to: $to, latest: state.today)
                    }
                }
                Section("统计什么") {
                    ForEach(SummaryMetric.allCases, id: \.self) { m in
                        Toggle(m.label, isOn: Binding(get: { metrics.contains(m) },
                                                      set: { if $0 { metrics.insert(m) } else { metrics.remove(m) } }))
                    }
                }
                Section { Toggle("保存为模板", isOn: $saveTemplate) }
            }
            .navigationTitle("新建总结").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { onClose(nil) } }
                ToolbarItem(placement: .confirmationAction) { Button("生成", action: create).fontWeight(.semibold).disabled(!valid) }
            }
            .onChange(of: periodKind) {
                if periodKind != .custom { (from, to) = period.range(today: state.today) }
            }
            .onAppear {
                groupID = state.data.visibleGroups.first?.id
                tag = state.data.allTags.first ?? ""
                (from, to) = SummaryPeriod.thisWeek.range(today: state.today)
            }
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
        case .custom: .custom(min(from, to), max(from, to))
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
        if saveTemplate {
            let t = state.data.addTemplate(name: title, scope: scope, period: period, metrics: ordered, now: Date())
            onClose(state.data.generate(templateID: t, today: state.today, now: Date())?.id)
        } else {
            let (a, b) = period.range(today: state.today)
            let r = makeReport(name: title, templateID: nil, scope: scope, from: a, to: b, metrics: ordered,
                               data: state.data, today: state.today, now: Date())
            state.data.reports.append(r)
            onClose(r.id)
        }
    }
}
