import Foundation

/// A 24-hour clock time with no date attached, parsed from and rendered as "HH:mm".
///
/// Pulled out of the Edit window as pure, dependency-free logic so the parsing rules
/// are testable on their own. The view previously parsed this inline, which meant the
/// only way to check "does typing 7:5 do the right thing?" was to run the app and try
/// it by hand.
public struct TimeOfDay: Equatable, Sendable {
    public let hour: Int
    public let minute: Int

    /// Fails rather than clamping for out-of-range values. A typo like "25:00" should
    /// bounce back to the previous value so the mistake is visible, not silently
    /// become 23:00 and look deliberate.
    public init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Parses "HH:mm", tolerating surrounding whitespace and single-digit components
    /// ("7:5" means 07:05), since those are natural things to type.
    public init?(text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        hour = components.hour ?? 0
        minute = components.minute ?? 0
    }

    public var formatted: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// This time-of-day applied to `date`'s calendar day, seconds zeroed.
    public func applied(to date: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? date
    }
}
