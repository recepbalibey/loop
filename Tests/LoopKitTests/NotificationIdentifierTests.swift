import Testing
@testable import LoopKit
import Foundation

struct NotificationIdentifierTests {
    private let reminderID = UUID()

    @Test func mainIdentifierIsTheBareUUID() {
        #expect(NotificationIdentifier.main(for: reminderID) == reminderID.uuidString)
    }

    @Test func checkInIdentifiersAreDistinctPerOccurrence() {
        let first = NotificationIdentifier.checkIn(for: reminderID, index: 0)
        let second = NotificationIdentifier.checkIn(for: reminderID, index: 1)
        #expect(first != second)
        #expect(first != NotificationIdentifier.main(for: reminderID))
    }

    @Test func readsTheReminderBackFromAMainIdentifier() {
        let identifier = NotificationIdentifier.main(for: reminderID)
        #expect(NotificationIdentifier.reminderID(from: identifier) == reminderID)
    }

    /// The regression that mattered: a check-in identifier is not itself a valid UUID,
    /// so parsing it directly returned nil and left "Mark Done" and "Snooze" doing
    /// nothing at all on every check-in notification.
    @Test func readsTheReminderBackFromACheckInIdentifier() {
        for index in [0, 1, 47] {
            let identifier = NotificationIdentifier.checkIn(for: reminderID, index: index)
            #expect(UUID(uuidString: identifier) == nil) // why the naive parse failed
            #expect(NotificationIdentifier.reminderID(from: identifier) == reminderID)
        }
    }

    @Test func returnsNilForIdentifiersLoopDidNotMintForAReminder() {
        #expect(NotificationIdentifier.reminderID(from: "loop-test-notification") == nil)
        #expect(NotificationIdentifier.reminderID(from: "") == nil)
        #expect(NotificationIdentifier.reminderID(from: "not-a-uuid-checkin-0") == nil)
    }
}
