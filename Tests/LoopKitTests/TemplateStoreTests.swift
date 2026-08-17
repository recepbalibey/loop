import Testing
@testable import LoopKit
import Foundation

@Suite(.serialized)
final class TemplateStoreTests {
    private let tempFileURL: URL

    init() {
        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopKitTemplateTests-\(UUID().uuidString).json")
    }

    deinit {
        try? FileManager.default.removeItem(at: tempFileURL)
    }

    private func makeStore() -> TemplateStore {
        TemplateStore(fileURL: tempFileURL)
    }

    @Test func addInsertsTemplate() {
        let store = makeStore()
        let template = store.add(title: "Weekly Standup Prep", tag: "work", durationMinutes: 30, priority: .medium)
        #expect(store.templates.count == 1)
        #expect(store.templates.first?.id == template.id)
        #expect(store.templates.first?.durationMinutes == 30)
        #expect(store.templates.first?.priority == .medium)
    }

    @Test func deleteRemovesTemplate() {
        let store = makeStore()
        let template = store.add(title: "Temporary")
        #expect(store.templates.count == 1)

        store.delete(template.id)
        #expect(store.templates.isEmpty)
    }

    @Test func templatesPersistAcrossStoreInstances() {
        let firstStore = makeStore()
        firstStore.add(title: "Persisted template", notes: "Some notes", tag: "home")

        let secondStore = TemplateStore(fileURL: tempFileURL)
        #expect(secondStore.templates.count == 1)
        #expect(secondStore.templates.first?.title == "Persisted template")
        #expect(secondStore.templates.first?.notes == "Some notes")
    }

    @Test func missingFileLoadsAsEmptyRatherThanCrashing() {
        let store = TemplateStore(fileURL: tempFileURL)
        #expect(store.templates.isEmpty)
    }
}
