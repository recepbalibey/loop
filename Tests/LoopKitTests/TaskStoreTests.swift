import Testing
@testable import LoopKit
import Foundation

@Suite(.serialized)
final class TaskStoreTests {
    private let tempFileURL: URL

    init() {
        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopKitTests-\(UUID().uuidString).json")
    }

    deinit {
        try? FileManager.default.removeItem(at: tempFileURL)
    }

    private func makeStore() -> TaskStore {
        TaskStore(fileURL: tempFileURL)
    }

    @Test func addInsertsItem() {
        let store = makeStore()
        let item = store.add(title: "Buy milk")
        #expect(store.items.count == 1)
        #expect(store.items.first?.id == item.id)
        #expect(store.items.first?.title == "Buy milk")
    }

    @Test func toggleCompletionSetsCompletedDateAndUndoesCleanly() {
        let store = makeStore()
        let item = store.add(title: "Ship it")

        store.toggleCompletion(item.id)
        #expect(store.items[0].isCompleted)
        #expect(store.items[0].completedDate != nil)

        store.toggleCompletion(item.id)
        #expect(!store.items[0].isCompleted)
        #expect(store.items[0].completedDate == nil)
    }

    @Test func setPriority() {
        let store = makeStore()
        let item = store.add(title: "Important thing")
        #expect(store.items[0].priority == .none)

        store.setPriority(item.id, .high)
        #expect(store.items[0].priority == .high)
    }

    @Test func moveItemRepositionsBeforeTarget() {
        let store = makeStore()
        let first = store.add(title: "First")
        let second = store.add(title: "Second")
        let third = store.add(title: "Third")
        #expect(store.items.map(\.id) == [first.id, second.id, third.id])

        store.moveItem(third.id, toBeBefore: first.id)

        #expect(store.items.map(\.id) == [third.id, first.id, second.id])
    }

    @Test func moveItemToEndWhenTargetIsSelf() {
        let store = makeStore()
        let first = store.add(title: "First")
        store.moveItem(first.id, toBeBefore: first.id) // no-op, not an infinite loop or a crash
        #expect(store.items.map(\.id) == [first.id])
    }

    @Test func reschedule() {
        let store = makeStore()
        let item = store.add(title: "Follow up", dueDate: .now)
        #expect(store.items[0].section == .today)

        store.reschedule(item.id, to: nil)
        #expect(store.items[0].section == .someday)
    }

    @Test func snoozingAnOverdueItemMakesItEligibleForNotificationAgain() {
        // Mirrors what the notification's "Snooze 1 Hour" action does: an item that
        // just fired (now overdue, no longer notification-eligible) gets rescheduled
        // an hour out and should become eligible again.
        let store = makeStore()
        let justPassed = Date().addingTimeInterval(-60)
        let item = store.add(title: "Snoozable", dueDate: justPassed)
        #expect(!store.items[0].needsScheduledNotification())

        let snoozedUntil = Date().addingTimeInterval(3600)
        store.reschedule(item.id, to: snoozedUntil)
        #expect(store.items[0].needsScheduledNotification())
        #expect(store.items[0].dueDate == snoozedUntil)
    }

    @Test func updateChangesAllFields() {
        let store = makeStore()
        let item = store.add(title: "Original title")

        store.update(item.id, title: "New title", notes: "Some notes", dueDate: nil, endDate: nil, tag: "office")

        let updated = store.items[0]
        #expect(updated.title == "New title")
        #expect(updated.notes == "Some notes")
        #expect(updated.tag == "office")
        #expect(updated.dueDate == nil)
    }

    @Test func updateWithValidEndDateAfterStartIsAccepted() {
        let store = makeStore()
        let item = store.add(title: "Meeting")
        let start = Date.now
        let end = start.addingTimeInterval(3600)

        store.update(item.id, title: "Meeting", notes: nil, dueDate: start, endDate: end, tag: nil)

        #expect(store.items[0].dueDate == start)
        #expect(store.items[0].endDate == end)
    }

