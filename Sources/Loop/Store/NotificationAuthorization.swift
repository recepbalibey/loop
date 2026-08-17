import AppKit
import Observation
import UserNotifications

/// Tracks whether macOS will actually deliver Loop's notifications.
///
/// The app's own "Notify me when reminders are due" switch is only half the story: macOS
/// can refuse delivery outright, and until now that failed completely silently. Nothing
/// fired, the bell icon still promised an alert on every scheduled reminder, and there
/// was nothing anywhere explaining why. This models the system side so the UI can be
/// honest about it.
@Observable
final class NotificationAuthorization {
    enum Status {
        /// Not asked yet, or asked and awaiting an answer.
        case undetermined
        case authorized
        case denied

        var blocksDelivery: Bool { self == .denied }
    }

    private(set) var status: Status = .undetermined

    private let center = UNUserNotificationCenter.current()

    /// Re-reads the system setting. Worth calling whenever Loop comes back to the
    /// foreground, since permission can be revoked in System Settings while the app is
    /// running and nothing tells us about it.
    func refresh() {
        center.getNotificationSettings { [weak self] settings in
            let resolved: Status
            switch settings.authorizationStatus {
            case .denied:
                resolved = .denied
            case .authorized, .provisional, .ephemeral:
                resolved = .authorized
            case .notDetermined:
                resolved = .undetermined
            @unknown default:
                // A status this build doesn't recognise shouldn't produce a scary
                // warning. Assume delivery works and let reality prove otherwise.
                resolved = .authorized
            }
            DispatchQueue.main.async { self?.status = resolved }
        }
    }

    func requestIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
            if let error {
                print("Loop: notification authorization failed: \(error)")
            }
            self?.refresh()
        }
    }

    /// Opens the Notifications pane of System Settings. The pane's identifier changed in
    /// Ventura, so the modern one is tried first and the older one is a fallback rather
    /// than leaving the user with a button that appears to do nothing.
    static func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
