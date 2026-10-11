import CreCore
import SwiftUI

/// 新建模块组：名称 → 类型 → 排期方式 → 具体排期。
struct NewGroupSheet: View {
    @ObservedObject var state: AppState
    /// When set, the sheet edits this group's name, kind and schedule instead of creating one.
    var editing: TodoGroup? = nil
    let onClose: () -> Void

    @State private var form = GroupForm(editing: nil, data: PlanData(), today: DayKey.from(Date()))

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("名称", text: $form.name).textFieldStyle(.roundedBorder).font(.title3)

            Picker("类型", selection: $form.kind) { ForEach(GroupForm.Kind.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)

            switch form.kind {
            case .cycle:
                Picker("排期方式", selection: $form.cycleMode) { ForEach(GroupForm.CycleMode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                if form.cycleMode == .fixed {
                    weekdayPicker
                } else {
                    Stepper("周期 \(form.period)", value: $form.period, in: 1...30)
                    Stepper("间隔 \(form.gap)", value: $form.gap, in: 0...14)
                }
                DayField(label: "开始", day: $form.start)
            case .list:
                Picker("排期方式", selection: $form.listMode) { ForEach(GroupForm.ListMode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                if form.listMode == .weekly { weekdayPicker }
                TextField("标准", text: $form.standard, prompt: Text("1 小时"))
                DayField(label: "开始", day: $form.start)
            case .phase, .ungrouped:
                EmptyView()
            }

            HStack {
                Spacer()
                Button("取消", action: onClose).keyboardShortcut(.cancelAction)
                Button(editing == nil ? "创建" : "保存") {
                    form.apply(to: &state.data, editing: editing, today: state.today, now: Date())
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!form.canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { form = GroupForm(editing: editing, data: state.data, today: state.today) }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 4) {
            ForEach(GroupForm.order, id: \.self) { w in
                Toggle(String(Fmt.weekdayName(w).dropFirst()), isOn: Binding(
                    get: { form.weekdays.contains(w) },
                    set: { if $0 { form.weekdays.insert(w) } else { form.weekdays.remove(w) } }
                ))
                .toggleStyle(.button)
            }
        }
    }
}

/// 编辑循环的每一天：名称与动作（每行一个）。
struct DayPlanEditor: View {
    @ObservedObject var state: AppState
    let anchorID: UUID
    let rule: Repeat
    let onClose: () -> Void

    @State private var names: [String] = []
    @State private var actions: [String] = []

    private var plan: DayPlan { rule.plan ?? DayPlan(mode: .fixedWeekday) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(plan.days.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(label(i)).font(.headline).frame(width: 56, alignment: .leading)
                                TextField("名称", text: binding($names, i)).textFieldStyle(.roundedBorder)
                            }
                            TextEditor(text: binding($actions, i))
                                .font(.body)
                                .frame(height: 64)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                                .overlay(alignment: .topLeading) {
                                    if actions.indices.contains(i) && actions[i].isEmpty {
                                        Text("动作，每行一个").foregroundStyle(.tertiary).padding(6).allowsHitTesting(false)
                                    }
                                }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("取消", action: onClose).keyboardShortcut(.cancelAction)
                Button("保存", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 520)
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

    private func save() {
        saveDayPlan(plan, names: names, actions: actions, anchorID: anchorID, in: &state.data)
        onClose()
    }
}