    @Test func updateSilentlyDropsEndDateThatIsNotAfterStart() {
        let store = makeStore()
        let item = store.add(title: "Meeting")
        let start = Date.now
        let earlierOrEqualEnd = start.addingTimeInterval(-60)

        store.update(item.id, title: "Meeting", notes: nil, dueDate: start, endDate: earlierOrEqualEnd, tag: nil)

        #expect(store.items[0].dueDate == start)
        #expect(store.items[0].endDate == nil)
    }

    @Test func updateDropsEndDateWhenThereIsNoStartDate() {
        let store = makeStore()
        let item = store.add(title: "Someday task")

        store.update(item.id, title: "Someday task", notes: nil, dueDate: nil, endDate: .now.addingTimeInterval(3600), tag: nil)

        #expect(store.items[0].dueDate == nil)
        #expect(store.items[0].endDate == nil)
    }

    @Test func rescheduleClearsAnyExistingEndDate() {
        let store = makeStore()
        let item = store.add(title: "Meeting")
        let start = Date.now
        store.update(item.id, title: "Meeting", notes: nil, dueDate: start, endDate: start.addingTimeInterval(3600), tag: nil)
        #expect(store.items[0].endDate != nil)

        store.reschedule(item.id, to: start.addingTimeInterval(86400))
        #expect(store.items[0].endDate == nil)
    }

    @Test func clearCompletedRemovesOnlyCompletedItems() {
        let store = makeStore()
        let stillPending = store.add(title: "Still pending")
        let done1 = store.add(title: "Done 1")
        let done2 = store.add(title: "Done 2")
        store.toggleCompletion(done1.id)
        store.toggleCompletion(done2.id)
        #expect(store.items.count == 3)

        store.clearCompleted()

        #expect(store.items.count == 1)
        #expect(store.items.first?.id == stillPending.id)
    }

    @Test func deleteRemovesItem() {
        let store = makeStore()
        let item = store.add(title: "Temporary")
        #expect(store.items.count == 1)

        store.delete(item.id)
        #expect(store.items.isEmpty)
    }

    @Test func dataPersistsAcrossStoreInstances() {
        let firstStore = makeStore()
        firstStore.add(title: "Persisted task", tag: "home")

        let secondStore = TaskStore(fileURL: tempFileURL)
        #expect(secondStore.items.count == 1)
        #expect(secondStore.items.first?.title == "Persisted task")
        #expect(secondStore.items.first?.tag == "home")
    }

    @Test func endDateRoundTripsThroughSaveAndReload() throws {
        let firstStore = makeStore()
        let item = firstStore.add(title: "Meeting", dueDate: .now)
        let end = Date.now.addingTimeInterval(3600)
        firstStore.update(item.id, title: "Meeting", notes: nil, dueDate: item.dueDate, endDate: end, tag: nil)

        let secondStore = TaskStore(fileURL: tempFileURL)
        // Compare to the nearest second — ISO8601 round-tripping can lose sub-second precision.
        let reloadedEnd = try #require(secondStore.items.first?.endDate)
        #expect(abs(reloadedEnd.timeIntervalSince(end)) < 1)
    }

    @Test func missingFileLoadsAsEmptyRatherThanCrashing() {
        let store = TaskStore(fileURL: tempFileURL) // file doesn't exist yet
        #expect(store.items.isEmpty)
    }

    @Test func unicodeAndEmojiTitleSurvivesSaveAndReload() {
        let firstStore = makeStore()
        firstStore.add(title: "Buy 🥛 milk — café run, naïve résumé 日本語")

        let secondStore = TaskStore(fileURL: tempFileURL)
        #expect(secondStore.items.first?.title == "Buy 🥛 milk — café run, naïve résumé 日本語")
    }

    @Test func manyRapidAddsAllPersist() {
        let store = makeStore()
        for index in 0..<200 {
            store.add(title: "Task \(index)")
        }
        #expect(store.items.count == 200)

        let reloaded = TaskStore(fileURL: tempFileURL)
        #expect(reloaded.items.count == 200)
    }

