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
        // This block week's target per muscle (`VolumeProgression`), drawn as a tick on each bar.
        let targets = plans.volumeTargets(muscles: muscles)?.sets ?? [:]
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
                Text(Self.targetChip(targets))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.recoveryHighText)
            }
            if !anyTrained {
                Text(sinceMonday ? "Log a gym session and each muscle's sets since Monday show here."
                                 : "Log a gym session and each muscle's sets for the last 7 days show here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(states) { state in
                    row(state, target: targets[state.muscle], period: sinceMonday ? "since Monday" : "in the last 7 days")
                }
                Text("A hard set is one taken within about 4 reps of failure. About 10-20 a week per muscle builds the most muscle for most people (Schoenfeld et al., J Sports Sci 2017); more still helps a little, with diminishing returns past 20 (Pelland et al., Sports Med 2026). Sets for helper muscles (e.g. triceps on bench press) count as half.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                if !targets.isEmpty {
                    Text("The tick on each bar is this block week's target for that muscle.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .card()
    }

    /// "Block target 8-12" for this week's per-muscle targets (the ticks);
    /// "Target 10-20" without a block (Schoenfeld et al. 2017).
    private static func targetChip(_ targets: [Muscle: Int]) -> String {
        let values = shown.compactMap { targets[$0] }
        guard let low = values.min(), let high = values.max() else { return "Target 10-20" }
        return low == high ? "Block target \(low)" : "Block target \(low)-\(high)"
    }

    private func row(_ state: MuscleRecovery.State, target: Int?, period: String) -> some View {
        let sets = state.weeklySets
        let color: Color = switch state.volume {
        case .none, .low: Theme.oxygen
        case .productive: Theme.recoveryHigh
        case .high: Theme.strain
        }
        // Name beside the bar normally; above it at accessibility sizes.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let targetText = target.map { ", target \($0) sets" } ?? ""
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Text(state.muscle.name)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .frame(width: stacked ? nil : nameWidth, alignment: .leading)
                .lineLimit(stacked ? 2 : 1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 10) {
                bar(sets: sets, color: color, target: target)
                Text(sets.formatted(.number.precision(.fractionLength(0...1))))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: countWidth, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.muscle.name): \(sets.formatted(.number.precision(.fractionLength(0...1)))) hard sets \(period), \(state.volume.rawValue.lowercased())\(targetText)")
    }

    private func bar(sets: Double, color: Color, target: Int?) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                // The 10-20 band.
                Rectangle()
                    .fill(Theme.recoveryHigh.opacity(0.18))
                    .frame(width: width * 10 / Self.scale)
                    .offset(x: width * 10 / Self.scale)
                Capsule()
                    .fill(color)
                    .frame(width: max(6, width * min(1, sets / Self.scale)))
                if let target {
                    Rectangle()
                        .fill(Theme.primaryText)
                        .frame(width: 2, height: 14)
                        .offset(x: width * min(1, Double(target) / Self.scale) - 1)
                }
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
                Chip(text: met ? "Goal reached" : "\(StrengthDays.weeklyTarget - thisWeek) more this week", color: met ? Theme.recoveryHigh : Theme.lifting)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(thisWeek)")
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.primaryText)
                Text("of \(StrengthDays.weeklyTarget)+ days in the last 7")
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
            Text("Cardio minutes this week: \(WeeklyActivityBand.line(total: total, goals: metrics.goals))")
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
                Text("of \(WeeklyActivityBand.target(for: metrics.goals)) this week")
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
            Text("WHO: 150–300 minutes moderate or 75–150 vigorous a week (Bull 2020). In a 30-year cohort of 116,221 adults, risk was lowest from about 300 moderate-equivalent minutes, with no extra benefit or harm above (Lee 2022).")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityLabel("\(total) active minutes this week; floor \(floorMinutes), best \(bestMinutes)")
    }
}

// MARK: - Cardio fitness

