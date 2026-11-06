import Foundation

// MARK: - Caffeine

/// When to stop caffeine so it doesn't cost sleep.
///
/// In a meta-analysis of 24 studies, caffeine cut total sleep by about 45
/// minutes. The model in that paper puts a coffee (~107 mg) at 8.8 hours
/// before bed and a typical pre-workout (~217 mg) at 13.2 hours (Gardiner et
/// al., Sleep Med Rev 2023; the 8.8/13.2 h figures are the paper's model
/// averages, from memory in the audit). The cut-off here is interpolated by
/// dose along that line rather than stepped, and it is a conservative
/// average: a 2025 crossover trial by the same group found 100 mg four hours
/// before bed had no measurable effect on sleep, while 400 mg at 12 hours did
/// (Gardiner et al., Sleep 2025; secondary source). Sensitivity varies a lot
/// between people.
public enum CaffeineTiming {
    /// Hours before bed at the reference dose (Gardiner et al., Sleep Med Rev 2023).
    public static let baseHours = 8.8
    /// The dose the base figure applies to: one coffee, ~107 mg (Gardiner 2023).
    public static let referenceDoseMg = 107.0
    /// Extra hours per mg above the reference dose: (13.2 − 8.8) / (217 − 107)
    /// = 0.04 h/mg, the slope between the paper's two model estimates.
    public static let hoursPerMg = 0.04
    /// Clamp so tiny doses still get a sensible gap and huge doses don't run
    /// past the morning (app choice; the paper's data cover ~100-400 mg).
    public static let minimumHours = 6.0
    public static let maximumHours = 14.0
    /// Used when there's no sleep data yet.
    public static let defaultBedtimeMinutes = 23 * 60

    /// Hours before bed for a dose: 8.8 + 0.04 × (mg − 107), clamped to 6-14 h.
    public static func hoursBeforeBed(mg: Double) -> Double {
        let hours = baseHours + hoursPerMg * (mg - referenceDoseMg)
        return min(maximumHours, max(minimumHours, hours))
    }

