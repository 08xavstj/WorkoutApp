import SwiftUI
import HealthKit
import AppCore

/// Small daily habits with research behind them: when to stop caffeine,
/// protein spread over meals, movement breaks, and whether weight is changing
/// too fast. They used to share one "Daily habits" card; in the redesign
/// (docs/research/ux-audit.md 4.3, 4.6) each one shows where it's acted on:
/// caffeine cut-off, movement nudge and weigh-in as Today › Up next rows
/// (`UpNextCard`), protein per meal and "weight is changing fast" as lines
/// on the Nutrition card, and cut × sleep and low energy availability in the
/// Calorie details sheet (they were already there).
///
/// This model loads today's timed caffeine and protein entries and hourly
/// steps from Apple Health and works out the rows' wording.
@Observable
final class TodayHabits {
    private(set) var caffeineToday: [DatedValue] = []
    private(set) var proteinToday: [DatedValue] = []
    // Movement breaks and the post-meal walk (`MovementBreaks`; Buffey 2022; Dunstan 2012).
    private(set) var movementNudge: MovementBreaks.Nudge?

    /// The one movement nudge allowed per day: the day it was shown and which
    /// one (same keys the old Habits card kept in `@AppStorage`).
    private static let nudgeDayKey = "movementNudgeDay"
    private static let nudgeIDKey = "movementNudgeID"

    // MARK: Caffeine

    /// The caffeine row: a cut-off before bed, or a warning when today's last
    /// caffeine was too late for the usual bedtime (`CaffeineTiming`).
    struct Caffeine {
        var isLate: Bool
        var title: String
        var detail: String
        /// Last coffee (100 mg) by this time, minutes after midnight.
        var cutoffMinutes: Int
    }

    /// The latest caffeine today: from your food app if it sends times, else the evening check-in.
    private func latestCaffeine(checkIns: CheckInStore) -> (minutes: Int, mg: Double)? {
        if let last = caffeineToday.last(where: { $0.value > 0 }) {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: last.date)
            return ((parts.hour ?? 0) * 60 + (parts.minute ?? 0), last.value)
        }
        if let evening = checkIns.evening(), let minutes = evening.lastCaffeineMinutes, let mg = evening.caffeineMg, mg > 0 {
            return (minutes, mg)
        }
        return nil
    }

    func caffeine(metrics: DailyMetricsModel, checkIns: CheckInStore) -> Caffeine {
        let bedtime = CaffeineTiming.usualBedtimeMinutes(metrics.recentBedtimes)
        let coffee = CaffeineTiming.cutoffMinutes(bedtimeMinutes: bedtime, mg: 100)
        let preWorkout = CaffeineTiming.cutoffMinutes(bedtimeMinutes: bedtime, mg: 200)
        let bed = CaffeineTiming.clockText(bedtime)
        if let latest = latestCaffeine(checkIns: checkIns),
           CaffeineTiming.isTooLate(minutes: latest.minutes, mg: latest.mg, bedtimeMinutes: bedtime) {
            return Caffeine(
                isLate: true,
                title: "Caffeine at \(CaffeineTiming.clockText(latest.minutes)) is late for a \(bed) bedtime",
                detail: "It can cut your sleep tonight. Next time, last coffee by \(CaffeineTiming.clockText(coffee)).",
                cutoffMinutes: coffee
            )
        }
        return Caffeine(
            isLate: false,
            title: "Last coffee by \(CaffeineTiming.clockText(coffee))",
            detail: "Pre-workout by \(CaffeineTiming.clockText(preWorkout)), for your usual \(bed) bedtime. Caffeine closer to bed cut sleep by about 45 minutes in studies.",
            cutoffMinutes: coffee
        )
    }

    // MARK: Protein per meal

    /// One line for the Nutrition card (`ProteinMeals`), or nil without a weight or entries.
    func proteinLine(metrics: DailyMetricsModel) -> String? {
        guard let weight = metrics.bodyMassKg,
              let result = ProteinMeals.assess(proteinToday.map { (date: $0.date, grams: $0.value) }, bodyMassKg: weight) else { return nil }
        switch result {
        case .noMealTimes:
            return "Your food app doesn't send meal times, so meals can't be told apart. Aim for about \(whole(weight * ProteinMeals.gramsPerKgPerMeal)) g at each of 4 meals."
        case .meals(let meals, goodMeals: let good, perMealTarget: let target):
            return "\(good) of \(ProteinMeals.targetMeals) meals with \(whole(target)) g+ protein. \(meals.count) meal\(meals.count == 1 ? "" : "s") logged today. Spreading protein over 4 meals of about \(whole(target)) g builds the most muscle."
        }
    }

    // MARK: Weight pace

    /// "Weight is changing fast" advice (`WeightPace`), for the Nutrition card.
    static func weightMessage(metrics: DailyMetricsModel) -> String? {
        guard let weekly = metrics.weightTrendWeekly, let weight = metrics.bodyMassKg else { return nil }
        return WeightPace.message(WeightPace.check(weeklyChangeKg: weekly, bodyMassKg: weight, goals: metrics.goals))
    }

    // MARK: Loading

    func load(health: HealthKitClient, metrics: DailyMetricsModel) async {
        let start = Calendar.current.startOfDay(for: .now)
        caffeineToday = (try? await health.timedSamples(.dietaryCaffeine, unit: .gramUnit(with: .milli), from: start, to: .now)) ?? []
        proteinToday = (try? await health.timedSamples(.dietaryProtein, unit: .gram(), from: start, to: .now)) ?? []
        // Movement breaks: today's hourly steps and the times meals were logged.
        let hourly = (try? await health.hourlySteps(for: .now)) ?? []
        let energyEntries = (try? await health.timedSamples(.dietaryEnergyConsumed, unit: .kilocalorie(), from: start, to: .now)) ?? []
        updateMovementNudge(hourlySteps: hourly, energyEntries: energyEntries, metrics: metrics)
    }

    /// At most one nudge a day (`MovementBreaks.assess`). Meal times come
    /// from the food app's timed calorie entries (entries within 90 minutes
    /// are one meal, as `ProteinMeals` groups them).
    private func updateMovementNudge(hourlySteps: [MovementBreaks.HourSteps], energyEntries: [DatedValue], metrics: DailyMetricsModel) {
        let meals = ProteinMeals.meals(energyEntries.map { (date: $0.date, grams: $0.value) }).map(\.time)
        let nudge = MovementBreaks.assess(hourlySteps: hourlySteps, mealTimes: meals, wake: metrics.sleep?.wakeTime, goals: metrics.goals)
        let today = Dose.dayKey(Calendar.current.startOfDay(for: .now))
        guard let nudge else {
            movementNudge = nil
            return
        }
        let defaults = UserDefaults.standard
        // One nudge a day: a second, different one waits for tomorrow.
        if defaults.string(forKey: Self.nudgeDayKey) == today, defaults.string(forKey: Self.nudgeIDKey) != nudge.id {
            movementNudge = nil
            return
        }
        defaults.set(today, forKey: Self.nudgeDayKey)
        defaults.set(nudge.id, forKey: Self.nudgeIDKey)
        movementNudge = nudge
    }
}
