import CreCore
import SwiftUI

/// What tide:// links and notifications ask the app to open.
@MainActor
final class Router: ObservableObject {
    @Published var quickAdd = false
    @Published var todaySummary = false
    /// tide://today (the widget): 首页 on today.
    @Published var today = false
    /// tide://todo/<id> (an item in the widget): 首页 on today, that item open.
    @Published var openTodo: UUID?
    /// Bumped by any link that shows 首页.
    @Published var showHome = 0

    func open(_ url: URL) {
        switch url.host {
        case "quickadd": quickAdd = true
        case "summary": todaySummary = true; showHome += 1
        case "today": today = true; showHome += 1
        case "todo":
            if let id = UUID(uuidString: url.lastPathComponent) { openTodo = id; showHome += 1 }
        default: break
        }
    }
}

/// 记一条: one line, same rules as the home input; closes on return.
struct QuickAddSheet: View {
    @ObservedObject var state: MobileState
    let onClose: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("记一条").font(.headline)
            TextField("记录想法或安排", text: $text)
                .focused($focused)
                .submitLabel(.done)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("记一条")
                .onSubmit {
                    // Lands on today (not the day being viewed), like the Mac's quick add.
                    if state.data.addLine(text, override: nil, groupID: nil, viewingDay: state.today, today: state.today, now: Date()) != nil {
                        onClose()
                    }
                }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(160)])
        .onAppear { focused = true }
    }
}
