import Foundation
import CreCore
import SwiftUI

/// The small card for choosing a todo's time kind, dates and priority.
/// Used by the input's date button and by tapping a row's time or priority tag.
struct EditCard: View {
    enum Kind: String, CaseIterable, Identifiable {
        case none = "不设", day = "某天", deadline = "截止", span = "阶段", repeating = "重复"
        var id: String { rawValue }
    }

    let title: String?
    let today: DayKey
    let initial: TimeChoice
    let onSave: (TimeChoice) -> Void
    let onCancel: () -> Void
    /// Tags already in use, offered in a menu so names needn't be remembered.
    var knownTags: [String] = []

    @State private var kind: Kind = .day
    @State private var day = Date()
    @State private var end = Date()
    @State private var weekdays: Set<Int> = []
    @State private var priority: Priority?
    @State private var tagText = ""
    #if os(iOS)
    @State private var addingTag = false
    @State private var newTag = ""
    #endif

    private let order = [2, 3, 4, 5, 6, 7, 1]

    #if os(iOS)
    /// Phone: 取消 / 保存 in the bar, tags as chips, labelled groups, content from the top.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            kindPicker
            if kind != .none {
                VStack(spacing: 10) { timeFields }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            groupLabel("标签")
            FlowLayout(spacing: 6) {
                ForEach(Array(NSOrderedSet(array: knownTags + currentTags)) as? [String] ?? [], id: \.self) { t in
                    let on = currentTags.contains(t)
                    Button { toggleTag(t) } label: {
                        Text("#\(t)").font(.subheadline)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(on ? Color.teal.opacity(0.16) : Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(on ? Color.teal : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button { newTag = ""; addingTag = true } label: {
                    Image(systemName: "plus").font(.subheadline.weight(.medium))
                        .frame(width: 34, height: 31)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("新标签")
            }
            groupLabel("优先级")
            priorityPicker
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { onSave(result) }.fontWeight(.semibold) }
        }
        .alert("新标签", isPresented: $addingTag) {
            TextField("标签", text: $newTag)
            Button("添加") {
                let t = newTag.trimmingCharacters(in: CharacterSet(charactersIn: "#＃ "))
                if !t.isEmpty && !currentTags.contains(t) { toggleTag(t) }
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear(perform: load)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary).padding(.leading, 4).padding(.top, 8)
    }

    private var kindPicker: some View {
        Picker("", selection: $kind) {
            ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder private var timeFields: some View {
        switch kind {
        case .none:
            EmptyView()
        case .day, .deadline:
            DayField(label: kind == .day ? "日期" : "截止", day: dayBinding($day))
        case .span:
            RangeField(label: "起止", from: dayBinding($day), to: dayBinding($end))
        case .repeating:
            HStack(spacing: 4) {
                ForEach(order, id: \.self) { w in
                    Toggle(String(Fmt.weekdayName(w).dropFirst()), isOn: Binding(
                        get: { weekdays.contains(w) },
                        set: { if $0 { weekdays.insert(w) } else { weekdays.remove(w) } }
                    ))
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
            }
            DayField(label: "开始", day: dayBinding($day))
        }
    }

    private var priorityPicker: some View {
        Picker("优先级", selection: $priority) {
            Text("无").tag(Priority?.none)
            ForEach(Priority.allCases, id: \.self) { Text($0.label).tag(Priority?.some($0)) }
        }
        .pickerStyle(.segmented)
    }
    #else
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(.headline).lineLimit(1) }

            Picker("", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch kind {
            case .none:
                EmptyView()
            case .day, .deadline:
                DayField(label: kind == .day ? "日期" : "截止", day: dayBinding($day))
            case .span:
                RangeField(label: "起止", from: dayBinding($day), to: dayBinding($end))
            case .repeating:
                HStack(spacing: 4) {
                    ForEach(order, id: \.self) { w in
                        Toggle(String(Fmt.weekdayName(w).dropFirst()), isOn: Binding(
                            get: { weekdays.contains(w) },
                            set: { if $0 { weekdays.insert(w) } else { weekdays.remove(w) } }
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                    }
                }
                DayField(label: "开始", day: dayBinding($day))
            }

            HStack(spacing: 6) {
                TextField("标签，空格分隔", text: $tagText).textFieldStyle(.roundedBorder)
                if !knownTags.isEmpty {
                    Menu {
                        ForEach(knownTags, id: \.self) { t in
                            Toggle("#\(t)", isOn: Binding(get: { currentTags.contains(t) }, set: { _ in toggleTag(t) }))
                        }
                    } label: { Image(systemName: "number") }
                        .menuStyle(.borderlessButton).fixedSize().help("选已有标签")
                }
            }

            Picker("优先级", selection: $priority) {
                Text("无").tag(Priority?.none)
                ForEach(Priority.allCases, id: \.self) { Text($0.label).tag(Priority?.some($0)) }
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存") { onSave(result) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear(perform: load)
    }
    #endif

    private var result: TimeChoice {
        let d = DayKey.from(day)
        let schedule: Schedule
        switch kind {
        case .none: schedule = .none
        case .day: schedule = .day(d)
        case .deadline: schedule = .deadline(d)
        case .span: schedule = .span(start: d, end: max(d, DayKey.from(end)))
        case .repeating:
            var r = Repeat(weekdays: weekdays.count == 7 ? [] : weekdays, start: d)
            if case .repeating(let old) = initial.schedule {
                r.plan = old.plan
                r.completions = old.completions
                r.itemCompletions = old.itemCompletions
            }
            schedule = .repeating(r)
        }
        let tags = tagText.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "，" })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "#＃")) }.filter { !$0.isEmpty }
        return TimeChoice(schedule: schedule, priority: priority, tags: Array(NSOrderedSet(array: tags)) as? [String] ?? tags)
    }

    private var currentTags: [String] {
        tagText.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "，" })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "#＃")) }.filter { !$0.isEmpty }
    }

    private func toggleTag(_ t: String) {
        var tags = currentTags
        if let i = tags.firstIndex(of: t) { tags.remove(at: i) } else { tags.append(t) }
        tagText = tags.joined(separator: " ")
    }

    private func load() {
        day = today.date()
        end = today.adding(days: 6).date()
        weekdays = Set(order)
        priority = initial.priority
        tagText = (initial.tags ?? []).joined(separator: " ")
        switch initial.schedule {
        case .none: kind = .none
        case .day(let d): kind = .day; day = d.date()
        case .deadline(let d): kind = .deadline; day = d.date()
        case .span(let s, let e): kind = .span; day = s.date(); end = e.date()
        case .repeating(let r): kind = .repeating; weekdays = r.weekdays.isEmpty ? Set(order) : r.weekdays; day = r.start.date()
        }
    }
}
