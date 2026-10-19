import Foundation

// MARK: - Caffeine

/// When to stop caffeine so it doesn't cost sleep.
///
/// In a meta-analysis of 24 studies, caffeine cut total sleep by about 45
/// minutes. To avoid losing sleep time, a coffee (~107 mg) should be at least
/// 8.8 hours before bed and a typical pre-workout (~217 mg) at least 13.2 hours
/// (Gardiner et al., Sleep Med Rev 2023).
public enum CaffeineTiming {
    public static let coffeeHours = 8.8
    public static let preWorkoutHours = 13.2
    /// Doses from about this size count as pre-workout strength.
    public static let largeDoseMg = 180.0
    /// Used when there's no sleep data yet.
    public static let defaultBedtimeMinutes = 23 * 60

    /// Hours before bed for a dose.
    public static func hoursBeforeBed(mg: Double) -> Double {
        mg >= largeDoseMg ? preWorkoutHours : coffeeHours
    }

    /// Usual time of falling asleep, in minutes after midnight (may exceed
    /// 1440 for after-midnight bedtimes, e.g. 1500 = 1:00 am). Median of recent
    /// sleep onsets, measured from noon so 11 pm and 1 am average sensibly.
    public static func usualBedtimeMinutes(_ onsets: [Date], calendar: Calendar = .current) -> Int {
        let fromNoon = onsets.map { onset -> Int in
            let parts = calendar.dateComponents([.hour, .minute], from: onset)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            return (minutes - 12 * 60 + 1440) % 1440
        }.sorted()
        guard !fromNoon.isEmpty else { return defaultBedtimeMinutes }
        let median = fromNoon[fromNoon.count / 2]
        return median + 12 * 60
    }

    /// Latest time for a dose, in minutes after midnight on the same day.
    public static func cutoffMinutes(bedtimeMinutes: Int, mg: Double) -> Int {
        max(0, bedtimeMinutes - Int((hoursBeforeBed(mg: mg) * 60).rounded()))
    }

    /// e.g. "2:12 pm"
    public static func clockText(_ minutes: Int, calendar: Calendar = .current) -> String {
        let midnight = calendar.startOfDay(for: .now)
        let date = calendar.date(byAdding: .minute, value: minutes % 1440, to: midnight) ?? midnight
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Was a dose taken at `minutes` (after midnight) too late for this bedtime?
    public static func isTooLate(minutes: Int, mg: Double, bedtimeMinutes: Int) -> Bool {
        minutes > cutoffMinutes(bedtimeMinutes: bedtimeMinutes, mg: mg)
    }
}

// MARK: - Alcohol

/// How drinking the evening before changes *your* next morning.
///
/// Alcohol lowers overnight HRV and raises heart rate in a dose-dependent way,
/// even in fit people (Pietilä et al., JMIR Ment Health 2018), and shortens and
/// delays REM sleep from about two drinks (Gardiner et al., Sleep Med Rev 2025).
/// This compares your own drink and no-drink nights.
public enum AlcoholEffect {
    public struct Night: Sendable, Equatable {
        public var morning: Date
        public var drinks: Int
        public var restingHeartRate: Double?
        public var hrv: Double?
        public var sleepScore: Double?

        public init(morning: Date, drinks: Int, restingHeartRate: Double?, hrv: Double?, sleepScore: Double?) {
            self.morning = morning
            self.drinks = drinks
            self.restingHeartRate = restingHeartRate
            self.hrv = hrv
            self.sleepScore = sleepScore
        }
    }

    public enum Measure: String, Sendable, CaseIterable {
        case restingHeartRate = "Resting heart rate"
        case hrv = "HRV"
        case sleepScore = "Sleep score"

        public var unit: String {
            switch self {
            case .restingHeartRate: "bpm"
            case .hrv: "ms"
            case .sleepScore: "points"
            }
        }

        /// Higher is better for HRV and sleep, worse for resting heart rate.
        public var higherIsBetter: Bool { self != .restingHeartRate }

        func value(_ night: Night) -> Double? {
            switch self {
            case .restingHeartRate: night.restingHeartRate
            case .hrv: night.hrv
            case .sleepScore: night.sleepScore
            }
        }
    }

