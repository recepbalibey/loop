import Testing
@testable import LoopKit
import Foundation

@Suite("Work log schedule")
struct WorkLogScheduleTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 26
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return utc.date(from: components)!
    }

    @Test func createsIntervalPromptsAndAnEndOfDayReview() {
        let schedule = WorkLogSchedule(
            intervalMinutes: 60,
            startTime: TimeOfDay(hour: 9, minute: 0)!,
            endTime: TimeOfDay(hour: 12, minute: 0)!
        )!
        let events = schedule.upcomingEvents(now: date(8), limit: 3, calendar: utc)

        #expect(events.map(\.date) == [date(10), date(11), date(12)])
        #expect(events.map(\.kind) == [.prompt, .prompt, .dailyReview])
    }

    @Test func skipsPromptsAlreadyInThePast() {
        let schedule = WorkLogSchedule(
            intervalMinutes: 60,
            startTime: TimeOfDay(hour: 9, minute: 0)!,
            endTime: TimeOfDay(hour: 12, minute: 0)!
        )!
        let events = schedule.upcomingEvents(now: date(10, 30), limit: 2, calendar: utc)

        #expect(events.map(\.date) == [date(11), date(12)])
    }

    @Test func rejectsIntervalsBelowThirtyMinutes() {
        #expect(WorkLogSchedule(
            intervalMinutes: 15,
            startTime: TimeOfDay(hour: 9, minute: 0)!,
            endTime: TimeOfDay(hour: 23, minute: 0)!
        ) == nil)
    }
}
