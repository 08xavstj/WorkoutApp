import SwiftUI
import SwiftData
import AppCore

/// The Monday review: last week in plain numbers, then three changes for this
/// week that the user edits and confirms, saved on the week's plan.
///
/// Self-monitoring works best combined with goal setting, feedback and a
/// review of goals (Michie et al., Health Psychol 2009: 0.42 vs 0.26), and
/// prompting progress monitoring raises goal attainment (Harkin et al.,
/// Psychol Bull 2016, d = 0.40). The numbers here are the ones the app already
/// computes; nothing new is worked out.
struct WeeklyReviewView: View {
    @Environment(WeeklyPlanStore.self) private var store
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(MuscleModel.self) private var muscles
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var changes = ["", "", ""]
    @State private var loaded = false
    @State private var showingPlan = false

    private var thisWeek: Date { WeeklyPlan.weekStart(containing: .now) }
    private var lastWeek: Date { Calendar.current.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ReviewNumbersCard(lines: lines)
                    if let identity = identityLine {
                        Text(identity)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .card(tint: Theme.recoveryHigh)
                    }
                    changesCard
                    planCard
                    Text("Looking back at the week against what you planned, then setting the next one, is what makes tracking pay off: monitoring plus a review of goals had a clearly bigger effect than monitoring alone in a meta-regression of 122 studies (Michie et al. 2009), and prompting progress checks raised goal attainment across 138 experiments (Harkin et al. 2016).")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .lockedToScreenWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Weekly review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { confirm() }
                }
            }
            .task { load() }
            .sheet(isPresented: $showingPlan) { WeeklyPlanView() }
        }
    }

    // MARK: Cards

    private var changesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Three changes for this week", color: Theme.liftingText)
            Text("Suggested from the numbers; change them to anything you'd rather do.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            ForEach(0..<3, id: \.self) { index in
                TextField("Change \(index + 1)", text: $changes[index], axis: .vertical)
                    .lineLimit(1...3)
                    .font(.subheadline)
                    .padding(12)
                    .background(Theme.cardRaised, in: .rect(cornerRadius: 14))
            }
        }
        .card(tint: Theme.lifting)
    }

    private var planCard: some View {
        let plan = store.plan(for: thisWeek) ?? store.lastPlan(before: thisWeek)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel(text: store.plan(for: thisWeek) == nil ? "This week's days (from last week)" : "This week's days")
                Spacer()
                Button(plan == nil ? "Plan the days" : "Edit days") { showingPlan = true }
                    .font(.subheadline.weight(.semibold))
            }
            if let plan, !plan.plannedDays.isEmpty {
                ForEach(plan.sortedDays) { day in
                    Text("\(WeeklyPlan.weekdayName(day.weekday)) \(day.clockText()) · \(day.focus.shortTitle) · \(day.minutes) min")
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                }
                if let ifThen = plan.sortedDays.compactMap(\.ifThen).first, !ifThen.isEmpty {
                    Text(ifThen)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                Text("No training days yet. Confirm saves the changes; the days can come later.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    // MARK: Numbers

    private var trainingDays: [Date] {
        WeeklyPlanStore.trainingDays(sessions: sessions, extra: metrics.recentTrainingDays)
    }

    private var lastWeekRecord: WeekRecord {
        let plan = store.plan(for: lastWeek) ?? WeeklyPlan(weekStart: lastWeek)
        return WeekRecord.make(plan: plan, trainingDays: trainingDays)
    }

    private var lines: [ReviewLine] {
        var lines: [ReviewLine] = []
        lines.append(sessionsLine)
        if let strain = strainLine { lines.append(strain) }
        if let sleep = sleepLine { lines.append(sleep) }
        if let hrv = hrvLine { lines.append(hrv) }
        if let sets = setsLine { lines.append(sets) }
        if let protein = proteinLine { lines.append(protein) }
        if let calories = caloriesLine { lines.append(calories) }
        if let weight = weightLine { lines.append(weight) }
        lines += liftGoalLines
        return lines
    }

    /// Progress toward each lift goal, framed as an approach goal (McEwan
    /// 2016; Swann 2021; `LiftGoalProjection`).
    private var liftGoalLines: [ReviewLine] {
        LiftGoalReview.lines(goals: settings.goals.liftGoals, sessions: sessions, bodyMassKg: metrics.bodyMassKg ?? settings.weightKg,
                             trainingStatus: metrics.trainingStatus, unit: settings.weightUnit)
            .map { ReviewLine(id: $0.id, title: $0.title, value: $0.value, detail: $0.detail) }
    }

    private var sessionsLine: ReviewLine {
        let record = lastWeekRecord
        if record.planned > 0 {
            let kept = Consistency.weekKept(planned: record.planned, done: record.done)
            return ReviewLine(id: "sessions", title: "Sessions", value: "\(record.done) of \(record.planned)",
                              detail: kept ? "On plan: \(Consistency.sessionsNeeded(planned: record.planned)) or more counts as a kept week." : "A lighter week than planned. This week starts fresh.")
        }
        return ReviewLine(id: "sessions", title: "Training days", value: "\(record.done)", detail: "No plan last week to compare with.")
    }

    private var strainLine: ReviewLine? {
        let values = metrics.weekStrain.map(\.strain)
        guard !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        let active = values.filter { $0 >= 25 }.count
        var detail = "\(active) of \(values.count) days at 25% or more (a training day)."
        if let target = metrics.targetStrain { detail += " Today's range is \(strainRangeText(target))." }
        return ReviewLine(id: "strain", title: "Average day strain, last 7 days", value: strainText(average), detail: detail)
    }

    private var sleepLine: ReviewLine? {
        let debt = metrics.sleepDebt
        let regularity = metrics.sleepConsistency
        guard debt != nil || regularity != nil else { return nil }
        let value = debt.map { $0.level == .none ? "Caught up" : "\(SleepText.hours($0.hours)) behind" } ?? "No debt data"
        let detail = regularity.map { "Regularity \($0)/100 over the last week" + ($0 >= 70 ? ", a regular pattern." : "; a steadier wake time helps more than extra hours (Windred 2024).") }
        return ReviewLine(id: "sleep", title: "Sleep debt, 14 nights", value: value, detail: detail)
    }

    private var hrvLine: ReviewLine? {
        guard let trend = metrics.recovery?.hrvTrend else { return nil }
        let status: String = switch trend.status {
        case .below: "below your normal range: easy days suit this week's start."
        case .within: "within your normal range."
        case .above: "above your normal range."
        }
        return ReviewLine(id: "hrv", title: "7-day HRV", value: "\(whole(trend.average)) ms",
                          detail: "Normal \(whole(trend.normalRange.lowerBound))–\(whole(trend.normalRange.upperBound)) ms, so " + status)
    }

    private var setsLine: ReviewLine? {
        let worked = muscles.states.values.filter { $0.weeklySets >= 0.5 }.sorted { $0.weeklySets > $1.weeklySets }
        guard !worked.isEmpty else { return nil }
        let top = worked.prefix(4).map { "\($0.muscle.name) \($0.weeklySets.formatted(.number.precision(.fractionLength(0))))" }
        return ReviewLine(id: "sets", title: "Hard sets per muscle, 7 days", value: top.joined(separator: " · "),
                          detail: worked.count > 4 ? "Plus \(worked.count - 4) more. About 10-20 a week is the productive range." : "About 10-20 a week is the productive range.")
    }

    private var proteinLine: ReviewLine? {
        guard let target = metrics.proteinTarget else { return nil }
        guard let protein = metrics.nutritionYesterday?.proteinGrams ?? metrics.nutritionToday?.proteinGrams else {
            return ReviewLine(id: "protein", title: "Protein", value: "Not logged", detail: "Target \(whole(target)) g a day.")
        }
        return ReviewLine(id: "protein", title: "Protein, latest logged day", value: "\(whole(protein)) of \(whole(target)) g", detail: nil)
    }

    private var caloriesLine: ReviewLine? {
        guard !settings.hideCalories, let maintenance = metrics.maintenance, let target = metrics.calorieTarget else { return nil }
        return ReviewLine(id: "calories", title: "Calories, average of logged days", value: "\(whole(maintenance.averageIntake)) vs \(whole(target)) target",
                          detail: "From \(maintenance.loggedDays) fully logged days in the last 4 weeks; the weekly average is what moves weight.")
    }

    private var weightLine: ReviewLine? {
        guard let weekly = metrics.weightTrendWeekly, let mass = metrics.bodyMassKg, settings.goalsSet, settings.goals.weight != .maintain else { return nil }
        let unit = settings.weightUnit
        let planned = mass * settings.goals.weeklyRatePercent / 100 * (settings.goals.weight == .lose ? -1 : 1)
        func fmt(_ kg: Double) -> String { "\(kg >= 0 ? "+" : "−")\(unit.display(abs(kg)).formatted(.number.precision(.fractionLength(2)))) \(unit.rawValue)" }
        let pace = WeightPace.message(WeightPace.check(weeklyChangeKg: weekly, bodyMassKg: mass, goals: settings.goals))
        return ReviewLine(id: "weight", title: "Weight trend per week", value: "\(fmt(weekly)) vs \(fmt(planned)) planned",
                          detail: pace ?? "4-week trend, not single weigh-ins. Flat for 3+ weeks is a normal plateau, not a failure.")
    }

    /// Identity, stated only when it's true for 3+ weeks and never as a chain
    /// to protect (Rhodes et al. 2016, identity–behaviour r = 0.44).
    private var identityLine: String? {
        let weeks = Consistency.weeksTrainingAtLeast(2, records: store.records(sessions: sessions, extra: metrics.recentTrainingDays))
        guard weeks >= 3 else { return nil }
        return "You've trained at least twice a week for \(weeks) weeks running. That's someone who lifts."
    }

    // MARK: Changes

    /// Plain suggestions from the same numbers; the user edits them.
    private var suggestedChanges: [String] {
        var suggestions: [String] = []
        let record = lastWeekRecord
        if record.planned > 0, !Consistency.weekKept(planned: record.planned, done: record.done) {
            suggestions.append("Keep the 15-minute version ready for busy days")
        }
        if let debt = metrics.sleepDebt, debt.level == .moderate || debt.level == .high {
            suggestions.append("In bed \(debt.extraMinutesPerNight ?? 30) minutes earlier on three nights")
        }
        if let regularity = metrics.sleepConsistency, regularity < 70 {
            suggestions.append("Same wake time every day, weekends too")
        }
        if let target = metrics.proteinTarget, let protein = metrics.nutritionYesterday?.proteinGrams, protein < target * 0.8 {
            suggestions.append("Protein with every meal")
        }
        if metrics.trainEasyToday {
            suggestions.append("Keep the first session of the week easy")
        }
        if let weekly = metrics.weightTrendWeekly, let mass = metrics.bodyMassKg, settings.goalsSet {
            switch WeightPace.check(weeklyChangeKg: weekly, bodyMassKg: mass, goals: settings.goals) {
            case .losingTooFast: suggestions.append("Eat a little more; the pace is faster than planned")
            case .gainingTooFast: suggestions.append("Trim a little; the pace is faster than planned")
            case .fine: break
            }
        }
        for filler in ["Train at the planned time, even if shorter", "A walk after lunch", "Phone out of the bedroom"] where suggestions.count < 3 {
            suggestions.append(filler)
        }
        return Array(suggestions.prefix(3))
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let saved = store.plan(for: thisWeek)?.changes ?? []
        let base = saved.isEmpty ? suggestedChanges : saved
        changes = (0..<3).map { $0 < base.count ? base[$0] : "" }
    }

    private func confirm() {
        let last = store.lastPlan(before: thisWeek)
        // Keep last week's mode: a flexible week stays "any days, N a week".
        var plan = store.plan(for: thisWeek)
            ?? WeeklyPlan(weekStart: thisWeek, plannedDays: last?.plannedDays ?? [],
                          mode: last?.mode ?? .fixedDays, sessionsPerWeek: last?.sessionsPerWeek)
        plan.changes = changes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        store.save(plan)
        dismiss()
    }
}

// MARK: - Pieces

private struct ReviewLine: Identifiable {
    var id: String
    var title: String
    var value: String
    var detail: String?
}

private struct ReviewNumbersCard: View {
    let lines: [ReviewLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Last week")
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.title)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Text(line.value)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Theme.primaryText)
                    if let detail = line.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .card()
    }
}
