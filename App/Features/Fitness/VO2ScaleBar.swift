import SwiftUI
import AppCore

// MARK: - Marks

/// A no-test VO₂ max estimate drawn on the scale: a hollow mark with its range.
struct VO2EstimateMark: Identifiable, Equatable {
    enum Kind: String {
        case heartRate, activity
    }

    let kind: Kind
    let value: Double
    let range: ClosedRange<Double>

    var id: String { kind.rawValue }
    /// Hollow, so they never read as the watch's solid dot.
    var symbol: String { kind == .heartRate ? "circle" : "diamond" }
    var name: String { kind == .heartRate ? "Estimate from heart rate" : "Estimate from activity, lifting included" }
}

extension VO2Norms.Category {
    /// Low → top 10%, warm to cool-green, from the Theme palette.
    var color: Color {
        switch self {
        case .low: Theme.recoveryLow
        case .belowAverage: Theme.strain
        case .average: Theme.recoveryModerate
        case .good: Theme.recoveryHighLight
        case .excellent: Theme.recoveryHigh
        case .topTen: Theme.recoveryDeep
        }
    }

    /// For a chip or verdict: caution under the 25th percentile, else good.
    var chipColor: Color { isBelowAverage ? Theme.recoveryModerate : Theme.recoveryHigh }
}

// MARK: - Scale bar

/// VO₂ max on a bar of FRIEND percentile bands for your age and sex
/// (`VO2Norms`; Kaminsky et al., Mayo Clin Proc 2015, treadmill): the watch
/// value as a solid dot, the two estimates as hollow marks with their ranges,
/// and ticks for the typical man and woman your age, the average adult and
/// the top 10%.
struct VO2ScaleBar: View {
    let age: Int
    let sex: BiologicalSex
    let watch: Double?
    let estimates: [VO2EstimateMark]

    private var references: [VO2Norms.Reference] { VO2Norms.references(age: age, sex: sex) }

    private var scale: ClosedRange<Double> {
        let marks = references.map(\.value) + [watch].compactMap { $0 } + estimates.map(\.value)
        return VO2Norms.scale(age: age, sex: sex, including: marks)
    }

    var body: some View {
        let scale = scale
        VStack(alignment: .leading, spacing: 3) {
            VO2AxisLabels(scale: scale)
            ForEach(estimates) { mark in
                VO2EstimateLane(mark: mark, scale: scale)
            }
            VO2BandRow(segments: VO2Norms.segments(age: age, sex: sex, scale: scale), scale: scale, watch: watch)
            VO2ReferenceTicks(references: references, scale: scale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let watch {
            let standing = VO2Norms.standing(vo2: watch, age: age, sex: sex)
            parts.append("Watch VO₂ max \(Int(watch.rounded())): \(standing.percentileText), \(standing.category.name).")
        }
        for mark in estimates {
            parts.append("\(mark.name) about \(Int(mark.value.rounded())).")
        }
        for reference in references {
            parts.append("\(reference.label) \(Int(reference.value.rounded())).")
        }
        return parts.joined(separator: " ")
    }
}

/// Where a value sits across the scale, 0...1.
nonisolated private func scaleFraction(_ value: Double, _ scale: ClosedRange<Double>) -> Double {
    let span = scale.upperBound - scale.lowerBound
    guard span > 0 else { return 0 }
    return min(1, max(0, (value - scale.lowerBound) / span))
}

/// The coloured bands with the watch value's dot.
private struct VO2BandRow: View {
    let segments: [VO2Norms.Segment]
    let scale: ClosedRange<Double>
    let watch: Double?

    private static let gap: CGFloat = 2
    private static let dot: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usable = max(0, width - Self.gap * CGFloat(max(0, segments.count - 1)))
            let span = scale.upperBound - scale.lowerBound
            ZStack(alignment: .leading) {
                HStack(spacing: Self.gap) {
                    ForEach(segments, id: \.category) { segment in
                        Rectangle()
                            .fill(segment.category.color.opacity(0.85))
                            .frame(width: span > 0 ? usable * (segment.range.upperBound - segment.range.lowerBound) / span : 0)
                    }
                }
                .frame(height: 12)
                .clipShape(.capsule)
                if let watch {
                    Circle()
                        .fill(Theme.primaryText)
                        .overlay(Circle().stroke(Theme.card, lineWidth: 3))
                        .frame(width: Self.dot, height: Self.dot)
                        .offset(x: width * scaleFraction(watch, scale) - Self.dot / 2)
                }
            }
            .frame(height: geo.size.height)
        }
        .frame(height: Self.dot + 2)
    }
}

/// One estimate: its range as a thin line and its value as a hollow mark.
private struct VO2EstimateLane: View {
    let mark: VO2EstimateMark
    let scale: ClosedRange<Double>

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let low = width * scaleFraction(mark.range.lowerBound, scale)
            let high = width * scaleFraction(mark.range.upperBound, scale)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.oxygen.opacity(0.3))
                    .frame(width: max(2, high - low), height: 4)
                    .offset(x: low)
                Image(systemName: mark.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.oxygenText)
                    .frame(width: 12, height: 12)
                    .background(Theme.card, in: .circle)
                    .offset(x: width * scaleFraction(mark.value, scale) - 6)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 12)
    }
}

/// Numbers every 10 along the top, each kept inside the bar's width.
private struct VO2AxisLabels: View {
    let scale: ClosedRange<Double>

    private var ticks: [Int] {
        let first = Int((scale.lowerBound / 10).rounded(.up)) * 10
        return Array(stride(from: first, through: Int(scale.upperBound), by: 10))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.self) { tick in
                    let fraction = scaleFraction(Double(tick), scale)
                    Text("\(tick)")
                        .fixedSize()
                        .alignmentGuide(.leading) { @Sendable dimensions in dimensions.width * fraction }
                        .offset(x: width * fraction)
                }
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(Theme.secondaryText)
        }
        .frame(height: 13)
    }
}

