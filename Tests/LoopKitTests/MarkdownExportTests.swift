import Testing
@testable import LoopKit
import Foundation

struct MarkdownExportTests {
    @Test func emptyListStillProducesAHeaderNotACrash() {
        let output = MarkdownExport.checklist(for: [])
        #expect(output.hasPrefix("# Loop Reminders"))
    }

    @Test func incompleteItemAppearsAsUncheckedUnderItsSection() {
        let item = ReminderItem(title: "Buy milk", dueDate: .now)
        let output = MarkdownExport.checklist(for: [item])
        #expect(output.contains("## Today"))
        #expect(output.contains("- [ ] Buy milk"))
    }

    @Test func completedItemAppearsCheckedUnderCompleted() {
        var item = ReminderItem(title: "Finish report")
        item.isCompleted = true
        item.completedDate = .now
        let output = MarkdownExport.checklist(for: [item])
        #expect(output.contains("## Completed"))
        #expect(output.contains("- [x] Finish report"))
    }

    @Test func tagAppearsInParenthesesAfterTitle() {
        let item = ReminderItem(title: "Call mom", tag: "home")
        let output = MarkdownExport.checklist(for: [item])
        #expect(output.contains("Call mom (home)"))
    }

    @Test func noDueDateItemLandsInSomeday() {
        let item = ReminderItem(title: "Someday task")
        let output = MarkdownExport.checklist(for: [item])
        #expect(output.contains("## Someday"))
    }
}
