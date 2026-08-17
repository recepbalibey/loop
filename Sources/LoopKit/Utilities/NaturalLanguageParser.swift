import Foundation

/// The result of parsing a raw line of typed text into a task.
public struct ParsedInput: Equatable, Sendable {
    public var cleanTitle: String
    public var date: Date?
    public var tag: String?
}

/// Lightweight natural-language parsing for the combined search/add bar.
///
/// Dates are detected with the system's `NSDataDetector`, the same engine behind
/// Mail/Messages/Reminders — it understands "today", "tomorrow", "next friday",
/// "in 3 days", explicit dates, and times, without any network calls.
/// A trailing "at <place>" is treated as a free-form context tag.
public enum NaturalLanguageParser {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )

    private static let tagPattern =
        #"\bat\s+([A-Za-z][\w'-]*(?:\s+[A-Za-z][\w'-]*){0,2})\s*$"#
    private static let tagPrefixPattern = #"^at\s+"#
    private static let collapseWhitespacePattern = #"\s{2,}"#
    private static let danglingPrepositionPattern = #"\s+(on|at|by|for|in)$"#

    /// Vague phrases NSDataDetector doesn't reliably resolve on its own, checked before
    /// falling back to the system detector. Longest/most-specific phrases first.
    private static let vaguePhrases: [(pattern: String, resolve: () -> Date)] = [
        (#"\bbefore\s+end\s+of\s+day\b"#, { endOfToday() }),
        (#"\bend\s+of\s+day\b"#, { endOfToday() }),
        (#"\beod\b"#, { endOfToday() }),
        (#"\btonight\b"#, { today(hour: 20) }),
        (#"\bthis\s+evening\b"#, { today(hour: 18) }),
        (#"\bthis\s+afternoon\b"#, { today(hour: 14) }),
        (#"\bthis\s+morning\b"#, { today(hour: 9) }),
        (#"\bbefore\s+end\s+of\s+week\b"#, { endOfWeek() }),
        (#"\bend\s+of\s+week\b"#, { endOfWeek() }),
        (#"\beow\b"#, { endOfWeek() })
    ]

    public static func parse(_ raw: String) -> ParsedInput {
        var text = raw
        var date: Date?

        for phrase in vaguePhrases {
            if let range = text.range(of: phrase.pattern, options: [.regularExpression, .caseInsensitive]) {
                date = phrase.resolve()
                text.removeSubrange(range)
                break
            }
        }

        if date == nil, let detector {
            let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = detector.matches(in: text, options: [], range: fullRange)
            if let match = matches.first, let matchRange = Range(match.range, in: text), let matchDate = match.date {
                date = matchDate
                text.removeSubrange(matchRange)
            }
        }

        var tag: String?
        if let tagRange = text.range(of: tagPattern, options: .regularExpression) {
            var matched = String(text[tagRange])
            matched = matched.replacingOccurrences(of: tagPrefixPattern, with: "", options: .regularExpression)
            let trimmed = matched.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                tag = trimmed
            }
            text.removeSubrange(tagRange)
        }

        var cleaned = text
            .replacingOccurrences(of: collapseWhitespacePattern, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Removing a date phrase from the middle/end of a sentence can leave a
        // dangling preposition behind ("Submit invoices on" once Friday is cut).
        while let range = cleaned.range(of: danglingPrepositionPattern, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        let title = cleaned.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
        return ParsedInput(cleanTitle: title, date: date, tag: tag)
    }

    private static func today(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
    }

    private static func endOfToday() -> Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: .now) ?? .now
    }

    private static func endOfWeek() -> Date {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: .now)
        // Calendar weekday: 1 = Sunday ... 6 = Friday, 7 = Saturday.
        let daysUntilFriday = (6 - weekday + 7) % 7
        let friday = calendar.date(byAdding: .day, value: daysUntilFriday, to: .now) ?? .now
        return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: friday) ?? friday
    }

    /// Short chip label for a parsed/assigned date, e.g. "Today", "Tomorrow", "Fri, 28 Aug".
    public static func dateChipLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let formatter = DateFormatter()
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: .now)
        formatter.dateFormat = sameYear ? "EEE, d MMM" : "EEE, d MMM yyyy"
        return formatter.string(from: date)
    }

    /// Fuller row subtitle label, e.g. "Tue, 28 Jul 10:00" or "Today".
    public static func dueLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let hasTime = calendar.component(.hour, from: date) != 0 || calendar.component(.minute, from: date) != 0
        let base = dateChipLabel(for: date)
        guard hasTime else { return base }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        return "\(base) \(timeFormatter.string(from: date))"
    }
}
