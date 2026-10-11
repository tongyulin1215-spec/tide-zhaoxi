import CreCore
import SwiftUI

/// 新建 / 编辑模块组 on the phone: 名称 → 类型 → 排期方式 → 具体排期 (rules in `GroupForm`, shared with the Mac).
struct NewGroupScreen: View {
    @ObservedObject var state: MobileState
    var editing: TodoGroup? = nil
    let onClose: () -> Void

    @State private var form = GroupForm(editing: nil, data: PlanData(), today: DayKey.from(Date()))
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("名称", text: $form.name).focused($nameFocused)
                Picker("类型", selection: $form.kind) { ForEach(GroupForm.Kind.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
            }
            switch form.kind {
            case .cycle:
                Section {
                    Picker("排期方式", selection: $form.cycleMode) { ForEach(GroupForm.CycleMode.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                    if form.cycleMode == .fixed {
                        weekdayPicker
                    } else {
                        Stepper("周期 \(form.period) 天", value: $form.period, in: 1...30)
                        Stepper("间隔 \(form.gap) 天", value: $form.gap, in: 0...14)
                    }
                    DayField(label: "开始", day: $form.start)
                }
            case .list:
                Section {
                    Picker("排期方式", selection: $form.listMode) { ForEach(GroupForm.ListMode.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                    if form.listMode == .weekly { weekdayPicker }
                    LabeledContent("标准") {
                        TextField("1 小时", text: $form.standard).multilineTextAlignment(.trailing)
                    }
                    DayField(label: "开始", day: $form.start)
                }
            case .phase, .ungrouped:
                EmptyView()
            }
        }
        .navigationTitle(editing == nil ? "新建模块组" : "编辑排期").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消", action: onClose) }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "创建" : "保存") {
                    form.apply(to: &state.data, editing: editing, today: state.today, now: Date())
                    onClose()
                }
                .fontWeight(.semibold)
                .disabled(!form.canSave)
            }
        }
        .onAppear {
            form = GroupForm(editing: editing, data: state.data, today: state.today)
            if editing == nil { nameFocused = true }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 4) {
            ForEach(GroupForm.order, id: \.self) { w in
                let on = form.weekdays.contains(w)
                Button {
                    if on { form.weekdays.remove(w) } else { form.weekdays.insert(w) }
                } label: {
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

/// 编辑安排: each cycle day's name and actions (one per line).
struct DayPlanScreen: View {
    @ObservedObject var state: MobileState
    let anchorID: UUID
    let rule: Repeat
    let onClose: () -> Void

    @State private var names: [String] = []
    @State private var actions: [String] = []

    private var plan: DayPlan { rule.plan ?? DayPlan(mode: .fixedWeekday) }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(plan.days.indices, id: \.self) { i in
                    Section(label(i)) {
                        TextField("名称", text: binding($names, i))
                        TextField("动作，每行一个", text: binding($actions, i), axis: .vertical).lineLimit(2...)
                    }
                }
            }
            .navigationTitle("编辑安排").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onClose) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveDayPlan(plan, names: names, actions: actions, anchorID: anchorID, in: &state.data)
                        onClose()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            names = plan.days.map(\.name)
            actions = plan.days.map { $0.items.map(\.text).joined(separator: "\n") }
        }
    }

    private func label(_ i: Int) -> String {
        plan.mode == .fixedWeekday ? Fmt.weekdayName(plan.days[i].weekday ?? 1) : "第 \(i + 1) 天"
    }

    private func binding(_ list: Binding<[String]>, _ i: Int) -> Binding<String> {
        Binding(get: { list.wrappedValue.indices.contains(i) ? list.wrappedValue[i] : "" },
                set: { if list.wrappedValue.indices.contains(i) { list.wrappedValue[i] = $0 } })
    }
}
