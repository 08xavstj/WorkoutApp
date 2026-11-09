import SwiftUI
import SwiftData
import AppCore

// MARK: - Weekly sets per muscle

/// Hard sets per muscle this week against the 10-20 range, with helper
/// muscles counted as half a set (Pelland et al., Sports Med 2026).
struct WeeklySetsCard: View {
    @Environment(MuscleModel.self) private var muscles
    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var nameWidth: CGFloat = 84
    @ScaledMetric(relativeTo: .subheadline) private var countWidth: CGFloat = 36

    /// Also counted by the Fitness › Progress › Muscles row.
    static let shown: [Muscle] = [.chest, .shoulders, .triceps, .lats, .middleBack, .biceps, .quadriceps, .hamstrings, .glutes, .calves, .abdominals]
    /// The bar's right end, in sets.
    private static let scale = 25.0

    var body: some View {
        // This block week's target per muscle (`VolumeProgression`), shaded on each bar.
        let week = plans.volumeTargets(muscles: muscles)
        let targets = week?.sets ?? [:]
        // Each muscle's band this week ("8-10"); the bars shade and colour against it.
        let bands = Dictionary((week?.targets ?? []).map { ($0.muscle, $0.band) }, uniquingKeysWith: { first, _ in first })
        // Block targets are per calendar week, so with them the bars count
        // since Monday (`MuscleModel.weekSets`); without, the last 7 days.
        let sinceMonday = !targets.isEmpty
        let states = Self.shown.compactMap { muscles.states[$0] }.map { state in
            var shown = state
            if sinceMonday { shown.weeklySets = muscles.weekSets[state.muscle] ?? 0 }
            return shown
        }
        let anyTrained = states.contains { $0.weeklySets >= 0.5 }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel(text: sinceMonday ? "Hard sets since Monday" : "Hard sets, last 7 days", color: Theme.lifting)
                Spacer()
                // The block week sits with the target, so the Muscles page needs no separate target list.
                Text(Self.targetChip(week?.targets ?? [], blockWeek: sinceMonday ? plans.blockWeek : nil))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.recoveryHighText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if !anyTrained {
                Text(sinceMonday ? "Log a gym session and each muscle's sets since Monday show here."
                                 : "Log a gym session and each muscle's sets for the last 7 days show here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(states) { state in
                    row(state, band: sinceMonday ? BarBand.target(bands[state.muscle]) : BarBand.general,
                        period: sinceMonday ? "since Monday" : "in the last 7 days")
                }
                Text("A hard set is one taken within about 4 reps of failure. About 10-20 a week per muscle builds the most muscle for most people (Schoenfeld et al., J Sports Sci 2017); more still helps a little, with diminishing returns past 20 (Pelland et al., Sports Med 2026). Sets for helper muscles (e.g. triceps on bench press) count as half.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                if !targets.isEmpty {
                    Text(Self.blockCaption(untracked: states.map(\.muscle).filter { bands[$0] == nil }))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }

    /// "Week 1 of 6 · Target 8-10" from this week's per-muscle bands
    /// (`VolumeProgression.Target.band`) and the block week; "Target
    /// 10-20" without a block (Schoenfeld et al. 2017).
    private static func targetChip(_ targets: [VolumeProgression.Target], blockWeek: TrainingBlock.WeekState? = nil) -> String {
        let bands = targets.filter { shown.contains($0.muscle) }.map(\.band)
        guard let low = bands.map(\.lowerBound).min(), let high = bands.map(\.upperBound).max() else { return "Target 10-20" }
        let target = low == high ? "Target \(low)" : "Target \(low)-\(high)"
        guard let blockWeek else { return target }
        let week = blockWeek.isDeload ? "Deload week" : "Week \(blockWeek.week) of \(blockWeek.length)"
        return week + " · " + target
    }

    /// What a bar is measured against: this block week's band for that
    /// muscle (nil when the block sets none), or the general 10-20 range
    /// when there's no block (Schoenfeld et al., J Sports Sci 2017).
    private enum BarBand {
        case general
        case target(ClosedRange<Int>?)

        var range: ClosedRange<Int>? {
            switch self {
            case .general: 10...20
            case .target(let band): band
            }
        }
    }

    /// The shading caption with a block; names muscles the block sets no target for.
    private static func blockCaption(untracked: [Muscle]) -> String {
        let base = "The shaded part of each bar is that muscle's target this week."
        guard !untracked.isEmpty else { return base }
        let names = untracked.map(\.name).formatted(.list(type: .and))
        return base + " No target this week: \(names)."
    }

    /// Under, in or over the band: blue, green, orange. Grey with no target.
    private func barColor(sets: Double, band: BarBand) -> Color {
        guard let range = band.range else { return Theme.secondaryText.opacity(0.5) }
        if sets < Double(range.lowerBound) { return Theme.oxygen }
        if sets > Double(range.upperBound) { return Theme.strain }
        return sets < 0.5 ? Theme.oxygen : Theme.recoveryHigh
    }

    private func spokenStatus(sets: Double, band: BarBand, state: MuscleRecovery.State) -> String {
        switch band {
        case .general:
            return state.volume.rawValue.lowercased()
        case .target(let range):
            guard let range else { return "no target this week" }
            let text = "target \(range.lowerBound) to \(range.upperBound) sets"
            if sets < Double(range.lowerBound) { return "under the \(text)" }
            if sets > Double(range.upperBound) { return "over the \(text)" }
            return "within the \(text)"
        }
    }

    private func row(_ state: MuscleRecovery.State, band: BarBand, period: String) -> some View {
        let sets = state.weeklySets
        let color = barColor(sets: sets, band: band)
        // Name beside the bar normally; above it at accessibility sizes.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let status = spokenStatus(sets: sets, band: band, state: state)
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Text(state.muscle.name)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .frame(width: stacked ? nil : nameWidth, alignment: .leading)
                .lineLimit(stacked ? 2 : 1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 10) {
                bar(sets: sets, color: color, band: band.range)
                Text(sets.formatted(.number.precision(.fractionLength(0...1))))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: countWidth, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.muscle.name): \(sets.formatted(.number.precision(.fractionLength(0...1)))) hard sets \(period), \(status)")
    }

    /// The shaded band is the same range the bar is coloured against.
    private func bar(sets: Double, color: Color, band: ClosedRange<Int>?) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let low = Double(band?.lowerBound ?? 0)
            let high = Double(band?.upperBound ?? 0)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                if band != nil {
                    Rectangle()
                        .fill(Theme.recoveryHigh.opacity(0.18))
                        .frame(width: max(3, width * min(1, (high - low) / Self.scale)))
                        .offset(x: width * min(1, low / Self.scale))
                }
                Capsule()
                    .fill(color)
                    .frame(width: max(6, width * min(1, sets / Self.scale)))
            }
        }
        .frame(height: 10)
    }
}

