import AppKit
import UserNotifications

/// 每日总结提醒：每天定时一条系统通知，点开即生成并显示今天的总结。
@MainActor
final class Reminder: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminder()

    static let enabledKey = "reminderEnabled"
    static let hourKey = "reminderHour"
    static let minuteKey = "reminderMinute"
    private static let requestID = "daily-summary"

    /// Called when the user clicks the notification.
    var onOpen: (() -> Void)?

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var hour: Int { UserDefaults.standard.object(forKey: hourKey) as? Int ?? 22 }
    static var minute: Int { UserDefaults.standard.object(forKey: minuteKey) as? Int ?? 0 }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        schedule()
    }

    /// Replaces the pending reminder according to the current settings.
    func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        guard Self.isEnabled else { return }
        let hour = Self.hour, minute = Self.minute
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "朝夕"
            content.body = "总结一下今天？"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
            center.add(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: trigger))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.onOpen?() }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