    public struct Finding: Sendable, Equatable, Identifiable {
        public var measure: Measure
        public var withDrinks: Double
        public var without: Double
        public var nightsWith: Int
        public var nightsWithout: Int
        /// True when the difference is unlikely to be chance (Welch t-test, p < 0.05).
        public var isClear: Bool
        public var id: String { measure.rawValue }
        public var difference: Double { withDrinks - without }
        public var isWorse: Bool { (difference > 0) != measure.higherIsBetter && difference != 0 }

        public var sentence: String {
            let amount = abs(difference).formatted(.number.precision(.fractionLength(measure == .restingHeartRate ? 1 : 0)))
            let direction = difference >= 0 ? "higher" : "lower"
            return "\(measure.rawValue) is \(amount) \(measure.unit) \(direction) after drinking (\(nightsWith) nights) than without (\(nightsWithout) nights)."
        }
    }

    /// Nights with at least `minimumDrinks` vs nights with none; needs
    /// `minimumNights` on each side for a measure to be shown.
    public static func compare(_ nights: [Night], minimumDrinks: Int = 1, minimumNights: Int = 5) -> [Finding] {
        Measure.allCases.compactMap { measure in
            let with = nights.filter { $0.drinks >= minimumDrinks }.compactMap { measure.value($0) }
            let without = nights.filter { $0.drinks == 0 }.compactMap { measure.value($0) }
            guard with.count >= minimumNights, without.count >= minimumNights else { return nil }
            let (meanWith, varWith) = CheckInInsights.meanVariance(with)
            let (meanWithout, varWithout) = CheckInInsights.meanVariance(without)
            let p = CheckInInsights.welchPValue(meanA: meanWith, varA: varWith, nA: with.count,
                                                meanB: meanWithout, varB: varWithout, nB: without.count)
            return Finding(measure: measure, withDrinks: meanWith, without: meanWithout,
                           nightsWith: with.count, nightsWithout: without.count, isClear: p < 0.05)
        }
    }
}

// MARK: - Protein per meal

/// Protein spread across meals. About 0.4 g per kg of body weight per meal,
/// over at least 4 meals, maximises muscle building (Schoenfeld & Aragon,
/// JISSN 2018).
public enum ProteinMeals {
    public static let gramsPerKgPerMeal = 0.4
    public static let targetMeals = 4

    public struct Meal: Sendable, Equatable {
        public var time: Date
        public var grams: Double
    }

    public enum Result: Sendable, Equatable {
        /// The food app writes every entry at the same time, so meals can't be told apart.
        case noMealTimes
        case meals([Meal], goodMeals: Int, perMealTarget: Double)
    }

    /// Groups protein entries into meals: a gap of more than 90 minutes starts a new meal.
    public static func meals(_ entries: [(date: Date, grams: Double)]) -> [Meal] {
        var meals: [Meal] = []
        var lastTime: Date?
        for entry in entries.filter({ $0.grams > 0 }).sorted(by: { $0.date < $1.date }) {
            if let lastTime, entry.date.timeIntervalSince(lastTime) <= 90 * 60, !meals.isEmpty {
                meals[meals.count - 1].grams += entry.grams
            } else {
                meals.append(Meal(time: entry.date, grams: entry.grams))
            }
            lastTime = entry.date
        }
        return meals
    }

    public static func assess(_ entries: [(date: Date, grams: Double)], bodyMassKg: Double) -> Result? {
        let positive = entries.filter { $0.grams > 0 }
        guard !positive.isEmpty, bodyMassKg > 0 else { return nil }
        let times = Set(positive.map { Int($0.date.timeIntervalSince1970 / 60) })
        // One timestamp for everything (or a single daily total) means no meal times.
        if times.count == 1 { return .noMealTimes }
        let target = bodyMassKg * gramsPerKgPerMeal
        let grouped = meals(positive)
        return .meals(grouped, goodMeals: grouped.filter { $0.grams >= target * 0.95 }.count, perMealTarget: target)
    }
}

// MARK: - Weight change speed

/// Warns when weight is changing faster than is good for muscle.
///
/// Losing more than about 1% of body weight a week costs more muscle and
/// strength (Helms et al., JISSN 2014; Garthe et al., IJSNEM 2011). Gaining
/// faster than planned mostly adds fat (Iraki et al., Sports 2019).
public enum WeightPace {
    public enum Status: Sendable, Equatable {
        case fine
        case losingTooFast(percentPerWeek: Double)
        case gainingTooFast(percentPerWeek: Double, planned: Double)
    }