// MARK: - Strength days

/// Strength training on 2+ days a week (WHO 2020), with the lifting "health
/// floor" (2+ days and 30–60 min a week, Momma 2022; Shailendra 2022) and,
/// for muscle and strength goals, this week's cardio minutes as one line.
struct StrengthDaysCard: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Environment(VitalsModel.self) private var vitals
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        let finished = sessions.filter { !$0.isActive && !$0.workingSets.isEmpty }
        let dates = finished.map(\.startedAt)
        let thisWeek = StrengthDays.lastSevenDays(dates)
        let weeks = StrengthDays.weekly(dates, weeks: 4)
        let met = thisWeek >= StrengthDays.weeklyTarget
        let floorStatus = StrengthHealthFloor.assess(finished.map(\.strainSummary))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel(text: "Strength days", color: Theme.lifting)
                Spacer()
                // "Last 7 days", the same rolling window as the number (not the calendar week bars).
                Chip(text: met ? "Met in the last 7 days" : "\(StrengthDays.weeklyTarget - thisWeek) more to go", color: met ? Theme.recoveryHigh : Theme.lifting)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(thisWeek)")
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.primaryText)
                Text("days in the last 7 · goal \(StrengthDays.weeklyTarget)+")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(spacing: 6) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { index, days in
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(days >= StrengthDays.weeklyTarget ? Theme.recoveryHigh : Theme.track)
                            .frame(height: 8)
                        Text(index == weeks.count - 1 ? "This week" : "\(weeks.count - 1 - index)w ago")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(index == weeks.count - 1 ? "This week" : "\(weeks.count - 1 - index) weeks ago"): \(days) strength days")
                }
            }
            healthFloor(floorStatus)
            if WeeklyActivityBand.emphasis(for: metrics.goals) == .secondary {
                cardioLine
            }
        }
        .card()
    }

    /// Met / not met this week: 2+ days and 30+ minutes (Momma 2022; Shailendra 2022).
    private func healthFloor(_ floor: StrengthHealthFloor.Result) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: floor.isMet ? "checkmark.seal.fill" : "seal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(floor.isMet ? Theme.recoveryHigh : Theme.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Health floor · \(floor.summary)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(StrengthHealthFloor.explanation)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// For muscle and strength goals the 150-minute WHO floor is enough, so
    /// cardio minutes sit here as a line instead of their own card (`WeeklyActivityBand`).
    private var cardioLine: some View {
        let total = vitals.intensityMinutes?.total ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(Theme.separator)
            Text("Cardio minutes, last 7 days: \(WeeklyActivityBand.line(total: total, goals: metrics.goals))")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Weekly active minutes

/// This week's moderate and vigorous minutes against the 150-floor / 300-best
/// band (WHO 2020, Bull et al.; Lee et al., Circulation 2022). Vigorous minutes
/// count double, as `IntensityMinutes` already does. Shown as its own card for
/// health, stamina and weight-loss goals (`WeeklyActivityBand.emphasis`).
struct WeeklyMinutesCard: View {
    @Environment(VitalsModel.self) private var vitals
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        let minutes = vitals.intensityMinutes ?? IntensityMinutes.Result(moderate: 0, vigorous: 0)
        let status = WeeklyActivityBand.status(total: minutes.total)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel(text: "Weekly active minutes", color: Theme.oxygen)
                Spacer()
                Chip(text: status.rawValue, color: status == .belowFloor ? Theme.oxygen : Theme.recoveryHigh)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(minutes.total)")
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.primaryText)
                // A band, not a cap: "522 of 300" read like a target overshot.
                Text("min, last 7 days · aim \(WeeklyActivityBand.floorMinutes)–\(WeeklyActivityBand.bestMinutes)+")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            MinutesBandBar(total: minutes.total)
            Text("\(minutes.moderate) moderate + \(minutes.vigorous) vigorous ×2, from heart rate over the last 7 days.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text(WeeklyActivityBand.line(total: minutes.total, goals: metrics.goals))
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            EvidenceDisclosure(points: [
                "WHO: 150–300 minutes moderate or 75–150 vigorous a week (Bull et al., Br J Sports Med 2020).",
                "In a 30-year cohort of 116,221 adults, risk was lowest from about 300 moderate-equivalent minutes, with no extra benefit or harm above (Lee et al., Circulation 2022).",
            ])
        }
        .card(tint: Theme.oxygen)
    }
}

