import Testing
@testable import LoopKit
import Foundation
import Observation

/// AppDelegate (in the app target, not unit-testable directly) uses
/// `withObservationTracking(_:onChange:)` to recolor the menu bar icon whenever
/// `TaskStore.items` changes. This proves that mechanism actually fires for our
/// `@Observable` store, since a broken assumption here would silently mean the
/// icon never updates and there's no way to notice that visually in this environment.
struct ObservationTrackingTests {
    @Test func storeItemsMutationTriggersObservationOnChange() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoopKitTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let store = TaskStore(fileURL: tempURL)

        actor Flag {
            private(set) var value = false
            func set() { value = true }
        }
        let flag = Flag()

        func observe() {
            withObservationTracking {
                _ = store.items
            } onChange: {
                Task { await flag.set() }
            }
        }
        observe()

        store.add(title: "Trigger change")

        // onChange can be coalesced to the next run-loop turn rather than firing
        // perfectly synchronously, so poll briefly instead of asserting instantly.
        for _ in 0..<50 {
            if await flag.value { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await flag.value)
    }
}