    /// - Parameter weeklyChangeKg: trend change per week (negative = losing).
    public static func check(weeklyChangeKg: Double, bodyMassKg: Double, goals: Goals?) -> Status {
        guard bodyMassKg > 0 else { return .fine }
        let percent = weeklyChangeKg / bodyMassKg * 100
        if percent < -1.0 { return .losingTooFast(percentPerWeek: -percent) }
        if let goals, goals.weight == .gain, percent > goals.weeklyRatePercent * 1.5 + 0.1 {
            return .gainingTooFast(percentPerWeek: percent, planned: goals.weeklyRatePercent)
        }
        if goals?.weight != .gain, goals != nil, percent > 0.5 {
            return .gainingTooFast(percentPerWeek: percent, planned: 0)
        }
        return .fine
    }

    public static func message(_ status: Status) -> String? {
        func fmt(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) }
        switch status {
        case .fine:
            return nil
        case .losingTooFast(let percent):
            return "You're losing about \(fmt(percent))% of your weight a week. Over 1% a week costs muscle and strength, so eat a little more: your target will adjust at the weekly check-in."
        case .gainingTooFast(let percent, let planned):
            if planned > 0 {
                return "You're gaining about \(fmt(percent))% a week, faster than your \(fmt(planned))% plan; extra speed is mostly fat. Trim a little: your target adjusts weekly."
            }
            return "Your weight trend is rising about \(fmt(percent))% a week. If that's not the plan, trim a little: targets adjust weekly, not daily."
        }
    }
}

// MARK: - Heat

/// Hot days: a lower strain target and heat acclimation.
///
/// Heat raises heart rate and core temperature at the same pace, and repeated
/// training in the heat over about 10-14 days brings most of the adaptation
/// (Périard et al., Physiol Rev 2021). "Feels like" stands in for wet-bulb
/// globe temperature, so the thresholds are approximate.
public enum HeatAdvice {
    public static let hotFeelsLikeC = 28.0
    public static let veryHotFeelsLikeC = 35.0
    public static let acclimatizedDays = 10

    /// Change to the strain target's upper end (0 or negative).
    public static func targetAdjustment(feelsLikeC: Double?, heatTrainingDays: Int) -> Double {
        guard let feels = feelsLikeC, feels >= hotFeelsLikeC else { return 0 }
        let base: Double = feels >= veryHotFeelsLikeC ? -15 : -10
        return heatTrainingDays >= acclimatizedDays ? base / 2 : base
    }

    /// Lowers the top of a target range; the range stays valid and at least 5 wide.
    public static func adjustTarget(_ range: ClosedRange<Double>, by adjustment: Double) -> ClosedRange<Double> {
        guard adjustment < 0 else { return range }
        let upper = max(10, range.upperBound + adjustment)
        let lower = max(0, min(range.lowerBound, upper - 5))
        return lower...upper
    }

    /// Days in the last 14 that were hot and had training.
    public static func heatTrainingDays(hotDays: Set<Date>, trainingDays: Set<Date>, now: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now)) ?? now
        return hotDays.intersection(trainingDays).filter { $0 >= start }.count
    }

    public static func advice(feelsLikeC: Double?, heatTrainingDays: Int) -> String? {
        guard let feels = feelsLikeC, feels >= hotFeelsLikeC else { return nil }
        let acclimation = heatTrainingDays >= acclimatizedDays
            ? "You've trained in the heat on \(heatTrainingDays) of the last 14 days, so you're largely acclimatised."
            : "Heat adaptation builds over about 10-14 days of training in it (\(heatTrainingDays) so far)."
        return "Hot today (feels \(Int(feels.rounded()))°C): your strain target is lower. Slow your pace to keep the same effort, drink regularly, and train early or indoors. \(acclimation)"
    }
}
