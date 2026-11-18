import SwiftUI

// Always On (docs/research/watch-app-redesign-2026-11.md §4.5.7). With the
// wrist down a workout app stays on screen at a lower update rate. Apple's
// guidance: dim what isn't essential, show controls as stroked outlines with
// dimmed interiors, stop animations, drop sub-second updates, and keep the
// layout the same (HIG Always On; "Designing your app for the Always On
// state"). Taps still wake the app, so outlined buttons stay tappable.
//
// Dimming levels are the app's choice: primary numbers at 85 % white, rings
// at 60 %, outlined labels at 70 %. With Increase Contrast on, numbers stay
// at full white.

extension View {
    /// Primary numbers: full colour when active; white at 85 % (100 % with
    /// Increase Contrast) when the luminance is reduced.
    func alwaysOnPrimary(_ color: Color) -> some View {
        modifier(AlwaysOnPrimary(color: color))
    }

    /// Non-essential content (sparklines, hints): hidden in Always On, with
    /// its space kept so nothing moves.
    func hiddenWhenLuminanceReduced() -> some View {
        modifier(HiddenWhenReduced())
    }

    /// Rings and bars: 60 % opacity in Always On.
    func dimmedWhenLuminanceReduced(_ opacity: Double = 0.6) -> some View {
        modifier(DimmedWhenReduced(opacity: opacity))
    }
}

private struct AlwaysOnPrimary: ViewModifier {
    @Environment(\.isLuminanceReduced) private var reduced
    @Environment(\.colorSchemeContrast) private var contrast
    let color: Color

    func body(content: Content) -> some View {
        content.foregroundStyle(reduced ? Color.white.opacity(contrast == .increased ? 1 : 0.85) : color)
    }
}

private struct HiddenWhenReduced: ViewModifier {
    @Environment(\.isLuminanceReduced) private var reduced

    func body(content: Content) -> some View {
        content.opacity(reduced ? 0 : 1)
    }
}

private struct DimmedWhenReduced: ViewModifier {
    @Environment(\.isLuminanceReduced) private var reduced
    let opacity: Double

    func body(content: Content) -> some View {
        content.opacity(reduced ? opacity : 1)
    }
}

/// How a filled control draws in each state: filled with a black label when
/// active, a stroked outline with a dimmed label in Always On.
struct AlwaysOnFill: ViewModifier {
    @Environment(\.isLuminanceReduced) private var reduced
    @Environment(\.colorSchemeContrast) private var contrast
    let tint: Color
    var cornerRadius: CGFloat = 16
    var lineWidth: CGFloat = 2

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .foregroundStyle(reduced ? tint.opacity(0.7) : WatchPalette.onTint)
            .background {
                if reduced {
                    shape.strokeBorder(tint.opacity(0.7), lineWidth: contrast == .increased ? lineWidth + 1 : lineWidth)
                } else {
                    shape.fill(tint)
                }
            }
            .contentShape(shape)
    }
}
