import SwiftUI
import AppCore

/// A calm level bar for VO₂ max: thin coloured bands for your age and sex
/// (`VO2Norms.segments`, FRIEND 2015), one marker for your value, one tick for
/// the typical value, and only the two end labels. Everything else lives in
/// the card's Details.
struct VO2LevelBar: View {
    let age: Int
    let sex: BiologicalSex
    let value: Double?
    /// Drawn as a hollow marker for an estimate, solid for a watch reading.
    let isEstimate: Bool

    private static let barHeight: CGFloat = 8
    private static let marker: CGFloat = 18

    var body: some View {
        let typical = VO2Norms.median(age: age, sex: sex)
        let scale = VO2Norms.scale(age: age, sex: sex, including: [value].compactMap { $0 })
        let segments = VO2Norms.segments(age: age, sex: sex, scale: scale)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(segments, id: \.category) { segment in
                            Capsule()
                                .fill(segment.category.color)
                                .frame(width: max(0, width * fraction(segment.range.upperBound, scale)
                                    - width * fraction(segment.range.lowerBound, scale) - 2))
                        }
                    }
                    .frame(height: Self.barHeight)
                    // Typical for your age.
                    Capsule()
                        .fill(Theme.primaryText.opacity(0.55))
                        .frame(width: 2, height: Self.barHeight + 8)
                        .offset(x: width * fraction(typical, scale) - 1)
                    if let value {
                        Circle()
                            .fill(isEstimate ? Theme.card : Theme.primaryText)
                            .overlay(Circle().stroke(Theme.primaryText, lineWidth: 3))
                            .frame(width: Self.marker, height: Self.marker)
                            .offset(x: width * fraction(value, scale) - Self.marker / 2)
                    }
                }
                .frame(height: Self.marker)
            }
            .frame(height: Self.marker)
            HStack {
                Text("Low")
                Spacer()
                Text("Typical \(Int(typical.rounded()))")
                Spacer()
                Text("Top 10%")
            }
            .font(.caption2)
            .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(typical: typical))
    }

    private func fraction(_ value: Double, _ scale: ClosedRange<Double>) -> CGFloat {
        let span = max(1, scale.upperBound - scale.lowerBound)
        return CGFloat(min(1, max(0, (value - scale.lowerBound) / span)))
    }

    private func accessibilityText(typical: Double) -> String {
        guard let value else { return "No VO₂ max yet. Typical for your age is \(Int(typical.rounded()))." }
        let standing = VO2Norms.standing(vo2: value, age: age, sex: sex)
        return "VO₂ max \(Int(value.rounded())), \(standing.category.name). \(standing.percentileText). Typical is \(Int(typical.rounded()))."
    }
}
