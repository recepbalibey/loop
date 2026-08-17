import Foundation

/// Builds and reads back the identifiers Loop registers notifications under.
///
/// A reminder's main alert uses its bare UUID, while each check-in appends a suffix so
/// the occurrences can be cancelled individually. Reading the reminder back out has to
/// account for that suffix: parsing the raw identifier as a UUID works for the main
/// alert and silently fails for every check-in, which is what left the "Mark Done" and
/// "Snooze" buttons on check-in notifications doing nothing at all.
public enum NotificationIdentifier {
    static let checkInMarker = "-checkin-"

    public static func main(for reminderID: UUID) -> String {
        reminderID.uuidString
    }

    public static func checkIn(for reminderID: UUID, index: Int) -> String {
        "\(reminderID.uuidString)\(checkInMarker)\(index)"
    }

    /// The reminder an identifier belongs to, whether it's a main alert or a check-in.
    /// Returns `nil` for identifiers Loop didn't mint for a reminder, such as the
    /// one-off test notification.
    public static func reminderID(from identifier: String) -> UUID? {
        guard let markerRange = identifier.range(of: checkInMarker) else {
            return UUID(uuidString: identifier)
        }
        return UUID(uuidString: String(identifier[identifier.startIndex..<markerRange.lowerBound]))
    }
}
