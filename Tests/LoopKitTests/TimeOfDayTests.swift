import Testing
@testable import LoopKit
import Foundation

struct TimeOfDayTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func parsesWellFormedTime() {
        let time = TimeOfDay(text: "14:36")
        #expect(time?.hour == 14)
        #expect(time?.minute == 36)
    }

    @Test func parsesSingleDigitComponents() {
        let time = TimeOfDay(text: "7:5")
        #expect(time?.hour == 7)
        #expect(time?.minute == 5)
        #expect(time?.formatted == "07:05")
    }

    @Test func toleratesSurroundingWhitespace() {
        #expect(TimeOfDay(text: "  09:30 ")?.formatted == "09:30")
    }

    @Test func rejectsOutOfRangeValuesRatherThanClamping() {
        // Bouncing back to the previous value makes a typo visible; silently clamping
        // "25:00" to 23:00 would look like a deliberate choice the user never made.
        #expect(TimeOfDay(text: "25:00") == nil)
        #expect(TimeOfDay(text: "12:60") == nil)
        #expect(TimeOfDay(hour: -1, minute: 0) == nil)
    }

    @Test func rejectsMalformedText() {
        #expect(TimeOfDay(text: "") == nil)
        #expect(TimeOfDay(text: "1430") == nil)
        #expect(TimeOfDay(text: "ab:cd") == nil)
        #expect(TimeOfDay(text: "12:30:45") == nil)
    }

    @Test func roundTripsThroughDate() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 16, minute: 51))!
        let time = TimeOfDay(date: date, calendar: calendar)
        #expect(time.formatted == "16:51")
    }

    @Test func appliedKeepsTheDayAndReplacesTheTime() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 3, minute: 7))!
        let applied = TimeOfDay(hour: 18, minute: 0)!.applied(to: day, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: applied)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 12)
        #expect(components.hour == 18)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }
}
