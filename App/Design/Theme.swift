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
    static let ink = adaptive(light: 0x111827, dark: 0xF5F5F7)

    // Text
    static let primaryText = adaptive(light: 0x111827, dark: 0xF5F5F7)
    static let secondaryText = adaptive(light: 0x6B7280, dark: 0x9A9AA5)

    // Score accents (a little deeper in light mode so they read on white)
    static let strain = adaptive(light: 0x1F7AFF, dark: 0x4D9BFF)
    static let strainLight = adaptive(light: 0x6FB1FF, dark: 0x8CC2FF)
    static let sleep = adaptive(light: 0x7A5CFF, dark: 0x9E86FF)
    static let sleepLight = adaptive(light: 0xB7A6FF, dark: 0xC4B6FF)
    static let recoveryHigh = adaptive(light: 0x10B866, dark: 0x30D67F)
    static let recoveryModerate = adaptive(light: 0xF29A00, dark: 0xFFC53D)
    static let recoveryLow = adaptive(light: 0xFF3B4E, dark: 0xFF5A5F)
    static let lifting = adaptive(light: 0xFF6A1A, dark: 0xFF8A3D)
    static let liftingLight = adaptive(light: 0xFFB27A, dark: 0xFFB98F)
    static let nutrition = adaptive(light: 0x00B3A4, dark: 0x2ED3C4)
    static let nutritionLight = adaptive(light: 0x5FE0D2, dark: 0x6FE6D9)

    static let zoneColors: [Color] = [
        adaptive(light: 0x5AA9FF, dark: 0x7DBBFF),
        adaptive(light: 0x14C38E, dark: 0x3ADBA6),
        adaptive(light: 0xFFC107, dark: 0xFFD24D),
        adaptive(light: 0xFF7A1A, dark: 0xFF9A4D),
        adaptive(light: 0xFF2D55, dark: 0xFF5C7A)
    ]

    static let cornerRadius: CGFloat = 24
    static let padding: CGFloat = 16

    static func recoveryColors(for score: Int?) -> [Color] {
        let base = recoveryColor(for: score)
        return [base.opacity(0.55), base]
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
    /// Standard rounded card container with a soft shadow (visible in light mode).
    func card() -> some View {
        padding(Theme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cornerRadius))
            .shadow(color: Color.black.opacity(0.07), radius: 9, y: 4)
    }
}

/// Rounds for display. Unlike `Int(_:)`, never crashes on NaN or infinity.
func whole(_ value: Double) -> Int {
    value.isFinite ? Int(value.rounded()) : 0
}
