import SwiftUI
import SwiftData
import AppCore

/// Today: how am I today, and what's the one thing to do next? Five blocks
/// on a normal day (docs/research/ux-audit.md 4.6, with the Decisions):
/// an alert slot (at most one), "Finish setting up" until it's done, the
/// Scores card (primary), Up next, Nutrition, a Conditions row on days the
/// weather matters, and the Health Monitor. Less, better-ordered information
/// helped lay readers understand and choose (Peters et al., Med Care Res Rev
/// 2007; ux-audit.md P7, P16, P20).
///
/// Moved off Today, still reachable: today's range and suggestions (Strain
/// ring › Strain sheet), sleep debt (Sleep ring and the bed-by Up next row),
/// this week's plan and consistency (Fitness › This week), the coach
/// suggestions (Coach tab), the full medication list (Health › Records, the
/// Log tab, Settings), and four more monitor tiles (Health › All measures).
struct TodayView: View {
    let askCoach: (String) -> Void

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(AppRefresher.self) private var refresher
    @Environment(\.healthClient) private var health
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \HRVReading.date, order: .reverse) private var hrvReadings: [HRVReading]
    @State private var showingHRVEntry = false
    /// Caffeine, protein and movement from Apple Health, for Up next and Nutrition.
    @State private var habits = TodayHabits()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AlertSlot()
                    TodaySetupCard()
                    ScoresCard(sessions: sessions, askCoach: askCoach)
                    UpNextCard(habits: habits)
                    NutritionCard(habits: habits)
                    ConditionsRow()
                    HealthMonitor(onEnterHRV: { showingHRVEntry = true })
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .lockedToScreenWidth()
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.peach, Theme.Wash.butter, Theme.Wash.sky])
            }
            .background(Theme.background)
            .navigationTitle("Today")
            .navigationSubtitle(Text(subtitle))
            .tabToolbar()
            .refreshable { await refresher.refresh() }
            .sheet(isPresented: $showingHRVEntry) {
                HRVEntrySheet(existing: hrvReadings.first { Calendar.current.isDateInToday($0.date) })
                    .presentationDetents([.medium])
            }
            .task(id: habitsKey) { await loadHabits() }
            .modifier(WeeklyReviewReminderSync())
        }
    }

    /// The date and sync status under the large title. Pull down to refresh.
    private var subtitle: String {
        let date = Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
        if metrics.isLoading {
            return "\(date) · Syncing"
        }
        if let lastUpdated = metrics.lastUpdated {
            return "\(date) · Updated \(lastUpdated.formatted(.relative(presentation: .named)))"
        }
        return "\(date) · Not synced yet"
    }

    /// Reloads caffeine, protein and steps when food or steps change.
    private var habitsKey: String {
        "\(metrics.nutritionToday?.proteinGrams ?? 0)|\(metrics.steps ?? 0)"
    }

    private func loadHabits() async {
        guard let health else { return }
        await habits.load(health: health, metrics: metrics)
    }
}

/// Keeps the Monday review reminder ("review|weekly") in step with its
/// settings. It ran on the This week card when that was on Home; kept here so
/// it still follows Settings now that the card lives on Fitness.
private struct WeeklyReviewReminderSync: ViewModifier {
    @Environment(UserSettings.self) private var settings

    func body(content: Content) -> some View {
        content
            .task(id: "\(settings.weeklyReviewOn)|\(settings.weeklyReviewMinutes)") {
                await Reminders.scheduleWeeklyReview(enabled: settings.weeklyReviewOn, minutes: settings.weeklyReviewMinutes)
            }
    }
}

// MARK: - Finish setting up

/// One "Finish setting up" checklist instead of separate prompts for goals,
/// city, gym and plan, shown until everything is set up and hideable with
/// "Not now" (ux-audit.md 4.6, H7; HIG Onboarding: postpone nonessential
/// setup, P9). Goals, city and gym equipment are also in Settings; the plan
/// is in Fitness › This week.
private struct TodaySetupCard: View {
    @Environment(UserSettings.self) private var settings
    @Environment(GymStore.self) private var gym
    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(AppRouter.self) private var router
    @AppStorage("todaySetupDismissed") private var dismissed = false
    @State private var step: SetupStep?

