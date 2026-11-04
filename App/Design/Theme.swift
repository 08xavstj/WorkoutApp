import SwiftUI
import UIKit

/// Colors and spacing used across the app. Light and bright by default, with
/// one vivid accent per score. Every color adapts if the user picks Dark in
/// Settings, so views should only use these, never `.white`/`.black`.
enum Theme {
    // Surfaces
    static let background = adaptive(light: 0xF2F4F8, dark: 0x0B0B0F)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x17171D)
    static let cardRaised = adaptive(light: 0xEEF1F6, dark: 0x22222A)
    static let separator = adaptive(light: 0xE3E6EC, dark: 0x2A2A33)
    static let track = adaptive(light: 0xEDEFF4, dark: 0x26262E)
    /// Untrained muscles on the body map.
    static let bodyNeutral = adaptive(light: 0xD5DAE1, dark: 0x3A3A44)
    static let ink = adaptive(light: 0x111827, dark: 0xF5F5F7)

    // Text
    static let primaryText = adaptive(light: 0x111827, dark: 0xF5F5F7)
    /// Darkened in the 2026 redesign so small text also passes on the page
    /// background, not only on cards (was 0x6B7280: 4.39:1 on `background`).
    /// WCAG 2.2 1.4.3 asks 4.5:1 for normal text (ux-audit.md P24, X4).
    /// Light: 6.1:1 on `card`, 5.6:1 on `background`, 5.1:1 on a neutral
    /// `Chip`. Dark: 6.6:1 on `card`, 7.3:1 on `background`, 5.5:1 on a chip.
    static let secondaryText = adaptive(light: 0x5C626E, dark: 0x9D9DA8)

    // Score accents. Each score has a two-stop gradient (light -> deep),
    // bright like the reference app: orange strain, lime-green recovery,
    // blue-indigo sleep.
    static let strain = adaptive(light: 0xFF7A1A, dark: 0xFF8E3C)
    static let strainLight = adaptive(light: 0xFFC94A, dark: 0xFFD066)
    static let sleep = adaptive(light: 0x5B5BF0, dark: 0x8A86FF)
    static let sleepLight = adaptive(light: 0x5CC8FF, dark: 0x7FD3FF)
    static let recoveryHigh = adaptive(light: 0x22C36A, dark: 0x3EDB84)
    static let recoveryHighLight = adaptive(light: 0xC9EC4C, dark: 0xD4F06A)
    static let recoveryModerate = adaptive(light: 0xF59E0B, dark: 0xFFC53D)
    static let recoveryModerateLight = adaptive(light: 0xFFE066, dark: 0xFFE680)
    static let recoveryLow = adaptive(light: 0xFF3B5C, dark: 0xFF5C77)
    static let recoveryLowLight = adaptive(light: 0xFF9F8A, dark: 0xFFB0A0)
    static let lifting = adaptive(light: 0xF0447A, dark: 0xFF6B97)
    static let liftingLight = adaptive(light: 0xFF9AC1, dark: 0xFFB0CF)
    static let nutrition = adaptive(light: 0x00B3A4, dark: 0x2ED3C4)
    static let nutritionLight = adaptive(light: 0x7EE8C8, dark: 0x8FEFD3)
    static let heart = adaptive(light: 0xFF4D6A, dark: 0xFF6E86)
    static let heartLight = adaptive(light: 0xFFA07A, dark: 0xFFB394)
    static let oxygen = adaptive(light: 0x2F80FF, dark: 0x5C9DFF)
    static let oxygenLight = adaptive(light: 0x5FE3F0, dark: 0x7DEAF4)

    // Text versions of the accents. Use these (or `textColor(for:)`) for any
    // text drawn in an accent; the bright accents are for rings, bars and
    // icons only. Target: WCAG 2.2 1.4.3, 4.5:1 for normal text (ux-audit.md
    // P24). Ratios computed with the WCAG relative-luminance formula, as
    // "on card / on page background / on its 13% `Chip` pill over a card".
    // Every value also stays >= 4.6:1 on `cardRaised` and on a chip pill over
    // the page background or `cardRaised` (the worst case for each is noted).
    // Light values were darkened slightly in the 2026 redesign so chip pills
    // pass too; dark values are the accent unless the accent fell short.
    /// Light 5.9 / 5.3 / 5.2 (worst 4.7). Dark 9.9 / 10.9 / 7.8.
    static let recoveryHighText = adaptive(light: 0x137438, dark: 0x3EDB84)
    /// Light 5.7 / 5.2 / 5.2 (worst 4.6). Dark 11.3 / 12.4 / 8.5.
    static let recoveryModerateText = adaptive(light: 0xA64C08, dark: 0xFFC53D)
    /// Light 6.2 / 5.6 / 5.2 (worst 4.6). Dark 6.3 / 7.0 / 5.4 (worst 4.7).
    static let recoveryLowText = adaptive(light: 0xBE1C37, dark: 0xFF6680)
    /// Light 5.8 / 5.3 / 5.2 (worst 4.6). Dark 7.8 / 8.6 / 6.3.
    static let strainTextColor = adaptive(light: 0xB43C0B, dark: 0xFF8E3C)
    /// Light 6.3 / 5.8 / 5.4 (worst 4.8). Dark 6.6 / 7.3 / 5.5 (worst 4.8).
    static let liftingText = adaptive(light: 0xB8175A, dark: 0xFF6B97)
    /// Light 6.7 / 6.1 / 5.7 (worst 5.1). Dark 7.2 / 8.0 / 6.0 (worst 5.2).
    /// (Raw `oxygen` is 3.7:1 on white and 3.3:1 on its chip.)
    static let oxygenText = adaptive(light: 0x1D4ED8, dark: 0x6BA6FF)
    /// Light 5.9 / 5.4 / 5.2 (worst 4.7). Dark 9.5 / 10.5 / 7.5.
    /// (Raw `nutrition` is 2.6:1 on white.)
    static let nutritionText = adaptive(light: 0x0E7068, dark: 0x2ED3C4)
    /// Light 6.3 / 5.7 / 5.4 (worst 4.8). Dark 7.2 / 7.9 / 6.0 (worst 5.2).
    static let heartText = adaptive(light: 0xBE123C, dark: 0xFF7A90)
    /// Light 7.9 / 7.2 / 6.7 (worst 5.9). Dark 6.7 / 7.3 / 5.6 (worst 4.8).
    static let sleepText = adaptive(light: 0x4338CA, dark: 0x9692FF)

    // Deep gradients for buttons with white text (both stops dark enough).
    static let recoveryDeep = adaptive(light: 0x15803D, dark: 0x16A34A)
    static let sleepDeep = adaptive(light: 0x4338CA, dark: 0x5B5BF0)
    static var strainButtonColors: [Color] { [strainTextColor, lifting] }
    static var recoveryButtonColors: [Color] { [recoveryHigh, recoveryDeep] }
    static var sleepButtonColors: [Color] { [sleep, sleepDeep] }

    /// Accent color to use for text of a given tone. Every accent maps to its
    /// text variant above (4.5:1+ in light and dark, also on a `Chip` pill);
    /// text variants, `primaryText` and `secondaryText` come back unchanged.
    static func textColor(for accent: Color) -> Color {
        if accent == recoveryHigh { return recoveryHighText }
        if accent == recoveryModerate { return recoveryModerateText }
        if accent == recoveryLow { return recoveryLowText }
        if accent == strain { return strainTextColor }
        if accent == lifting { return liftingText }
        if accent == oxygen { return oxygenText }
        if accent == nutrition { return nutritionText }
        if accent == heart { return heartText }
        if accent == sleep { return sleepText }
        return accent
    }

    static var strainColors: [Color] { [strainLight, strain] }
    static var sleepColors: [Color] { [sleepLight, sleep] }
    static var liftingColors: [Color] { [liftingLight, lifting] }
    static var nutritionColors: [Color] { [nutritionLight, nutrition] }
    static var heartColors: [Color] { [heartLight, heart] }
    static var oxygenColors: [Color] { [oxygenLight, oxygen] }

    /// Pastel colors for the soft gradient wash at the top of each tab.
    enum Wash {
        static let peach = adaptive(light: 0xFFD3B0, dark: 0x6B3A1E)
        static let butter = adaptive(light: 0xFFF0A6, dark: 0x5E5320)
        static let lime = adaptive(light: 0xD9F5A6, dark: 0x3B5A1E)
        static let mint = adaptive(light: 0xB8F0DA, dark: 0x1E5A48)
        static let sky = adaptive(light: 0xB9DEFF, dark: 0x1E3F6B)
        static let lavender = adaptive(light: 0xD8CCFF, dark: 0x3A2E6B)
        static let rose = adaptive(light: 0xFFC8DA, dark: 0x6B2440)
    }

    static let zoneColors: [Color] = [
        adaptive(light: 0x5AA9FF, dark: 0x7DBBFF),
        adaptive(light: 0x14C38E, dark: 0x3ADBA6),
        adaptive(light: 0xFFC107, dark: 0xFFD24D),
        adaptive(light: 0xFF7A1A, dark: 0xFF9A4D),
        adaptive(light: 0xFF2D55, dark: 0xFF5C7A)
    ]

    /// The one corner radius and padding for every card and tile (ux-audit.md
    /// 4.5: "One corner radius (26) and one padding (16) everywhere").
    static let cornerRadius: CGFloat = 26
    static let padding: CGFloat = 16

    /// Type tokens (ux-audit.md 4.5). All are built-in text styles, or sizes
    /// scaled with `@ScaledMetric`, so Dynamic Type works (HIG Typography;
    /// WCAG 2.2 1.4.4, ux-audit.md P22). Never use `.system(size:)` for text
    /// without scaling it.
    enum Typography {
        /// Screen title. Prefer the system navigation bar's large title
        /// (`.navigationTitle`); use this only where there is no bar.
        static let screenTitle: Font = .largeTitle.weight(.bold)
        /// Section header between cards (`SectionHeader`).
        static let section: Font = .title3.weight(.bold)
        /// Card label (`CardLabel`): small caps-style caption, tracked.
        static let cardLabel: Font = .caption.weight(.semibold)
        static let cardLabelTracking: CGFloat = 1.2
        /// Value in a list row (`MetricRow`); add `.fontDesign(.rounded)`.
        static let rowNumber: Font = .title2.weight(.semibold)
        /// Unit next to a hero number.
        static let heroUnit: Font = .title3.weight(.semibold)
        /// Body text in cards.
        static let body: Font = .subheadline
        /// Context and footnotes; pair with `Theme.secondaryText`.
        static let context: Font = .footnote
        /// Hero number base size, scaled relative to `.largeTitle`
        /// (use `.heroNumberFont()`).
        static let heroNumberSize: CGFloat = 44
        /// Tile number base size, scaled relative to `.title`
        /// (use `.tileNumberFont()`).
        static let tileNumberSize: CGFloat = 30
    }

    static func recoveryColors(for score: Int?) -> [Color] {
        guard let score else { return [track, secondaryText] }
        switch score {
        case ..<34: return [recoveryLowLight, recoveryLow]
        case 34..<67: return [recoveryModerateLight, recoveryModerate]
        default: return [recoveryHighLight, recoveryHigh]
        }
    }

    static func recoveryColor(for score: Int?) -> Color {
        guard let score else { return secondaryText }
        switch score {
        case ..<34: return recoveryLow
        case 34..<67: return recoveryModerate
        default: return recoveryHigh
        }
    }

    /// SwiftUI resolves colors on a background render thread, so the provider
    /// closure must not be tied to the main actor (that crashed on launch).
    nonisolated static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { @Sendable traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension View {
    /// Standard rounded card with a soft shadow. Pass `tint` for a card that
    /// glows faintly in a score's color from the top corner: only for the one
    /// primary card of a tab (ux-audit.md 4.5, P21: hierarchy through layout,
    /// not decoration).
    func card(tint: Color? = nil) -> some View {
        padding(Theme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.card)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .fill(RadialGradient(colors: [tint.opacity(0.16), tint.opacity(0)], center: .topLeading, startRadius: 0, endRadius: 320))
                        }
                    }
            }
            .shadow(color: Color.black.opacity(0.06), radius: 14, y: 6)
    }

    /// Pins scrolling content to the screen width, so a wide child can never
    /// make the page pan sideways.
    func lockedToScreenWidth() -> some View {
        containerRelativeFrame(.horizontal, alignment: .top)
    }

    /// Hero number: rounded bold, 44 pt at the default text size, scaled with
    /// Dynamic Type relative to `.largeTitle` (ux-audit.md 4.5).
    func heroNumberFont() -> some View {
        modifier(ScaledNumberFont(style: .hero))
    }

    /// Tile number: rounded semibold, 30 pt at the default text size, scaled
    /// relative to `.title` (ux-audit.md 4.5).
    func tileNumberFont() -> some View {
        modifier(ScaledNumberFont(style: .tile))
    }
}

/// Scaled number fonts behind `heroNumberFont()` and `tileNumberFont()`.
/// The base sizes match `Theme.Typography.heroNumberSize` / `tileNumberSize`.
private struct ScaledNumberFont: ViewModifier {
    enum Style {
        case hero, tile
    }

    let style: Style
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title) private var tileSize: CGFloat = 30

    private var font: Font {
        switch style {
        case .hero: .system(size: heroSize, weight: .bold, design: .rounded)
        case .tile: .system(size: tileSize, weight: .semibold, design: .rounded)
        }
    }

    func body(content: Content) -> some View {
        content
            .font(font)
            .monospacedDigit()
    }
}

/// Strain as shown everywhere: a whole percentage, e.g. "62%".
func strainText(_ value: Double) -> String {
    "\(whole(value))%"
}

/// A strain range as shown everywhere, e.g. "45–65%".
func strainRangeText(_ range: ClosedRange<Double>) -> String {
    "\(whole(range.lowerBound))–\(whole(range.upperBound))%"
}

/// Rounds for display. Unlike `Int(_:)`, never crashes on NaN or infinity.
func whole(_ value: Double) -> Int {
    value.isFinite ? Int(value.rounded()) : 0
}
