import Foundation
import AppCore

/// Gathers what the Longevity page (`Longevity`) and the Insights feed
/// (`DailyInsights`) need from the models the app already has. Nothing is
/// read from Apple Health here and nothing is recomputed: every number is
/// the one another screen already shows (Key measures, Body, the alcohol
/// page), so the pages can't disagree.
enum LongevityAssembler {
    /// The app's models, as the Health tab's environment holds them.
    struct Models {
        let vitals: VitalsModel
        let biology: BiologyModel
        let metrics: DailyMetricsModel
        let settings: UserSettings
        let checkIns: CheckInStore
        let measurements: BodyMeasurementsStore
    }

    static func assessment(_ models: Models, sessionDates: [Date], now: Date = .now) -> Longevity.Assessment {
        Longevity.assess(longevityInputs(models, sessionDates: sessionDates, now: now))
    }

    // MARK: Longevity

    static func longevityInputs(_ m: Models, sessionDates: [Date], now: Date = .now) -> Longevity.Inputs {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var inputs = Longevity.Inputs(age: m.settings.age, sex: m.settings.sex, goals: m.settings.goalsSet ? m.settings.goals : nil)

        if let vo2 = m.vitals.vo2ForScores {
            inputs.vo2Max = vo2.value
            inputs.vo2IsEstimate = vo2.isEstimate
        }
        inputs.restingHeartRate = average(recent(m.vitals.stat("rhr")?.series, days: 14, now: now))

        // The pair Key measures shows (`VitalsModel`'s "bp" stat): a 7-day home
        // average once the check has its readings, a single reading before that.
        if let stat = m.vitals.stat("bp"), let value = stat.value {
            let parts = value.split(separator: "/").compactMap { Double($0) }
            if parts.count == 2 {
                inputs.systolic = parts[0]
                inputs.diastolic = parts[1]
                let status = stat.status ?? ""
                inputs.bloodPressureIsHomeAverage = !status.isEmpty && status != "Latest reading" && !status.hasSuffix("so far")
            }
        }

        // Full days only: today's steps are still coming in.
        let fullDays = recent(m.vitals.stat("steps")?.series, days: 30, now: now).filter { $0.date < today }
        if fullDays.count >= 7 { inputs.dailySteps = average(fullDays) }

        // `intensityMinutes` is zero, not nil, without heart rate; the day series says whether there was any.
        if let minutes = m.vitals.intensityMinutes, m.vitals.stat("intensity")?.series.isEmpty == false {
            inputs.moderateMinutes = minutes.moderate
            inputs.vigorousMinutes = minutes.vigorous
        }

        // Judged only for someone who logs sessions here (one in the last 8 weeks).
        let cutoff = now.addingTimeInterval(-56 * 86_400)
        if sessionDates.contains(where: { $0 >= cutoff }) {
            inputs.strengthDaysByWeek = StrengthDays.weekly(sessionDates, weeks: 4, now: now)
        }
        inputs.gripKg = m.measurements.latestGrip?.kilograms

        let nights = recent(m.vitals.stat("sleepAverage")?.series, days: 14, now: now)
        inputs.sleepHours = average(nights)
        inputs.sleepNights = nights.count
        inputs.sleepRegularity = m.metrics.sleepConsistency

        let height = m.metrics.heightCm ?? (m.settings.heightCm > 0 ? m.settings.heightCm : nil)
        inputs.waistToHeight = m.measurements.waistToHeightRatio(heightCm: height)

        inputs.fiberGrams = fiberAverage(m)
        let protein = proteinSeries(m).filter { $0.date < today && $0.date >= today.addingTimeInterval(-7 * 86_400) && $0.value > 0 }
        if protein.count >= 3 { inputs.proteinGrams = average(protein) }
        inputs.proteinTargetGrams = m.metrics.proteinTarget

        // The same 7 evenings the alcohol page totals (`AlcoholEffectCard`).
        let evenings = (0..<AlcoholWeek.nights)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .compactMap { m.checkIns.evening(on: $0) }
        let week = AlcoholWeek.total(evenings: evenings)
        inputs.drinksPerWeek = week.drinks
        inputs.drinkNightsLogged = week.nightsLogged

        inputs.headphoneBudgetPercent = headphonePercent(m)

        let moods = m.checkIns.moods.filter { $0.date >= now.addingTimeInterval(-14 * 86_400) }
        if !moods.isEmpty {
            inputs.moodValence = moods.map(\.valence).reduce(0, +) / Double(moods.count)
            inputs.moodEntries = moods.count
        }
        return inputs
    }

    // MARK: Insights

