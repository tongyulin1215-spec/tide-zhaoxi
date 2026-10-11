import CreCore
import SwiftUI

/// 设置：新的一天、同步、每晚提醒.
struct MobileSettingsSheet: View {
    @ObservedObject var state: MobileState
    @EnvironmentObject private var sync: SyncCoordinator
    let onClose: () -> Void
    @State private var pairing = false
    @State private var confirmForget = false

    var body: some View {
        NavigationStack {
            Form {
                Section("新的一天") {
                    Picker("开始于", selection: $state.dayStartHour) {
                        ForEach(0...6, id: \.self) { Text("\($0):00").tag($0) }
                    }
                }
                Section("同步") {
                    if let mac = sync.macName {
                        LabeledContent(mac) {
                            Text(status).foregroundStyle(.secondary)
                        }
                        Button("立即同步") { Task { await sync.syncNow() } }.disabled(sync.syncing)
                        Button("断开", role: .destructive) { confirmForget = true }
                    } else {
                        Button("连接 Mac") { pairing = true }
                    }
                }
                ReminderSection()
                if let expiry = SigningExpiry.date {
                    Section {
                        LabeledContent("可用到", value: expiry.formatted(.dateTime.month().day().hour().minute()))
                    } footer: {
                        Text("到期前一天晚上会提醒重新安装")
                    }
                }
            }
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: onClose) } }
            .sheet(isPresented: $pairing) { PairScreen(sync: sync) { pairing = false } }
            .alert("断开与 Mac 的同步？", isPresented: $confirmForget) {
                Button("断开", role: .destructive) { sync.forget() }
                Button("取消", role: .cancel) {}
            } message: { Text("手机上的数据会保留。") }
        }
    }

    private var status: String {
        if sync.syncing { return "同步中…" }
        guard let t = sync.lastSync else { return "尚未同步" }
        let when = Calendar.current.isDateInToday(t) ? t.formatted(date: .omitted, time: .shortened) : t.formatted(date: .abbreviated, time: .shortened)
        return (sync.reachable ? "已连接 · " : "未连接 · ") + "上次 \(when)"
    }
}
