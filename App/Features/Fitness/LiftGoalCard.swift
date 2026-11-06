import SwiftUI
import SwiftData
import Charts
import AppCore

// Long-term lift goals (lifting-features.md §3, pick 6): the e1RM trend with
// a projection band, framed as an approach goal. The maths and the evidence
// notes (McEwan 2016; Swann 2021) are in `LiftGoalProjection`.

/// History and text helpers shared by the lift-goal views.
enum LiftGoalHistory {
    /// Best e1RM per finished session for one exercise, in kg, from
    /// completed working sets of 10 reps or fewer.
    static func samples(exerciseID: String, sessions: [WorkoutSession]) -> [LiftGoalProjection.Sample] {
        let logged = sessions.filter { !$0.isActive }.compactMap { session -> LiftProgress.LoggedSession? in
            let sets = session.exercises
                .filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets)
                .filter { $0.isCompleted && !$0.isWarmup }
                .map { LiftProgress.LoggedSet(weight: $0.weightKg, reps: $0.reps, rpe: $0.rpe) }
            return sets.isEmpty ? nil : LiftProgress.LoggedSession(date: session.startedAt, sets: sets)
        }
        return LiftGoalProjection.series(logged)
    }

    /// The projection for a goal, or nil when a bodyweight goal has no body weight.
    static func projection(for goal: LiftGoal, sessions: [WorkoutSession], bodyMassKg: Double?,
                           trainingStatus: TrainingStatus?) -> LiftGoalProjection.Projection? {
        guard let target = goal.resolvedTargetKg(bodyMassKg: bodyMassKg) else { return nil }
        return LiftGoalProjection.project(samples: samples(exerciseID: goal.exerciseID, sessions: sessions),
                                          targetKg: target, targetDate: goal.targetDate, trainingStatus: trainingStatus)
    }

    /// Whole units with the unit, e.g. "100 kg".
    static func weightText(_ kilograms: Double, unit: WeightUnit) -> String {
        let value = unit.display(kilograms).formatted(.number.precision(.fractionLength(0)))
        return "\(value) \(unit.rawValue)"
    }

    /// "March", or "March 2027" outside this year.
    static func monthText(_ date: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.month(.wide)) : date.formatted(.dateTime.month(.wide).year())
    }

    /// "Bench press 100 kg" or "Squat 1.5 × body weight".
    static func title(_ goal: LiftGoal, unit: WeightUnit) -> String {
        if let multiple = goal.bodyweightMultiple, multiple > 0 {
            let text = multiple.formatted(.number.precision(.fractionLength(0...2)))
            return "\(goal.name) \(text) × body weight"
        }
        if let target = goal.targetKg {
            return "\(goal.name) \(weightText(target, unit: unit))"
        }
        return goal.name
    }

    /// "125 kg" or "1.5 × body weight": the target without the lift's name.
    static func targetText(_ goal: LiftGoal, unit: WeightUnit) -> String {
        if let multiple = goal.bodyweightMultiple, multiple > 0 {
            return "\(multiple.formatted(.number.precision(.fractionLength(0...2)))) × body weight"
        }
        if let target = goal.targetKg {
            return weightText(target, unit: unit)
        }
        return goal.name
    }

    static func headline(_ projection: LiftGoalProjection.Projection, unit: WeightUnit) -> String {
        LiftGoalProjection.headline(projection, weight: { weightText($0, unit: unit) }, month: { monthText($0) })
    }

    static func rangeLine(_ projection: LiftGoalProjection.Projection, unit: WeightUnit) -> String? {
        LiftGoalProjection.rangeLine(projection, weight: { weightText($0, unit: unit) }, month: { monthText($0) })
    }
}

