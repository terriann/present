import Foundation
import UserNotifications
import PresentCore

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendTimerCompleted(activityTitle: String, sessionType: SessionType, playSound: Bool = true) {
        let content = UNMutableNotificationContent()
        let config = SessionTypeConfig.config(for: sessionType)

        content.title = "Time's Up"
        content.body = "\(activityTitle) — \(config.displayName) session complete."
        if playSound { content.sound = .default }

        let request = UNNotificationRequest(
            identifier: "timer-completed-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendBreakSuggestion(isLongBreak: Bool, breakMinutes: Int, playSound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = isLongBreak ? "Time for a Long Break" : "Take a Short Break"
        content.body = "You've earned a \(breakMinutes)-minute break. Step away and recharge."
        if playSound { content.sound = .default }

        let request = UNNotificationRequest(
            identifier: "break-suggestion-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
