import SwiftUI
import SwiftData
import AppCore

/// The Monday review: last week in plain numbers, the health basics, how last
/// week's changes went, then this week's change (one by default, up to
/// three), saved on the week's plan.
///
/// Self-monitoring works best combined with goal setting, feedback and a
/// review of goals (Michie et al., Health Psychol 2009: 0.42 vs 0.26), and
/// prompting progress monitoring raises goal attainment (Harkin et al.,
/// Psychol Bull 2016, d = 0.40). The numbers here are the ones the app already
/// computes; nothing new is worked out.
struct WeeklyReviewView: View {
    @Environment(WeeklyPlanStore.self) private var store
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals
    @Environment(CheckInStore.self) private var checkIns
    @Environment(UserSettings.self) private var settings
    @Environment(MuscleModel.self) private var muscles
    @Environment(\.healthClient) private var health
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @AppStorage(HealthyLivingSettings.drinkLimitKey) private var drinkLimit: Double?
    /// This week's changes as chosen so far (`WeeklyPlan.changes`).
    @State private var changes: [WeeklyChange] = []
    @State private var customText = ""
    @State private var writingCustom = false
    @State private var food = WeeklyReviewData.FoodTimes()
    /// Last week worked out once per load, not on every keystroke.
    @State private var snapshot: Snapshot?
    @State private var loaded = false
    @State private var showingPlan = false

