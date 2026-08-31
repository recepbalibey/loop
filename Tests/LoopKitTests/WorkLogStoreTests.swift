import Testing
@testable import LoopKit
import Foundation

@Suite(.serialized)
final class WorkLogStoreTests {
    private let tempFileURL: URL

    init() {
        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopKitWorkLogTests-\(UUID().uuidString).json")
    }

    deinit { try? FileManager.default.removeItem(at: tempFileURL) }

    private func date(_ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: hour))!
    }

    @Test func appendsEntriesToTheSameDay() {
        let store = WorkLogStore(fileURL: tempFileURL)
        let morning = date(10)
        let afternoon = date(11)

        #expect(store.append("Outlined the proposal", at: morning))
        #expect(store.append("Sent it for review", at: afternoon))
        #expect(store.days.count == 1)
        #expect(store.entries(for: morning).map(\.text) == ["Outlined the proposal", "Sent it for review"])
    }

    @Test func lockedDayRejectsNewEntries() {
        let store = WorkLogStore(fileURL: tempFileURL)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(store.append("Initial note", at: date))
        store.lockFinishedDays(now: date.addingTimeInterval(86_400), workDayEndsAt: TimeOfDay(hour: 23, minute: 0)!)

        #expect(store.isLocked(on: date))
        #expect(!store.append("Too late", at: date))
        #expect(store.entries(for: date).count == 1)
    }

    @Test func persistsEntriesAcrossStoreInstances() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = WorkLogStore(fileURL: tempFileURL)
        #expect(first.append("Created a test", at: date))

        let second = WorkLogStore(fileURL: tempFileURL)
        #expect(second.entries(for: date).first?.text == "Created a test")
    }

    @Test func writesReadableMarkdownArchive() throws {
        let store = WorkLogStore(fileURL: tempFileURL)
        let loggedAt = date(10)
        #expect(store.append("Completed the threat model", at: loggedAt))

        let archive = store.archiveDirectoryURL.appendingPathComponent("2026-08-26.md")
        let contents = try String(contentsOf: archive, encoding: .utf8)
        #expect(contents.contains("# Work Log: 2026-08-26"))
        #expect(contents.contains("Completed the threat model"))
    }
}
