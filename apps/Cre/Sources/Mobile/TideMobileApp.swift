import CreCore
import SwiftUI
import UserNotifications

@main
struct TideMobileApp: App {
    @StateObject private var state = MobileState()
    @StateObject private var sync = SyncCoordinator()
    @StateObject private var router = Router()
    @Environment(\.scenePhase) private var phase
    private let opener = NotificationOpener()

    var body: some Scene {
        WindowGroup {
            RootTabs(state: state)
                .environmentObject(sync)
                .environmentObject(router)
                .onAppear {
                    sync.attach(state)
                    opener.onOpen = { router.open($0) }
                    UNUserNotificationCenter.current().delegate = opener
                    if !DemoData.isOn { SigningExpiry.scheduleReminder() }
                }
                .onOpenURL { router.open($0) }
                .onReceive(NotificationCenter.default.publisher(for: .planChangedOutside)) { _ in state.reloadFromDisk() }
                .onChange(of: phase) {
                    if phase == .active { state.reloadFromDisk(); state.refreshToday() }
                    sync.setActive(phase == .active)
                }
        }
    }
}
