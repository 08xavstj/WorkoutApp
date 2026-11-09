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
    /// completed working sets of 10 reps or fewer. Drop stages and mini-sets
    /// are left out (lighter or fatigued by design), as in the PR logic (`LiftHistory`).
    static func samples(exerciseID: String, sessions: [WorkoutSession]) -> [LiftGoalProjection.Sample] {
        let logged = sessions.filter { !$0.isActive }.compactMap { session -> LiftProgress.LoggedSession? in
            let sets = session.exercises
                .filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets)
                .filter { $0.isCompleted && !$0.isWarmup && !$0.kind.isStage }
                .map { LiftProgress.LoggedSet(weight: $0.weightKg, reps: $0.reps, rpe: $0.rpe) }
            return sets.isEmpty ? nil : LiftProgress.LoggedSession(date: session.startedAt, sets: sets)
        }
        return LiftGoalProjection.series(logged)
    }

    /// Another lift for the same movement (`ExerciseCatalog.slot`) logged in the
    /// last 4 weeks while the goal's own lift wasn't: the goal only tracks its
    /// own lift, so the card says so instead of going quiet. Nil otherwise.
    static func recentVariant(of goal: LiftGoal, sessions: [WorkoutSession], now: Date = .now) -> String? {
        guard let slot = ExerciseCatalog.slot(for: goal.exerciseID) else { return nil }
        let since = now.addingTimeInterval(-28 * 86_400)
        let recent = sessions.filter { !$0.isActive && $0.startedAt >= since }.sorted { $0.startedAt > $1.startedAt }
        let logged = recent.flatMap(\.exercises).filter { exercise in exercise.sets.contains { $0.isCompleted && !$0.isWarmup } }
        guard !logged.contains(where: { $0.exerciseID == goal.exerciseID }) else { return nil }
        return logged.first { $0.exerciseID != goal.exerciseID && ExerciseCatalog.slot(for: $0.exerciseID) == slot }?.name
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
                EditLiftGoalLink(goal: goal)
            }
            Text(LiftGoalHistory.title(goal, unit: unit))
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            if let variant = LiftGoalHistory.recentVariant(of: goal, sessions: sessions) {
                // Tracking is by the exact lift: a swapped variant doesn't count toward it.
                Label("You've been doing \(variant) lately. This goal tracks \(goal.name) only.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let projection {
                LiftGoalProgressBar(projection: projection, unit: unit, liftName: goal.name)
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
            VStack(alignment: .leading, spacing: 10) {
                CardLabel(text: "Lift goal", color: Theme.liftingText)
                Text("Pick a lift and a target, like a 100 kg bench. You'll see how close you are and where your last 12 weeks are heading.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                AddLiftGoalButton(title: "Add a lift goal")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        } else {
            ForEach(goals) { goal in
                LiftGoalCard(goal: goal)
            }
            AddLiftGoalButton(title: "Add another lift goal")
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
        if let exerciseID, goals.isEmpty {
            // No goal for this lift yet: set one starting on this lift.
            AddLiftGoalButton(title: "Set a goal for this lift", exerciseID: exerciseID)
                .card()
        } else {
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

/// Opens the lift-goal editor and saves the new goal straight to settings.
struct AddLiftGoalButton: View {
    var title: String
    var exerciseID: String?
    @Environment(UserSettings.self) private var settings

    var body: some View {
        NavigationLink {
            LiftGoalEditor(goal: nil, exerciseID: exerciseID) { goal in
                LiftGoalStore.save(goal, in: settings)
            }
        } label: {
            Label(title, systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.liftingText)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(exerciseID == nil ? "add-lift-goal" : "add-lift-goal-for-exercise")
    }
}

/// "Edit" on a goal card: change the target or date, or delete it.
private struct EditLiftGoalLink: View {
    let goal: LiftGoal
    @Environment(UserSettings.self) private var settings

    var body: some View {
        NavigationLink {
            LiftGoalEditor(goal: goal, onDelete: { LiftGoalStore.remove(goal.id, in: settings) }) { updated in
                LiftGoalStore.save(updated, in: settings)
            }
        } label: {
            Text("Edit")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.liftingText)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(goal.name) goal")
    }
}

/// How far today's estimated 1RM is toward the target, as a bar and in words.
private struct LiftGoalProgressBar: View {
    let projection: LiftGoalProjection.Projection
    let unit: WeightUnit
    let liftName: String

    var body: some View {
        let target = LiftGoalHistory.weightText(projection.targetKg, unit: unit)
        VStack(alignment: .leading, spacing: 6) {
            if let latest = projection.latestKg, let progress = projection.progress {
                let now = LiftGoalHistory.weightText(latest, unit: unit)
                let percent = Int((progress * 100).rounded())
                let left = max(0, projection.targetKg - latest)
                HStack(alignment: .firstTextBaseline) {
                    Text("Now \(now) of \(target)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 8)
                    Text("\(percent)%")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(progress >= 1 ? Theme.recoveryHigh : Theme.liftingText)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule()
                            .fill(progress >= 1 ? Theme.recoveryHigh : Theme.liftingText)
                            .frame(width: max(8, proxy.size.width * progress))
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
                Text(left > 0 ? "\(LiftGoalHistory.weightText(left, unit: unit)) to go · estimated 1RM from your best recent set" : "Goal reached")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Log \(liftName) (a set of 10 reps or fewer) and your progress toward \(target) shows here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fitness page: one ring per lift goal (up to three), filled to how close
/// today's estimated 1RM is to the target. Tap opens the goal cards.
struct LiftGoalRingsCard: View {
    @Environment(UserSettings.self) private var settings
    @Environment(GymStore.self) private var gym
    @Environment(DailyMetricsModel.self) private var metrics
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]

    var body: some View {
        let goals = Array(settings.goals.liftGoals.prefix(3))
        if goals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set a target, like a 100 kg bench or a 2× body-weight squat, and see how close you are.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                AddLiftGoalButton(title: "Add a lift goal")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        } else {
            NavigationLink {
                LiftGoalsDetailView()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(goals) { goal in
                        ring(goal, size: goals.count == 1 ? 120 : (goals.count == 2 ? 104 : 88))
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .card()
            .accessibilityIdentifier("lift-goal-rings")
            .accessibilityHint("Shows your lift goals and where the trend is heading")
        }
    }

    private func ring(_ goal: LiftGoal, size: CGFloat) -> some View {
        let unit = gym.liftingUnit
        let projection = LiftGoalHistory.projection(for: goal, sessions: sessions,
                                                    bodyMassKg: metrics.bodyMassKg ?? settings.weightKg,
                                                    trainingStatus: metrics.trainingStatus)
        let target = projection.map { LiftGoalHistory.weightText($0.targetKg, unit: unit) }
            ?? LiftGoalHistory.targetText(goal, unit: unit)
        let progress = projection?.progress
        let reached = (progress ?? 0) >= 1
        let subtitle: String
        if let latest = projection?.latestKg {
            subtitle = "\(LiftGoalHistory.weightText(latest, unit: unit).replacingOccurrences(of: " \(unit.rawValue)", with: "")) of \(target)"
        } else {
            subtitle = "Goal \(target) · log it to start"
        }
        return ScoreRing(
            title: goal.name,
            value: progress.map { "\(Int(($0 * 100).rounded()))" } ?? "–",
            unit: progress == nil ? "" : "%",
            subtitle: subtitle,
            progress: progress ?? 0,
            colors: reached ? [Theme.recoveryHighLight, Theme.recoveryHigh] : Theme.liftingColors,
            size: size
        )
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(goal.name) goal: \(progress.map { "\(Int(($0 * 100).rounded())) percent" } ?? "no data yet"), \(subtitle)")
    }
}
