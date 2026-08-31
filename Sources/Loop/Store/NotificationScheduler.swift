import Foundation
import UserNotifications
import LoopKit

/// Turns due dates into real macOS notifications. Reconciles the full set of
/// scheduled notifications against the store's current items on every change —
/// simple and correct at the small scale a personal reminders list runs at, rather
/// than tracking incremental diffs by hand.
final class NotificationScheduler {
    static let reminderCategoryID = "REMINDER"
    static let markDoneActionID = "MARK_DONE"
    static let snoozeActionID = "SNOOZE_1H"
    static let snoozeInterval: TimeInterval = 3600

    private let center = UNUserNotificationCenter.current()

    static var notificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.notificationsEnabled)
    }

    static func chosenSound(for key: String) -> UNNotificationSound {
        let defaults = UserDefaults.standard
        // Existing installs keep their former selected sound until each new sound is
        // explicitly customized.
        let raw = defaults.string(forKey: key)
            ?? defaults.string(forKey: PreferenceKeys.notificationSoundOption)
            ?? NotificationSoundOption.system.rawValue
        return NotificationSoundOption.resolved(from: raw).unNotificationSound
    }

    func registerCategories() {
        let markDone = UNNotificationAction(
            identifier: Self.markDoneActionID,
            title: "Mark Done",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionID,
            title: "Snooze 1 Hour",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.reminderCategoryID,
            actions: [markDone, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// Schedules a notification for every item that needs one (plus any recurring
    /// check-in notifications across its start–end block) and cancels any pending
    /// notification for an item — or check-in occurrence — that no longer qualifies
    /// (completed, deleted, rescheduled to no date/a past date, or an interval that
    /// no longer produces that occurrence).
    func sync(with items: [ReminderItem]) {
        guard Self.notificationsEnabled else {
            center.removeAllPendingNotificationRequests()
            return
        }

        // Every incomplete reminder is considered, not just those whose start is still
        // ahead. A block that has already begun no longer needs its opening alert but
        // very much still needs the check-ins that remain inside it. Filtering on
        // "starts in the future" here used to drop in-progress blocks entirely, so
        // their pending check-ins looked stale and were cancelled the first time
        // anything resynced mid-block, including simply relaunching Loop.
        let now = Date.now
        let active = items.filter { !$0.isCompleted }
        let expectedIDs = Set(active.flatMap { Self.identifiers(for: $0, now: now) })

        center.getPendingNotificationRequests { [center] requests in
            let scheduledIDs = Set(requests.map(\.identifier))
            let staleIDs = scheduledIDs.subtracting(expectedIDs)
            if !staleIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: Array(staleIDs))
            }

            // Re-adding with the same identifier replaces any existing request, so
            // it's safe to unconditionally reschedule everything on every sync rather
            // than diffing what actually changed — simple and correct at the small
            // scale a personal reminders list runs at.
            for item in active {
                Self.schedule(item: item, on: center, now: now)
            }
        }
    }

    /// Fires a one-off notification a couple seconds from now, independent of any
    /// reminder — lets someone confirm notifications actually work (permission granted,
    /// Do Not Disturb not silently eating them, etc.) without setting a real due date
    /// and waiting for it.
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "If you can see this, Loop's notifications are working."
        content.sound = Self.chosenSound(for: PreferenceKeys.reminderSoundOption)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "loop-test-notification", content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                print("Loop: failed to send test notification: \(error)")
            }
        }
    }

    private static func schedule(item: ReminderItem, on center: UNUserNotificationCenter, now: Date) {
        if item.needsScheduledNotification(now: now), let dueDate = item.dueDate {
            let content = UNMutableNotificationContent()
            content.title = item.title
            if let notes = item.notes, !notes.isEmpty {
                content.body = notes
            }
            content.sound = Self.chosenSound(for: PreferenceKeys.reminderSoundOption)
            content.categoryIdentifier = reminderCategoryID

            let request = UNNotificationRequest(
                identifier: NotificationIdentifier.main(for: item.id),
                content: content,
                trigger: calendarTrigger(for: dueDate)
            )
            center.add(request) { error in
                if let error {
                    print("Loop: failed to schedule notification for \(item.title): \(error)")
                }
            }
        }

        for checkIn in item.upcomingCheckIns(now: now) {
            let checkInContent = UNMutableNotificationContent()
            checkInContent.title = "Still on it?"
            checkInContent.body = "Checking in on “\(item.title)”"
            checkInContent.sound = Self.chosenSound(for: PreferenceKeys.checkInSoundOption)
            checkInContent.categoryIdentifier = reminderCategoryID

            let checkInRequest = UNNotificationRequest(
                identifier: NotificationIdentifier.checkIn(for: item.id, index: checkIn.index),
                content: checkInContent,
                trigger: calendarTrigger(for: checkIn.date)
            )
            center.add(checkInRequest) { error in
                if let error {
                    print("Loop: failed to schedule check-in for \(item.title): \(error)")
                }
            }
        }
    }

    private static func calendarTrigger(for date: Date) -> UNCalendarNotificationTrigger {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    /// Every identifier this item should still occupy in the notification centre as of
    /// `now`: its opening alert while that is still ahead, plus each check-in that has
    /// not happened yet. Anything pending outside this set belongs to a deleted,
    /// completed, or since-rescheduled reminder and gets cleared.
    private static func identifiers(for item: ReminderItem, now: Date) -> [String] {
        var identifiers: [String] = []
        if item.needsScheduledNotification(now: now) {
            identifiers.append(NotificationIdentifier.main(for: item.id))
        }
        identifiers.append(contentsOf: item.upcomingCheckIns(now: now).map {
            NotificationIdentifier.checkIn(for: item.id, index: $0.index)
        })
        return identifiers
    }
}

enum PreferenceKeys {
    static let notificationsEnabled = "notificationsEnabled"
    /// Whether the menu bar shows a short live text label (next/active reminder) in
    /// place of the icon. Read directly via `UserDefaults` in `AppDelegate` (it's not
    /// a SwiftUI view, so no `@AppStorage`) and via `@AppStorage` everywhere else.
    static let menuBarShowsText = "menuBarShowsText"
    static let accentColorOption = "accentColorOption"
    static let notificationSoundOption = "notificationSoundOption"
    static let reminderSoundOption = "reminderSoundOption"
    static let checkInSoundOption = "checkInSoundOption"
    static let workLogPromptSoundOption = "workLogPromptSoundOption"
    static let workLogReviewSoundOption = "workLogReviewSoundOption"
    static let workLogEnabled = "workLogEnabled"
    static let workLogIntervalMinutes = "workLogIntervalMinutes"
    static let workLogStartHour = "workLogStartHour"
    static let workLogStartMinute = "workLogStartMinute"
    static let workLogEndHour = "workLogEndHour"
    static let workLogEndMinute = "workLogEndMinute"
    /// Virtual keycode (`NSEvent.keyCode` / Carbon `kVK_*`) and `NSEvent.ModifierFlags`
    /// raw value for the global "open Loop" shortcut. Missing means the original
    /// fixed default, ⌥⌘L.
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifierFlags = "hotKeyModifierFlags"
}
