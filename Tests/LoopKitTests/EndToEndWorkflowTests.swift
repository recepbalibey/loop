import Testing
@testable import LoopKit
import Foundation

/// Walks whole user journeys rather than single methods, so a feature that works in
/// isolation but breaks in combination (a reschedule silently dropping a check-in
/// schedule, say) gets caught.
@Suite(.serialized)
final class EndToEndWorkflowTests {
    private let remindersURL: URL
    private let templatesURL: URL

    init() {
        let directory = FileManager.default.temporaryDirectory
        remindersURL = directory.appendingPathComponent("LoopE2E-reminders-\(UUID().uuidString).json")
        templatesURL = directory.appendingPathComponent("LoopE2E-templates-\(UUID().uuidString).json")
    }

    deinit {
        try? FileManager.default.removeItem(at: remindersURL)
        try? FileManager.default.removeItem(at: templatesURL)
    }

    private func makeStore() -> TaskStore { TaskStore(fileURL: remindersURL) }
    private func makeTemplateStore() -> TemplateStore { TemplateStore(fileURL: templatesURL) }

    private var calendar: Calendar { .current }

    /// The reported bug: editing a reminder's time and saving once had to be repeated
    /// before it stuck. The view-level cause was a focus/save race, but this pins the
    /// contract the fixed view now relies on: one `update` writes the new time through,
    /// and reloading from disk sees it.
    @Test func editingATimeTakesEffectOnTheFirstSave() throws {
        let store = makeStore()
        let original = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9, minute: 0))!
        let item = store.add(title: "Video Shooting", dueDate: original)

        let retimed = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 18, minute: 30))!
        store.update(item.id, title: "Video Shooting", notes: nil, dueDate: retimed, endDate: nil, tag: nil)

        #expect(store.items[0].dueDate == retimed)

        let reloaded = TaskStore(fileURL: remindersURL)
        let persisted = try #require(reloaded.items.first?.dueDate)
        #expect(abs(persisted.timeIntervalSince(retimed)) < 1)
    }

    /// A scheduled block edited to a new start keeps its duration and its check-in
    /// cadence, and the resulting check-ins line up with the new start.
    @Test func retimingABlockMovesItsCheckInsWithIt() {
        let store = makeStore()
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9))!
        let item = store.add(title: "Focus", dueDate: start)
        store.update(item.id, title: "Focus", notes: nil, dueDate: start, endDate: start.addingTimeInterval(3600), tag: nil, checkInIntervalMinutes: 15)
        #expect(store.items[0].checkInDates().count == 3)

        let newStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 14))!
        store.update(item.id, title: "Focus", notes: nil, dueDate: newStart, endDate: newStart.addingTimeInterval(3600), tag: nil, checkInIntervalMinutes: 15)

        let checkIns = store.items[0].checkInDates()
        #expect(checkIns.count == 3)
        #expect(checkIns.first == newStart.addingTimeInterval(15 * 60))
    }

    @Test func addCompleteAndUndoRoundTrip() {
        let store = makeStore()
        let item = store.add(title: "Buy milk", dueDate: .now.addingTimeInterval(3600))
        #expect(store.items[0].needsScheduledNotification())

        store.toggleCompletion(item.id)
        #expect(store.items[0].isCompleted)
        #expect(!store.items[0].needsScheduledNotification()) // completed items stop nagging

        store.toggleCompletion(item.id)
        #expect(!store.items[0].isCompleted)
        #expect(store.items[0].completedDate == nil)
        #expect(store.items[0].needsScheduledNotification())
    }

    @Test func recurringReminderRollsForwardAndStaysNotifiable() {
        let store = makeStore()
        let start = Date.now.addingTimeInterval(3600)
        let item = store.add(title: "Standup", dueDate: start)
        store.update(item.id, title: "Standup", notes: nil, dueDate: start, endDate: nil, tag: nil, recurrenceRule: .daily)

        store.toggleCompletion(item.id)

        let advanced = store.items[0]
        #expect(!advanced.isCompleted) // rolls forward instead of landing in Completed
        #expect(advanced.needsScheduledNotification())
        let expected = calendar.date(byAdding: .day, value: 1, to: start)!
        #expect(calendar.isDate(advanced.dueDate!, equalTo: expected, toGranularity: .minute))
    }

    @Test func priorityAndManualOrderSurviveAReload() {
        let store = makeStore()
        let first = store.add(title: "First")
        let second = store.add(title: "Second")
        let third = store.add(title: "Third")

        store.setPriority(second.id, .high)
        store.moveItem(third.id, toBeBefore: first.id)

        let reloaded = TaskStore(fileURL: remindersURL)
        #expect(reloaded.items.map(\.title) == ["Third", "First", "Second"])
        #expect(reloaded.items.first(where: { $0.id == second.id })?.priority == .high)
    }

    /// Mirrors what applying a template does: a template with a duration becomes a
    /// scheduled block starting now, carrying its tag and priority across.
    @Test func templateAppliesAsAScheduledBlock() throws {
        let templates = makeTemplateStore()
        let template = templates.add(title: "Deep Work", notes: "Phone away", tag: "office", durationMinutes: 90, priority: .high)

        let store = makeStore()
        let start = Date.now.roundedUpToNearestFiveMinutesForTesting()
        let end = start.addingTimeInterval(TimeInterval(template.durationMinutes! * 60))
        store.add(title: template.title, notes: template.notes, dueDate: start, endDate: end, tag: template.tag, priority: template.priority)

        let created = try #require(store.items.first)
        #expect(created.title == "Deep Work")
        #expect(created.tag == "office")
        #expect(created.priority == .high)
        #expect(created.endDate!.timeIntervalSince(created.dueDate!) == 90 * 60)
    }

    @Test func everyFieldSurvivesSaveAndReload() throws {
        let store = makeStore()
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9))!
        let item = store.add(title: "Everything", dueDate: start)
        store.setPriority(item.id, .medium)
        store.update(
            item.id,
            title: "Everything",
            notes: "With notes",
            dueDate: start,
            endDate: start.addingTimeInterval(7200),
            tag: "home",
            checkInIntervalMinutes: 30,
            recurrenceRule: .weekdays
        )

        let reloaded = try #require(TaskStore(fileURL: remindersURL).items.first)
        #expect(reloaded.title == "Everything")
        #expect(reloaded.notes == "With notes")
        #expect(reloaded.tag == "home")
        #expect(reloaded.priority == .medium)
        #expect(reloaded.checkInIntervalMinutes == 30)
        #expect(reloaded.recurrenceRule == .weekdays)
        #expect(abs(reloaded.endDate!.timeIntervalSince(start) - 7200) < 1)
    }

    @Test func exportsCoverScheduledWorkAndSkipCompleted() {
        let store = makeStore()
        let upcoming = store.add(title: "Upcoming", dueDate: .now.addingTimeInterval(3600))
        let done = store.add(title: "Finished", dueDate: .now.addingTimeInterval(3600))
        store.toggleCompletion(done.id)
        _ = upcoming

        let ics = ICSExport.calendar(for: store.items)
        #expect(ics.contains("SUMMARY:Upcoming"))
        #expect(!ics.contains("SUMMARY:Finished")) // an .ics of what's ahead, not a log

        let markdown = MarkdownExport.checklist(for: store.items)
        #expect(markdown.contains("- [ ] Upcoming"))
        #expect(markdown.contains("- [x] Finished")) // the text export is the full picture
    }

    @Test func naturalLanguageAddProducesAScheduledReminder() throws {
        let parsed = NaturalLanguageParser.parse("Call the dentist tomorrow at 3pm")
        let store = makeStore()
        store.add(title: parsed.cleanTitle, dueDate: parsed.date, tag: parsed.tag)

        let created = try #require(store.items.first)
        #expect(created.title.localizedCaseInsensitiveContains("dentist"))
        let due = try #require(created.dueDate)
        #expect(created.section(now: .now) == .tomorrow)
        #expect(calendar.component(.hour, from: due) == 15)
    }
}

private extension Date {
    /// Mirrors the app-side rounding used when a template starts "now". Duplicated here
    /// because that helper lives in the app target, which the LoopKit tests can't import.
    func roundedUpToNearestFiveMinutesForTesting(calendar: Calendar = .current) -> Date {
        let remainder = calendar.component(.minute, from: self) % 5
        let rounded = remainder == 0 ? self : calendar.date(byAdding: .minute, value: 5 - remainder, to: self) ?? self
        return calendar.date(bySetting: .second, value: 0, of: rounded) ?? rounded
    }
}