/// The Fitness headline: VO₂ max with its 90-day trend, where it sits against
/// people your age and sex, a fitness age from this one measure, and the
/// interval nudge when the trend is flat or falling (`CardioFitness`;
/// Mandsager 2018; Kokkinos 2022; Milanović 2015; Wen 2019).
struct CardioFitnessCard: View {
    @Environment(VitalsModel.self) private var vitals
    @Environment(UserSettings.self) private var settings

    var body: some View {
        let history = vitals.vo2MaxHistory
        let series = history.map { DayValue(date: $0.date, value: $0.value) }
        let result = CardioFitness.assess(series, age: settings.age, sex: settings.sex)
        let trend = CardioFitness.trend(series)
        VStack(alignment: .leading, spacing: 10) {
            header(result)
            if let result {
                headline(result, trend: trend)
                trendChart(history)
                normsLine(result)
                fitnessAgeLine(result)
                adviceLabel(result, trend: trend)
                Text("Higher fitness is strongly linked with longer life, with no upper limit found (Mandsager et al., JAMA Netw Open 2018; Kokkinos et al., J Am Coll Cardiol 2022). Watch VO₂ max is an estimate, about 10% low in fit people; watch the trend.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No VO₂ max yet. Your watch estimates it from outdoor walks and runs with heart rate; it appears here once it's in Apple Health.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(tint: Theme.oxygen)
    }

    private func header(_ result: CardioFitness.Result?) -> some View {
        HStack {
            CardLabel(text: "Cardio fitness (VO₂ max)", color: Theme.oxygen)
            Spacer()
            if let result {
                Chip(text: result.label, color: result.label == "Poor" ? Theme.recoveryModerate : Theme.recoveryHigh)
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

    /// "+1.2 over 90 days, rising" / "flat over 90 days" / "needs 90 days of readings"
    private func trendText(_ trend: CardioFitness.Trend?) -> String {
        guard let trend, let change = trend.change else { return "Needs readings across 90 days" }
        let amount = "\(change >= 0 ? "+" : "−")\(abs(change).formatted(.number.precision(.fractionLength(1))))"
        return "\(amount) over 90 days, \(trend.direction.rawValue)"
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

    private func normsLine(_ result: CardioFitness.Result) -> some View {
        Text("The typical \(settings.sex == .male ? "man" : "woman") your age is about \(result.median.formatted(.number.precision(.fractionLength(0)))); you're at \(Int(result.percentOfMedian.rounded()))% of that (FRIEND registry, Kaminsky et al., Mayo Clin Proc 2015).")
            .font(.subheadline)
            .foregroundStyle(Theme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Fitness age from VO₂ max alone (Loe 2013 norms; Nes 2011), with the
    /// ±5-year range a watch estimate deserves. An estimate from one measure.
    private func fitnessAgeLine(_ result: CardioFitness.Result) -> some View {
        let age = CardioFitness.fitnessAge(vo2Max: result.latest, sex: settings.sex)
        let spread = CardioFitness.watchUncertaintyYears
        return Text("Fitness age about \(age) (\(max(18, age - spread))–\(age + spread)): the age whose average VO₂ max matches yours, estimated from this one measure (Loe 2013; Nes 2011). Your age: \(settings.age).")
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

    /// The 90-day trend decides: flat or falling → the interval nudge
    /// (Milanović 2015; Wen 2019); rising → keep going. Without 90 days of
    /// readings, the 8-week comparison from `CardioFitness.assess` stands in.
    private func advice(_ result: CardioFitness.Result, trend: CardioFitness.Trend?) -> String {
        if let trend, let nudge = CardioFitness.nudge(for: trend) {
            let lead = trend.direction == .falling ? "It has fallen over 90 days. " : "It has been flat over 90 days. "
            return lead + nudge + " Keep easy, conversational cardio as your base, not as the way to push VO₂ max up (Storoschuk 2025)."
        }
        if trend?.direction == .rising {
            return "It's rising over 90 days. Keep the mix of easy cardio and 1-2 harder sessions a week."
        }
        if result.isPlateau {
            return "It hasn't risen in about 8 weeks. " + CardioFitness.intervalNudge
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
