import Testing
@testable import LoopKit
import Foundation

/// These pin the grouping against an explicit "now" rather than the real clock. An
/// earlier version asserted against `.now` and passed all week, then failed on a
/// Sunday: the moment just after the current week is literally tomorrow on the week's
/// last day, so `.tomorrow` correctly won over `.later`. Injecting the date makes the
/// rules verifiable on any day the suite happens to run.
struct ReminderItemSectionTests {
    /// Wednesday 12 Aug 2026, midday, in a Monday-start week (so the week runs
    /// Mon 10 Aug through Sun 16 Aug).
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    private var wednesday: Date { date(12) }

    @Test func noDueDateIsSomeday() {
        let item = ReminderItem(title: "Someday task")
        #expect(item.section(now: wednesday, calendar: calendar) == .someday)
    }

    @Test func pastDueDateIsOverdueWhenIncomplete() {
        let item = ReminderItem(title: "Late task", dueDate: date(11))
        #expect(item.section(now: wednesday, calendar: calendar) == .overdue)
    }

    @Test func completedPastItemIsNotOverdue() {
        var item = ReminderItem(title: "Done late", dueDate: date(11))
        item.isCompleted = true
        #expect(item.section(now: wednesday, calendar: calendar) != .overdue)
    }

    @Test func todayDueDateIsToday() {
        let item = ReminderItem(title: "Today task", dueDate: date(12, hour: 8))
        #expect(item.section(now: wednesday, calendar: calendar) == .today)
    }

    @Test func tomorrowDueDateIsTomorrow() {
        let item = ReminderItem(title: "Tomorrow task", dueDate: date(13))
        #expect(item.section(now: wednesday, calendar: calendar) == .tomorrow)
    }

    @Test func laterThisWeekIsThisWeek() {
        // Friday and Sunday are both past tomorrow but still inside this week.
        #expect(ReminderItem(title: "Fri", dueDate: date(14)).section(now: wednesday, calendar: calendar) == .thisWeek)
        #expect(ReminderItem(title: "Sun", dueDate: date(16)).section(now: wednesday, calendar: calendar) == .thisWeek)
    }

    @Test func nextWeekIsLater() {
        // Monday 17 Aug starts the following week.
        #expect(ReminderItem(title: "Mon", dueDate: date(17)).section(now: wednesday, calendar: calendar) == .later)
    }

    @Test func farFutureDueDateIsLater() {
        let nextMonth = calendar.date(byAdding: .day, value: 30, to: wednesday)!
        let item = ReminderItem(title: "Later task", dueDate: nextMonth)
        #expect(item.section(now: wednesday, calendar: calendar) == .later)
    }

    @Test func onTheLastDayOfAWeekTheNextDayIsStillTomorrowNotLater() {
        // Sunday 16 Aug is the week's last day, so Monday 17 Aug falls outside the
        // current week yet is genuinely tomorrow. Day-level grouping wins.
        let sunday = date(16)
        let item = ReminderItem(title: "Mon", dueDate: date(17))
        #expect(item.section(now: sunday, calendar: calendar) == .tomorrow)
    }
}
