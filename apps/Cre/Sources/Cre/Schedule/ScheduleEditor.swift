import CreCore
import SwiftUI

/// 新建 / 修改一条日程。
struct ScheduleEditor: View {
    @ObservedObject var state: AppState
    let target: EditorTarget
    let onClose: () -> Void

    enum RepeatKind: Hashable { case none, daily, weekly }

    @State private var title = ""
    @State private var day = DayKey.from(Date())
    @State private var start = 9 * 60
    @State private var end = 10 * 60
    @State private var repeatKind: RepeatKind = .none
    @State private var weekdays: Set<Int> = []
    @State private var askScope: Action?
    @FocusState private var titleFocused: Bool

    enum Action { case save, delete }

    private let order = [2, 3, 4, 5, 6, 7, 1]
    /// Every quarter hour of the day, for the time menus.
    private let quarters = Array(stride(from: 0, through: 24 * 60, by: 15))

    private var item: ScheduleItem? { target.occurrence.flatMap { o in state.schedule.items.first { $0.id == o.itemID } } }
    private var isRepeatingItem: Bool { item?.isRepeating ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("名称", text: $title).textFieldStyle(.roundedBorder).font(.title3).focused($titleFocused)
            DayField(label: "日期", day: $day)
            HStack {
                Text("时间")
                Spacer()
                Picker("", selection: $start) { ForEach(quarters.dropLast(), id: \.self) { Text(clock($0)).tag($0) } }
                    .labelsHidden().fixedSize()
                Text("–")
                Picker("", selection: $end) { ForEach(quarters.filter { $0 > start }, id: \.self) { Text(clock($0)).tag($0) } }
                    .labelsHidden().fixedSize()
            }
            HStack {
                Text("重复")
                Spacer()
                SoftSegments(selection: $repeatKind, options: [(.none, "不重复"), (.daily, "每天"), (.weekly, "每周")])
            }
            if repeatKind == .weekly {
                HStack(spacing: 4) {
                    ForEach(order, id: \.self) { w in
                        Toggle(String(Fmt.weekdayName(w).dropFirst()), isOn: Binding(
                            get: { weekdays.contains(w) },
                            set: { if $0 { weekdays.insert(w) } else { weekdays.remove(w) } }
                        ))
                        .toggleStyle(.button).controlSize(.small)
                    }
                }
            }
            HStack {
                if target.occurrence != nil {
                    Button("删除", role: .destructive) { isRepeatingItem ? (askScope = .delete) : delete(.all) }
                }
                Spacer()
                Button("取消", action: onClose).keyboardShortcut(.cancelAction)
                Button("保存") { isRepeatingItem ? (askScope = .save) : save(.all) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || (repeatKind == .weekly && weekdays.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear(perform: load)
        .onChange(of: start) { if end <= start { end = min(1440, start + 15) } }
        .confirmationDialog("这是重复日程", isPresented: Binding(get: { askScope != nil }, set: { if !$0 { askScope = nil } })) {
            Button("只改这一次") { run(.one) }
            Button("改全部") { run(.all) }
            Button("取消", role: .cancel) { askScope = nil }
        }
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