    @Test func hasOverdueItemsReflectsOnlyIncompletePastDueItems() {
        let store = makeStore()
        #expect(!store.hasOverdueItems)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let overdue = store.add(title: "Late thing", dueDate: yesterday)
        #expect(store.hasOverdueItems)

        store.toggleCompletion(overdue.id)
        #expect(!store.hasOverdueItems) // completing it should clear the "overdue" signal

        store.toggleCompletion(overdue.id) // undo
        let futureItem = store.add(title: "Future thing", dueDate: Calendar.current.date(byAdding: .day, value: 5, to: .now))
        #expect(store.hasOverdueItems) // the original overdue item is still incomplete
        _ = futureItem
    }

    @Test func completingARecurringItemAdvancesItInsteadOfMarkingItDone() {
        let store = makeStore()
        let due = Date.now
        let item = store.add(title: "Standup", dueDate: due)
        store.update(item.id, title: "Standup", notes: nil, dueDate: due, endDate: nil, tag: nil, recurrenceRule: .daily)

        store.toggleCompletion(item.id)

        let updated = store.items[0]
        #expect(!updated.isCompleted) // rolled forward, not sitting in Completed
        #expect(updated.completedDate != nil) // still records that it happened
        let expectedNext = Calendar.current.date(byAdding: .day, value: 1, to: due)!
        #expect(Calendar.current.isDate(updated.dueDate!, equalTo: expectedNext, toGranularity: .minute))
    }

    @Test func completingARecurringItemWithEndDatePreservesDuration() {
        let store = makeStore()
        let due = Date.now
        let end = due.addingTimeInterval(3600)
        let item = store.add(title: "Focus block", dueDate: due)
        store.update(item.id, title: "Focus block", notes: nil, dueDate: due, endDate: end, tag: nil, recurrenceRule: .daily)

        store.toggleCompletion(item.id)

        let updated = store.items[0]
        let duration = updated.endDate!.timeIntervalSince(updated.dueDate!)
        #expect(abs(duration - 3600) < 1)
    }

    @Test func nonRecurringItemStillCompletesNormally() {
        let store = makeStore()
        let item = store.add(title: "One-off", dueDate: .now)

        store.toggleCompletion(item.id)

        #expect(store.items[0].isCompleted)
        #expect(store.items[0].dueDate == item.dueDate) // unchanged, no recurrence to advance
    }

    @Test func updateDropsRecurrenceWhenThereIsNoStartDate() {
        let store = makeStore()
        let item = store.add(title: "Someday task")

        store.update(item.id, title: "Someday task", notes: nil, dueDate: nil, endDate: nil, tag: nil, recurrenceRule: .weekly)

        #expect(store.items[0].recurrenceRule == nil)
    }

    @Test func preExistingFileWithoutPriorityFieldMigratesCleanly() throws {
        // Mirrors a reminders.json written before `priority` existed, when the field
        // was a plain `isFlagged` bool — this must load as a normal reminder with
        // `.none` priority, not get treated as corrupted and backed up/discarded.
        let legacyJSON = """
        [{
            "id": "\(UUID().uuidString)",
            "title": "Old-format reminder",
            "isCompleted": false,
            "isFlagged": true,
            "createdDate": "2026-01-01T00:00:00Z"
        }]
        """
        try Data(legacyJSON.utf8).write(to: tempFileURL)

        let store = TaskStore(fileURL: tempFileURL)

        #expect(store.items.count == 1)
        #expect(store.items.first?.title == "Old-format reminder")
        #expect(store.items.first?.priority == Priority.none) // `.none` alone is ambiguous with Optional.none here
    }

    @Test func corruptedFileIsBackedUpRatherThanSilentlyDiscarded() throws {
        try Data("{ this is not valid json at all".utf8).write(to: tempFileURL)

        let store = TaskStore(fileURL: tempFileURL)
        #expect(store.items.isEmpty) // starts fresh rather than crashing…

        // …but the original unreadable file must still exist somewhere, never just gone.
        let directory = tempFileURL.deletingLastPathComponent()
        let baseName = tempFileURL.deletingPathExtension().lastPathComponent
        let siblings = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let backups = siblings.filter { $0.hasPrefix("\(baseName).corrupted-") }
        #expect(backups.count == 1)

        for name in backups {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
