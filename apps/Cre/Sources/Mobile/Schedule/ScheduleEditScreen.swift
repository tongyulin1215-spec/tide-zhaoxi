import CreCore
import SwiftUI

/// 新建 / 修改一条日程 (phone). Repeating items ask 只改这一次 / 改全部 before saving or deleting.
struct ScheduleEditScreen: View {
    @ObservedObject var state: MobileState
    let target: EditorTarget
    let onClose: () -> Void

    enum RepeatKind: Hashable { case none, daily, weekly }
    enum Action { case save, delete }

    @State private var title = ""
    @State private var day = DayKey.from(Date())
    @State private var start = 9 * 60
    @State private var end = 10 * 60
    @State private var repeatKind: RepeatKind = .none
    @State private var weekdays: Set<Int> = []
    @State private var askScope: Action?
    @FocusState private var titleFocused: Bool

    private let order = [2, 3, 4, 5, 6, 7, 1]
    private let quarters = Array(stride(from: 0, through: 24 * 60, by: 15))

    private var item: ScheduleItem? { target.occurrence.flatMap { o in state.schedule.items.first { $0.id == o.itemID } } }
    private var isRepeatingItem: Bool { item?.isRepeating ?? false }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && !(repeatKind == .weekly && weekdays.isEmpty) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $title).focused($titleFocused)
                    DayField(label: "日期", day: $day)
                    Picker("开始", selection: $start) { ForEach(quarters.dropLast(), id: \.self) { Text(clock($0)).tag($0) } }
                    Picker("结束", selection: $end) { ForEach(quarters.filter { $0 > start }, id: \.self) { Text(clock($0)).tag($0) } }
                }
                Section {
                    Picker("重复", selection: $repeatKind) {
                        Text("不重复").tag(RepeatKind.none)
                        Text("每天").tag(RepeatKind.daily)
                        Text("每周").tag(RepeatKind.weekly)
                    }
                    .pickerStyle(.segmented)
                    if repeatKind == .weekly {
                        HStack(spacing: 4) {
                            ForEach(order, id: \.self) { w in
                                let on = weekdays.contains(w)
                                Button { if on { weekdays.remove(w) } else { weekdays.insert(w) } } label: {
                                    Text(String(Fmt.weekdayName(w).dropFirst())).font(.subheadline)
                                        .frame(maxWidth: .infinity).frame(height: 34)
                                        .background(on ? Color.accentColor : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(on ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if target.occurrence != nil {
                    Section {
                        Button("删除", role: .destructive) { isRepeatingItem ? (askScope = .delete) : delete(.all) }
                    }
                }
            }
            .navigationTitle(target.occurrence == nil ? "新日程" : "日程").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onClose) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { isRepeatingItem ? (askScope = .save) : save(.all) }.fontWeight(.semibold).disabled(!canSave)
                }
            }
            .confirmationDialog("这是重复日程", isPresented: Binding(get: { askScope != nil }, set: { if !$0 { askScope = nil } }),
                                titleVisibility: .visible) {
                Button("只改这一次") { run(.one) }
                Button("改全部") { run(.all) }
                Button("取消", role: .cancel) { askScope = nil }
            }
        }
        .onAppear(perform: load)
        .onChange(of: start) { if end <= start { end = min(1440, start + 15) } }
    }

    private func load() {
        title = target.title
        day = target.day
        start = target.start
        end = max(target.end, target.start + 15)
        weekdays = [target.day.weekday]
        if let r = item?.repeats {
            switch r {
            case .none: repeatKind = .none
            case .daily: repeatKind = .daily
            case .weekly(let w): repeatKind = .weekly; weekdays = w
            }
        }
        if target.occurrence == nil { titleFocused = true }
    }

    private var repeats: ScheduleRepeat {
        switch repeatKind {
        case .none: .none
        case .daily: .daily
        case .weekly: .weekly(weekdays)
        }
    }

    private func run(_ scope: ScheduleScope) {
        let a = askScope
        askScope = nil
        if a == .delete { delete(scope) } else { save(scope) }
    }

    private func save(_ scope: ScheduleScope) {
        let t = title.trimmingCharacters(in: .whitespaces)
        if let o = target.occurrence {
            state.schedule.update(o.itemID, on: o.day, title: t, day: day, start: start, end: end, repeats: repeats, scope: scope)
        } else {
            state.schedule.add(title: t, day: day, start: start, end: end, repeats: repeats)
        }
        onClose()
    }

    private func delete(_ scope: ScheduleScope) {
        if let o = target.occurrence { state.schedule.delete(o.itemID, on: o.day, scope: scope) }
        onClose()
    }
}
