import SwiftUI

/// A small curated palette rather than a full color wheel — enough to make the app
/// feel personalized without a picker UI heavier than the rest of this app's controls.
enum AccentColorOption: String, CaseIterable, Identifiable {
    case system
    case blue
    case purple
    case pink
    case orange
    case green
    case teal
    case red

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// `nil` for `.system` — meaning "use the platform's own accent color," which a
    /// view resolves by falling back to `Color.accentColor` itself.
    var color: Color? {
        switch self {
        case .system: return nil
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .orange: return .orange
        case .green: return .green
        case .teal: return .teal
        case .red: return .red
        }
    }
}

extension View {
    /// Reads the user's chosen accent color from the same `@AppStorage` key every
    /// other view reads, resolving `.system`/an unrecognized value to the platform
    /// default. A plain function rather than a property wrapper so it can be called
    /// from anywhere a `View` already has access to `@AppStorage`-backed state.
    func resolvedAccentColor(from rawValue: String) -> Color {
        AccentColorOption(rawValue: rawValue)?.color ?? .accentColor
    }
}
