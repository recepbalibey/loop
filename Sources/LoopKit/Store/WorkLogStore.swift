import Foundation
import Observation

/// JSON-backed daily work log. It has its own file so a problem in this feature can
/// never modify the user's reminders or templates.
@Observable
public final class WorkLogStore {
    public private(set) var days: [WorkLogDay] = []
    public let fileURL: URL

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let directory = appSupport.appendingPathComponent("Loop", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("work-log.json")
        }
        load()
    }

    public func day(for date: Date, calendar: Calendar = .current) -> WorkLogDay? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    public func entries(for date: Date, calendar: Calendar = .current) -> [WorkLogEntry] {
        day(for: date, calendar: calendar)?.entries ?? []
    }

    public func isLocked(on date: Date, calendar: Calendar = .current) -> Bool {
        day(for: date, calendar: calendar)?.isLocked ?? false
    }

    /// Adds text to the current calendar day. Empty notes and locked days are rejected
    /// rather than creating invisible or editable-after-review records.
    @discardableResult
    public func append(_ text: String, at date: Date = .now, calendar: Calendar = .current) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let dayStart = calendar.startOfDay(for: date)
        if let index = days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            guard !days[index].isLocked else { return false }
            days[index].entries.append(WorkLogEntry(createdAt: date, text: trimmed))
        } else {
            days.append(WorkLogDay(date: dayStart, entries: [WorkLogEntry(createdAt: date, text: trimmed)]))
            days.sort { $0.date < $1.date }
        }
        save()
        return true
    }

    /// Locks all earlier days and the current day once the configured work-day end has
    /// passed. This is called when Loop launches, prompts, and refreshes its schedule,
    /// so read-only status is preserved even if the 23:00 notification is ignored.
    public func lockFinishedDays(now: Date = .now, workDayEndsAt endTime: TimeOfDay, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        var didChange = false
        for index in days.indices where !days[index].isLocked {
            let shouldLock: Bool
            if days[index].date < today {
                shouldLock = true
            } else if calendar.isDate(days[index].date, inSameDayAs: now) {
                shouldLock = now >= endTime.applied(to: now, calendar: calendar)
            } else {
                shouldLock = false
            }
            if shouldLock {
                days[index].isLocked = true
                didChange = true
            }
        }
        if didChange { save() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? decoder.decode([WorkLogDay].self, from: data) {
            days = decoded.sorted { $0.date < $1.date }
        } else {
            backUpUnreadableFile()
        }
    }

    private func backUpUnreadableFile() {
        let timestamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("work-log.corrupted-\(timestamp).json")
        try? FileManager.default.copyItem(at: fileURL, to: backupURL)
    }

    private func save() {
        guard let data = try? encoder.encode(days) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
