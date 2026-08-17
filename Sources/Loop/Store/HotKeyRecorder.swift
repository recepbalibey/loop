import AppKit
import Combine

/// Captures the next key combination pressed while "recording," for the Preferences
/// shortcut-recorder control. A local `NSEvent` monitor rather than any global
/// mechanism — it only needs to see keys while Loop's own Preferences window has
/// focus and the record button is active, not system-wide.
final class HotKeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?

    func startRecording(onCapture: @escaping (UInt16, NSEvent.ModifierFlags) -> Void) {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Require at least one modifier — a global hotkey with no modifier at all
            // would swallow that plain key everywhere, which is never what someone
            // recording a shortcut actually wants.
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !modifiers.isEmpty else { return event }
            onCapture(event.keyCode, modifiers)
            self?.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

enum HotKeyFormatter {
    /// Virtual keycodes for the keys someone would realistically pick for a global
    /// app shortcut — letters, digits, and a few named keys. Not exhaustive (there's
    /// no simple stable API mapping every keycode to a display glyph), but covers the
    /// realistic range; anything outside it just falls back to "Key <code>".
    private static let keyLabels: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
        40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
        32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        49: "Space", 36: "Return", 48: "Tab", 53: "Escape"
    ]

    static func label(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        symbols += keyLabels[keyCode] ?? "Key \(keyCode)"
        return symbols
    }
}
