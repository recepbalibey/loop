import Foundation

extension Date {
    /// Rounds up to the nearest 5 minutes — shared by anywhere that defaults a
    /// freshly-scheduled block to "now" (the Edit window's schedule toggle, applying a
    /// reminder template), so it never lands on an odd off-by-seconds value. Uses
    /// `calendar.date(byAdding:)` rather than reconstructing components by hand so
    /// minute-60 overflow (e.g. rounding up from :58) correctly rolls into the next
    /// hour instead of producing an invalid time.
    func roundedUpToNearestFiveMinutes(calendar: Calendar = .current) -> Date {
        let remainder = calendar.component(.minute, from: self) % 5
        let rounded = remainder == 0 ? self : calendar.date(byAdding: .minute, value: 5 - remainder, to: self) ?? self
        return calendar.date(bySetting: .second, value: 0, of: rounded) ?? rounded
    }
}
