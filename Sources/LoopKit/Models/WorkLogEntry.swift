import Foundation

/// One dated note captured during a work day. Work logs deliberately live apart from
/// reminders: a progress journal is a record of what happened, not another task list.
public struct WorkLogEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let text: String

    public init(id: UUID = UUID(), createdAt: Date = .now, text: String) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
    }
}

/// The immutable record for one calendar day. A day becomes read-only at the configured
/// end of the work day, so notes never bleed into the following day's record.
public struct WorkLogDay: Identifiable, Codable, Equatable, Sendable {
    public let date: Date
    public var entries: [WorkLogEntry]
    public var isLocked: Bool

    public init(date: Date, entries: [WorkLogEntry] = [], isLocked: Bool = false) {
        self.date = date
        self.entries = entries
        self.isLocked = isLocked
    }

    public var id: Date { date }
}
