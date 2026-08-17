import Testing
@testable import LoopKit
import Foundation

/// Guards the bug where a block that had already started lost the check-ins it still
/// had left. Scheduling keyed off "does this start in the future", which stops being
/// true the moment a block begins, so the remaining check-ins were treated as stale and
/// cancelled on the next resync. In practice that meant adding a reminder or relaunching
/// Loop mid-block silently switched the nagging off.
struct UpcomingCheckInTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: hour, minute: minute))!
    }

    /// 14:00-15:00, checking in every 15 minutes.
    private var block: ReminderItem {
        ReminderItem(title: "Focus", dueDate: at(14), endDate: at(15), checkInIntervalMinutes: 15)
    }

    @Test func beforeTheBlockStartsEveryCheckInIsStillAhead() {
        let upcoming = block.upcomingCheckIns(now: at(13))
        #expect(upcoming.map(\.date) == [at(14, 15), at(14, 30), at(14, 45)])
    }

    @Test func midBlockTheRemainingCheckInsSurvive() {
        // The block has started, so its opening alert is done with, but 14:30 and 14:45
        // must still be scheduled. This is the case that used to come back empty.
        let item = block
        #expect(!item.needsScheduledNotification(now: at(14, 20)))
        #expect(item.upcomingCheckIns(now: at(14, 20)).map(\.date) == [at(14, 30), at(14, 45)])
    }

    @Test func indicesStayStableAsTheBlockProgresses() {
        // 14:30 keeps index 1 rather than being renumbered to 0, so it holds the same
        // notification identifier across syncs instead of colliding with 14:15's.
        let item = block
        let early = item.upcomingCheckIns(now: at(13))
        let later = item.upcomingCheckIns(now: at(14, 20))
        #expect(early.first(where: { $0.date == at(14, 30) })?.index == 1)
        #expect(later.first(where: { $0.date == at(14, 30) })?.index == 1)
    }

    @Test func afterTheBlockEndsNothingRemains() {
        #expect(block.upcomingCheckIns(now: at(15, 1)).isEmpty)
    }

    @Test func aCheckInExactlyNowIsNotRescheduled() {
        // It is either being delivered or already gone; re-registering it would fire a
        // duplicate.
        #expect(block.upcomingCheckIns(now: at(14, 30)).map(\.date) == [at(14, 45)])
    }

    @Test func completingTheBlockClearsItsCheckIns() {
        var item = block
        item.isCompleted = true
        #expect(item.upcomingCheckIns(now: at(14, 20)).isEmpty)
    }
}