/// One goal: where the lift is, the projection line and band, and the text.
struct LiftGoalCard: View {
    let goal: LiftGoal

    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(GymStore.self) private var gym
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]

    private var unit: WeightUnit { gym.liftingUnit }
    private var bodyMassKg: Double { metrics.bodyMassKg ?? settings.weightKg }

    var body: some View {
        let projection = LiftGoalHistory.projection(for: goal, sessions: sessions, bodyMassKg: bodyMassKg,
                                                    trainingStatus: metrics.trainingStatus)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel(text: "Lift goal", color: Theme.liftingText)
                Spacer()
                if let projection {
                    LiftGoalStatusChip(status: projection.status)
                }
            }
            Text(LiftGoalHistory.title(goal, unit: unit))
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            if let projection {
                LiftGoalProjectionText(projection: projection, unit: unit)
                if !projection.band.isEmpty || projection.recent.count > 1 {
                    LiftGoalChart(projection: projection, unit: unit)
                }
            } else {
                Text("Add your body weight in Apple Health or Settings to use a body-weight goal.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            // e1RM accuracy about ±3 kg from 3-5RM (watch-features.md 3.6 [B22]).
            DisclosureGroup("About the projection") {
                Text(evidence(projection))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .font(.caption)
            .tint(Theme.secondaryText)
        }
        .card()
    }

    private func evidence(_ projection: LiftGoalProjection.Projection?) -> String {
        let accuracy = LiftGoalHistory.weightText(LiftGoalProjection.minimumSpreadKg, unit: unit)
        let note = LiftGoalProjection.evidenceNote + " Estimated 1RMs are good to about ±" + accuracy + "."
        // How the line was adjusted for this lifter goes first (QA round 4: not in the main text).
        guard let projection, let adjusted = LiftGoalProjection.adjustmentNote(projection) else { return note }
        return adjusted + " " + note
    }
}

/// Neutral chips: an off-trend goal isn't a warning (Swann 2021).
private struct LiftGoalStatusChip: View {
    let status: LiftGoalProjection.Status

    var body: some View {
        switch status {
        case .reached: Chip(text: "Reached", color: Theme.recoveryHigh)
        case .onTrend: Chip(text: "On the current trend", color: Theme.recoveryHigh)
        case .possible: Chip(text: "Possible", color: Theme.secondaryText)
        case .notOnTrend: Chip(text: "Open", color: Theme.secondaryText)
        case .needsMoreData: Chip(text: "Building history", color: Theme.secondaryText)
        }
    }
}

