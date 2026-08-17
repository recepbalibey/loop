import Testing
@testable import LoopKit
import Foundation

/// Covers the "check in every N minutes" schedule. This was previously verifiable only
/// by launching the app and dumping the notification centre's pending requests by hand,
/// which is a poor way to be sure a reminder will actually nag you on time.
struct CheckInScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: hour, minute: minute))!
    }

    private func block(start: Date, end: Date, everyMinutes: Int?) -> ReminderItem {
        ReminderItem(
            title: "Focus block",
            dueDate: start,
            endDate: end,
            checkInIntervalMinutes: everyMinutes
        )
    }

    @Test func everyThirtyMinutesAcrossATwoHourBlock() {
        // Mirrors a real verified case: 08:30-10:30 checking in every 30 minutes should
        // produce 09:00, 09:30 and 10:00. The start already has its own notification and
        // the 10:30 end needs none, so neither appears here.
        let item = block(start: date(hour: 8, minute: 30), end: date(hour: 10, minute: 30), everyMinutes: 30)
        let expected = [date(hour: 9), date(hour: 9, minute: 30), date(hour: 10)]
        #expect(item.checkInDates() == expected)
    }

    @Test func everyFifteenMinutesAcrossAnHour() {
        let item = block(start: date(hour: 14), end: date(hour: 15), everyMinutes: 15)
        let expected = [date(hour: 14, minute: 15), date(hour: 14, minute: 30), date(hour: 14, minute: 45)]
        #expect(item.checkInDates() == expected)
    }

    @Test func aCheckInLandingExactlyOnTheEndIsExcluded() {
        // 14:00-15:00 every 60 minutes: the only candidate is 15:00, which is the end of
        // the block. Nagging someone the instant their block finishes is noise.
        let item = block(start: date(hour: 14), end: date(hour: 15), everyMinutes: 60)
        #expect(item.checkInDates().isEmpty)
    }

    @Test func intervalLongerThanTheBlockProducesNoCheckIns() {
        let item = block(start: date(hour: 14), end: date(hour: 14, minute: 20), everyMinutes: 60)
        #expect(item.checkInDates().isEmpty)
    }

    @Test func noCheckInsWithoutAnInterval() {
        let item = block(start: date(hour: 14), end: date(hour: 16), everyMinutes: nil)
        #expect(item.checkInDates().isEmpty)
    }

    @Test func noCheckInsWithoutAnEndTime() {
        let item = ReminderItem(title: "Single moment", dueDate: date(hour: 14), checkInIntervalMinutes: 15)
        #expect(item.checkInDates().isEmpty)
    }

    @Test func zeroOrNegativeIntervalDoesNotLoopForever() {
        let zero = block(start: date(hour: 14), end: date(hour: 16), everyMinutes: 0)
        #expect(zero.checkInDates().isEmpty)

        let negative = block(start: date(hour: 14), end: date(hour: 16), everyMinutes: -15)
        #expect(negative.checkInDates().isEmpty)
    }

    @Test func longBlockWithShortIntervalIsCapped() {
        // 24 hours checking in every minute would be 1439 notifications without the cap.
        let item = block(start: date(hour: 0), end: date(hour: 23, minute: 59), everyMinutes: 1)
        #expect(item.checkInDates().count == 48)
    }
}