    private enum SetupStep: String, Identifiable {
        case goals, city, gym, plan
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if !dismissed {
                card
            }
        }
        .sheet(item: $step) { step in
            switch step {
            case .goals: GoalsView()
            case .city: LocationPicker()
            case .gym: MyGymView()
            case .plan: EmptyView()
            }
        }
    }

    @ViewBuilder
    private var card: some View {
        let items = self.items
        if let next = items.first(where: { !$0.isDone }).flatMap({ SetupStep(rawValue: $0.id) }) {
            VStack(alignment: .trailing, spacing: 0) {
                SetupChecklistCard(items: items, buttonTitle: Self.buttonTitle(next)) {
                    open(next)
                }
                Button("Not now") { dismissed = true }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                    .accessibilityHint("Hides this card. Goals, city and gym equipment are also in Settings.")
            }
        }
    }

    private var items: [SetupChecklistCard.Item] {
        [
            .init(id: SetupStep.goals.rawValue, title: "Set your goals",
                  detail: "Sets your calories, protein and workouts.", systemImage: "target", isDone: settings.goalsSet),
            .init(id: SetupStep.city.rawValue, title: "Add your city",
                  detail: "Weather, air quality and daylight for smarter coaching.", systemImage: "location", isDone: settings.hasLocation),
            .init(id: SetupStep.gym.rawValue, title: "Add your gym equipment",
                  detail: "Workouts only use what your gym has.", systemImage: "dumbbell", isDone: gym.isConfigured),
            .init(id: SetupStep.plan.rawValue, title: "Plan your training week",
                  detail: "Pick your days and a time.", systemImage: "calendar", isDone: !plans.plans.isEmpty),
        ]
    }

    private static func buttonTitle(_ step: SetupStep) -> String {
        switch step {
        case .goals: "Set your goals"
        case .city: "Add your city"
        case .gym: "Add your gym equipment"
        case .plan: "Plan your week"
        }
    }

    private func open(_ next: SetupStep) {
        if next == .plan {
            // This week's plan is an app-level sheet (`AppRouter.showWeeklyPlan`).
            router.showWeeklyPlan = true
        } else {
            step = next
        }
    }
}

// MARK: - Nutrition

/// Calories as a flexible band, never a daily "over" in red: daily deficit
/// judgement adds burden, and calorie counting correlates with eating-
/// disorder symptoms in some users (Simpson & Mazzeo 2017; Levinson 2017,
/// cited from memory in docs/research/behaviour-change.md). The weekly
/// average is what moves weight. "Hide calories" in Settings leaves protein
/// and fibre only. Water is a fourth bar only when water is logged; its
/// target is in the water sheet (ux-audit.md 4.6, H7).
private struct NutritionCard: View {
    let habits: TodayHabits

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @State private var showingDetails = false

    var body: some View {
        let food = metrics.nutritionToday
        VStack(alignment: .leading, spacing: 18) {
            header
            if !settings.hideCalories {
                CaloriesToday()
                Divider().overlay(Theme.separator)
            }
            if let food, !food.isEmpty {
                MacroBars(food: food)
                if let line = habits.proteinLine(metrics: metrics) {
                    // Protein per meal (`ProteinMeals`), from the old Daily habits card.
                    Text(line)
                        .font(Theme.Typography.context)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                NoFoodRow(proteinTarget: metrics.proteinTarget)
                if food?.waterLiters ?? 0 > 0 {
                    WaterColumn()
                }
            }
            WeightPaceLine()
            if settings.hideCalories {
                HiddenCaloriesSafetyLines()
            }
        }
        .card()
        .sheet(isPresented: $showingDetails) {
            CalorieDetailsSheet()
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var header: some View {
        if settings.hideCalories {
            CardLabel(text: "Nutrition")
        } else {
            HStack {
                CardLabel(text: "Calories today")
                Spacer()
                Button {
                    showingDetails = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How calories are calculated")
            }
        }
    }
}

/// Weight changing too fast for the goal (`WeightPace`), from the old Daily
/// habits card; shown only when it applies.
private struct WeightPaceLine: View {
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        if let pace = TodayHabits.weightMessage(metrics: metrics) {
            Label {
                Text("Weight is changing fast. " + pace)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "scalemass.fill")
                    .foregroundStyle(Theme.recoveryModerateText)
            }
        }
    }
}

/// Protein against its goal, then carbs and fat (or fibre when calories are
/// hidden), and water when it's logged.
private struct MacroBars: View {
    let food: NutritionDay

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MacroColumn(label: "Protein", grams: food.proteinGrams ?? 0, goal: metrics.proteinTarget, color: Theme.nutrition)
            if settings.hideCalories {
                // The app's fibre table (25/38 g Adequate Intake); 25-29 g/day
                // and above is where the benefit sits (Reynolds et al., Lancet 2019).
                MacroColumn(label: "Fibre", grams: food.fiberGrams ?? 0,
                            goal: Micronutrients.Nutrient.fiber.target(settings.sex, age: settings.age), color: Theme.oxygen)
            } else {
                MacroColumn(label: "Carbs", grams: food.carbsGrams ?? 0, goal: nil, color: Theme.strain)
                MacroColumn(label: "Fat", grams: food.fatGrams ?? 0, goal: nil, color: Theme.sleep)
            }
            if food.waterLiters ?? 0 > 0 {
                WaterColumn()
            }
        }
    }
}

