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
    static let secondaryText = adaptive(light: 0x6B7280, dark: 0x9A9AA5)

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

    static let cornerRadius: CGFloat = 26
    static let padding: CGFloat = 16

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
    /// glows faintly in a score's color from the top corner.
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
}

/// Strain as shown everywhere: a whole percentage, e.g. "62%".
func strainText(_ value: Double) -> String {
    "\(whole(value))%"
}

/// Rounds for display. Unlike `Int(_:)`, never crashes on NaN or infinity.
func whole(_ value: Double) -> Int {
    value.isFinite ? Int(value.rounded()) : 0
}
