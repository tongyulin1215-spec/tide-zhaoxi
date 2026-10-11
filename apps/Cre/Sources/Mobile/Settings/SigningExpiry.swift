import CreCore
import Foundation
import UserNotifications

/// Free signing lasts 7 days; this reads when this install stops opening and reminds the day before.
enum SigningExpiry {
    private static let id = "tide.signing"

    /// From embedded.mobileprovision (absent in the simulator).
    static var date: Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return profileExpiry(from: data)
    }

    /// 20:00 the evening before it expires: 「明天到期，请接上 Mac 重新安装」.
    static func scheduleReminder() {
        guard let expiry = date else { return }
        let cal = Calendar.current
        guard let dayBefore = cal.date(byAdding: .day, value: -1, to: expiry),
              let fireAt = cal.date(bySettingHour: 20, minute: 0, second: 0, of: dayBefore) else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard fireAt > Date() else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "朝夕"
            content.body = "明天到期，请接上 Mac 重新安装"
            let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt), repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