private struct LiftGoalProjectionText: View {
    let projection: LiftGoalProjection.Projection
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LiftGoalHistory.headline(projection, unit: unit))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let range = LiftGoalHistory.rangeLine(projection, unit: unit) {
                Text(range)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let open = LiftGoalProjection.openAlternative(projection, month: { LiftGoalHistory.monthText($0) }) {
                Text(open)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Last 12 weeks' e1RMs, the projected line with its band, and the target.
private struct LiftGoalChart: View {
    let projection: LiftGoalProjection.Projection
    let unit: WeightUnit

    var body: some View {
        Chart {
            ForEach(projection.band) { point in
                AreaMark(x: .value("Date", point.date),
                         yStart: .value("Low", unit.display(point.low)),
                         yEnd: .value("High", unit.display(point.high)))
                    .foregroundStyle(Theme.lifting.opacity(0.18))
                LineMark(x: .value("Date", point.date), y: .value("Trend", unit.display(point.mid)),
                         series: .value("Series", "Projection"))
                    .foregroundStyle(Theme.lifting.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            ForEach(projection.recent) { sample in
                LineMark(x: .value("Date", sample.date), y: .value("e1RM", unit.display(sample.kg)),
                         series: .value("Series", "Logged"))
                    .foregroundStyle(Theme.lifting)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                PointMark(x: .value("Date", sample.date), y: .value("e1RM", unit.display(sample.kg)))
                    .foregroundStyle(Theme.lifting)
                    .symbolSize(30)
            }
            RuleMark(y: .value("Target", unit.display(projection.targetKg)))
                .foregroundStyle(Theme.secondaryText.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text("Goal \(LiftGoalHistory.weightText(projection.targetKg, unit: unit))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        // Every month, dropping labels that would collide (greedy), so even a
        // short chart (a reached goal has no band ahead) gets month labels.
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated), collisionResolution: .greedy)
            }
        }
        .frame(height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated one-rep max over the last 12 weeks, with the projected range and the target line")
    }
}

/// Every lift goal, for Fitness › Progress › Lift goals; a prompt when there are none.
struct LiftGoalsSection: View {
    @Environment(UserSettings.self) private var settings

    var body: some View {
        let goals = settings.goals.liftGoals
        if goals.isEmpty {
            NavigationLink {
                GoalsView(pushed: true)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    CardLabel(text: "Lift goal", color: Theme.liftingText)
                    Text("Set a target lift in Goals to see where your trend is heading.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .buttonStyle(.plain)
        } else {
            ForEach(goals) { goal in
                LiftGoalCard(goal: goal)
            }
        }
    }
}

/// Fitness › Progress › Lift goals: every goal card on its own page, so the
/// row opens the goals rather than the whole Strength page.
struct LiftGoalsDetailView: View {
    var body: some View {
        FitnessDetailPage(title: "Lift goals") {
            LiftGoalsSection()
        }
    }
}

/// One line that opens Fitness › Progress › Lift goals, so the goal cards
/// live on one page only (QA round 4). With an exercise, only when it has a
/// goal ("Goal: 115 kg"); without, the first goal or "Set a target lift".
struct LiftGoalsLink: View {
    var exerciseID: String?
    @Environment(UserSettings.self) private var settings
    @Environment(GymStore.self) private var gym

    var body: some View {
        let all = settings.goals.liftGoals
        let goals = exerciseID.map { id in all.filter { $0.exerciseID == id } } ?? all
        if exerciseID == nil || !goals.isEmpty {
            NavigationLink {
                LiftGoalsDetailView()
            } label: {
                HStack(spacing: 10) {
                    Label(text(goals), systemImage: "flag.checkered")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .card()
            .accessibilityHint("Shows your lift goals and where the trend is heading")
        }
    }

    private func text(_ goals: [LiftGoal]) -> String {
        guard let first = goals.first else { return "Lift goals: set a target lift" }
        let target = LiftGoalHistory.targetText(first, unit: gym.liftingUnit)
        if exerciseID != nil { return "Goal: \(target)" }
        return goals.count > 1 ? "Lift goals (\(goals.count)) · \(first.name) \(target)" : "Lift goal · \(first.name) \(target)"
    }
}

/// Fitness › Progress row: progress toward the first lift goal.
struct LiftGoalsMetricRow: View {
    @Environment(UserSettings.self) private var settings
    @Environment(GymStore.self) private var gym
    @Environment(DailyMetricsModel.self) private var metrics
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]

    var body: some View {
        let goals = settings.goals.liftGoals
        let first = goals.first
        let projection = first.flatMap {
            LiftGoalHistory.projection(for: $0, sessions: sessions, bodyMassKg: metrics.bodyMassKg ?? settings.weightKg,
                                       trainingStatus: metrics.trainingStatus)
        }
        let percent = projection?.progress.map { "\(Int(($0 * 100).rounded()))%" }
        // Short pieces so nothing truncates: the lift in the title, the target in the unit.
        let unitText = first.map { "of " + LiftGoalHistory.targetText($0, unit: gym.liftingUnit) } ?? "Set a target lift"
        let title: String
        if let first {
            title = goals.count > 1 ? "Lift goals (\(goals.count)) · \(first.name)" : "\(first.name) goal"
        } else {
            title = "Lift goal"
        }
        return MetricRow(
            title: title,
            value: percent,
            unit: unitText,
            verdict: verdict(projection?.status),
            hint: "Shows your lift goals and where the trend is heading",
            destination: LiftGoalsDetailView()
        )
    }

    private func verdict(_ status: LiftGoalProjection.Status?) -> MetricVerdict? {
        switch status {
        case .reached: MetricVerdict("Reached", color: Theme.recoveryHigh)
        case .onTrend: MetricVerdict("On the current trend", color: Theme.recoveryHigh)
        default: nil
        }
    }
}

/// One weekly-review line per lift goal.
enum LiftGoalReview {
    struct Line {
        var id: String
        var title: String
        var value: String
        var detail: String
    }

    static func lines(goals: [LiftGoal], sessions: [WorkoutSession], bodyMassKg: Double?,
                      trainingStatus: TrainingStatus?, unit: WeightUnit) -> [Line] {
        goals.compactMap { goal -> Line? in
            guard let projection = LiftGoalHistory.projection(for: goal, sessions: sessions, bodyMassKg: bodyMassKg,
                                                              trainingStatus: trainingStatus) else { return nil }
            let target = LiftGoalHistory.weightText(projection.targetKg, unit: unit)
            let value: String
            if projection.status == .reached, let best = projection.recent.map(\.kg).max() {
                value = "\(LiftGoalHistory.weightText(best, unit: unit)) · \(target) goal reached"
            } else if let latest = projection.latestKg {
                value = "\(LiftGoalHistory.weightText(latest, unit: unit)) of \(target)"
            } else {
                value = "Target \(target)"
            }
            // The headline only; the range and its notes are on the goal card.
            let detail = LiftGoalHistory.headline(projection, unit: unit)
            return Line(id: "lift-\(goal.id.uuidString)", title: "\(goal.name) goal", value: value, detail: detail)
        }
    }
}
