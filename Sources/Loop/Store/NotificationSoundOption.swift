import Foundation
import UserNotifications

/// The classic macOS alert sound set (the same names under System Settings → Sound →
/// Sound Effects) — a curated, recognizable list rather than exposing every possible
/// sound file, since those names are what people already associate with a specific
/// alert feel.
enum NotificationSoundOption: String, CaseIterable, Identifiable {
    case system = "Default"
    case basso = "Basso"
    case glass = "Glass"
    case hero = "Hero"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case submarine = "Submarine"
    case tink = "Tink"

    var id: String { rawValue }

    /// `UNNotificationSound(named:)` resolves these standard macOS alert sound names
    /// directly — the same names `NSSound(named:)` uses for the Preferences preview
    /// button.
    var unNotificationSound: UNNotificationSound {
        switch self {
        case .system: return .default
        default: return UNNotificationSound(named: UNNotificationSoundName(rawValue))
        }
    }

    static func resolved(from rawValue: String) -> NotificationSoundOption {
        NotificationSoundOption(rawValue: rawValue) ?? .system
    }
}