    static func insightInputs(_ m: Models, sessionDates: [Date], assessment: Longevity.Assessment, now: Date = .now) -> DailyInsights.Inputs {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var inputs = DailyInsights.Inputs(day: now, calendar: calendar)
        inputs.restingHeartRate = dayValues(m.vitals.stat("rhr")?.series)
        inputs.hrv = dayValues(m.biology.hrvSeries)
        inputs.sleepHours = dayValues(m.vitals.stat("sleepAverage")?.series)
        inputs.sleepRegularity = m.metrics.sleepConsistency
        // Shorter nights are the plan while the insomnia path's window is on (`SleepWindow`).
        inputs.sleepWindowOn = m.metrics.sleepWindowOn
        inputs.steps = dayValues(m.vitals.stat("steps")?.series).filter { $0.date < today }
        inputs.vo2Max = dayValues(m.vitals.vo2MaxHistory)
        inputs.activeMinutes = dayValues(m.vitals.stat("intensity")?.series)
        inputs.strengthSessions = sessionDates
        inputs.respiratoryRate = dayValues(m.vitals.stat("respiration")?.series)
        inputs.bloodOxygen = dayValues(m.vitals.stat("spo2")?.series)
        inputs.proteinGrams = dayValues(proteinSeries(m))
        inputs.proteinTargetGrams = m.metrics.proteinTarget
        inputs.fiberGrams = fiberAverage(m)
        // Five weeks of evenings: this week against the four before. A logged zero counts.
        inputs.drinks = (0..<35).compactMap { back -> DayValue? in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today),
                  let evening = m.checkIns.evening(on: day) else { return nil }
            if let standard = evening.standardDrinks { return DayValue(date: day, value: standard) }
            return evening.drinks.map { DayValue(date: day, value: Double($0)) }
        }
        inputs.mood = m.checkIns.moods.map { DayValue(date: $0.date, value: $0.valence) }
        inputs.headphoneBudgetPercent = headphonePercent(m)
        if let top = m.checkIns.insights.first {
            inputs.pattern = DailyInsights.Pattern(sentence: top.sentence, daysWith: top.daysWith, daysWithout: top.daysWithout)
        }
        inputs.longevity = assessment
        return inputs
    }

    // MARK: Pieces

    private static func dayValues(_ series: [DatedValue]?) -> [DayValue] {
        (series ?? []).map { DayValue(date: $0.date, value: $0.value) }
    }

    /// The values dated in the last `days` days.
    private static func recent(_ series: [DatedValue]?, days: Int, now: Date) -> [DatedValue] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return (series ?? []).filter { $0.date >= cutoff }
    }

    private static func average(_ values: [DatedValue]) -> Double? {
        values.isEmpty ? nil : values.map(\.value).reduce(0, +) / Double(values.count)
    }

    /// Daily protein from the food log, as the Body page charts it (`BiologyModel`'s "protein" marker).
    private static func proteinSeries(_ m: Models) -> [DatedValue] {
        m.biology.markers.first { $0.id == "protein" }?.series ?? []
    }

    /// 7-day fibre average from the food log (`Micronutrients`; there once 4 days are logged).
    private static func fiberAverage(_ m: Models) -> Double? {
        m.metrics.micronutrients.first { $0.nutrient == .fiber }?.average
    }

    /// Percent of the weekly headphone budget, as the Headphone sound stat shows it.
    private static func headphonePercent(_ m: Models) -> Double? {
        m.vitals.stat("hearing")?.value.flatMap { Double($0) }
    }
}

/// The Insights feed as last worked out, and what it remembers between days
/// (`DailyInsights.State`: which lines showed when, so they neither flicker
/// nor repeat). The state is a small JSON blob in UserDefaults, not a
/// SwiftData model. One shared instance, so the Health tab, the feed page
/// and the coach read the same lines.
@Observable
final class InsightsFeedStore {
    static let shared = InsightsFeedStore()

    private(set) var feed: DailyInsights.Feed?

    private static let stateKey = "dailyInsightsState"
    /// Demo mode starts fresh on every launch and saves nothing, so the
    /// screenshot tour shows the same feed each run.
    @ObservationIgnored private var demoState = DailyInsights.State()

    /// Works the feed out again from `inputs`. Safe to call on every refresh:
    /// the same day's lines stay as they were (`DailyInsights.evaluate`).
    func refresh(_ inputs: DailyInsights.Inputs) {
        let result = DailyInsights.evaluate(inputs, state: loadState())
        saveState(result.state)
        if feed != result.feed { feed = result.feed }
    }

    private func loadState() -> DailyInsights.State {
        if DemoMode.isOn { return demoState }
        guard let data = UserDefaults.standard.data(forKey: Self.stateKey),
              let state = try? JSONDecoder().decode(DailyInsights.State.self, from: data) else { return DailyInsights.State() }
        return state
    }

    private func saveState(_ state: DailyInsights.State) {
        if DemoMode.isOn {
            demoState = state
        } else if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
    }
}
