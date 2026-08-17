import Foundation

/// Renders scheduled reminders as a standard iCalendar (.ics) file — a bridge out of
/// Loop rather than another Loop-only view, so the same reminders can show up in
/// Calendar.app or any other calendar that reads .ics. Only reminders with a due date
/// are included; an undated one has nothing to put on a calendar. Completed reminders
/// are left out too — this is meant to mirror "what's ahead," not a history log.
public enum ICSExport {
    public static func calendar(for items: [ReminderItem], generatedAt: Date = .now) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Loop//Reminders Export//EN",
            "CALSCALE:GREGORIAN"
        ]

        let exportable = items.filter { !$0.isCompleted && $0.dueDate != nil }
        for item in exportable {
            lines.append(contentsOf: event(for: item, dateFormatter: dateFormatter, generatedAt: generatedAt))
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    private static func event(for item: ReminderItem, dateFormatter: DateFormatter, generatedAt: Date) -> [String] {
        guard let start = item.dueDate else { return [] }
        // A calendar event with neither DTEND nor DURATION renders inconsistently
        // across clients — default to a short 15-minute block for reminders that
        // don't have their own end time, rather than leave it ambiguous.
        let end = item.endDate ?? start.addingTimeInterval(15 * 60)

        var lines = [
            "BEGIN:VEVENT",
            "UID:\(item.id.uuidString)@loop-app",
            "DTSTAMP:\(dateFormatter.string(from: generatedAt))",
            "DTSTART:\(dateFormatter.string(from: start))",
            "DTEND:\(dateFormatter.string(from: end))",
            "SUMMARY:\(escape(item.title))"
        ]
        if let notes = item.notes, !notes.isEmpty {
            lines.append("DESCRIPTION:\(escape(notes))")
        }
        if let rule = item.recurrenceRule {
            lines.append("RRULE:\(rrule(for: rule))")
        }
        lines.append("END:VEVENT")
        return lines
    }

    private static func rrule(for rule: RecurrenceRule) -> String {
        switch rule {
        case .daily: return "FREQ=DAILY"
        case .weekly: return "FREQ=WEEKLY"
        case .weekdays: return "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        }
    }

    /// Escapes the characters iCalendar TEXT values require escaped. Backslash must be
    /// escaped first — otherwise the escapes just added for comma/semicolon/newline
    /// would themselves get doubled up on a second pass.
    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