/// Minutes on a 0–360 bar with the 150–300 band shaded.
struct MinutesBandBar: View {
    let total: Int

    private let scale = Double(WeeklyActivityBand.scaleMinutes)
    private let floorMinutes = WeeklyActivityBand.floorMinutes
    private let bestMinutes = WeeklyActivityBand.bestMinutes

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                let floorX = width * Double(floorMinutes) / scale
                let bestX = width * Double(bestMinutes) / scale
                let fillX = width * min(1, Double(total) / scale)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Rectangle()
                        .fill(Theme.recoveryHigh.opacity(0.18))
                        .frame(width: max(0, bestX - floorX))
                        .offset(x: floorX)
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.oxygenLight, Theme.oxygen], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, fillX))
                }
            }
            .frame(height: 12)
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    Text("0")
                    Text("\(floorMinutes) floor")
                        .foregroundStyle(Theme.recoveryHigh)
                        .offset(x: width * Double(floorMinutes) / scale - 18)
                    Text("\(bestMinutes) best")
                        .foregroundStyle(Theme.recoveryHigh)
                        .offset(x: width * Double(bestMinutes) / scale - 26)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total) active minutes in the last 7 days; floor \(floorMinutes), best \(bestMinutes)")
    }
}

// MARK: - Cardio fitness

