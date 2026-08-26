import Foundation

/// Pure scheduling rules for the daily work log. Keeping this arithmetic out of the
/// notification layer makes the selected interval and work-day boundaries testable.
public struct WorkLogSchedule: Sendable {
    public enum EventKind: Equatable, Sendable {
        case prompt
        case dailyReview
    }

    public struct Event: Equatable, Sendable {
        public let kind: EventKind
        public let date: Date
    }

    public let intervalMinutes: Int
    public let startTime: TimeOfDay
    public let endTime: TimeOfDay

    public init?(intervalMinutes: Int, startTime: TimeOfDay, endTime: TimeOfDay) {
        guard intervalMinutes >= 30,
              startTime.applied(to: Date(timeIntervalSince1970: 0)) < endTime.applied(to: Date(timeIntervalSince1970: 0))
        else { return nil }
        self.intervalMinutes = intervalMinutes
        self.startTime = startTime
        self.endTime = endTime
    }

    /// Upcoming prompts, followed by a final review at the end of each work day. The
    /// limit remains below macOS's 64-pending-notification ceiling.
    public func upcomingEvents(now: Date = .now, limit: Int = 60, calendar: Calendar = .current) -> [Event] {
        guard limit > 0 else { return [] }
        var events: [Event] = []
        let firstDay = calendar.startOfDay(for: now)

        for offset in 0..<14 where events.count < limit {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
            let start = startTime.applied(to: day, calendar: calendar)
            let end = endTime.applied(to: day, calendar: calendar)
            var candidate = start.addingTimeInterval(TimeInterval(intervalMinutes * 60))
            var dayEvents: [Event] = []
            while candidate < end {
                if candidate > now { dayEvents.append(Event(kind: .prompt, date: candidate)) }
                candidate = candidate.addingTimeInterval(TimeInterval(intervalMinutes * 60))
            }
            if end > now { dayEvents.append(Event(kind: .dailyReview, date: end)) }

            let remaining = limit - events.count
            if dayEvents.count <= remaining {
                events.append(contentsOf: dayEvents)
            } else if remaining > 0 {
                // Keep the final review when a cap falls in the middle of a day. A
                // skipped prompt is less harmful than losing the promised daily close.
                events.append(contentsOf: dayEvents.filter { $0.kind == .prompt }.prefix(max(0, remaining - 1)))
                events.append(dayEvents.last!)
            }
        }
        return events.sorted { $0.date < $1.date }
    }
}
