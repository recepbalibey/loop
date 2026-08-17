import Foundation

public struct ReminderItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var notes: String?
    /// The start time — when a task with just one moment is "due," or the start of a
    /// scheduled block if `endDate` is also set.
    public var dueDate: Date?
    /// Optional end time, for tasks that are really a scheduled block of time rather
    /// than a single instant — e.g. "meeting 2–3pm." Only meaningful when `dueDate` is
    /// also set; always `nil` for plain one-moment reminders. Notifications still fire
    /// at `dueDate` only — the end time is informational, not a second alert.
    public var endDate: Date?
    /// Free-form context tag, e.g. "home", "office" — parsed from "at X" in the input.
    public var tag: String?
    public var isCompleted: Bool
    public var completedDate: Date?
    public var createdDate: Date
    /// How important this reminder is relative to others in the same section — the
    /// primary sort key within a section (see `TaskStore` / row sorting), and a
    /// multi-tier replacement for what used to be a single on/off "flag."
    public var priority: Priority
    /// If set, Loop sends a repeating "still on this?" check-in notification every N
    /// minutes between `dueDate` and `endDate` — for staying on a focused block of work,
    /// not just being alerted once at the start. Only meaningful when both `dueDate` and
    /// `endDate` are set; ignored otherwise.
    public var checkInIntervalMinutes: Int?
    /// If set, completing this reminder advances it to its next occurrence instead of
    /// marking it permanently done — there's no separate "next Tuesday's" item to
    /// create. Only meaningful when `dueDate` is set.
    public var recurrenceRule: RecurrenceRule?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        endDate: Date? = nil,
        tag: String? = nil,
        isCompleted: Bool = false,
        completedDate: Date? = nil,
        createdDate: Date = .now,
        priority: Priority = .none,
        checkInIntervalMinutes: Int? = nil,
        recurrenceRule: RecurrenceRule? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.endDate = endDate
        self.tag = tag
        self.isCompleted = isCompleted
        self.completedDate = completedDate
        self.createdDate = createdDate
        self.priority = priority
        self.checkInIntervalMinutes = checkInIntervalMinutes
        self.recurrenceRule = recurrenceRule
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, dueDate, endDate, tag, isCompleted, completedDate, createdDate
        case priority, checkInIntervalMinutes, recurrenceRule
    }

    // Hand-written rather than synthesized so a `reminders.json` saved before `priority`
    // existed (when this field was still a plain `isFlagged` bool) decodes cleanly
    // instead of failing entirely and getting swept into a `.corrupted-*.json` backup —
    // a missing `priority` key just defaults to `.none`, same as any other reminder
    // created before priorities existed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        tag = try container.decodeIfPresent(String.self, forKey: .tag)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        completedDate = try container.decodeIfPresent(Date.self, forKey: .completedDate)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .none
        checkInIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .checkInIntervalMinutes)
        recurrenceRule = try container.decodeIfPresent(RecurrenceRule.self, forKey: .recurrenceRule)
    }
}

/// Four tiers rather than a plain on/off flag — lets "today" hold both a couple of
/// must-do items and a longer tail of lower-stakes ones without them all looking
/// equally urgent.
public enum Priority: Int, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    public var id: Int { rawValue }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .none: return "No Priority"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    public var symbolName: String {
        self == .none ? "flag" : "flag.fill"
    }
}

/// How a reminder repeats. Deliberately just three common patterns rather than a full
/// RFC 5545-style recurrence engine — this is a personal reminders app, not a calendar
/// server, and "every day / every weekday / every week" covers the overwhelming
/// majority of real recurring reminders without needing a rule-builder UI.
public enum RecurrenceRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily = "Daily"
    case weekdays = "Weekdays"
    case weekly = "Weekly"

    public var id: String { rawValue }

    /// The next date after `date` this rule lands on, preserving `date`'s time-of-day.
    public func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .weekdays:
            var candidate = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while calendar.isDateInWeekend(candidate) {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate
        }
    }
}

