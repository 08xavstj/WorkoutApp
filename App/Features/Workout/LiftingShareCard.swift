import AppCore
import SwiftUI

/// The lifting share image (spec B3): title and date, total volume in the
/// user's unit, sets and time, the top exercises with their best set and the
/// change since last time, records, the change against the last similar
/// session, and a front/back muscle map of this session's hard sets.
/// Feedback on lifting performance improved strength over a training cycle
/// (Weakley et al., Sports Med 2023); sharing it is reporting progress to
/// others (Harkin 2016).
struct LiftingShareCard: View {
    let data: SummaryData
    let heart: SummaryHeart?
    let unit: WeightUnit
    let style: ShareCardStyle
    var showMuscles = true
    var showHeart = true

    private var exercises: [SummaryExercise] {
        let withRecords = Set(data.exercises.filter { !$0.records.isEmpty }.map(\.id))
        let chosen = Set(ShareCards.topExercises(data.exercises.map(\.result), withRecords: withRecords).map(\.index))
        return data.exercises.filter { chosen.contains($0.id) }
    }

    private var recordCount: Int { data.exercises.reduce(0) { $0 + $1.records.count } }

    private var footnote: String {
        var parts = ["Best set per exercise; ▲▼ is volume against the last time you did it."]
        // Only when strain is drawn: records take its place in the stats.
        if recordCount == 0, showHeart, heart != nil { parts.append("Strain is Tensile's own 0–100% scale.") }
        return parts.joined(separator: " ")
    }

    var body: some View {
        ShareCardFrame(style: style, wash: [Theme.Wash.rose, Theme.Wash.peach], footnote: footnote) {
            header
            stats
            HStack(alignment: .top, spacing: 12) {
                exerciseList
                if showMuscles, !data.muscles.isEmpty {
                    muscleMap
                        .frame(width: 104)
                }
            }
            if let change = data.sessionChange, let name = data.lastName {
                Text("vs \(name), \(SummaryFormat.shortDate(change.lastDate)): volume \(SummaryFormat.delta(change.volumeKg, unit))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(data.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(data.date.formatted(date: .long, time: .omitted))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: 8) {
            // Bodyweight work logs no weight: its reps say more than "0 kg".
            if data.totals.volumeKg > 0 {
                ShareStat(label: "Volume", value: "\(SummaryFormat.volume(data.totals.volumeKg, unit)) \(unit.rawValue)")
            } else {
                ShareStat(label: "Reps", value: "\(data.totals.reps)")
            }
            ShareStat(label: "Sets", value: "\(data.totals.workingSets)")
            ShareStat(label: "Time", value: SummaryFormat.duration(data.totals.duration))
            if recordCount > 0 {
                ShareStat(label: recordCount == 1 ? "Record" : "Records", value: "\(recordCount)")
            } else if showHeart, let heart {
                ShareStat(label: "Strain", value: "\(whole(heart.strain))%")
            }
        }
    }

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(exercises) { item in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(item.result.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if !item.records.isEmpty {
                            Text("PR")
                                .font(.system(size: 8, weight: .heavy))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .foregroundStyle(Theme.card)
                                .background(Theme.liftingText, in: .capsule)
                        }
                    }
                    Text(line(item))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            if data.exercises.count > exercises.count {
                Text("+\(data.exercises.count - exercises.count) more")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "100 kg × 5 · ▲ 120 kg", "12 reps", "3 × 30 s".
    private func line(_ item: SummaryExercise) -> String {
        var parts: [String] = []
        if let best = item.result.bestSet {
            if item.result.isHold {
                parts.append("\(best.reps) s")
            } else if best.weightKg > 0 {
                parts.append("\(SummaryFormat.weight(best.weightKg, unit)) × \(best.reps)")
            } else {
                parts.append("\(best.reps) reps")
            }
        }
        parts.append(item.result.workingSets == 1 ? "1 set" : "\(item.result.workingSets) sets")
        if let change = item.change, item.result.volumeKg > 0 {
            parts.append(SummaryFormat.delta(change.volumeKg, unit))
        }
        return parts.joined(separator: " · ")
    }

    private var muscleMap: some View {
        let sets = Dictionary(data.muscles.map { ($0.muscle, $0.sessionSets) }, uniquingKeysWith: +)
        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                BodyFigure(data: BodyMapData.front, bounds: BodyMapData.backBounds) { color(region: $0, sets) }
                BodyFigure(data: BodyMapData.back, bounds: BodyMapData.backBounds) { color(region: $0, sets) }
            }
            .frame(height: 120)
            Text("Muscles worked")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// Shaded by this session's hard sets (`ShareCards.shade`); "upperBack"
    /// is lats and upper back together, as on Fitness › Muscles.
    private func color(region: String, _ sets: [Muscle: Double]) -> Color {
        let value: Double
        if region == "upperBack" {
            value = max(sets[.lats] ?? 0, sets[.middleBack] ?? 0)
        } else if let muscle = Muscle(rawValue: region) {
            value = sets[muscle] ?? 0
        } else {
            return Theme.bodyNeutral
        }
        switch ShareCards.shade(sets: value) {
        case .none: return Theme.bodyNeutral
        case .some: return Theme.liftingLight
        case .worked: return Theme.lifting
        }
    }
}
