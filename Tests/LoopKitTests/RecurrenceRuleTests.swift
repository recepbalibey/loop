import Testing
@testable import LoopKit
import Foundation

@Suite
struct RecurrenceRuleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9, minute: Int = 30) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func dailyAdvancesByOneDayPreservingTime() {
        let start = date(2026, 8, 12, hour: 9, minute: 30) // Wednesday
        let next = RecurrenceRule.daily.nextOccurrence(after: start, calendar: calendar)
        #expect(calendar.isDate(next, equalTo: date(2026, 8, 13, hour: 9, minute: 30), toGranularity: .minute))
    }

    @Test func weeklyAdvancesBySevenDays() {
        let start = date(2026, 8, 12, hour: 9, minute: 30)
        let next = RecurrenceRule.weekly.nextOccurrence(after: start, calendar: calendar)
        #expect(calendar.isDate(next, equalTo: date(2026, 8, 19, hour: 9, minute: 30), toGranularity: .minute))
    }

    @Test func weekdaysSkipsSaturdayAndSunday() {
        // Aug 14, 2026 is a Friday — the next weekday should be Monday Aug 17, not Sat/Sun.
        let friday = date(2026, 8, 14)
        let next = RecurrenceRule.weekdays.nextOccurrence(after: friday, calendar: calendar)
        #expect(calendar.isDate(next, equalTo: date(2026, 8, 17), toGranularity: .day))
        #expect(!calendar.isDateInWeekend(next))
    }

    @Test func weekdaysFromSundayLandsOnMonday() {
        let sunday = date(2026, 8, 16)
        #expect(calendar.isDateInWeekend(sunday))
        let next = RecurrenceRule.weekdays.nextOccurrence(after: sunday, calendar: calendar)
        #expect(calendar.isDate(next, equalTo: date(2026, 8, 17), toGranularity: .day))
    }
}
