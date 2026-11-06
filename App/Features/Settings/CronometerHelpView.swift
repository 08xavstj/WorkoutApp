import SwiftUI

/// How Cronometer's food log reaches Tensile through Apple Health. Setup
/// help, so it lives under Settings › Data sources next to the Garmin page
/// (ux-audit.md 4.3, S4; moved from the README). Works pushed onto any
/// NavigationStack.
struct CronometerHelpView: View {
    var body: some View {
        HealthDetailPage(title: "Using Cronometer") {
            HelpCard(title: "Turn on sharing", lines: [
                "In Cronometer, open its settings, find Apple Health under connected apps and devices, and turn on exporting nutrition.",
                "In Apple Health, tap your profile picture › Apps › Cronometer, and check it can write Energy Consumed, Protein, Carbohydrates, Fat, Fiber and Water.",
                "In Tensile, allow reading the same types: Settings › Data sources › Ask for Apple Health access.",
            ])
            HelpCard(title: "What Tensile gets", lines: [
                "Food you log in Cronometer shows on Today's nutrition card, and the coach uses it. Vitamins and minerals show in Health › Key measures › Vitamins & minerals.",
            ], note: "Cronometer has no public API, so Apple Health is the only route. If it doesn't send a nutrient, that number shows \"--\".")
        }
    }
}

/// A titled card of short help paragraphs, with an optional grey note.
private struct HelpCard: View {
    let title: String
    let lines: [String]
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: title)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