/// Small ticks under the bar for the reference values, labels on two rows
/// so neighbours don't overlap.
private struct VO2ReferenceTicks: View {
    let references: [VO2Norms.Reference]
    let scale: ClosedRange<Double>

    private static let rowHeight: CGFloat = 13

    var body: some View {
        let sorted = references.sorted { $0.value < $1.value }
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, reference in
                    let fraction = scaleFraction(reference.value, scale)
                    let row = CGFloat(index % 2)
                    Rectangle()
                        .fill(color(reference))
                        .frame(width: 1.5, height: 4 + row * Self.rowHeight)
                        .offset(x: width * fraction - 0.75)
                    Text(reference.shortLabel)
                        .font(.caption2.weight(reference.kind == .sameSex ? .bold : .medium))
                        .foregroundStyle(color(reference))
                        .fixedSize()
                        .alignmentGuide(.leading) { @Sendable dimensions in dimensions.width * fraction }
                        .offset(x: width * fraction, y: 4 + row * Self.rowHeight)
                }
            }
        }
        .frame(height: 4 + Self.rowHeight * 2 + 2)
    }

    private func color(_ reference: VO2Norms.Reference) -> Color {
        switch reference.kind {
        case .sameSex: Theme.primaryText
        case .topTen: Theme.recoveryHighText
        case .otherSex, .adult: Theme.secondaryText
        }
    }
}

// MARK: - Comparison

/// The bar, its key, the numbers side by side, and your standing in words.
/// With no watch reading the estimates' average drives the standing, labelled
/// as rough.
struct VO2Comparison: View {
    let age: Int
    let sex: BiologicalSex
    let watch: Double?
    let estimates: [VO2EstimateMark]

    /// The watch value, else the estimates' average.
    private var basis: Double? {
        if let watch { return watch }
        guard !estimates.isEmpty else { return nil }
        return estimates.map(\.value).reduce(0, +) / Double(estimates.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VO2ScaleBar(age: age, sex: sex, watch: watch, estimates: estimates)
            VO2CategoryKey()
            VO2NumbersList(age: age, sex: sex, watch: watch, estimates: estimates)
            if let basis {
                standingLine(basis)
            }
        }
    }

    private func standingLine(_ value: Double) -> some View {
        let standing = VO2Norms.standing(vo2: value, age: age, sex: sex)
        let lead = watch == nil ? "From the estimates (rough), " : ""
        let percentile = watch == nil ? standing.percentileText.lowercased() : standing.percentileText
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(standing.category.color)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            Text("\(lead)\(percentile): \(standing.category.name).")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The six bands' names and colours.
private struct VO2CategoryKey: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .leading), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(VO2Norms.Category.allCases, id: \.self) { category in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(category.color.opacity(0.85))
                        .frame(width: 10, height: 8)
                    Text(category.name)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// "You (watch) 45 · Estimate ≈47 · Typical man your age 43 · ...".
private struct VO2NumbersList: View {
    let age: Int
    let sex: BiologicalSex
    let watch: Double?
    let estimates: [VO2EstimateMark]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let watch {
                row(symbol: "circle.fill", title: "You (watch)", value: watch.formatted(.number.precision(.fractionLength(1))), bold: true)
            }
            ForEach(estimates) { mark in
                let low = Int(mark.range.lowerBound.rounded())
                let high = Int(mark.range.upperBound.rounded())
                row(symbol: mark.symbol, title: mark.name, value: "≈\(Int(mark.value.rounded())) (\(low)–\(high))", bold: watch == nil)
            }
            ForEach(VO2Norms.references(age: age, sex: sex)) { reference in
                let value = Int(reference.value.rounded())
                row(symbol: "line.diagonal", title: reference.label,
                    value: reference.kind == .topTen ? "\(value)+" : "\(value)", bold: false)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func row(symbol: String, title: String, value: String, bold: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(symbol == "line.diagonal" ? Theme.secondaryText : Theme.oxygenText)
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundStyle(bold ? Theme.primaryText : Theme.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(bold ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
        }
    }
}

// MARK: - Tips

/// 3-4 short ways to raise VO₂ max for where you stand and your goals
/// (`VO2Norms.tips`), a button into the weekly plan's easy-cardio setting,
/// and the studies folded away.
struct VO2Tips: View {
    let category: VO2Norms.Category
    let lifts: Bool
    let losingWeight: Bool

    @Environment(WeeklyPlanStore.self) private var plans
    @State private var showingPlan = false

    var body: some View {
        let tips = VO2Norms.tips(category: category, lifts: lifts, losingWeight: losingWeight)
        VStack(alignment: .leading, spacing: 8) {
            Text("How to raise it")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
            ForEach(tips) { tip in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.oxygenText)
                        .accessibilityHidden(true)
                    Text(tip.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                showingPlan = true
            } label: {
                Label(buttonTitle, systemImage: "figure.indoor.cycle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.oxygen)
            .accessibilityHint("Opens this week's plan; easy cardio is near the bottom")
            Text("Check again after about 8 weeks, the length of the trials. A brisk 20+ minute outdoor walk or run gives your Watch a fresh reading.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            EvidenceDisclosure(points: tips.map(\.evidence), title: "Evidence for these tips")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingPlan) { WeeklyPlanView() }
    }

    private var buttonTitle: String {
        let planned = plans.plan(containing: .now)?.cardio?.sessionsPerWeek ?? 0
        return planned > 0 ? "Change easy cardio in your week" : "Add easy cardio to your week"
    }
}
