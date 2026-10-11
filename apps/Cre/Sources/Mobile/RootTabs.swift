import CreCore
import SwiftUI

/// 底部图标栏：首页、规划、日程、记账、总结 (same names and icons as the Mac sidebar).
struct RootTabs: View {
    @ObservedObject var state: MobileState
    @StateObject private var intake = ScreenshotIntake()
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var phase
    @State private var tab: Board = .home
    @State private var askUndo = false

    enum Board: Hashable { case home, planning, schedule, ledger, summary }

    var body: some View {
        TabView(selection: $tab) {
            HomeScreen(state: state)
                .tabItem { Label("首页", systemImage: "sun.horizon") }.tag(Board.home)
            PlanningScreen(state: state).tabItem { Label("规划", systemImage: "list.bullet.rectangle") }.tag(Board.planning)
            ScheduleScreen(state: state).tabItem { Label("日程", systemImage: "calendar.day.timeline.left") }.tag(Board.schedule)
            LedgerScreen(state: state, intake: intake).tabItem { Label("记账", systemImage: "creditcard") }.tag(Board.ledger)
            SummaryScreen(state: state).tabItem { Label("总结", systemImage: "chart.bar") }.tag(Board.summary)
        }
        .onChange(of: phase) {
            guard phase == .active else { return }
            // Images shared to 朝夕 from other apps open straight into the ledger form.
            if intake.collectInbox(state: state) { tab = .ledger }
            if tab == .ledger { intake.checkLatest() }
        }
        .sheet(isPresented: $router.quickAdd) { QuickAddSheet(state: state) { router.quickAdd = false } }
        .onChange(of: router.showHome) { tab = .home }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            if state.undoManager.canUndo { askUndo = true }
        }
        .alert("撤销上一步？", isPresented: $askUndo) {
            Button("撤销") { state.undoManager.undo() }
            Button("取消", role: .cancel) {}
        }
    }
}

/// Boards not built yet on the phone.
struct ComingSoon: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            PageTitleRow { Text(title) } trailing: { EmptyView() }
                .padding(.leading, 20).padding(.trailing, 12).padding(.top, 4)
            Text("即将推出").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

/// The system only routes shake-to-undo to an editing text field; catch the shake for the whole app instead.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}

/// Every board's top line: big title at the top left, its buttons on the right, nothing above.
struct PageTitleRow<Title: View, Trailing: View>: View {
    @ViewBuilder let title: Title
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            title.font(.largeTitle.bold()).lineLimit(1)
            Spacer()
            trailing
        }
        .font(.title3)
        .tint(.primary)
        .frame(minHeight: 44)
    }
}
