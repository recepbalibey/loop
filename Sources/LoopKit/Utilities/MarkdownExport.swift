import Foundation

/// Renders reminders as a plain Markdown checklist — grouped the same way the app
/// itself groups them on screen, so the export reads as a recognizable snapshot of
/// the list rather than a raw data dump.
public enum MarkdownExport {
    public static func checklist(for items: [ReminderItem], generatedAt: Date = .now) -> String {
        var lines: [String] = ["# Loop Reminders"]

        let timestampFormatter = DateFormatter()
        timestampFormatter.dateStyle = .medium
        timestampFormatter.timeStyle = .short
        lines.append("_Exported \(timestampFormatter.string(from: generatedAt))_")
        lines.append("")

        let incomplete = items.filter { !$0.isCompleted }
        let completed = items.filter(\.isCompleted)
        let groups = Dictionary(grouping: incomplete, by: \.section)

        for section in ReminderSection.allCases {
            guard let sectionItems = groups[section], !sectionItems.isEmpty else { continue }
            lines.append("## \(section.rawValue)")
            let sorted = sectionItems.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            lines.append(contentsOf: sorted.map(checklistLine))
            lines.append("")
        }

        if !completed.isEmpty {
            lines.append("## Completed")
            let sorted = completed.sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }
            lines.append(contentsOf: sorted.map(checklistLine))
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func checklistLine(for item: ReminderItem) -> String {
        var line = "- [\(item.isCompleted ? "x" : " ")] \(item.title)"
        if let dueDate = item.dueDate {
            line += " - \(NaturalLanguageParser.dueLabel(for: dueDate))"
        }
        if let tag = item.tag {
            line += " (\(tag))"
        }
        return line
    }
}
