import Foundation
import UserNotifications
import LoopKit

/// Schedules the separate daily work-log prompts. Its identifiers have their own prefix
/// so reminder reconciliation never cancels a work-log prompt, and vice versa.
final class WorkLogNotificationScheduler {
    static let promptCategoryID = "WORK_LOG_PROMPT"
    static let reviewCategoryID = "WORK_LOG_REVIEW"
    static let writeActionID = "WRITE_WORK_LOG"
    static let reviewActionID = "VIEW_WORK_LOG"
    static let identifierPrefix = "work-log-"

    private let center = UNUserNotificationCenter.current()

    func registerCategories() {
        let write = UNNotificationAction(identifier: Self.writeActionID, title: "Write Update", options: [.foreground])
        let review = UNNotificationAction(identifier: Self.reviewActionID, title: "Read Today’s Log", options: [.foreground])
        let prompt = UNNotificationCategory(identifier: Self.promptCategoryID, actions: [write], intentIdentifiers: [], options: [])
        let finalReview = UNNotificationCategory(identifier: Self.reviewCategoryID, actions: [review], intentIdentifiers: [], options: [])
        center.setNotificationCategories([prompt, finalReview])
    }

    func sync() {
        guard UserDefaults.standard.bool(forKey: PreferenceKeys.workLogEnabled),
              NotificationScheduler.notificationsEnabled,
              let schedule = Self.currentSchedule()
        else {
            removePendingWorkLogRequests()
            return
        }

        let events = schedule.upcomingEvents()
        let expectedIDs = Set(events.map(identifier(for:)))
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let stale = requests.map(\.identifier)
                .filter { $0.hasPrefix(Self.identifierPrefix) && !expectedIDs.contains($0) }
            if !stale.isEmpty {
                self.center.removePendingNotificationRequests(withIdentifiers: stale)
            }
            for event in events {
                self.center.add(self.request(for: event)) { error in
                    if let error { print("Loop: failed to schedule work log notification: \(error)") }
                }
            }
        }
    }

    func removePendingWorkLogRequests() {
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
            if !ids.isEmpty { self.center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
    }

    static func currentSchedule() -> WorkLogSchedule? {
        let defaults = UserDefaults.standard
        let interval = defaults.integer(forKey: PreferenceKeys.workLogIntervalMinutes)
        let start = TimeOfDay(
            hour: defaults.object(forKey: PreferenceKeys.workLogStartHour) == nil ? 9 : defaults.integer(forKey: PreferenceKeys.workLogStartHour),
            minute: defaults.integer(forKey: PreferenceKeys.workLogStartMinute)
        )
        let end = TimeOfDay(
            hour: defaults.object(forKey: PreferenceKeys.workLogEndHour) == nil ? 23 : defaults.integer(forKey: PreferenceKeys.workLogEndHour),
            minute: defaults.integer(forKey: PreferenceKeys.workLogEndMinute)
        )
        guard let start, let end else { return nil }
        return WorkLogSchedule(intervalMinutes: interval == 0 ? 60 : interval, startTime: start, endTime: end)
    }

    static func workDayEndTime() -> TimeOfDay {
        currentSchedule()?.endTime ?? TimeOfDay(hour: 23, minute: 0)!
    }

    static func isWorkLogNotification(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    private func request(for event: WorkLogSchedule.Event) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.sound = notificationSound
        switch event.kind {
        case .prompt:
            content.title = "What have you done so far?"
            content.body = "Add a short update to today’s work log."
            content.categoryIdentifier = Self.promptCategoryID
        case .dailyReview:
            content.title = "Your work day is complete"
            content.body = "Read today’s work log. It is now read-only."
            content.categoryIdentifier = Self.reviewCategoryID
        }
        return UNNotificationRequest(identifier: identifier(for: event), content: content, trigger: calendarTrigger(for: event.date))
    }

    private var notificationSound: UNNotificationSound {
        let raw = UserDefaults.standard.string(forKey: PreferenceKeys.notificationSoundOption) ?? NotificationSoundOption.system.rawValue
        return NotificationSoundOption.resolved(from: raw).unNotificationSound
    }

    private func identifier(for event: WorkLogSchedule.Event) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let kind = event.kind == .prompt ? "prompt" : "review"
        return "\(Self.identifierPrefix)\(kind)-\(formatter.string(from: event.date))"
    }

    private func calendarTrigger(for date: Date) -> UNCalendarNotificationTrigger {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}
