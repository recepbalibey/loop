import Foundation
import Observation

/// Single source of truth for reminders. Backed by a JSON file in Application Support —
/// everything lives on this Mac, nothing leaves it.
@Observable
public final class TaskStore {
    public private(set) var items: [ReminderItem] = []

    /// Where reminders are stored on disk — exposed so the app can, for example,
    /// offer a "reveal in Finder" button. Read-only from outside the store.
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

    /// - Parameter fileURL: Override the backing store location — used by tests to avoid
    ///   touching the real `~/Library/Application Support/Loop/reminders.json`. Defaults
    ///   to that real location for normal app use.
    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let directory = appSupport.appendingPathComponent("Loop", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("reminders.json")
        }
        load()
    }

    @discardableResult
    public func add(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        endDate: Date? = nil,
        tag: String? = nil,
        priority: Priority = .none
    ) -> ReminderItem {
        let item = ReminderItem(title: title, notes: notes, dueDate: dueDate, endDate: endDate, tag: tag, priority: priority)
        items.append(item)
        save()
        return item
    }

    /// For a plain reminder, toggles `isCompleted` as usual. For a *recurring* one
    /// that's being marked done, there's no separate "next occurrence" item to create —
    /// instead this advances its own `dueDate` (and `endDate`, preserving the same
    /// duration) to the next occurrence and leaves it incomplete, so it simply reappears
    /// under its new date rather than piling up in the Completed section. Recurring
    /// reminders intentionally don't support Undo the way a one-off completion does —
    /// see `MenuBarContentView.toggle`.
    public func toggleCompletion(_ id: ReminderItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        if !items[index].isCompleted, let rule = items[index].recurrenceRule, let due = items[index].dueDate {
            let nextDue = rule.nextOccurrence(after: due)
            if let end = items[index].endDate {
                items[index].endDate = nextDue.addingTimeInterval(end.timeIntervalSince(due))
            }
            items[index].dueDate = nextDue
            items[index].completedDate = .now
            save()
            return
        }

        items[index].isCompleted.toggle()
        items[index].completedDate = items[index].isCompleted ? .now : nil
        save()
    }

    public func setPriority(_ id: ReminderItem.ID, _ priority: Priority) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].priority = priority
        save()
    }

    /// Repositions `id` to sit directly before `targetID` in the backing array. This is
    /// the manual-order axis drag-to-reorder writes to — see `sortWithinSection` in
    /// `MenuBarContentView`, which uses each item's position here as the tiebreaker
    /// once same-priority items are grouped together. A no-op if either id is missing
    /// or they're the same item.
    public func moveItem(_ id: ReminderItem.ID, toBeBefore targetID: ReminderItem.ID) {
        guard id != targetID, let fromIndex = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: fromIndex)
        let toIndex = items.firstIndex(where: { $0.id == targetID }) ?? items.count
        items.insert(item, at: toIndex)
        save()
    }

    public func reschedule(_ id: ReminderItem.ID, to date: Date?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].dueDate = date
        // A quick reschedule (e.g. the "Today"/"Tomorrow" context menu shortcuts)
        // doesn't know about any previously-set end time, and an end time from before
        // could now be nonsensical relative to the new start — clear it rather than
        // risk leaving a stale, invalid range. Setting a new end time is always
        // available again via Edit.
        items[index].endDate = nil
        save()
    }

    public func update(
        _ id: ReminderItem.ID,
        title: String,
        notes: String?,
        dueDate: Date?,
        endDate: Date?,
        tag: String?,
        checkInIntervalMinutes: Int? = nil,
        recurrenceRule: RecurrenceRule? = nil
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = title
        items[index].notes = notes
        items[index].dueDate = dueDate
        // An end time only makes sense alongside a start time, and only when it's
        // actually after it — otherwise silently drop it rather than store nonsense.
        if let dueDate, let endDate, endDate > dueDate {
            items[index].endDate = endDate
        } else {
            items[index].endDate = nil
        }
        // Check-ins only make sense across an actual bounded block of time — drop them
        // silently the same way a nonsensical end date gets dropped above.
        items[index].checkInIntervalMinutes = items[index].endDate != nil ? checkInIntervalMinutes : nil
        // Recurrence only makes sense with a start time to recur from.
        items[index].recurrenceRule = dueDate != nil ? recurrenceRule : nil
        items[index].tag = tag
        save()
    }

    public func delete(_ id: ReminderItem.ID) {
        items.removeAll { $0.id == id }
        save()
    }

    /// Removes every completed reminder at once — the Completed section is now
    /// permanent (it used to just vanish after a few seconds), so this is how someone
    /// tidies it up once they no longer need the record.
    public func clearCompleted() {
        items.removeAll { $0.isCompleted }
        save()
    }

    /// Whether any incomplete reminder is currently overdue — cheap enough to check
    /// on every UI refresh (e.g. to recolor a menu bar glyph) without extra bookkeeping.
    public var hasOverdueItems: Bool {
        items.contains { $0.section == .overdue }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? decoder.decode([ReminderItem].self, from: data) {
            items = decoded
        } else {
            // The file exists but isn't valid JSON we recognize (corruption, a manual
            // edit gone wrong, a future format we don't understand yet). Never let that
            // silently vanish someone's reminders — preserve the original bytes next to
            // it before starting fresh, so recovery is always possible.
            backUpUnreadableFile()
            items = []
        }
    }

    private func backUpUnreadableFile() {
        let timestamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.deletingPathExtension().lastPathComponent).corrupted-\(timestamp).json")
        try? FileManager.default.copyItem(at: fileURL, to: backupURL)
    }

    private func save() {
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
