import SwiftUI

struct MainView: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager
    @State private var issueSeen = false

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { state.section }, set: { if let s = $0 { state.section = s } })) {
                ForEach(AppSection.allCases) { s in
                    Label {
                        Text(s.title)
                    } icon: {
                        Image(systemName: s.icon).foregroundStyle(.primary)
                    }
                    .tag(s)
                    .listItemTint(.monochrome)
                }
            }
            .safeAreaInset(edge: .bottom) {
                SettingsLink {
                    Label("设置", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 64, ideal: 140, max: 200)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear { state.openMainWindow = { [openWindow] in openWindow(id: "main") } }
        .onOpenURL { _ in
            state.section = .home
            state.viewingDay = state.today
        }
        .sheet(isPresented: $state.showTriage) { TriageSheet(state: state) }
        .onAppear { state.undoManager = undoManager }
        .onChange(of: undoManager) { state.undoManager = undoManager }
        .alert("数据未载入", isPresented: Binding(get: { state.loadIssueMessage != nil && !issueSeen },
                                                set: { if !$0 { issueSeen = true } })) {
            Button("好") { issueSeen = true }
        } message: {
            Text(state.loadIssueMessage ?? "")
        }
    }

    @ViewBuilder private var detail: some View {
            switch state.section {
            case .home: HomeView(state: state)
            case .planning: PlanningView(state: state)
            case .schedule: ScheduleView(state: state)
            case .ledger: LedgerView(state: state)
            case .summary: SummaryView(state: state)
            }
    }
}