    /// One line for the UI: why the cut-off is an average, not a rule.
    public static let cautionNote = "That's a conservative average; a 2025 trial found 100 mg four hours before bed had no measurable effect, and sensitivity varies a lot between people."

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
        // To the nearest 5 minutes: "11:05 pm", not "11:03 pm" (display choice;
        // night-to-night onset varies far more than that).
        return Int((Double(median) / 5).rounded()) * 5 + 12 * 60
    }

    /// Latest time for a dose, in minutes after midnight on the same day.
    /// Rounded down to 5 minutes ("2:25 pm", not "2:29 pm"): a little earlier,
    /// never later, than the model's figure (display choice).
    public static func cutoffMinutes(bedtimeMinutes: Int, mg: Double) -> Int {
        let exact = bedtimeMinutes - Int((hoursBeforeBed(mg: mg) * 60).rounded())
        return max(0, Int((Double(exact) / 5).rounded(.down)) * 5)
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

// MARK: - Weekly alcohol

/// Standard drinks over the last 7 nights against Canada's 2023 guidance
/// (Canadian Centre on Substance Use and Addiction, Canada's Guidance on
/// Alcohol and Health, 2023): 0–2 a week low risk, 3–6 moderate, 7 or more
/// increasingly high. The guidance's own authors rate its evidence base as
/// low quality, GBD 2020 puts the risk-minimising amount under 40 at about
/// 0–0.6 drinks a day (Lancet 2022), and GBD 2016 said "no safe level", so
/// the tiers are a reference band, not a verdict (health-metrics.md §7).
/// The next-morning effect on your own HRV and heart rate (`AlcoholEffect`)
/// is the personal measure and stays alongside.
public enum AlcoholWeek {
    public static let nights = 7
    /// Top of the low-risk tier, standard drinks a week (CCSA 2023).
    public static let lowMax = 2.0
    /// Top of the moderate tier; 7 and up is "increasingly high" (CCSA 2023).
    public static let moderateMax = 6.0

    public enum Tier: String, Sendable, Equatable, CaseIterable {
        case low = "Low risk"
        case moderate = "Moderate risk"
        case high = "Increasingly high risk"

        /// "0–2", "3–6", "7+"
        public var range: String {
            switch self {
            case .low: "0–2"
            case .moderate: "3–6"
            case .high: "7+"
            }
        }
    }

    /// Fractions count up: 2.5 standard drinks is past the low tier.
    public static func tier(drinks: Double) -> Tier {
        if drinks <= lowMax { return .low }
        if drinks < moderateMax + 1 { return .moderate }
        return .high
    }

    public struct Total: Sendable, Equatable {
        public var drinks: Double
        /// Evenings with a known drink count (zero counts).
        public var nightsLogged: Int
        public var tier: Tier { AlcoholWeek.tier(drinks: drinks) }

        public init(drinks: Double, nightsLogged: Int) {
            self.drinks = drinks
            self.nightsLogged = nightsLogged
        }
    }

    /// Sums the itemised standard drinks where logged, else the quick count.
    public static func total(evenings: [EveningCheckIn]) -> Total {
        var drinks = 0.0
        var logged = 0
        for evening in evenings {
            if let standard = evening.standardDrinks {
                drinks += standard
                logged += 1
            } else if let count = evening.drinks {
                drinks += Double(count)
                logged += 1
            }
        }
        return Total(drinks: drinks, nightsLogged: logged)
    }

    /// Neutral wording for the card.
    public static func sentence(_ total: Total) -> String {
        let amount = total.drinks.formatted(.number.precision(.fractionLength(0...1)))
        let base = "\(amount) standard drink\(total.drinks == 1 ? "" : "s") in the last 7 nights (\(total.nightsLogged) of 7 logged): \(total.tier.rawValue.lowercased()) on Canada's 2023 guidance (0–2 low, 3–6 moderate, 7+ increasingly high)."
        switch total.tier {
        case .low: return base + " Within the band the guidance calls low risk; its authors rate the evidence as low quality."
        case .moderate: return base + " The guidance's own evidence is rated low quality; your morning numbers below are the measure that's yours."
        case .high: return base + " From 7 a week the guidance's risk estimates climb with each drink; your morning numbers below show what it does to you."
        }
    }
}

// MARK: - Sauna and cold water

/// Check-in footer copy for the two recovery habits.
///
/// - Cold water right after lifting blunted strength and muscle gains over 12
///   weeks (type II fibre area, satellite cells, p70S6K; Roberts et al.,
///   J Physiol 2015, 21 men) and a meta-analysis of 8 studies found smaller
///   hypertrophy (Piñero et al., Eur J Sport Sci 2024). Fine on rest days or
///   after cardio; the report says not within ~4–6 h of lifting.
/// - Sauna 4–7 times a week vs once was linked with HR 0.60 for all-cause and
///   0.50 for fatal cardiovascular events in 2,315 Finnish men, with sessions
///   over 19 minutes doing best (Laukkanen et al., JAMA Intern Med 2015; one
///   cohort, observational). It adds heat stress, so it counts as a hot day.
public enum HeatAndCold {
    public static let coldPlungeNote = "Cold water right after lifting blunts muscle growth (Roberts 2015; Piñero 2024); on lifting days, keep it to the morning or skip."
    public static let saunaNote = "Regular sauna (4–7 times a week, about 20 minutes) was linked with fewer heart deaths in Finnish men (Laukkanen 2015); it also adds heat stress, so count it as a hot day."
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
/// Heat risk is judged on wet-bulb globe temperature (WBGT), which combines
/// air temperature, humidity and, in the full measurement, sun and wind. With
/// no sensor it is estimated from air temperature and relative humidity using
/// the Australian Bureau of Meteorology approximation, which assumes moderate
/// sun and light wind, so it reads high for shaded or indoor training (BoM
/// "approximation to the WBGT"; named in the audit from memory). The bands
/// follow the ACSM consensus on exertional heat illness (Roberts et al., Curr
/// Sports Med Rep 2021; bands from memory in the audit): under 18 °C low,
/// 18-23 moderate, 23-28 high, 28-30 very high, over 30 extreme, where
/// unacclimatised people should not train hard outdoors.
///
/// Repeated training in the heat over about 7-14 days brings most of the
/// adaptation (Périard et al., Scand J Med Sci Sports 2015), and it fades over
/// about 2-3 weeks away from the heat (Daanen et al., Sports Med 2018; from
/// memory in the audit). The size of the strain-target cut is the app's choice.
public enum HeatAdvice {
    /// ACSM WBGT bands (Roberts et al. 2021), lower bound of each.
    public static let moderateWBGT = 18.0
    public static let highWBGT = 23.0
    public static let veryHighWBGT = 28.0
    public static let extremeWBGT = 30.0
    /// Hot training days (of 14) that count as acclimatised (Périard 2015: most adaptation in 7-14 days).
    public static let acclimatizedDays = 10
    /// Days away from the heat over which acclimation is kept in full, then partly, then lost (Daanen 2018: ~2-3 weeks).
    public static let acclimationKeptDays = 14
    public static let acclimationLostDays = 21
    /// Relative humidity assumed when the weather source has none (app choice).
    public static let defaultHumidityPercent = 50.0

    public enum Risk: Int, Sendable, Comparable {
        case low, moderate, high, veryHigh, extreme
        public static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }

        public var label: String {
            switch self {
            case .low: "Low"
            case .moderate: "Moderate"
            case .high: "High"
            case .veryHigh: "Very high"
            case .extreme: "Extreme"
            }
        }
    }

    /// WBGT estimate, °C, from air temperature and relative humidity
    /// (Australian BoM approximation): WBGT = 0.567 T + 0.393 e + 3.94, where
    /// e is the water-vapour pressure in hPa from T and humidity.
    public static func estimatedWBGT(temperatureC: Double, humidityPercent: Double?) -> Double {
        let humidity = min(100, max(0, humidityPercent ?? defaultHumidityPercent))
        let vapourPressure = humidity / 100 * 6.105 * exp(17.27 * temperatureC / (237.7 + temperatureC))
        return 0.567 * temperatureC + 0.393 * vapourPressure + 3.94
    }

    /// ACSM band for an estimated WBGT.
    public static func risk(wbgtC: Double) -> Risk {
        switch wbgtC {
        case ..<moderateWBGT: .low
        case ..<highWBGT: .moderate
        case ..<veryHighWBGT: .high
        case ...extremeWBGT: .veryHigh
        default: .extreme
        }
    }

    /// How acclimatised the user is, from hot days that had training.
    public struct Acclimation: Sendable, Equatable {
        /// Hot training days in the last 14.
        public var heatTrainingDays: Int
        /// Hot training days in the 14 days ending on the most recent one.
        public var peakHeatTrainingDays: Int
        /// Days since the last hot training day (0 = today); nil if none.
        public var daysSinceHeatTraining: Int?

        public init(heatTrainingDays: Int, peakHeatTrainingDays: Int, daysSinceHeatTraining: Int?) {
            self.heatTrainingDays = heatTrainingDays
            self.peakHeatTrainingDays = peakHeatTrainingDays
            self.daysSinceHeatTraining = daysSinceHeatTraining
        }

        public static let notAcclimatized = Acclimation(heatTrainingDays: 0, peakHeatTrainingDays: 0, daysSinceHeatTraining: nil)

        /// 1 = fully acclimatised, 0.5 = fading (15-21 days away from the heat), 0 = not.
        public var level: Double {
            guard peakHeatTrainingDays >= HeatAdvice.acclimatizedDays, let days = daysSinceHeatTraining else { return 0 }
            if days <= HeatAdvice.acclimationKeptDays { return 1 }
            if days <= HeatAdvice.acclimationLostDays { return 0.5 }
            return 0
        }

        public var isAcclimatized: Bool { level >= 1 }
    }

    /// Days in the last 14 that were hot and had training.
    public static func heatTrainingDays(hotDays: Set<Date>, trainingDays: Set<Date>, now: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now)) ?? now
        return hotDays.intersection(trainingDays).filter { $0 >= start }.count
    }

    /// Acclimation from hot days and training days (both as start-of-day dates).
    public static func acclimation(hotDays: Set<Date>, trainingDays: Set<Date>, now: Date = .now, calendar: Calendar = .current) -> Acclimation {
        let today = calendar.startOfDay(for: now)
        let hotTraining = hotDays.intersection(trainingDays).filter { $0 <= today }
        let recent = heatTrainingDays(hotDays: hotDays, trainingDays: trainingDays, now: now, calendar: calendar)
        guard let last = hotTraining.max() else {
            return Acclimation(heatTrainingDays: recent, peakHeatTrainingDays: 0, daysSinceHeatTraining: nil)
        }
        let windowStart = calendar.date(byAdding: .day, value: -13, to: last) ?? last
        let peak = hotTraining.filter { $0 >= windowStart }.count
        let since = calendar.dateComponents([.day], from: last, to: today).day ?? 0
        return Acclimation(heatTrainingDays: recent, peakHeatTrainingDays: peak, daysSinceHeatTraining: max(0, since))
    }

    /// Change to the strain target's upper end (0 or negative): −10 from the
    /// "high" band, −15 "very high", −20 "extreme", halved when acclimatised
    /// (app choice, as before the WBGT change).
    public static func targetAdjustment(wbgtC: Double?, acclimation: Acclimation) -> Double {
        guard let wbgt = wbgtC else { return 0 }
        let base: Double
        switch risk(wbgtC: wbgt) {
        case .low, .moderate: return 0
        case .high: base = -10
        case .veryHigh: base = -15
        case .extreme: base = -20
        }
        return base * (1 - 0.5 * acclimation.level)
    }

    /// Lowers the top of a target range; the range stays valid and at least 5 wide.
    public static func adjustTarget(_ range: ClosedRange<Double>, by adjustment: Double) -> ClosedRange<Double> {
        guard adjustment < 0 else { return range }
        let upper = max(10, range.upperBound + adjustment)
        let lower = max(0, min(range.lowerBound, upper - 5))
        return lower...upper
    }

    /// One sentence on where acclimation stands.
    public static func acclimationText(_ acclimation: Acclimation) -> String {
        let since = acclimation.daysSinceHeatTraining ?? 0
        if acclimation.isAcclimatized {
            if since > 2 {
                return "You were training in the heat until \(since) days ago, so most of your heat adaptation is still there."
            }
            return "You've trained in the heat on \(acclimation.heatTrainingDays) of the last 14 days, so you're largely acclimatised."
        }
        if acclimation.level > 0 {
            return "Your last hot session was \(since) days ago; heat adaptation fades over 2-3 weeks, so some of it has gone."
        }
        return "Heat adaptation builds over about 7-14 days of training in it (\(acclimation.heatTrainingDays) of the last 14 so far)."
    }

    /// Advice for the high band and up; nil below it (the weather tips cover milder days).
    public static func advice(wbgtC: Double?, acclimation: Acclimation) -> String? {
        guard let wbgt = wbgtC else { return nil }
        let index = "heat stress about \(Int(wbgt.rounded())) °C WBGT, estimated from temperature and humidity"
        let acclimationNote = acclimationText(acclimation)
        switch risk(wbgtC: wbgt) {
        case .low, .moderate:
            return nil
        case .high:
            return "Hot for training (\(index)): your strain target is lower. Slow your pace to keep the same effort, drink regularly, and train early or indoors. \(acclimationNote)"
        case .veryHigh:
            return "Very hot (\(index)): your strain target is lower. Keep hard efforts short, or move them indoors; drink before you're thirsty. \(acclimationNote)"
        case .extreme:
            let stop = acclimation.isAcclimatized
                ? "Even acclimatised, keep outdoor efforts short and easy."
                : "ACSM advises against hard outdoor training at this level unless you're heat-acclimatised: train indoors or at dawn."
            return "Extreme heat (\(index)): your strain target is lower. \(stop) \(acclimationNote)"
        }
    }
}
