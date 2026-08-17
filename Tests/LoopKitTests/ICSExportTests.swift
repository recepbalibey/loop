import Testing
@testable import LoopKit
import Foundation

struct ICSExportTests {
    @Test func emptyListStillProducesAValidWrapper() {
        let output = ICSExport.calendar(for: [])
        #expect(output.contains("BEGIN:VCALENDAR"))
        #expect(output.contains("END:VCALENDAR"))
        #expect(output.contains("VERSION:2.0"))
    }

    @Test func itemWithoutDueDateIsExcluded() {
        let item = ReminderItem(title: "Someday task")
        let output = ICSExport.calendar(for: [item])
        #expect(!output.contains("BEGIN:VEVENT"))
    }

    @Test func completedItemIsExcluded() {
        var item = ReminderItem(title: "Done already", dueDate: .now)
        item.isCompleted = true
        let output = ICSExport.calendar(for: [item])
        #expect(!output.contains("BEGIN:VEVENT"))
    }

    @Test func scheduledItemProducesAnEvent() {
        let item = ReminderItem(title: "Team sync", dueDate: .now)
        let output = ICSExport.calendar(for: [item])
        #expect(output.contains("BEGIN:VEVENT"))
        #expect(output.contains("SUMMARY:Team sync"))
        #expect(output.contains("UID:\(item.id.uuidString)@loop-app"))
        #expect(output.contains("END:VEVENT"))
    }

    @Test func recurringItemIncludesRRule() {
        let item = ReminderItem(title: "Standup", dueDate: .now, recurrenceRule: .weekdays)
        let output = ICSExport.calendar(for: [item])
        #expect(output.contains("RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"))
    }

    @Test func commaAndSemicolonInTitleAreEscaped() {
        let item = ReminderItem(title: "Buy milk, eggs; bread", dueDate: .now)
        let output = ICSExport.calendar(for: [item])
        #expect(output.contains("SUMMARY:Buy milk\\, eggs\\; bread"))
    }
}
