import SwiftUI
import UserNotifications

/// 每晚提醒: off unless turned on; a daily notification 「总结一下今天？」 that opens today's summary.
enum NightlyReminder {
    static let enabledKey = "reminderOn"
    static let hourKey = "reminderHour"
    static let minuteKey = "reminderMinute"
    private static let id = "tide.nightly"

    static func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let d = UserDefaults.standard
        guard d.bool(forKey: enabledKey) else { return }
        let hour = d.object(forKey: hourKey) as? Int ?? 22, minute = d.object(forKey: minuteKey) as? Int ?? 0
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "朝夕"
            content.body = "总结一下今天？"
            content.userInfo = ["open": "tide://summary"]
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}

/// Opens the link a tapped notification carries.
final class NotificationOpener: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: ((URL) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let s = response.notification.request.content.userInfo["open"] as? String, let url = URL(string: s) {
            await MainActor.run { onOpen?(url) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

struct ReminderSection: View {
    @AppStorage(NightlyReminder.enabledKey) private var on = false
    @AppStorage(NightlyReminder.hourKey) private var hour = 22
    @AppStorage(NightlyReminder.minuteKey) private var minute = 0

    var body: some View {
        Section {
            Toggle("每晚提醒", isOn: $on)
            if on {
                DatePicker("时间", selection: Binding(
                    get: { Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date() },
                    set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); hour = c.hour ?? 22; minute = c.minute ?? 0 }
                ), displayedComponents: .hourAndMinute)
            }
        } footer: {
            if on { Text("到点提醒总结今天") }
        }
        .onChange(of: on) { NightlyReminder.schedule() }
        .onChange(of: hour) { NightlyReminder.schedule() }
        .onChange(of: minute) { NightlyReminder.schedule() }
    }
}
