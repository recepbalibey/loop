import Foundation
import Observation

/// Persists saved reminder templates to their own JSON file, alongside but separate
/// from `TaskStore`'s `reminders.json` — templates are a small convenience list, not
/// the user's actual reminders, and keeping them in a different file means a template
/// read/write can never risk touching real reminder data.
@Observable
public final class TemplateStore {
    public private(set) var templates: [ReminderTemplate] = []

    public let fileURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let directory = appSupport.appendingPathComponent("Loop", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("templates.json")
        }
        load()
    }

    @discardableResult
    public func add(title: String, notes: String? = nil, tag: String? = nil, durationMinutes: Int? = nil, priority: Priority = .none) -> ReminderTemplate {
        let template = ReminderTemplate(title: title, notes: notes, tag: tag, durationMinutes: durationMinutes, priority: priority)
        templates.append(template)
        save()
        return template
    }

    public func delete(_ id: ReminderTemplate.ID) {
        templates.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL), let decoded = try? decoder.decode([ReminderTemplate].self, from: data) else {
            return
        }
        templates = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(templates) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
