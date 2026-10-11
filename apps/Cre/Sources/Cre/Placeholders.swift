import SwiftUI

struct PlaceholderView: View {
    let title: String
    let note: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.title2.bold())
            Text(note).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @AppStorage(Reminder.enabledKey) private var reminderOn = true
    @AppStorage(Reminder.hourKey) private var hour = 22
    @AppStorage(Reminder.minuteKey) private var minute = 0

    var body: some View {
        Form {
            Section("新的一天") {
                Picker("开始于", selection: $state.dayStartHour) {
                    ForEach(0...6, id: \.self) { h in Text("\(h):00").tag(h) }
                }
            }
            Section("每日总结提醒") {
                Toggle("开启", isOn: $reminderOn)
                DatePicker("时间", selection: Binding(
                    get: { Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date() },
                    set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); hour = c.hour ?? 22; minute = c.minute ?? 0 }
                ), displayedComponents: .hourAndMinute)
                .disabled(!reminderOn)
            }
            if !DemoData.isOn { PhoneSyncSection() }
            Section("快捷键") {
                LabeledContent("打开朝夕", value: "⌥Space")
                if state.hotKeyFailed {
                    Text("快捷键被其他应用占用").foregroundStyle(.red)
                }
            }
            Section("周五清理") {
                LabeledContent("出现时间", value: "每周五 19:00 起")
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .onChange(of: reminderOn) { Reminder.shared.schedule() }
        .onChange(of: hour) { Reminder.shared.schedule() }
        .onChange(of: minute) { Reminder.shared.schedule() }
    }
}
