import Foundation

/// A reusable starting point for a reminder you create often — captures everything
/// about a reminder except *when* it happens, since that's usually the one thing that
/// changes each time (today's standup prep isn't tomorrow's).
public struct ReminderTemplate: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var notes: String?
    public var tag: String?
    /// If set, applying this template starts a scheduled block right now, for this
    /// many minutes — matching the app's existing "start + duration" model rather
    /// than baking in a specific clock time that wouldn't make sense on reuse.
    public var durationMinutes: Int?
    public var priority: Priority

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        tag: String? = nil,
        durationMinutes: Int? = nil,
        priority: Priority = .none
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.tag = tag
        self.durationMinutes = durationMinutes
        self.priority = priority
    }
}
