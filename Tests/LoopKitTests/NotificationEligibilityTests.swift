import Testing
@testable import LoopKit
import Foundation

struct NotificationEligibilityTests {
    private let now = Date(timeIntervalSince1970: 1_754_640_000) // fixed reference point

    @Test func incompleteWithFutureDueDateNeedsNotification() {
        let item = ReminderItem(title: "Future", dueDate: now.addingTimeInterval(3600))
        #expect(item.needsScheduledNotification(now: now))
    }

    @Test func incompleteWithPastDueDateDoesNotNeedNotification() {
        // It's overdue, not upcoming — the red status icon covers that case, not a
        // fresh notification for a moment that already passed.
        let item = ReminderItem(title: "Past", dueDate: now.addingTimeInterval(-3600))
        #expect(!item.needsScheduledNotification(now: now))
    }

    @Test func noDueDateDoesNotNeedNotification() {
        let item = ReminderItem(title: "No date")
        #expect(!item.needsScheduledNotification(now: now))
    }

    @Test func completedItemDoesNotNeedNotificationEvenWithFutureDueDate() {
        var item = ReminderItem(title: "Done early", dueDate: now.addingTimeInterval(3600))
        item.isCompleted = true
        #expect(!item.needsScheduledNotification(now: now))
    }

    @Test func exactlyNowDoesNotCountAsFuture() {
        let item = ReminderItem(title: "Right now", dueDate: now)
        #expect(!item.needsScheduledNotification(now: now))
    }
}