/// No food today: one row, no paragraph (ux-audit.md 4.6).
private struct NoFoodRow: View {
    let proteinTarget: Double?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.nutrition)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("No food logged yet" + (proteinTarget.map { " · Protein goal \(whole($0)) g" } ?? ""))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Meals from your food app show up here via Apple Health.")
                    .font(Theme.Typography.context)
                    .foregroundStyle(Theme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Today's intake against the daily target and its flexible band. Only
/// today is available here (`DailyMetricsModel` keeps no intake history), so
/// the number is shown without a verdict and the weekly view is noted.
private struct CaloriesToday: View {
    @Environment(DailyMetricsModel.self) private var metrics
    /// The number inside the ring, 24 pt at the default size, scaled (ux-audit.md 4.5).
    @ScaledMetric(relativeTo: .title2) private var eatenSize: CGFloat = 24

    var body: some View {
        if let summary = metrics.calories, let target = metrics.calorieTarget {
            let eaten = summary.eaten ?? 0
            // ±10% flexible band: flexible targets kept more fat-free mass than
            // rigid ones for the same fat loss (Conlin et al., JISSN 2021; see `CalorieBand`).
            let band = GoalPlanner.calorieBand(target: target)
            HStack(alignment: .center, spacing: 20) {
                GradientRing(
                    progress: eaten / max(target, 1),
                    colors: Theme.nutritionColors,
                    lineWidth: 13
                ) {
                    VStack(spacing: 0) {
                        Text(whole(eaten).formatted())
                            .font(.system(size: eatenSize, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.primaryText)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("kcal eaten")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.horizontal, 14)
                }
                .frame(width: 124, height: 124)
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 12) {
                    CalorieLine(icon: "target", color: Theme.nutrition, label: metrics.goals == nil ? "Maintenance" : "Daily target",
                                text: "\(whole(target).formatted()) kcal")
                    CalorieLine(icon: "arrow.left.and.right", color: Theme.nutrition, label: "Flexible band (±10%)",
                                text: "\(whole(band.lowerBound).formatted())–\(whole(band.upperBound).formatted()) kcal")
                }
            }
            Text("One day over or under the band is fine; the weekly average is what moves weight.")
                .font(Theme.Typography.context)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Add your weight in Apple Health (or Settings) to see calories burned.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct CalorieLine: View {
    let icon: String
    let color: Color
    let label: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(color.gradient, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Text(text)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One bar: a label, the value (against a goal when there is one) and a fill.
private struct MacroColumn: View {
    let label: String
    let text: String
    /// 0...1
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(6, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension MacroColumn {
    /// Grams against an optional goal; without one the bar is relative to the value.
    init(label: String, grams value: Double, goal: Double?, color: Color) {
        self.init(
            label: label,
            text: goal.map { "\(whole(value))/\(whole($0)) g" } ?? "\(whole(value)) g",
            fraction: value / max(goal ?? max(value, 1) * 1.2, 1),
            color: color
        )
    }
}

// MARK: - Water

/// Today's water against the day's target (`Hydration`): sex-based base,
/// plus training and heat.
private struct HydrationNumbers {
    let drank: Double
    let target: Hydration.Target
    let assessment: Hydration.Assessment

    init(metrics: DailyMetricsModel, conditions: ConditionsModel, settings: UserSettings) {
        drank = metrics.nutritionToday?.waterLiters ?? 0
        let exerciseMinutes = Double(metrics.activities.map(\.minutes).reduce(0, +))
        target = Hydration.target(sex: settings.sex, exerciseMinutes: exerciseMinutes, feelsLikeC: conditions.current?.feelsLike)
        assessment = Hydration.assess(drank: drank, target: target, hour: Calendar.current.component(.hour, from: .now))
    }

    var color: Color {
        switch assessment.status {
        case .low: Theme.recoveryModerate
        case .onTrack: Theme.oxygen
        case .high: Theme.recoveryModerate
        }
    }
}

/// Water as the Nutrition card's fourth bar; tap for the target.
private struct WaterColumn: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(ConditionsModel.self) private var conditions
    @Environment(UserSettings.self) private var settings
    @State private var showingWater = false

    var body: some View {
        let water = HydrationNumbers(metrics: metrics, conditions: conditions, settings: settings)
        Button { showingWater = true } label: {
            MacroColumn(
                label: "Water",
                text: "\(water.drank.formatted(.number.precision(.fractionLength(1))))/\(water.target.liters.formatted(.number.precision(.fractionLength(1)))) L",
                fraction: water.drank / max(water.target.liters, 0.1),
                color: Theme.oxygen
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows today's water target")
        .sheet(isPresented: $showingWater) {
            WaterDetailsSheet()
                .presentationDetents([.medium, .large])
        }
    }
}

/// Today's water in detail: the even-pace line, what the amount means and
/// where the target comes from (was Home's water card).
private struct WaterDetailsSheet: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(ConditionsModel.self) private var conditions
    @Environment(UserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let water = HydrationNumbers(metrics: metrics, conditions: conditions, settings: settings)
        NavigationStack {
            ScrollView {
                WaterDetailsCard(water: water)
                    .padding()
                    .lockedToScreenWidth()
            }
            .background(Theme.background)
            .navigationTitle("Water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct WaterDetailsCard: View {
    let water: HydrationNumbers

    var body: some View {
        let target = water.target
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "Water today")
                Spacer()
                Chip(text: water.assessment.status.rawValue, color: water.color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(water.drank.formatted(.number.precision(.fractionLength(1))))
                    .heroNumberFont()
                    .foregroundStyle(Theme.primaryText)
                Text("of \(target.liters.formatted(.number.precision(.fractionLength(1)))) L")
                    .font(.headline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            WaterPaceBar(drank: water.drank, target: target.liters, expectedByNow: water.assessment.expectedByNow)
            ForEach(water.assessment.effects, id: \.self) { effect in
                Text(effect)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Target \(target.base.formatted()) L\(target.exercise > 0 ? " + \(target.exercise.formatted(.number.precision(.fractionLength(1)))) L training" : "")\(target.heat > 0 ? " + \(target.heat.formatted()) L heat" : ""). The line shows an even pace for now.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}

/// The water bar with a mark where an even pace would be by now.
private struct WaterPaceBar: View {
    let drank: Double
    let target: Double
    let expectedByNow: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(LinearGradient(colors: Theme.oxygenColors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(10, geo.size.width * min(1, drank / max(target, 0.1))))
                // Where you'd be by now on an even pace.
                Rectangle()
                    .fill(Theme.primaryText.opacity(0.35))
                    .frame(width: 2, height: 16)
                    .offset(x: geo.size.width * min(1, expectedByNow / max(target, 0.1)) - 1)
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - Calorie details

/// Where each calorie number comes from.
private struct CalorieDetailsSheet: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(CheckInStore.self) private var checkIns
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if metrics.calories == nil {
                    ContentUnavailableView(
                        "No calorie data yet",
                        systemImage: "flame",
                        description: Text("Add your weight in Apple Health (or Settings) and wear your watch to see calories burned.")
                    )
                }
                if let summary = metrics.calories {
                    Section {
                        Text(metrics.maintenance.map { "Your maintenance is \(whole($0.maintenance).formatted()) kcal, worked out from \($0.loggedDays) fully logged days of food and your weight trend." }
                             ?? "Maintenance is estimated from your watch until there are 14 fully logged days of food and enough weigh-ins.")
                        Text(metrics.goals.map { "Goal: \($0.title.lowercased()). Your daily target is maintenance adjusted for that goal." }
                             ?? "Set your goals in Settings › Goals to turn maintenance into a daily target.")
                        if let low = metrics.implausibleMaintenance {
                            Text("Your food log points to a maintenance of \(whole(low).formatted()) kcal, which is less than a body your size burns on a quiet day (1.4× resting metabolism; FAO/WHO 2004). Some days were probably only partly logged, so your watch's estimate is used until the log looks complete.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        if metrics.targetHeldAtMinimum, let minimum = metrics.calorieMinimum {
                            Text("Your target is held at \(whole(minimum).formatted()) kcal: below that, the energy left after training drops under 30 kcal per kg of lean mass, which affects hormones, bone and muscle (IOC consensus, 2023). Choose a slower rate in Goals to stay above it.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        if let note = metrics.calorieAdjustmentNote {
                            // Monday adjustment of at most ±100 kcal (`CalorieBand`).
                            Text(note)
                        }
                        PersonalCalorieNotes(cycleNote: CycleEnergy.note(sex: metrics.sex, daysSinceLastPeriod: checkIns.daysSinceLastPeriod()))
                        // Cut × sleep debt (`CutAndSleep`, Nedeltcheva 2010): advice to pick a
                        // slower rate; the weekly adjustment itself is unchanged.
                        if let cut = CutAndSleep.advice(goals: metrics.goals, sleepDebt: metrics.sleepDebt) {
                            Text(CutAndSleep.title + ". " + cut.message)
                        }
                        // Carbs by training day (`NutritionTargets.carbsText`: Burke 2011; Kerksick 2017) and
                        // low energy availability (`EnergyAvailability`: IOC REDs 2023). Calorie targets are unchanged.
                        if let carbs = NutritionTargets.carbsText(bodyMassKg: metrics.bodyMassKg, trainingDay: !metrics.activities.isEmpty, goals: metrics.goals) {
                            Text(carbs + " The calorie target doesn't change; this is how to split it, with protein first.")
                        }
                        if let availability = metrics.energyAvailability, let message = EnergyAvailability.message(availability, goals: metrics.goals) {
                            Text("Energy availability is low. " + message)
                        }
                    } header: {
                        Text("Where your target comes from")
                    }
                    Section {
                        row("Resting so far", summary.restingSoFar)
                        row("Active so far", summary.activeSoFar)
                        row("Burned so far", summary.burnedSoFar, bold: true)
                        row("Resting still to come", summary.projected - summary.burnedSoFar)
                        row("Burn by midnight", summary.projected, bold: true)
                    } header: {
                        Text("Burned")
                    } footer: {
                        Text(summary.fromWatch
                             ? "From your watch via Apple Health, so \"burned so far\" matches your watch. \"By midnight\" adds the resting calories your body will burn before the day ends; more activity adds to it."
                             : "Estimated: resting from \(metrics.energy?.bmrMethod ?? "your profile"), activity from heart rate and steps, plus the energy digestion costs (about 10% overall; more for protein).")
                    }
                    Section {
                        if let maintenance = metrics.maintenance {
                            row("Maintenance (your data)", maintenance.maintenance, bold: true)
                            row("Average eaten", maintenance.averageIntake)
                            LabeledContent("Weight trend", value: "\(maintenance.weeklyChangeKg >= 0 ? "+" : "")\(maintenance.weeklyChangeKg.formatted(.number.precision(.fractionLength(2)))) kg/week")
                            if maintenance.partialDaysSkipped > 0 {
                                Text("\(maintenance.partialDaysSkipped) day\(maintenance.partialDaysSkipped == 1 ? " looks" : "s look") only partly logged, so \(maintenance.partialDaysSkipped == 1 ? "it's" : "they're") left out.")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            if maintenance.creatineWaterRemovedKg > 0.05 {
                                Text("About \(maintenance.creatineWaterRemovedKg.formatted(.number.precision(.fractionLength(1)))) kg of the weight change is likely water from starting creatine, so it isn't counted as fat or muscle. Set the start date on Creatine in Medications if it's wrong.")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        } else {
                            let progress = metrics.maintenanceProgress
                            Text(progress.map { p -> String in
                                let skipped = p.partialDays > 0 ? " (\(p.partialDays) partly logged day\(p.partialDays == 1 ? "" : "s") don't count)" : ""
                                return "\(p.fullyLoggedDays) of 14 fully logged days in the last 4 weeks\(skipped), and 4+ weigh-ins over 10+ days. Until then, maintenance comes from your watch."
                            } ?? "Needs 14 fully logged days of food and 4+ weigh-ins over 10+ days in the last 4 weeks.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        if let target = metrics.calorieTarget {
                            row("Daily target", target, bold: true)
                        }
                        row("Eaten today", summary.eaten ?? 0)
                    } header: {
                        Text("Your real maintenance")
                    } footer: {
                        Text("Wrist trackers are off by over 30% on calories burned, on average. Comparing what you eat (from your food app) with how your weight moves gives a truer number: each kg of weight change is about 7,700 kcal.")
                    }
                }
            }
            .navigationTitle("Calories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, _ value: Double, bold: Bool = false) -> some View {
        LabeledContent(label) {
            Text("\(whole(value).formatted()) kcal")
                .monospacedDigit()
                .fontWeight(bold ? .semibold : .regular)
        }
    }
}

/// Personal parts of the calorie numbers (docs/research/calories.md): the
/// resting-energy equation used, a pace held at the personal maximum, and the
/// luteal-phase note (`CycleEnergy`; a note only, the target doesn't change).
private struct PersonalCalorieNotes: View {
    @Environment(DailyMetricsModel.self) private var metrics
    let cycleNote: String?

    var body: some View {
        if let method = metrics.energy?.bmrMethod {
            Text("Resting energy: \(method).")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        if let goals = metrics.goals, let held = metrics.personalGoals, held.weeklyRatePercent < goals.weeklyRatePercent {
            Text("Your pace is held at \(held.weeklyRatePercent.formatted())% a week. " + metrics.rateLimit(for: goals).message)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        if let cycleNote {
            Text(cycleNote)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

// MARK: - Health monitor

/// Four signals that say whether something is off today: resting heart
/// rate, HRV, breathing rate and sleep, each against your usual range
/// (ux-audit.md 4.6, H10). Blood oxygen, heart-rate recovery, heart-rate
/// stress and steps are long-term stats and live in Health ("All measures").
private struct HealthMonitor: View {
    let onEnterHRV: () -> Void
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals
    @Environment(AppRouter.self) private var router
    @State private var selected: VitalsModel.Stat?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HealthMonitorHeader(verdict: summary)
            TileGrid {
                opens("rhr") { rhrTile }
                hrvTile
                opens("respiration") { respiratoryTile }
                opens("sleepAverage") { sleepTile }
            }
            AllMeasuresLink { router.selectedTab = .health }
        }
        .sheet(item: $selected) { stat in
            VitalDetailView(stat: stat, colors: VitalTile.colors(for: stat.category))
                .presentationDetents([.medium, .large])
        }
    }

    /// Makes a tile open the same history view as on Health, when that stat exists.
    @ViewBuilder
    private func opens<Content: View>(_ id: String, @ViewBuilder _ tile: () -> Content) -> some View {
        if let stat = vitals.stat(id) {
            Button { selected = stat } label: { tile() }
                .buttonStyle(.plain)
                .accessibilityHint("Shows history")
        } else {
            tile()
        }
    }

    /// Everything on this card that's outside your normal today.
    private var summary: MetricVerdict? {
        guard let recovery = metrics.recovery, recovery.isCalibrated else { return nil }
        let flags = [
            (recovery.hrvChangePercent ?? 0) < -15,
            (recovery.restingHeartRateChange ?? 0) > 5,
            metrics.respiratoryRate.map { !(12...20).contains($0) } ?? false,
            metrics.sleep.map { $0.asleep < $0.need * 0.9 } ?? false,
        ].filter { $0 }.count
        return flags == 0 ? MetricVerdict("All normal", color: Theme.recoveryHigh) : MetricVerdict("\(flags) to watch", color: Theme.recoveryModerate)
    }

    /// Position of a value within baseline ± 2 SD, as 0...1. Nil (no gauge)
    /// until there's a baseline, so the gauge never pretends to be normal.
    private func position(_ value: Double?, mean: Double?, sd: Double?) -> Double? {
        guard let value, let mean, let sd, sd > 0 else { return nil }
        return min(1, max(0, (value - (mean - 2 * sd)) / (4 * sd)))
    }

    private var rhrTile: some View {
        let change = metrics.recovery?.restingHeartRateChange
        return MetricTile(
            title: "Resting heart rate",
            value: metrics.restingHeartRate.map { "\(whole($0.rounded()))" },
            unit: "bpm",
            spokenUnit: "beats per minute",
            status: change.map { delta -> MetricTile.Status in
                delta <= 0
                    ? MetricTile.Status(text: "Below normal", icon: "arrow.down", color: Theme.recoveryHigh)
                    : MetricTile.Status(text: "Above normal", icon: "arrow.up", color: delta > 5 ? Theme.recoveryModerate : Theme.secondaryText)
            },
            gauge: position(metrics.restingHeartRate, mean: metrics.baseline?.meanRHR, sd: metrics.baseline?.sdRHR),
            color: Theme.heart,
            lightColor: Theme.heartLight
        )
    }

    private var hrvTile: some View {
        let change = metrics.recovery?.hrvChangePercent
        let logValue = metrics.hrv.map { log($0) }
        return MetricTile(
            title: "HRV",
            value: metrics.hrv.map { "\(whole($0.rounded()))" },
            unit: "ms",
            spokenUnit: "milliseconds",
            status: change.map { delta -> MetricTile.Status in
                delta >= 0
                    ? MetricTile.Status(text: "Above normal", icon: "arrow.up", color: Theme.recoveryHigh)
                    : MetricTile.Status(text: "Below normal", icon: "arrow.down", color: delta < -15 ? Theme.recoveryModerate : Theme.secondaryText)
            },
            gauge: position(logValue, mean: metrics.baseline?.meanLogHRV, sd: metrics.baseline?.sdLogHRV),
            color: Theme.recoveryHigh,
            lightColor: Theme.recoveryHighLight,
            actionTitle: metrics.hrv == nil ? "Add HRV" : (metrics.hrvIsManual ? "Edit" : nil),
            onAction: onEnterHRV
        )
    }

    private var respiratoryTile: some View {
        let rate = metrics.respiratoryRate
        let normal = rate.map { (12...20).contains($0) } ?? true
        return MetricTile(
            title: "Breathing rate",
            value: rate.map { $0.formatted(.number.precision(.fractionLength(1))) },
            unit: "/min",
            spokenUnit: "breaths per minute",
            status: rate.map { _ -> MetricTile.Status in
                normal ? MetricTile.Status(text: "Normal") : MetricTile.Status(text: "Unusual", color: Theme.recoveryModerate)
            },
            gauge: rate.map { min(1, max(0, ($0 - 8) / 16)) },
            color: Theme.oxygen,
            lightColor: Theme.oxygenLight
        )
    }

    private var sleepTile: some View {
        let sleep = metrics.sleep
        return MetricTile(
            title: "Sleep",
            value: sleep.map { Duration.seconds($0.asleep).formatted(.units(allowed: [.hours, .minutes], width: .narrow)) },
            status: sleep.map { night -> MetricTile.Status in
                night.asleep >= night.need * 0.9
                    ? MetricTile.Status(text: "Normal")
                    : MetricTile.Status(text: "Short", color: Theme.recoveryModerate)
            },
            gauge: sleep.map { min(1, $0.asleep / max($0.need * 1.3, 1)) },
            color: Theme.sleep,
            lightColor: Theme.sleepLight
        )
    }
}

/// "Health Monitor" with its verdict ("All normal" / "2 to watch").
private struct HealthMonitorHeader: View {
    let verdict: MetricVerdict?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Health Monitor")
                .font(Theme.Typography.section)
                .foregroundStyle(Theme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let verdict {
                Chip(text: verdict.text, color: verdict.color)
            }
        }
        .padding(.top, 8)
    }
}

/// "All measures ›": switches to the Health tab, where the other stats live.
private struct AllMeasuresLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("All measures")
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityHint("Opens the Health tab")
    }
}

/// With calories hidden there's no details sheet, so the two safety notes it
/// carries show on the Nutrition card instead (as on the old Habits card):
/// cut × sleep debt (`CutAndSleep`, Nedeltcheva 2010) and low energy
/// availability (`EnergyAvailability`: IOC REDs 2023; Loucks 2011).
private struct HiddenCaloriesSafetyLines: View {
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        if let cut = CutAndSleep.advice(goals: metrics.goals, sleepDebt: metrics.sleepDebt) {
            Label(CutAndSleep.title + ". " + cut.message, systemImage: "moon.zzz.fill")
                .font(Theme.Typography.context)
                .foregroundStyle(Theme.recoveryModerateText)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let availability = metrics.energyAvailability, let message = EnergyAvailability.message(availability, goals: metrics.goals) {
            Label("Energy availability is low. " + message, systemImage: "bolt.heart.fill")
                .font(Theme.Typography.context)
                .foregroundStyle(Theme.recoveryModerateText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
