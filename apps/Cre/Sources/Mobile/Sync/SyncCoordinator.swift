import CreCore
import Network
import SwiftUI

/// Keeps the phone in step with 朝夕 on the Mac over Wi-Fi: on opening, a few seconds after a change,
/// and every 30 seconds while open. No Mac in reach: nothing happens, the next try catches up.
@MainActor
final class SyncCoordinator: ObservableObject {
    @Published private(set) var macName: String? = UserDefaults.standard.string(forKey: "syncMac")
    @Published private(set) var lastSync: Date? = UserDefaults.standard.object(forKey: "syncLast") as? Date
    @Published private(set) var reachable = false
    @Published private(set) var syncing = false
    /// The last try couldn't reach the Mac (shown on 首页 when it has been a while).
    @Published private(set) var lastTryFailed = false

    private var token: String? {
        get { UserDefaults.standard.string(forKey: "syncToken") }
        set { UserDefaults.standard.set(newValue, forKey: "syncToken") }
    }
    private weak var state: MobileState?
    private var timer: Timer?
    private var debounce: Task<Void, Never>?

    var isPaired: Bool { macName != nil && token != nil }

    func attach(_ state: MobileState) {
        self.state = state
        state.onChange = { [weak self] in self?.soon() }
    }

    /// Foreground: sync now and every 30 s; background: stop.
    func setActive(_ active: Bool) {
        timer?.invalidate()
        guard active, isPaired, !DemoData.isOn || ProcessInfo.processInfo.environment["CRE_SYNC"] == "1" else { return }
        Task { await syncNow() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
    }

    /// A local change: send it after a short pause, so typing doesn't sync every key.
    private func soon() {
        guard isPaired else { return }
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { await syncNow() }
        }
    }

    func syncNow() async {
        guard let state, let macName, let token, !syncing else { return }
        syncing = true
        defer { syncing = false }
        let sent = state.syncPayload
        do {
            let r = try await SyncClient.send(.sync(token: token, payload: sent), to: SyncClient.endpoint(serviceName: macName))
            switch r {
            case .synced(let theirs):
                // Changes made while the request was out are kept: merge the answer with what's here now.
                var merged = state.syncPayload.merged(with: theirs)
                merged.pruneOldMarks(now: Date())
                state.applySynced(merged)
                lastTryFailed = false
                lastSync = Date()
                UserDefaults.standard.set(lastSync, forKey: "syncLast")
                reachable = true
            case .unpaired:
                forget()
            default:
                reachable = false
                lastTryFailed = true
            }
        } catch {
            reachable = false
            lastTryFailed = true
        }
    }

    // MARK: Pairing

    func requestCode(from mac: String) async -> Bool {
        let r = try? await SyncClient.send(.pair(deviceName: UIDevice.current.name), to: SyncClient.endpoint(serviceName: mac))
        return r == .codeShown
    }

    /// The 4 digits shown on the Mac; true when paired.
    func confirm(code: String, with mac: String) async -> Bool {
        guard case .paired(let t)? = try? await SyncClient.send(.confirm(code: code, deviceName: UIDevice.current.name),
                                                                 to: SyncClient.endpoint(serviceName: mac)) else { return false }
        token = t
        macName = mac
        UserDefaults.standard.set(mac, forKey: "syncMac")
        setActive(true)
        return true
    }

    func forget() {
        token = nil
        macName = nil
        lastSync = nil
        reachable = false
        timer?.invalidate()
        ["syncMac", "syncLast", "syncToken"].forEach(UserDefaults.standard.removeObject)
    }
}

/// 连接 Mac: pick the Mac (found on this Wi-Fi), then type the 4 digits it shows.
struct PairScreen: View {
    @ObservedObject var sync: SyncCoordinator
    let onClose: () -> Void

    @State private var macs: [String] = []
    @State private var searching = true
    @State private var chosen: String?
    @State private var code = ""
    @State private var failed = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if let chosen {
                    Section {
                        TextField("4 位数字", text: $code)
                            .keyboardType(.numberPad)
                            .font(.title2.monospacedDigit())
                            .focused($codeFocused)
                            .onChange(of: code) {
                                code = String(code.filter(\.isNumber).prefix(4))
                                if code.count == 4 { confirm(chosen) }
                            }
                    } header: {
                        Text("输入「\(chosen)」上显示的数字")
                    } footer: {
                        if failed { Text("数字不对或已过期，请重试").foregroundStyle(.red) }
                    }
                } else {
                    Section {
                        if macs.isEmpty {
                            HStack {
                                Text(searching ? "正在查找…" : "没找到。确认 Mac 上的朝夕已打开，且在同一 Wi-Fi")
                                    .foregroundStyle(.secondary)
                                if searching { Spacer(); ProgressView() }
                            }
                        }
                        ForEach(macs, id: \.self) { mac in
                            Button(mac) { pick(mac) }
                        }
                    } header: { Text("同一 Wi-Fi 下的 Mac") }
                }
            }
            .navigationTitle("连接 Mac").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onClose) }
                if chosen == nil && !searching {
                    ToolbarItem(placement: .confirmationAction) { Button("重新查找") { Task { await search() } } }
                }
            }
            .task { await search() }
        }
    }

    private func search() async {
        searching = true
        macs = await SyncClient.discover()
        searching = false
    }

    private func pick(_ mac: String) {
        Task {
            if await sync.requestCode(from: mac) {
                chosen = mac
                codeFocused = true
            } else {
                failed = true
            }
        }
    }

    private func confirm(_ mac: String) {
        Task {
            if await sync.confirm(code: code, with: mac) { onClose() } else { failed = true; code = "" }
        }
    }
}
