import SwiftUI

// The Watch app's type scale (docs/research/watch-app-redesign-2026-11.md
// §4.8.1). Sizes are for the 46 mm Series 12 at its default text size
// (xLarge): Title 2 is 30 pt, Title 3 20 pt, Headline 17 pt, Footnote 14 pt,
// Footnote 2 13 pt (HIG Typography, watchOS Dynamic Type sizes). The big
// numerals are the app's choice above Title 1 (38 pt), following the HIG's
// "use large font sizes" for workouts (HIG Workouts). Every size scales with
// Dynamic Type through `@ScaledMetric`, so text grows to the 140 % the HIG
// asks watchOS apps to support (HIG Accessibility). Weights are semibold or
// bold, never light (HIG Typography).

/// The roles numbers and labels take on a workout page.
enum WatchNumeral {
    /// Weight on the Set page, heart rate on Main: 48 pt.
    case primary
    /// The rest countdown in its ring: 40 pt.
    case rest
    /// Reps, pace, distance: 32 pt.
    case secondary
    /// Smaller values beside a primary one: 24 pt.
    case tertiary

    var baseSize: CGFloat {
        switch self {
        case .primary: 48
        case .rest: 40
        case .secondary: 32
        case .tertiary: 24
        }
    }

    var weight: Font.Weight {
        switch self {
        case .primary, .rest: .bold
        case .secondary, .tertiary: .semibold
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .primary, .rest: .title
        case .secondary, .tertiary: .title2
        }
    }
}

/// Rounded, monospaced numerals at a role's size, scaled with Dynamic Type.
private struct NumeralFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(_ role: WatchNumeral) {
        _size = ScaledMetric(wrappedValue: role.baseSize, relativeTo: role.relativeTo)
        weight = role.weight
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
    }
}

/// Toolbar values (elapsed time, heart rate): 15 pt, monospaced (Caption 2 size).
private struct StatusFont: ViewModifier {
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 15

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }
}

extension View {
    /// A big workout number (see `WatchNumeral`).
    func numeral(_ role: WatchNumeral) -> some View {
        modifier(NumeralFont(role))
    }

    /// The status row's small values.
    func statusFont() -> some View {
        modifier(StatusFont())
    }

    /// The smallest text a workout page shows: Footnote (14 pt). Footnote 2
    /// (13 pt) is the floor (app's choice, above the HIG's 12 pt minimum), so
    /// nothing here shrinks with `minimumScaleFactor`.
    func supportingText() -> some View {
        font(.footnote)
    }
}
