import AppIntents
import CreCore
import Foundation
import WidgetKit

/// 「用朝夕记一条」: asks for one line and files it like the home input, without opening the app.
/// Works from Shortcuts, Siri and the Action button.
struct QuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "记一条"
    static var description = IntentDescription("记一条待办，识别规则同首页。")

    @Parameter(title: "内容", requestValueDialog: "记什么？")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let url = PlanStore.sharedURL() else { return .result(dialog: "没记上") }
        let store = PlanStore(fileURL: url)
        let before = store.load()
        var data = before
        let now = Date()
        let today = logicalDay(now, startHour: loadDayStartHour())
        guard data.addLine(text, override: nil, groupID: nil, viewingDay: today, today: today, now: now) != nil else {
            return .result(dialog: "没记上")
        }
        try store.save(data.stamped(since: before, now: now))
        WidgetCenter.shared.reloadAllTimelines()
        // The app, if open, takes it in.
        await MainActor.run { NotificationCenter.default.post(name: .planChangedOutside, object: nil) }
        return .result(dialog: "记下了")
    }
}

extension Notification.Name {
    static let planChangedOutside = Notification.Name("planChangedOutside")
}

struct TideShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: QuickAddIntent(), phrases: ["用\(.applicationName)记一条", "\(.applicationName)记一条"],
                    shortTitle: "记一条", systemImageName: "plus.circle")
    }
}
