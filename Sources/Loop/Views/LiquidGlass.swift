import SwiftUI

/// A translucent frosted background for the main panel.
///
/// This deliberately uses the long-established `Material` API rather than macOS 26's
/// newer `.glassEffect()`. `.glassEffect()` is designed around SwiftUI owning the
/// window (a real Scene); our panel is hosted inside a manually-created `NSPopover`
/// (see `AppDelegate.setupPopover`), and in that hosting context it was rendering as a
/// flat, opaque dark rectangle instead of a translucent blur — confirmed visually, not
/// theoretical. `Material` is the same mechanism macOS itself has used for popover-style
/// chrome for years and is reliable in exactly this situation.
struct LiquidGlassBackground: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background(
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                HolographicSheen(cornerRadius: cornerRadius)
            }
        )
    }
}

/// A slow, faint diagonal sheen drifting across the panel — the "liquid" half of
/// "liquid glass": a hint of iridescent motion under the frosted material rather than
/// a static pane of blur. Kept very low-opacity and blended with `.plusLighter` so it
/// only ever brightens, never muddies, the material underneath or the text sitting on
/// top of it.
private struct HolographicSheen: View {
    var cornerRadius: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10) / 10
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.05), location: max(0, phase - 0.12)),
                            .init(color: .white.opacity(0.10), location: phase),
                            .init(color: .white.opacity(0.05), location: min(1, phase + 0.12)),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: cornerRadius))
    }
}

/// Small rounded pill used for the date / tag chips inline in the add row.
struct Chip: View {
    var systemImage: String
    var text: String
    var color: Color = .accentColor

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 13, weight: .medium))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
    }
}