    private var thisWeek: Date { WeeklyPlan.weekStart(containing: .now) }
    private var lastWeek: Date { Calendar.current.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ReviewNumbersCard(lines: lines, basics: snapshot?.basics)
                    BusyWeekReviewCard(thisWeek: thisWeek) // after three busy weeks in a row: build again?
                    if let reports = snapshot?.reports, !reports.isEmpty {
                        ChangeReportCard(reports: reports)
                    }
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
                    Button("Save changes") { confirm() }
                        .accessibilityHint("Saves this week's changes to your plan")
                }
            }
            .task { await load() }
            .sheet(isPresented: $showingPlan) { WeeklyPlanView() }
        }
    }

    // MARK: Cards

    private var changesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: changes.count > 1 ? "Changes for this week" : "One change for this week", color: Theme.liftingText)
            Text("Suggested from last week's numbers. \"Checked for you\" means no ticking: next Monday this page shows how many days it was kept. One is plenty; up to \(WeeklyChange.maximumCount) if you want.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(changes) { change in
                ChangeRow(change: change) { changes.removeAll { $0.id == change.id } }
            }
            if writingCustom {
                HStack(spacing: 8) {
                    TextField("Your own change", text: $customText, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.subheadline)
                        .submitLabel(.done)
                        .accessibilityIdentifier("review-change-custom-field")
                    Button("Add") { addCustom() }
                        .font(.subheadline.weight(.semibold))
                        .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("review-change-custom-add")
                }
                .padding(12)
                .background(Theme.cardRaised, in: .rect(cornerRadius: 14))
            } else if changes.count < WeeklyChange.maximumCount {
                addMenu
            }
        }
        .card(tint: Theme.lifting)
    }

    /// Choices the data can check first, then the plain ideas, then free text.
    private var addMenu: some View {
        let pool = options.filter { option in !changes.contains { $0.id == option.id } }
        return Menu {
            let measured = pool.filter(\.isMeasured)
            if !measured.isEmpty {
                Section("Checked for you") {
                    ForEach(measured) { option in
                        Button(option.title) { changes.append(option) }
                    }
                }
            }
            let ideas = pool.filter { !$0.isMeasured }
            if !ideas.isEmpty {
                Section("Not measured") {
                    ForEach(ideas) { option in
                        Button(option.title) { changes.append(option) }
                    }
                }
            }
            Button("Write your own", systemImage: "pencil") { writingCustom = true }
        } label: {
            Label(changes.isEmpty ? "Choose a change" : "Add another", systemImage: "plus.circle")
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityIdentifier("review-change-add")
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
                Text("No training days yet. Save changes keeps this week's changes; the days can come later.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    // MARK: Numbers

    private var trainingDays: [Date] {
        WeeklyPlanStore.trainingDays(sessions: sessions, extra: metrics.recentLiftingDays)
    }

    private var lastWeekRecord: WeekRecord {
        let plan = store.plan(for: lastWeek) ?? WeeklyPlan(weekStart: lastWeek)
        return WeekRecord.make(plan: plan, trainingDays: trainingDays)
    }

    private var lines: [ReviewLine] {
        var lines: [ReviewLine] = []
        lines.append(sessionsLine)
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
            // Training days (gym sessions, or watch workouts at 35%+ strain), the
            // same count as Fitness › This week and the consistency score.
            let days = record.done == 1 ? "training day" : "training days"
            let difference = record.done - record.planned
            let versusPlan = switch difference {
            case 0: "As planned"
            case 1...: "\(difference) more than planned"
            default: "\(-difference) fewer than planned"
            }
            let swaps = store.swapLines(weekStart: lastWeek).map { "Swapped " + $0 }.joined(separator: "; ")
            // A busy week with no session was chosen ahead: not a miss (`Consistency.weekMissed`).
            let base = kept ? versusPlan + " · week kept"
                : record.isBusy ? "A busy week, planned ahead. This week starts fresh."
                : "A lighter week than planned. This week starts fresh."
            return ReviewLine(id: "sessions", title: "Training days", value: "\(record.done) \(days)",
                              detail: swaps.isEmpty ? base : base + ". " + swaps)
        }
        return ReviewLine(id: "sessions", title: "Training days", value: "\(record.done)", detail: "No plan last week to compare with.")
    }

    /// Sleep debt. Regularity is one of the basics (`HealthFloors`), so it isn't repeated here.
    private var sleepLine: ReviewLine? {
        // Paused while the sleep window runs: short nights are the plan (`SleepWindow.debtPausedNote`).
        guard !metrics.sleepWindowOn, let debt = metrics.sleepDebt else { return nil }
        // The same rule as Health: "Caught up" only at zero; a debt under an hour says so.
        let value: String
        if debt.hours > 0 {
            let behind = SleepText.hours(debt.hours) + " behind"
            value = debt.level == .none ? behind + " (under 1 h)" : behind
        } else {
            value = "Caught up"
        }
        return ReviewLine(id: "sleep", title: "Sleep debt, \(debt.windowLabel)", value: value, detail: nil)
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

    /// Lifting hard sets per muscle last Monday to Sunday
    /// (`MuscleModel.lastWeekSets`, the same count as Fitness › Muscles; cardio
    /// adds fatigue, not sets).
    private var setsLine: ReviewLine? {
        let worked = muscles.lastWeekSets.filter { $0.value >= 0.5 }.sorted { $0.value > $1.value }
        guard !worked.isEmpty else { return nil }
        // Top 3 only, so the value fits on a line or two without an odd wrap.
        let top = worked.prefix(3).map { "\($0.key.name) \(Int($0.value.rounded()))" }
        var parts: [String] = []
        if worked.count > 3 { parts.append("Plus \(worked.count - 3) more.") }
        // With a block, each muscle's band for this week (`VolumeProgression.Target.band`);
        // without, the general 10-20 range (Schoenfeld et al., J Sports Sci 2017).
        let targets = store.volumeTargets(muscles: muscles)
        let bands = (targets?.targets ?? []).map(\.band)
        let over = worked.filter { entry in
            let upper = targets?.target(for: entry.key).map { Double($0.band.upperBound) } ?? MuscleCoverage.productiveRange.upperBound
            return entry.value.rounded() > upper
        }.count
        if let low = bands.map(\.lowerBound).min(), let high = bands.map(\.upperBound).max() {
            parts.append(low == high ? "This week's target is \(low) sets per muscle." : "This week's target is \(low)-\(high) sets per muscle.")
            if over > 0 { parts.append(over == 1 ? "1 muscle was above it." : "\(over) muscles were above it.") }
        } else {
            parts.append("About 10-20 a week is the productive range.")
            if over > 0 { parts.append(over == 1 ? "1 muscle was above 20." : "\(over) muscles were above 20.") }
        }
        return ReviewLine(id: "sets", title: "Hard sets per muscle, last week", value: top.joined(separator: " · "),
                          detail: parts.joined(separator: " "))
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
        return ReviewLine(id: "calories", title: "Calories, average of logged days", value: "\(whole(maintenance.averageIntake).formatted()) vs \(whole(target).formatted()) target",
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
        let weeks = Consistency.weeksTrainingAtLeast(2, records: store.records(sessions: sessions, extra: metrics.recentLiftingDays))
        guard weeks >= 3 else { return nil }
        return "You've trained at least twice a week for \(weeks) weeks running. That's someone who lifts."
    }

    // MARK: Last week, worked out

    /// The basics, the report on last week's changes and this week's
    /// suggestions, from the same days (`WeeklyReviewData`).
    struct Snapshot {
        var basics: HealthFloors.Result
        var reports: [WeeklyChangeReview.Report]
        /// Best first; the first is chosen by default (`WeeklyChangeSuggestions.suggested`).
        var suggestions: [WeeklyChange]
        /// Everything the data can check, for the menu.
        var measurable: [WeeklyChange]
    }

    private func makeSnapshot() -> Snapshot {
        let calendar = Calendar.current
        let sources = WeeklyReviewData.Sources(metrics: metrics, vitals: vitals, checkIns: checkIns,
                                               trainingDays: trainingDays, food: food)
        let earlierStart = calendar.date(byAdding: .day, value: -7 * WeeklyReviewData.earlierWeeks, to: lastWeek) ?? lastWeek
        let week = WeeklyReviewData.days(from: lastWeek, count: 7, sources)
        let earlier = WeeklyReviewData.days(from: earlierStart, count: 7 * WeeklyReviewData.earlierWeeks, sources)
        let floors = HealthFloors.week(from: week, sleepRegularity: WeeklyReviewData.sleepRegularity(metrics, weekStart: lastWeek))
        let basics = HealthFloors.assess(floors)
        let context = suggestionContext(floors: floors, days: week + earlier)
        let reports = WeeklyChangeReview.report(changes: store.plan(for: lastWeek)?.changes ?? [], week: week, earlier: earlier)
        return Snapshot(basics: basics, reports: reports,
                        suggestions: WeeklyChangeSuggestions.suggested(basics: basics, context: context),
                        measurable: WeeklyChangeSuggestions.measurable(context))
    }

    /// What the app knows for this week's suggestions.
    private func suggestionContext(floors: HealthFloors.Week, days: [WeeklyChangeReview.Day]) -> WeeklyChangeSuggestions.Context {
        var context = WeeklyChangeSuggestions.Context()
        if !metrics.recentBedtimes.isEmpty {
            // The same "last coffee by" as Today's Up next row (`TodayHabits.caffeine`).
            context.caffeineCutoffMinutes = CaffeineTiming.cutoffMinutes(bedtimeMinutes: CaffeineTiming.usualBedtimeMinutes(metrics.recentBedtimes), mg: 100)
        }
        // Not while the insomnia path's sleep window is on: its start is the earliest
        // bedtime, not a time to be in bed by, and the window is short on purpose.
        context.bedByMinutes = metrics.bedtimeWindow.flatMap { $0.isSleepWindow ? nil : WeeklyChange.eveningMinutes($0.end) }
        // While the sleep window runs, its fixed wake time is the one to keep.
        context.usualWakeMinutes = SleepWindowStore.shared.course?.wakeMinutes
            ?? BedtimeWindow.usualWakeMinutes(metrics.sleepNights.suffix(14).map(\.wake))
        context.hasMealTimes = WeeklyReviewData.hasMealTimes(food)
        context.drinkLimit = drinkLimit
        if floors.drinkNightsLogged >= HealthFloors.drinksMinimumNights { context.lastWeekDrinks = floors.drinks }
        // A drinks change only for someone who drinks and logs it.
        context.logsDrinks = days.contains { ($0.drinks ?? 0) > 0 }
        context.vigorousMinutes = floors.vigorousMinutes
        if !metrics.sleepWindowOn, let debt = metrics.sleepDebt, debt.level == .moderate || debt.level == .high {
            context.sleepDebtExtraMinutes = debt.extraMinutesPerNight ?? 30
        }
        if let target = metrics.proteinTarget, let protein = metrics.nutritionYesterday?.proteinGrams, protein < target * 0.8 {
            context.proteinLow = true
        }
        let record = lastWeekRecord
        context.weekNotKept = Consistency.weekMissed(record)
        context.trainEasy = metrics.trainEasyToday
        if let weekly = metrics.weightTrendWeekly, let mass = metrics.bodyMassKg, settings.goalsSet {
            context.weightPace = WeightPace.check(weeklyChangeKg: weekly, bodyMassKg: mass, goals: settings.goals)
        }
        return context
    }

    /// Suggestions first, then the other checkable choices, then plain ideas; no repeats.
    private var options: [WeeklyChange] {
        guard let snapshot else { return WeeklyChangeSuggestions.plainIdeas }
        var seen = Set<String>()
        return (snapshot.suggestions + snapshot.measurable + WeeklyChangeSuggestions.plainIdeas).filter { seen.insert($0.id).inserted }
    }

    // MARK: Changes

    private func load() async {
        snapshot = makeSnapshot()
        if !loaded {
            loaded = true
            let saved = store.plan(for: thisWeek)?.changes ?? []
            // One tracked change by default; more only when the owner adds them
            // (healthy-living-2026-11.md §3 item 4: three can feel like homework).
            changes = saved.isEmpty ? Array((snapshot?.suggestions ?? []).prefix(WeeklyChange.defaultCount)) : saved
        }
        // The food app's timed entries, for caffeine and protein per meal; then again with them.
        if let health {
            food = await WeeklyReviewData.loadFoodTimes(health: health, lastWeek: lastWeek)
            snapshot = makeSnapshot()
        }
    }

    private func addCustom() {
        let text = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let change = WeeklyChange(text: text)
        if !changes.contains(where: { $0.id == change.id }), changes.count < WeeklyChange.maximumCount {
            changes.append(change)
        }
        customText = ""
        writingCustom = false
    }

    private func confirm() {
        let last = store.lastPlan(before: thisWeek)
        // Keep last week's mode (a flexible week stays "any days, N a week") and its
        // easy cardio, as "Same days as last week" does (`ThisWeekCard`).
        var plan = store.plan(for: thisWeek)
            ?? WeeklyPlan(weekStart: thisWeek,
                          plannedDays: store.newWeekDays(from: last?.plannedDays ?? [], weekStart: thisWeek, sessions: sessions),
                          mode: last?.mode ?? .fixedDays, sessionsPerWeek: last?.sessionsPerWeek,
                          // Two easy sessions unless none was chosen (evidence audit M2).
                          cardio: EasyCardio.carriedOver(last?.cardio, choiceSaved: UserDefaults.standard.bool(forKey: WeeklyPlanView.cardioChoiceSavedKey),
                                                         kind: CardioPlanner.recommendedKind(goals: settings.goalsSet ? settings.goals : nil)))
        // Text still in the field counts, as it did when the changes were three text fields.
        if writingCustom { addCustom() }
        plan.changes = Array(changes.prefix(WeeklyChange.maximumCount))
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
    /// The five health basics, shown after the training days.
    let basics: HealthFloors.Result?

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
                if line.id == "sessions", let basics {
                    BasicsRow(result: basics)
                }
            }
        }
        .card()
    }
}

/// "Basics: 4 of 5", opening to the five checks (`HealthFloors`). Ticks and
/// numbers only: no percentage, and no colour for a check that wasn't met
/// (healthy-living-2026-11.md §3 item 1: it must not read as a score).
private struct BasicsRow: View {
    let result: HealthFloors.Result
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { open.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Basics")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        Text(result.summary)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Theme.primaryText)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Basics, \(result.summary)")
            .accessibilityValue(open ? "Open" : "Closed")
            .accessibilityHint("Shows cardio minutes, strength days, steps, sleep regularity and drinks")
            .accessibilityIdentifier("review-basics")
            if open {
                ForEach(result.checks) { check in
                    BasicsCheckRow(check: check)
                }
                Text(HealthFloors.evidenceNote)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BasicsCheckRow: View {
    let check: HealthFloors.Check

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(check.met == true ? Theme.recoveryHigh : Theme.secondaryText)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(check.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 8)
                    Text(check.valueText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.primaryText)
                }
                Text("Line: " + check.targetText)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = check.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(check.met == true ? "Met" : check.met == false ? "Not met" : "No data")
    }

    private var icon: String {
        switch check.met {
        case true?: "checkmark.circle.fill"
        case false?: "circle"
        case nil: "minus.circle"
        }
    }
}

/// How last week's changes went: days kept and what moved, with the caveat
/// that one week proves nothing (`WeeklyChangeReview`).
private struct ChangeReportCard: View {
    let reports: [WeeklyChangeReview.Report]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: reports.count == 1 ? "Last week's change" : "Last week's changes")
            ForEach(reports) { report in
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(report.kept)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.primaryText)
                    if let moved = report.moved {
                        Text(moved)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if reports.contains(where: \.change.isMeasured) {
                Text(WeeklyChangeReview.caveat)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("review-last-week-changes")
    }
}

/// One chosen change, with whether the app checks it.
private struct ChangeRow: View {
    let change: WeeklyChange
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(change.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(change.isMeasured ? "Checked for you" : "Not measured")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(change.title)")
            .accessibilityIdentifier("review-change-remove-\(change.id)")
        }
        .padding(.leading, 12)
        .padding(.vertical, 4)
        .background(Theme.cardRaised, in: .rect(cornerRadius: 14))
    }
}
