import SwiftUI
import Charts
import AppCore

/// Apple's number beside Tensile's over the days that have both: a small
/// chart, how often they moved the same way, and a rank correlation once
/// there are enough days (`ScoreAgreement` in AppCore).
///
/// Descriptive only. Apple hasn't published how its numbers are worked out,
/// so nothing here treats either one as the reference.
struct AppleScoreComparisonCard: View {
    let kind: AppleScoreKind
    let log: AppleScoreLog

    nonisolated private struct Point: Identifiable {
        let id: String
        let date: Date
        let apple: Double
        let tensile: Double
    }

    /// Days drawn (the newest ones).
    private static let chartDays = 30

    var body: some View {
        let pairs = log.pairs(kind)
        let summary = ScoreAgreement.summary(pairs)
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: title)
            if pairs.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if kind.isDaily, pairs.count >= 3 {
                    chart
                    Text(legend)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(lines(summary), id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if kind.isDaily {
                    EvidenceDisclosure(points: Self.method, title: "How this is counted")
                }
            }
        }
        .card()
        .accessibilityIdentifier("apple-scores-compare-\(kind.rawValue)")
    }

    // MARK: Words

    private var title: String {
        switch kind {
        case .readiness: "Readiness and recovery"
        case .sleepScore: "Sleep scores"
        case .healthAge: "Health Age and body age"
        }
    }

    private var emptyText: String {
        switch kind {
        case .readiness: "Nothing to compare yet. Add Apple's Readiness on a day Tensile has a recovery score."
        case .sleepScore: "Nothing to compare yet. Add Apple's Sleep score on a morning Tensile has one too."
        case .healthAge: "Nothing to compare yet. Add Apple's Health Age on a day Tensile has a body age."
        }
    }

    private var legend: String {
        switch kind {
        case .readiness: "Dashed: Apple's Readiness, its 0 to 10 stretched to the same height. Solid: Tensile's recovery."
        case .sleepScore: "Dashed: Apple's Sleep score. Solid: Tensile's."
        case .healthAge: ""
        }
    }

    private func lines(_ summary: ScoreAgreement.Summary) -> [String] {
        var lines = ["\(summary.count) day\(summary.count == 1 ? "" : "s") with both numbers."]
        if kind.isDaily {
            let direction = summary.direction
            if direction.compared > 0 {
                var line = "They moved the same way on \(direction.same) of \(direction.compared) day-to-day changes."
                if direction.flat > 0 { line += " On \(direction.flat) more, one of them didn't move." }
                lines.append(line)
            } else if summary.count >= 2 {
                lines.append("No back-to-back days yet where both moved.")
            }
            if let correlation = summary.correlation {
                lines.append("Rank correlation \(Self.decimal(correlation.rho)) over \(correlation.count) days, likely between \(Self.decimal(correlation.low)) and \(Self.decimal(correlation.high)). It describes these days; it isn't a test of either score.")
            } else if summary.pairsUntilCorrelation > 0 {
                lines.append("A correlation shows at \(ScoreAgreement.minimumPairsForCorrelation) days with both. \(summary.pairsUntilCorrelation) to go.")
            }
        }
        if kind.sharesScaleWithApp, let difference = summary.meanDifference {
            let size = abs(difference)
            let unit = kind == .healthAge ? "year" : "point"
            let amount = size.formatted(.number.precision(.fractionLength(0...1)))
            if size < 0.05 {
                lines.append("On average the two are level.")
            } else {
                lines.append("On average Apple's is \(amount) \(unit)\(amount == "1" ? "" : "s") \(difference > 0 ? "higher" : "lower") than Tensile's.")
            }
        }
        return lines
    }

    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    /// How the figures above are counted, with their limits.
    private static let method = [
        "Direction compares each change with the one before it, for days at most \(ScoreAgreement.maxGapDays) apart. A day when either score stayed the same isn't counted.",
        "The correlation is Spearman's, on ranks, because the two scales differ and nothing says they rise in a straight line together. The range is an approximate 95% interval (Bonett & Wright, Psychometrika 2000).",
        "It waits for \(ScoreAgreement.minimumPairsForCorrelation) days, which is this app's choice: with fewer, the range covers almost anything. Correlations only settle at around 250 pairs (Schönbrodt & Perugini, J Res Pers 2013), and days in a row aren't independent, so read it loosely.",
        "A high or low figure says how alike the two move, not which one is right.",
    ]

    // MARK: Chart

    private var points: [Point] {
        // Readiness is 0–10; drawn tenfold so both lines share the 0–100 height.
        let scale = kind == .readiness ? 10.0 : 1.0
        return log.entries(kind).suffix(Self.chartDays).compactMap { entry in
            guard let tensile = entry.appValue, let date = AppleScoreLog.date(forKey: entry.day) else { return nil }
            return Point(id: entry.day, date: date, apple: Double(entry.reading.value) * scale, tensile: Double(tensile))
        }
    }

    private var tint: Color {
        kind == .sleepScore ? Theme.sleep : Theme.recoveryHigh
    }

    private var chart: some View {
        Chart(points) { point in
            LineMark(x: .value("Day", point.date), y: .value("Score", point.apple), series: .value("From", "Apple"))
                .foregroundStyle(Theme.secondaryText)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
            LineMark(x: .value("Day", point.date), y: .value("Score", point.tensile), series: .value("From", "Tensile"))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .chartYScale(domain: 0...100)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartLegend(.hidden)
        .frame(height: 120)
        // The sentences under the chart say the same in words.
        .accessibilityHidden(true)
    }
}
