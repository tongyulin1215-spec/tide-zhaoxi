import AppKit
import CreCore
import SwiftUI

/// 朝夕 on the Mac as the phone's sync partner: listens on the Wi-Fi, shows the pairing code, merges, backs up first.
@MainActor
final class SyncHost: ObservableObject {
    static let shared = SyncHost()

    @Published private(set) var book = PairingBook()
    private var server: SyncServer?
    private weak var state: AppState?
    private var codePanel: NSPanel?

    private var bookURL: URL? {
        DemoData.isOn ? DemoData.directory.appendingPathComponent("sync-devices.json") : sharedFileURL("sync-devices.json")
    }

    func start(state: AppState) {
        self.state = state
        if let url = bookURL, let d = try? Data(contentsOf: url), let b = try? JSONDecoder().decode(PairingBook.self, from: d) { book = b }
        let name = (Host.current().localizedName ?? "Mac") + (DemoData.isOn ? "（演示）" : "")
        do {
            let server = try SyncServer(serviceName: name) { [weak self] request in
                await self?.handle(request) ?? .unpaired
            }
            self.server = server
            Task { _ = try? await server.start() }
        } catch {
            NSLog("Tide sync server failed: \(error)")
        }
    }

    func unpair(_ name: String) {
        book.unpair(name)
        saveBook()
    }

    private func handle(_ request: SyncRequest) -> SyncResponse {
        switch request {
        case .pair(let device):
            showCode(book.requestCode(device: device, now: Date()), for: device)
            saveBook()
            return .codeShown
        case .confirm(let code, let device):
            guard let token = book.confirm(code: code, device: device, now: Date()) else { return .badCode }
            closeCode()
            saveBook()
            return .paired(token: token)
        case .sync(let token, let payload):
            guard let state, let device = book.device(token: token) else { return .unpaired }
            if device.lastSync == nil && !backUp(state) { return .refused }
            // A tick made in the desktop widget since the last check must be in memory before merging and saving.
            state.pickUpExternalChanges()
            var merged = state.syncPayload.merged(with: payload)
            merged.pruneOldMarks(now: Date())
            state.applySynced(merged)
            book.synced(token: token, now: Date())
            saveBook()
            return .synced(merged)
        }
    }

    private func saveBook() {
        guard let url = bookURL, let d = try? JSONEncoder().encode(book) else { return }
        try? d.write(to: url, options: .atomic)
    }

    /// Before the first sync with a phone: every data file to 文稿/朝夕备份/<time>/. False if any copy failed.
    private func backUp(_ state: AppState) -> Bool {
        let fm = FileManager.default
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmm"
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("朝夕备份", isDirectory: true)
            .appendingPathComponent((DemoData.isOn ? "演示 " : "") + f.string(from: Date()), isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let files = [state.store.fileURL, state.ledgerStore.fileURL, state.scheduleStore.fileURL] + [AppState.dayStartFile].compactMap { $0 }
            for file in files where fm.fileExists(atPath: file.path) {
                try fm.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
            }
            return true
        } catch {
            NSLog("Tide backup before first sync failed: \(error)")
            return false
        }
    }

    // MARK: Pairing code window

    private func showCode(_ code: String, for device: String) {
        closeCode()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 170),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "连接手机"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: VStack(spacing: 10) {
            Text("在「\(device)」上输入").foregroundStyle(.secondary)
            Text(code).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit().kerning(8)
            Text("1 分钟内有效").font(.caption).foregroundStyle(.tertiary)
        }.padding(20).frame(width: 280, height: 170))
        panel.center()
        panel.orderFrontRegardless()
        codePanel = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self, weak panel] in
            if let panel, self?.codePanel === panel { self?.closeCode() }
        }
    }

    private func closeCode() {
        codePanel?.close()
        codePanel = nil
    }
}

/// 设置 ▸ 手机: paired phones and their last sync.
struct PhoneSyncSection: View {
    @ObservedObject var host = SyncHost.shared

    var body: some View {
        Section("手机") {
            if host.book.devices.isEmpty {
                Text("在手机朝夕的设置里点「连接 Mac」").foregroundStyle(.secondary)
            }
            ForEach(host.book.devices, id: \.name) { d in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name)
                        Text(d.lastSync.map { "上次同步 \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "尚未同步")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("取消配对") { host.unpair(d.name) }
                }
            }
        }
    }
}
