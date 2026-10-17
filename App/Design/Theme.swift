import SwiftUI

/// Colors and spacing used across the app. Dark, card-based, with one accent
/// color per score - the same visual language as Bevel/Whoop-style apps,
/// under our own branding.
enum Theme {
    static let background = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let card = Color(red: 0.09, green: 0.09, blue: 0.12)
    static let cardRaised = Color(red: 0.13, green: 0.13, blue: 0.17)
    static let separator = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.6)

    static let strain = Color(red: 0.37, green: 0.63, blue: 1.00)
    static let sleep = Color(red: 0.62, green: 0.52, blue: 1.00)
    static let recoveryHigh = Color(red: 0.20, green: 0.84, blue: 0.53)
    static let recoveryModerate = Color(red: 1.00, green: 0.78, blue: 0.25)
    static let recoveryLow = Color(red: 1.00, green: 0.33, blue: 0.33)
    static let lifting = Color(red: 1.00, green: 0.56, blue: 0.25)

    static let zoneColors: [Color] = [
        Color(red: 0.55, green: 0.75, blue: 1.00),
        Color(red: 0.30, green: 0.85, blue: 0.70),
        Color(red: 1.00, green: 0.82, blue: 0.30),
        Color(red: 1.00, green: 0.55, blue: 0.25),
        Color(red: 1.00, green: 0.30, blue: 0.35)
    ]

    static let cornerRadius: CGFloat = 20
    static let padding: CGFloat = 16

    static func recoveryColor(for score: Int?) -> Color {
        guard let score else { return secondaryText }
        switch score {
        case ..<34: return recoveryLow
        case 34..<67: return recoveryModerate
        default: return recoveryHigh
        }
    }
}

extension View {
    /// Standard rounded card container.
    func card() -> some View {
        padding(Theme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cornerRadius))
    }
}