/// The Fitness headline: VO₂ max with its 90-day trend, where it sits against
/// people your age and sex on a FRIEND percentile bar (`VO2Norms`, with the
/// no-test estimates marked), a fitness age from this one measure, the
/// interval nudge when the trend is flat or falling, and tips to raise it
/// (`CardioFitness`; Mandsager 2018; Kokkinos 2022; Milanović 2015; Wen 2019).
struct CardioFitnessCard: View {
    @Environment(VitalsModel.self) private var vitals
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        let history = vitals.vo2MaxHistory
        let series = history.map { DayValue(date: $0.date, value: $0.value) }
        let result = CardioFitness.assess(series, age: settings.age, sex: settings.sex)
        let trend = CardioFitness.trend(series)
        let estimates = VO2Estimates(vitals: vitals, settings: settings, metrics: metrics, sessions: sessions)
        // One number, one bar, one line, two tips; everything else under Details.
        let value = result?.latest ?? estimates.average
        let isEstimate = result == nil
        let category = value.map { VO2Norms.category(vo2: $0, age: settings.age, sex: settings.sex) }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardLabel(text: "Cardio fitness (VO₂ max)", color: Theme.oxygen)
                Spacer()
                if let category {
                    Chip(text: category.name, color: category.chipColor)
                }
            }
            hero(value: value, isEstimate: isEstimate, trend: trend)
            VO2LevelBar(age: settings.age, sex: settings.sex, value: value, isEstimate: isEstimate)
            if let value {
                Text(VO2Norms.standing(vo2: value, age: settings.age, sex: settings.sex).percentileText + ".")
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if result != nil {
                trendChart(history)
            }
            tips(category ?? .average)
            DisclosureGroup("Details") {
                details(result, history: history, estimates: estimates)
                    .padding(.top, 8)
            }
            .font(.subheadline.weight(.semibold))
            .tint(Theme.secondaryText)
        }
        .card(tint: Theme.oxygen)
    }

    /// The big number: the watch reading, else the average of the two estimates.
    private func hero(value: Double?, isEstimate: Bool, trend: CardioFitness.Trend?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value.map { (isEstimate ? "≈" : "") + $0.formatted(.number.precision(.fractionLength(isEstimate ? 0 : 1))) } ?? "–")
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.primaryText)
                Text("ml/kg/min")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(isEstimate
                 ? (value == nil ? "No reading yet: walk or run outdoors 20+ min with your Watch." : "Estimate · no Apple Watch reading yet")
                 : trendText(trend))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Everything that used to crowd the card: the estimates, other
    /// comparisons, fitness age, where readings come from, and the evidence.
    @ViewBuilder
    private func details(_ result: CardioFitness.Result?, history: [DatedValue], estimates: VO2Estimates) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let heart = estimates.heart {
                EstimateRow(title: "Estimate from heart rate", result: heart.result, detail: heart.detail)
            }
            if let activity = estimates.activity {
                EstimateRow(title: "Estimate from activity, lifting included", result: activity.result, detail: activity.detail)
            }
            ForEach(VO2Norms.references(age: settings.age, sex: settings.sex)) { reference in
                HStack {
                    Text(reference.label)
                    Spacer()
                    Text(reference.kind == .topTen ? "\(Int(reference.value.rounded()))+" : "\(Int(reference.value.rounded()))")
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            }
            if let result {
                fitnessAgeLine(result)
                Text("Watch VO₂ max is an estimate, about 10% low in fit people; watch the trend.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Text("Apple Watch only measures VO₂ max on outdoor walks, runs and hikes, so lifting never gives a reading. The two estimates above need no test but are rough (about ±5).")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            EvidenceDisclosure(points: Self.evidence + Self.estimateEvidence + tipEvidence(result, estimates: estimates))
        }
        .font(.subheadline)
        .fontWeight(.regular)
    }

    /// The studies behind the two tips on the card.
    private func tipEvidence(_ result: CardioFitness.Result?, estimates: VO2Estimates) -> [String] {
        let value = result?.latest ?? estimates.average
        let category = value.map { VO2Norms.category(vo2: $0, age: settings.age, sex: settings.sex) } ?? .average
        let goals: Goals? = settings.goalsSet ? settings.goals : nil
        let lifts = goals.map { $0.focuses.contains(.muscle) || $0.focuses.contains(.strength) } ?? true
        return VO2Norms.tips(category: category, lifts: lifts, losingWeight: goals?.weight == .lose).prefix(2).map(\.evidence)
    }

    static let estimateEvidence = [
        "Heart-rate estimate: VO₂ max ≈ 15.3 × max HR ÷ resting HR (Uth et al., Eur J Appl Physiol 2004).",
        "Activity estimate: the NASA non-exercise model (Jackson et al., Med Sci Sports Exerc 1990); lifting counts as moderate activity, hard heart-rate minutes from any workout as hard exercise.",
        "Bands: percentiles of measured treadmill VO₂ max by age and sex (FRIEND registry; Kaminsky et al., Mayo Clin Proc 2015).",
    ]

    private func comparison(watch: Double?, estimates: VO2Estimates) -> some View {
        VO2Comparison(age: settings.age, sex: settings.sex, watch: watch, estimates: estimates.marks)
    }

    /// Tips by level; the lifting tip for muscle or strength goals (or before
    /// goals are set: this is a gym app), the per-kilogram tip when losing weight.
    private func tips(_ category: VO2Norms.Category) -> some View {
        let goals: Goals? = settings.goalsSet ? settings.goals : nil
        let lifts = goals.map { $0.focuses.contains(.muscle) || $0.focuses.contains(.strength) } ?? true
        return VO2Tips(category: category, lifts: lifts, losingWeight: goals?.weight == .lose)
    }

    private func header(_ result: CardioFitness.Result?) -> some View {
        HStack {
            CardLabel(text: "Cardio fitness (VO₂ max)", color: Theme.oxygen)
            Spacer()
            if let result {
                Chip(text: result.label, color: result.category.chipColor)
            }
        }
    }

    private func headline(_ result: CardioFitness.Result, trend: CardioFitness.Trend?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(result.latest.formatted(.number.precision(.fractionLength(1))))
                .font(.largeTitle.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(Theme.primaryText)
            Text("ml/kg/min")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(trendText(trend))
                .font(.caption.weight(.semibold))
                .foregroundStyle(trend?.direction == .rising ? Theme.recoveryHighText : Theme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    /// "+1.2 vs 2 months ago, rising" / "Flat vs 2 months ago" / "needs 90 days of readings"
    /// (`CardioFitness.trend`: the last 30 days against the first 30 of 90).
    private func trendText(_ trend: CardioFitness.Trend?) -> String {
        guard let trend, let change = trend.change else { return "Needs readings across 90 days" }
        guard trend.direction != .flat else { return "Flat vs 2 months ago" }
        let amount = "\(change >= 0 ? "+" : "−")\(abs(change).formatted(.number.precision(.fractionLength(1))))"
        return "\(amount) vs 2 months ago, \(trend.direction.rawValue)"
    }

    /// The last 90 days of readings.
    @ViewBuilder
    private func trendChart(_ history: [DatedValue]) -> some View {
        let start = Date.now.addingTimeInterval(-Double(CardioFitness.trendDays) * 86_400)
        let recent = history.filter { $0.date >= start }
        if recent.count >= 2 {
            Sparkline(values: recent, color: Theme.oxygen)
                .frame(height: 56)
        }
    }

    /// The same FRIEND median as the bar's "Avg" tick (`VO2Norms.median`).
    private func normsLine(_ result: CardioFitness.Result) -> some View {
        let noun = settings.sex == .male ? "man" : "woman"
        let median = result.median.formatted(.number.precision(.fractionLength(0)))
        // Says so while sex or age are stand-ins (`UserSettings.normsStandInNote`).
        let standIn = settings.normsStandInNote.map { " " + $0 } ?? ""
        return Text("You're at \(Int(result.percentOfMedian.rounded()))% of the typical \(noun) your age (\(median)).\(standIn)")
            .font(.subheadline)
            .foregroundStyle(Theme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Fitness age from VO₂ max alone (FRIEND medians, the same as the norms line; Nes 2011), with the
    /// ±5-year range a watch estimate deserves. An estimate from one measure.
    private func fitnessAgeLine(_ result: CardioFitness.Result) -> some View {
        let age = CardioFitness.fitnessAge(vo2Max: result.latest, age: settings.age, sex: settings.sex)
        let spread = CardioFitness.watchUncertaintyYears
        return Text("Fitness age about \(age) (\(max(18, age - spread))–\(age + spread)): the age whose typical VO₂ max matches yours, estimated from this one measure (FRIEND; Nes 2011). Your age: \(settings.ageText).")
            .font(.subheadline)
            .foregroundStyle(Theme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func adviceLabel(_ result: CardioFitness.Result, trend: CardioFitness.Trend?) -> some View {
        let nudging = trend.flatMap(CardioFitness.nudge(for:)) != nil || (trend?.change == nil && result.isPlateau)
        return Label {
            Text(advice(result, trend: trend))
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: nudging ? "arrow.up.right.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(nudging ? Theme.strain : Theme.recoveryHigh)
        }
    }

    /// The interval tip in plain words; its studies are in `evidence`
    /// (Milanović 2015; Wen 2019; Storoschuk 2025).
    static let intervalTip = "1–2 sessions a week of 4 × 4-minute hard intervals (3 minutes easy between) raise VO₂ max the most."

    static let evidence = [
        "Higher fitness is strongly linked with longer life, with no upper limit found (Mandsager et al., JAMA Netw Open 2018; Kokkinos et al., J Am Coll Cardiol 2022).",
        "High-intensity intervals raised VO₂ max more than steady cardio in meta-analyses (Milanović et al., Sports Med 2015; Wen et al., J Sports Sci 2019).",
        "Easy cardio builds a base but isn't the main way to raise VO₂ max (Storoschuk et al. 2025).",
        "Typical values and percentiles by age and sex: FRIEND registry, 7,783 treadmill lab tests of US adults 20–79 (Kaminsky et al., Mayo Clin Proc 2015). The percentile is approximate, read between the table's cut points; band names are the app's.",
        "Average adult: FRIEND's all-ages means for men (37.9) and women (27.6), pooled by the app.",
    ]

    /// The 90-day trend decides: flat or falling → the interval nudge
    /// (Milanović 2015; Wen 2019); rising → keep going. Without 90 days of
    /// readings, the 8-week comparison from `CardioFitness.assess` stands in.
    private func advice(_ result: CardioFitness.Result, trend: CardioFitness.Trend?) -> String {
        if let trend, CardioFitness.nudge(for: trend) != nil {
            let lead = trend.direction == .falling ? "It has fallen over 90 days. " : "It has been flat over 90 days. "
            return lead + Self.intervalTip + " Keep easy, conversational cardio as your base."
        }
        if trend?.direction == .rising {
            return "It's rising over 90 days. Keep the mix of easy cardio and 1-2 harder sessions a week."
        }
        if result.isPlateau {
            return "It hasn't risen in about 8 weeks. " + Self.intervalTip
        }
        if let change = result.change, change >= CardioFitness.meaningfulChange {
            return "It's rising. Keep the mix of easy cardio and 1-2 harder sessions a week."
        }
        return "Keep at least 150 minutes of moderate cardio a week, with 1-2 harder interval sessions to keep it improving."
    }
}

// MARK: - Strength for health

/// Relative strength (best e1RM ÷ body weight) for bench, squat and
/// deadlift against age-and-sex bands (`StrengthForHealth`): a health marker
/// next to VO₂ max, not a leaderboard. The bands are an app choice adapted
/// from strength-standards tables; the mortality link is for strength in
/// general (García-Hermoso 2018; Leong 2015).
struct StrengthForHealthCard: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(GymStore.self) private var gym

    var body: some View {
        let results = StrengthForHealth.assess(lifts: bestLifts, bodyMassKg: bodyMassKg, sex: settings.sex, age: settings.age)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel(text: "Strength for health", color: Theme.lifting)
                Spacer()
                Chip(text: "App choice", color: Theme.secondaryText)
            }
            ForEach(results) { result in
                liftRow(result)
            }
            Text(StrengthForHealth.summary(results, goals: metrics.goals))
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Best estimated 1RM ÷ body weight from the last year's sets. " + StrengthForHealth.evidenceNote)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    /// Body weight from Apple Health, else the profile.
    private var bodyMassKg: Double {
        metrics.bodyMassKg ?? settings.weightKg
    }

    /// Best e1RM per exercise name over the last year (completed working sets).
    private var bestLifts: [(name: String, estimatedOneRepMaxKg: Double)] {
        let cutoff = Date.now.addingTimeInterval(-365 * 86_400)
        var best: [String: Double] = [:]
        for session in sessions where !session.isActive && session.startedAt >= cutoff {
            for exercise in session.exercises {
                let top = exercise.sets.filter { $0.isCompleted && !$0.isWarmup }.map(\.estimatedOneRepMax).max() ?? 0
                if top > 0 { best[exercise.name] = max(best[exercise.name] ?? 0, top) }
            }
        }
        return best.map { (name: $0.key, estimatedOneRepMaxKg: $0.value) }
    }

    private func liftRow(_ result: StrengthForHealth.Result) -> some View {
        // Lifts in the gym's unit, as on every lifting screen (`GymStore.liftingUnit`).
        let unit = gym.liftingUnit
        let e1RM = unit.display(result.estimatedOneRepMaxKg).formatted(.number.precision(.fractionLength(0)))
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.lift.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("e1RM \(e1RM) \(unit.rawValue) · \(result.ratio.formatted(.number.precision(.fractionLength(2)))) × body weight")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            BandDots(band: result.band)
            Chip(text: result.band.label, color: result.band >= StrengthForHealth.healthTargetBand ? Theme.recoveryHigh : Theme.lifting)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result.lift.name): \(result.band.label), \(result.ratio.formatted(.number.precision(.fractionLength(2)))) times body weight")
    }
}

/// Five dots, filled up to the band.
private struct BandDots: View {
    let band: StrengthForHealth.Band

    var body: some View {
        HStack(spacing: 3) {
            ForEach(StrengthForHealth.Band.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step <= band ? Theme.lifting : Theme.track)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Where VO₂ max comes from, so a lifter isn't left wondering why their
/// sessions don't move it. Apple Watch estimates VO₂ max only from outdoor
/// walks, runs and hikes (about 20 minutes or more, with GPS and heart rate:
/// Apple, "Using Apple Watch to estimate cardio fitness", 2021); strength
/// workouts give no reading. Lifting heart rate still counts toward the weekly
/// minutes. Resistance training raised VO₂ max in older adults but not clearly
/// in younger ones (Ozaki et al., Eur Rev Aging Phys Act 2013, meta-analysis).
private struct VO2SourceNote: View {
    let lastReading: Date?

    /// Two weeks without a reading: say how to get a new one (app choice).
    private static let staleDays = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Where it comes from", systemImage: "figure.walk")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.track.opacity(0.6), in: .rect(cornerRadius: 12))
    }

    private var text: String {
        var parts = ["Apple Watch only measures VO₂ max on outdoor walks, runs and hikes. Lifting doesn't give a reading, though its heart-rate minutes still count toward your weekly minutes."]
        if let lastReading {
            let days = Calendar.current.dateComponents([.day], from: lastReading, to: .now).day ?? 0
            let date = lastReading.formatted(.dateTime.month(.abbreviated).day())
            if days >= Self.staleDays {
                parts.append("Last reading \(date), \(days) days ago. For a new one, walk briskly or run outdoors for 20+ minutes with your Watch.")
            } else {
                parts.append("Last reading \(date).")
            }
        } else {
            parts.append("For a first reading, walk briskly or run outdoors for 20+ minutes with your Watch.")
        }
        return parts.joined(separator: " ")
    }
}

/// Two VO₂ max estimates that need no test (`VO2MaxEstimate`): from resting
/// and max heart rate (Uth 2004), and from activity with lifting counted
/// (Jackson 1990). Shown beside the watch value, never instead of it.
private struct VO2EstimatesSection: View {
    let estimates: VO2Estimates

    var body: some View {
        let heart = estimates.heart
        let activity = estimates.activity
        if heart != nil || activity != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Estimates without a test")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(.uppercase)
                if let heart {
                    EstimateRow(title: "From your heart rate", result: heart.result, detail: heart.detail)
                }
                if let activity {
                    EstimateRow(title: "From your activity, lifting included", result: activity.result, detail: activity.detail)
                }
                Text("Rough guides, about ±5 mL/kg/min. A watch reading, when there is one, is closer to a lab test.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                EvidenceDisclosure(points: [
                    "Heart rate: VO₂ max ≈ 15.3 × max HR ÷ resting HR (Uth et al., Eur J Appl Physiol 2004). Built in trained men; less accurate in other groups and with an age-based max.",
                    "Activity: the NASA non-exercise model from age, sex, body size and a 0-7 activity level (Jackson et al., Med Sci Sports Exerc 1990). Its scale counts weight lifting as moderate activity; hard heart-rate minutes from any workout, lifting included, count as hard exercise.",
                    "Lifting on its own raises VO₂ max only a little, mostly in older or untrained people (Ozaki et al., Eur Rev Aging Phys Act 2013).",
                ], title: "About these estimates")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The two no-test estimates, worked out once for the bar and the rows.
struct VO2Estimates {
    let heart: (result: VO2MaxEstimate.Result, detail: String)?
    let activity: (result: VO2MaxEstimate.Result, detail: String)?

    init(vitals: VitalsModel, settings: UserSettings, metrics: DailyMetricsModel, sessions: [WorkoutSession]) {
        let source = VO2EstimateSource(vitals: vitals, settings: settings, metrics: metrics, sessions: sessions)
        heart = source.heartEstimate
        activity = source.activityEstimate
    }

    /// For the scale bar: hollow marks with their ranges.
    var marks: [VO2EstimateMark] {
        var marks: [VO2EstimateMark] = []
        if let heart = heart?.result {
            marks.append(VO2EstimateMark(kind: .heartRate, value: heart.value, range: heart.range))
        }
        if let activity = activity?.result {
            marks.append(VO2EstimateMark(kind: .activity, value: activity.value, range: activity.range))
        }
        return marks
    }

    /// The estimates' mean, when there's no watch reading.
    var average: Double? {
        let values = marks.map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

/// Reads the inputs for `VO2Estimates`.
private struct VO2EstimateSource {
    let vitals: VitalsModel
    let settings: UserSettings
    let metrics: DailyMetricsModel
    let sessions: [WorkoutSession]

    /// Awake resting heart rate: Apple Health's value averaged over the last
    /// 7 readings (sleeping heart rate runs lower and would inflate the ratio).
    private var restingHeartRate: Double? {
        let recent = (vitals.stat("rhr")?.series ?? []).suffix(7).map(\.value)
        if !recent.isEmpty { return recent.reduce(0, +) / Double(recent.count) }
        // Today's value only when it is Apple Health's awake one, not sleeping heart rate.
        return metrics.restingHeartRateSource == .healthKit ? metrics.restingHeartRate : nil
    }

    var heartEstimate: (result: VO2MaxEstimate.Result, detail: String)? {
        guard let resting = restingHeartRate, let profile = metrics.heartRateProfile else { return nil }
        let measured = settings.maxHeartRate > 0 || settings.learnedMaxOverride != nil
        guard let result = VO2MaxEstimate.heartRateRatio(maxHeartRate: profile.maxHeartRate, restingHeartRate: resting,
                                                         measuredMax: measured) else { return nil }
        let maxText = Int(profile.maxHeartRate.rounded())
        let restText = Int(resting.rounded())
        let source = measured ? "your max" : "age-based max"
        return (result, "\(source) \(maxText) ÷ resting \(restText) bpm")
    }

    var activityEstimate: (result: VO2MaxEstimate.Result, detail: String)? {
        let minutes = vitals.intensityMinutes
        let rating = VO2MaxEstimate.activityRating(vigorousMinutes: Double(minutes?.vigorous ?? 0),
                                                   moderateMinutes: Double(minutes?.moderate ?? 0),
                                                   liftingMinutes: liftingMinutesPerWeek)
        let weight = metrics.bodyMassKg ?? settings.weightKg
        let height = settings.heightCm / 100
        let bmi = height > 0 && weight > 0 ? weight / (height * height) : nil
        guard let result = VO2MaxEstimate.activity(rating: rating, age: settings.age, sex: settings.sex,
                                                   bmi: bmi, bodyFatPercent: metrics.bodyFatPercent) else { return nil }
        let lifting = Int(liftingMinutesPerWeek.rounded())
        return (result, "Level \(rating) of 7: \(VO2MaxEstimate.ratingText(rating)) · lifting \(lifting) min a week")
    }

    /// Logged lifting over the last 4 weeks, per week.
    private var liftingMinutesPerWeek: Double {
        let start = Date.now.addingTimeInterval(-28 * 86_400)
        let total = sessions.prefix(while: { $0.startedAt >= start })
            .filter { !$0.isActive }
            .reduce(0.0) { $0 + min($1.duration, 3 * 3_600) }
        return total / 60 / 4
    }
}

private struct EstimateRow: View {
    let title: String
    let result: VO2MaxEstimate.Result
    let detail: String

    var body: some View {
        let value = Int(result.value.rounded())
        let low = Int(result.range.lowerBound.rounded())
        let high = Int(result.range.upperBound.rounded())
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 8)
                Text("≈\(value)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                Text("(\(low)–\(high))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
