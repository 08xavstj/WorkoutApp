import SwiftUI
import WidgetKit

/// Colours for the Plan and Scores widgets in light and dark. The app's
/// `Theme` isn't part of this target (it needs UIKit colour providers), so the
/// values are copied from `App/Design/Theme.swift`: text in an accent uses the
/// accent's text variant (4.5:1 or better on a card), rings use the bright one.
nonisolated struct GlancePalette {
    /// Dark values: a dark Home Screen, and StandBy or the Lock Screen, where
    /// the widget's own background is taken away and it sits on black.
    let dark: Bool

    var ink: Color { Self.color(dark ? 0xF5F5F7 : 0x111827) }
    var secondary: Color { Self.color(dark ? 0x9D9DA8 : 0x5C626E) }
    var track: Color { Self.color(dark ? 0x26262E : 0xE3E6EC) }

    var liftingText: Color { Self.color(dark ? 0xFF6B97 : 0xB8175A) }
    var sleepText: Color { Self.color(dark ? 0x9692FF : 0x4338CA) }
    var strainText: Color { Self.color(dark ? 0xFF8E3C : 0xB43C0B) }
    var doneText: Color { Self.color(dark ? 0x3EDB84 : 0x137438) }

    var strainRing: [Color] { dark ? [Self.color(0xFFD066), Self.color(0xFF8E3C)] : [Self.color(0xFFC94A), Self.color(0xFF7A1A)] }
    var sleepRing: [Color] { dark ? [Self.color(0x7FD3FF), Self.color(0x8A86FF)] : [Self.color(0x5CC8FF), Self.color(0x5B5BF0)] }

    /// The recovery ring's gradient for a band ("low", "moderate", "high"):
    /// blue for an easy day, not alarm red (`RecoveryWording.colors`).
    func recoveryRing(_ band: String?) -> [Color] {
        switch band {
        case "low": dark ? [Self.color(0x7DEAF4), Self.color(0x5C9DFF)] : [Self.color(0x5FE3F0), Self.color(0x2F80FF)]
        case "moderate": dark ? [Self.color(0xFFE680), Self.color(0xFFC53D)] : [Self.color(0xFFE066), Self.color(0xF59E0B)]
        case "high": dark ? [Self.color(0xD4F06A), Self.color(0x3EDB84)] : [Self.color(0xC9EC4C), Self.color(0x22C36A)]
        default: [secondary, secondary]
        }
    }

    func recoveryText(_ band: String?) -> Color {
        switch band {
        case "low": Self.color(dark ? 0x6BA6FF : 0x1D4ED8)
        case "moderate": Self.color(dark ? 0xFFC53D : 0xA64C08)
        case "high": Self.color(dark ? 0x3EDB84 : 0x137438)
        default: secondary
        }
    }

    static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The soft pastel wash behind a Home Screen widget, like the top of each tab
/// in the app. iOS takes it away on the Lock Screen, in StandBy and on a
/// tinted Home Screen.
struct GlanceBackground: View {
    enum Wash {
        /// Rose to lavender (the Fitness tab's colours): the Plan widget.
        case plan
        /// Peach to sky (the Today tab's colours): the Scores widget.
        case scores
    }

    let wash: Wash
    @Environment(\.colorScheme) private var colorScheme

    private var stops: [UInt32] {
        switch (wash, colorScheme == .dark) {
        case (.plan, false): [0xFFE3EC, 0xFFFFFF, 0xECE6FF]
        case (.plan, true): [0x2B1B24, 0x17171D, 0x1F1C30]
        case (.scores, false): [0xFFE8D6, 0xFFFFFF, 0xDCEEFF]
        case (.scores, true): [0x2B2019, 0x17171D, 0x18222F]
        }
    }

    var body: some View {
        LinearGradient(colors: stops.map(GlancePalette.color), startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A score as a ring with its number in the middle. In a tinted or vibrant
/// widget the gradient goes and the filled arc joins the accent group.
struct GlanceRing<Center: View>: View {
    /// 0-1; nil draws the empty track only.
    let fraction: Double?
    let colors: [Color]
    let track: Color
    let lineWidth: CGFloat
    let center: Center
    @Environment(\.widgetRenderingMode) private var renderingMode

    init(fraction: Double?, colors: [Color], track: Color, lineWidth: CGFloat = 8, @ViewBuilder center: () -> Center) {
        self.fraction = fraction
        self.colors = colors
        self.track = track
        self.lineWidth = lineWidth
        self.center = center()
    }

    private var fullColor: Bool { renderingMode == .fullColor }

    private var arc: AnyShapeStyle {
        fullColor
            ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(Color.primary)
    }

    private var trackStyle: Color {
        fullColor ? track : Color.primary.opacity(0.2)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackStyle, lineWidth: lineWidth)
            if let fraction, fraction > 0 {
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(arc, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
            center
        }
        .padding(lineWidth / 2)
    }
}