public enum ReminderSection: String, CaseIterable, Identifiable, Sendable {
    case overdue = "Overdue"
    case today = "Today"
    case tomorrow = "Tomorrow"
    case thisWeek = "This Week"
    case later = "Later"
    case someday = "Someday"

    public var id: String { rawValue }
}

public extension ReminderItem {
    /// Which group this item belongs to, based on its due date and completion state.
    var section: ReminderSection { section(now: .now) }

    /// The same grouping, against an explicit "now" so it can be tested deterministically
    /// rather than only behaving one way on the day the test happens to run. Day-level
    /// sections deliberately win over the coarser week grouping: on the last day of a
    /// week, the day right after the week ends is genuinely "Tomorrow," and labelling it
    /// "Later" would be worse, not more consistent.
    ///
    /// "This Week" covers whatever's left of the current calendar week after tomorrow;
    /// everything beyond it lands in "Later" rather than blurring together with things
    /// due next month.
    func section(now: Date, calendar: Calendar = .current) -> ReminderSection {
        guard let dueDate else { return .someday }
        if !isCompleted, dueDate < calendar.startOfDay(for: now) {
            return .overdue
        }
        if calendar.isDate(dueDate, inSameDayAs: now) {
            return .today
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(dueDate, inSameDayAs: tomorrow) {
            return .tomorrow
        }
        if let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now), currentWeek.contains(dueDate) {
            return .thisWeek
        }
        return .later
    }

    /// Whether this reminder should have a system notification scheduled for its due
    /// date — true only for incomplete reminders with a due date still in the future.
    /// Pulled out as pure, dependency-free logic so it's testable without touching
    /// UserNotifications (which needs a running app + user permission to do anything).
    func needsScheduledNotification(now: Date = .now) -> Bool {
        guard !isCompleted, let dueDate else { return false }
        return dueDate > now
    }

    /// The moments to send a "still on it?" check-in at: every `checkInIntervalMinutes`
    /// step strictly between the start and end of the block. It starts one interval
    /// *after* the start (the start already gets the main notification) and stops before
    /// the end (the block being over needs no check-in).
    ///
    /// Lives here rather than in the scheduler so the interval arithmetic is testable
    /// without a running app: verifying it used to mean launching Loop and dumping the
    /// notification centre's pending requests by hand.
    ///
    /// The check-ins still ahead of `now`, each paired with the index it occupies in the
    /// full schedule.
    ///
    /// The index comes from the whole schedule rather than the filtered result so an
    /// occurrence keeps the same notification identifier as the block progresses.
    /// Re-numbering the survivors from zero would make 15:30 register under the id that
    /// 15:15 already holds, and the two would fight each other on every sync.
    ///
    /// This exists because scheduling used to hang off `needsScheduledNotification`,
    /// which is false once the start time passes. That meant a block's remaining
    /// check-ins were treated as stale and cancelled the moment anything triggered a
    /// resync mid-block, so the feature quietly stopped working exactly when it was
    /// supposed to be doing its job.
    func upcomingCheckIns(now: Date = .now, limit: Int = 48) -> [(index: Int, date: Date)] {
        guard !isCompleted else { return [] }
        return checkInDates(limit: limit).enumerated()
            .filter { $0.element > now }
            .map { (index: $0.offset, date: $0.element) }
    }

    /// - Parameter limit: A defensive cap. A one-minute interval across an all-day block
    ///   would otherwise try to register hundreds of system notifications.
    func checkInDates(limit: Int = 48) -> [Date] {
        guard let start = dueDate,
              let end = endDate,
              let minutes = checkInIntervalMinutes,
              minutes > 0
        else { return [] }

        let interval = TimeInterval(minutes * 60)
        var dates: [Date] = []
        var next = start.addingTimeInterval(interval)
        while next < end, dates.count < limit {
            dates.append(next)
            next = next.addingTimeInterval(interval)
        }
        return dates
    }
}
