import Foundation
import HealthKit
import AppCore

/// Gathers last week, day by day, for the Monday review's "Basics" row
/// (`HealthFloors`) and the report on last week's changes
/// (`WeeklyChangeReview`), from what the models already hold. Nothing new is
/// read from Apple Health except the food app's timed caffeine and protein
/// entries, which only the review needs (`FoodTimes`).
enum WeeklyReviewData {
    /// The weeks before last week that the report compares against.
    static let earlierWeeks = 4

    /// The food app's timed entries over the review's five weeks. Empty when
    /// nothing is logged or Health can't be read.
    struct FoodTimes {
        var caffeine: [DatedValue] = []
        var protein: [DatedValue] = []
    }

    static func loadFoodTimes(health: HealthKitClient, lastWeek: Date) async -> FoodTimes {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -7 * earlierWeeks, to: lastWeek) ?? lastWeek
        let end = calendar.date(byAdding: .day, value: 7, to: lastWeek) ?? lastWeek
        async let caffeine = health.timedSamples(.dietaryCaffeine, unit: .gramUnit(with: .milli), from: start, to: end)
        async let protein = health.timedSamples(.dietaryProtein, unit: .gram(), from: start, to: end)
        return FoodTimes(caffeine: (try? await caffeine) ?? [], protein: (try? await protein) ?? [])
    }

    /// The models the days are read from.
    struct Sources {
        let metrics: DailyMetricsModel
        let vitals: VitalsModel
        let checkIns: CheckInStore
        /// Gym sessions and watch strength workouts (`WeeklyPlanStore.trainingDays`).
        let trainingDays: [Date]
        let food: FoodTimes
    }

    /// One `Day` per calendar day from `start`, `count` days, stopping before today.
    static func days(from start: Date, count: Int, _ s: Sources, now: Date = .now) -> [WeeklyChangeReview.Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        // Watch strength workouts are only known for the last 28 days (`recentLiftingDays`).
        let sessionsKnownFrom = calendar.date(byAdding: .day, value: -27, to: today) ?? today
        let trained = Set(s.trainingDays.map { calendar.startOfDay(for: $0) })
        let steps = Dictionary((s.vitals.stat("steps")?.series ?? []).map { (calendar.startOfDay(for: $0.date), $0.value) },
                               uniquingKeysWith: { first, _ in first })
        let nights = Dictionary(s.metrics.sleepNights.map { (calendar.startOfDay(for: $0.date), $0) },
                                uniquingKeysWith: { _, latest in latest })
        let foodLogHasCaffeine = s.food.caffeine.contains { $0.value > 0 }
        let bodyMass = s.metrics.bodyMassKg

        return (0..<count).compactMap { offset -> WeeklyChangeReview.Day? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: start)), date < today,
                  let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            var day = WeeklyChangeReview.Day(date: date)

            // Food: protein per meal when the food app sends real times.
            let protein = s.food.protein.filter { $0.date >= date && $0.date < next }
            let assessed = bodyMass.flatMap { ProteinMeals.assess(protein.map { (date: $0.date, grams: $0.value) }, bodyMassKg: $0) }
            var timesAreReal = false
            if case .meals(_, goodMeals: let good, perMealTarget: _)? = assessed {
                day.proteinMeals = good
                timesAreReal = true
            }
            let grams = protein.map(\.value).reduce(0, +)
            if grams > 0 { day.proteinGrams = grams }
            let caffeine = s.food.caffeine.filter { $0.date >= date && $0.date < next }
            let evening = s.checkIns.evening(on: date)
            let last = WeeklyChangeReview.caffeine(samples: caffeine.map { (date: $0.date, mg: $0.value) }, timesAreReal: timesAreReal,
                                                   evening: evening, foodLogged: !protein.isEmpty || !caffeine.isEmpty,
                                                   foodLogHasCaffeine: foodLogHasCaffeine, calendar: calendar)
            day.lastCaffeineMinutes = last.lastMinutes
            day.noCaffeine = last.none

            // Sleep: that morning's wake time; that evening's bedtime and hours.
            if let morning = nights[date] {
                let parts = calendar.dateComponents([.hour, .minute], from: morning.wake)
                day.wakeMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
            if let night = nights[next] {
                day.bedtimeMinutes = WeeklyChange.eveningMinutes(night.bedtime, calendar: calendar)
                day.sleepHours = night.hoursAsleep
            }

            // Activity.
            if let count = steps[date], count > 0 { day.steps = count }
            if let minutes = s.vitals.intensitySplitByDay[date] {
                day.moderateMinutes = minutes.moderate
                day.vigorousMinutes = minutes.vigorous
            }
            day.cardioVigorousMinutes = s.vitals.cardioVigorousByDay[date]
            if date >= sessionsKnownFrom { day.strengthSession = trained.contains(date) }

            // Drinks that evening: the itemised log, else the quick count. A logged zero counts.
            if let evening {
                if let standard = evening.standardDrinks {
                    day.drinks = standard
                } else if let count = evening.drinks {
                    day.drinks = Double(count)
                }
            }
            return day
        }
    }

    /// The Sleep Regularity Index of the week starting `weekStart`.
    static func sleepRegularity(_ metrics: DailyMetricsModel, weekStart: Date) -> Int? {
        HealthFloors.sleepRegularity(asleep: metrics.sleepNights.flatMap(\.intervals), weekStart: weekStart)
    }

    /// Whether the food app sends real meal times (two or more timestamps on some day).
    static func hasMealTimes(_ food: FoodTimes) -> Bool {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: food.protein.filter { $0.value > 0 }) { calendar.startOfDay(for: $0.date) }
        return byDay.values.contains { Set($0.map { Int($0.date.timeIntervalSince1970 / 60) }).count > 1 }
    }
}
