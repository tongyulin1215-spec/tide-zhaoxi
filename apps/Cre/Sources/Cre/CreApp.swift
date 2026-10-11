import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One instance only: a second copy would overwrite the first one's data.
        if let id = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: id)
               .first(where: { $0 != NSRunningApplication.current }) {
            other.activate()
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "朝夕")
        item.button?.target = self
        item.button?.action = #selector(showMain)
        statusItem = item
        hotKey = HotKey { [weak self] in Task { @MainActor in self?.showMain() } }
        state.hotKeyFailed = !(hotKey?.isRegistered ?? false)
        Reminder.shared.onOpen = { [weak self] in
            guard let self else { return }
            self.showMain()
            self.state.summarizeToday()
        }
        if !DemoData.isOn { Reminder.shared.start() }
        #if !PUBLIC_DEMO
        SyncHost.shared.start(state: state)  // the public edition doesn't listen on anyone's network
        #endif
    }

    /// Menu bar icon and hotkey: bring up the full app on the home page.
    @objc func showMain() {
        state.section = .home
        state.viewingDay = state.today
        state.openMainWindow?()
        NSApp.activate()
        NSApp.windows.first { $0.identifier?.rawValue == "main" || $0.title == "朝夕" }?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { state.openMainWindow?() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct CreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Window(DemoData.isOn ? "朝夕 · 演示" : "朝夕", id: "main") {
            MainView(state: delegate.state)
        }
        Settings {
            SettingsView(state: delegate.state)
        }
    }
}
