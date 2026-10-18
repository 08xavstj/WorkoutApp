import Foundation
import HealthKit
import AppCore

/// Every health stat the app can read from Apple Health, grouped for the
/// Biology tab. Garmin Connect writes some of these, scales and food apps
/// write others; anything missing shows as "No data".
@Observable
final class VitalsModel {
    enum Tone: Equatable { case good, neutral, caution }

    enum Category: String, CaseIterable, Identifiable {
        case heart = "Heart"
        case breathing = "Breathing & temperature"
        case activity = "Activity"
        case body = "Body"
        var id: String { rawValue }
    }

    struct Stat: Identifiable, Equatable {
        var id: String
        var category: Category
        var title: String
        var icon: String
        var value: String?
        var unit: String
        var status: String?
        var tone: Tone = .neutral
        /// Where today's value sits in its usual range, 0...1 (for the pill gauge).
        var gauge: Double?
        var series: [DatedValue] = []
        var footnote: String?
    }

    private(set) var stats: [Stat] = []
    private(set) var heartRateRecovery: HeartRateRecovery.Result?
    private(set) var stress: StressEstimate.Result?
    private(set) var bloodOxygen: Double?
    private(set) var intensityMinutes: IntensityMinutes.Result?
    private(set) var bodyAge: BodyAge.Result?
    private(set) var isLoading = false
    @ObservationIgnored private var isRefreshing = false

    func stats(in category: Category) -> [Stat] {
        stats.filter { $0.category == category }
    }

    func stat(_ id: String) -> Stat? {
        stats.first { $0.id == id }
    }

    /// - Parameters:
    ///   - profile: today's heart-rate profile (from the main refresh), if known.
    ///   - sessions: gym sessions logged in this app.
    func refresh(health: HealthKitClient, settings: UserSettings, profile: HeartRateProfile?, sessions: [StrengthSessionSummary]) async {
        guard health.isAvailable, !isRefreshing else { return }
        isRefreshing = true
        isLoading = true
        defer {
            isRefreshing = false
            isLoading = false
        }

        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let vo2Unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

        async let rhr = health.dailySeries(.restingHeartRate, unit: bpm, days: 30, cumulative: false)
        async let walkingHR = health.dailySeries(.walkingHeartRateAverage, unit: bpm, days: 30, cumulative: false)
        async let appleHRR = health.dailySeries(.heartRateRecoveryOneMinute, unit: bpm, days: 60, cumulative: false)
        async let spo2 = health.dailySeries(.oxygenSaturation, unit: .percent(), days: 30, cumulative: false)
        async let respiration = health.dailySeries(.respiratoryRate, unit: bpm, days: 30, cumulative: false)
        async let wristTemp = health.dailySeries(.appleSleepingWristTemperature, unit: .degreeCelsius(), days: 30, cumulative: false)
        async let bodyTemp = health.dailySeries(.bodyTemperature, unit: .degreeCelsius(), days: 30, cumulative: false)
        async let steps = health.dailySeries(.stepCount, unit: .count(), days: 30, cumulative: true)
        async let distance = health.dailySeries(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), days: 30, cumulative: true)
        async let floors = health.dailySeries(.flightsClimbed, unit: .count(), days: 30, cumulative: true)
        async let active = health.dailySeries(.activeEnergyBurned, unit: .kilocalorie(), days: 30, cumulative: true)
        async let resting = health.dailySeries(.basalEnergyBurned, unit: .kilocalorie(), days: 30, cumulative: true)
        async let vo2 = health.dailySeries(.vo2Max, unit: vo2Unit, days: 180, cumulative: false)
        async let weight = health.dailySeries(.bodyMass, unit: .gramUnit(with: .kilo), days: 90, cumulative: false)
        async let fat = health.dailySeries(.bodyFatPercentage, unit: .percent(), days: 90, cumulative: false)
        async let bmi = health.dailySeries(.bodyMassIndex, unit: .count(), days: 90, cumulative: false)
        async let lean = health.dailySeries(.leanBodyMass, unit: .gramUnit(with: .kilo), days: 90, cumulative: false)
        async let systolic = health.dailySeries(.bloodPressureSystolic, unit: .millimeterOfMercury(), days: 90, cumulative: false)
        async let diastolic = health.dailySeries(.bloodPressureDiastolic, unit: .millimeterOfMercury(), days: 90, cumulative: false)
        async let water = health.dailySeries(.dietaryWater, unit: .liter(), days: 30, cumulative: true)
        async let mindful = health.mindfulMinutes(days: 30)
        async let workouts = health.workoutIntervals(from: twoWeeksAgo, to: now)
        async let perMinute = health.heartRatePerMinute(from: twoWeeksAgo, to: now)
        async let lastNight = health.sleepSamples(forNightEnding: today)
        async let sleepAverage = health.averageSleepHours(nights: 7)

        func get(_ value: [DatedValue]?) -> [DatedValue] { value ?? [] }
        let rhrSeries = get(try? await rhr)
        let resolvedProfile = profile ?? settings.heartRateProfile(restingHeartRate: rhrSeries.last?.value)

        // Heart-rate derived stats are computed off the main thread.
        let workoutWindows = ((try? await workouts) ?? [])
            + sessions.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        let derived = await Self.derive(
            heartRate: (try? await perMinute) ?? [],
            workouts: workoutWindows,
            sleep: (try? await lastNight) ?? [],
            profile: resolvedProfile,
            today: today,
            weekStart: weekAgo
        )
        stress = derived.stressToday
        intensityMinutes = derived.intensityWeek

        var result: [Stat] = []
        func fmt(_ value: Double, _ digits: Int = 0) -> String { value.formatted(.number.precision(.fractionLength(digits))) }
        func latestToday(_ series: [DatedValue]) -> DatedValue? {
            series.last.flatMap { calendar.isDateInToday($0.date) ? $0 : nil }
        }

        // MARK: Heart
        result.append(makeStat(
            "rhr", .heart, "Resting heart rate", "heart.fill", series: rhrSeries, unit: "bpm", digits: 0,
            status: { Biomarkers.restingHeartRateLabel($0) },
            tone: { $0 <= 65 ? .good : ($0 <= 80 ? .neutral : .caution) }
        ))
        if let sleeping = derived.sleepingHeartRate {
            result.append(Stat(
                id: "sleepingHR", category: .heart, title: "Sleeping heart rate", icon: "bed.double.fill",
                value: fmt(sleeping.average), unit: "bpm",
                status: "Lowest \(fmt(sleeping.lowest))", tone: .neutral,
                footnote: "Average while asleep last night"
            ))
        } else {
            result.append(Stat(id: "sleepingHR", category: .heart, title: "Sleeping heart rate", icon: "bed.double.fill", unit: "bpm"))
        }
        result.append(makeStat("walkingHR", .heart, "Walking heart rate", "figure.walk", series: get(try? await walkingHR), unit: "bpm", digits: 0))

        // Heart-rate recovery: Apple's value if any device wrote one, else measured from workouts.
        let appleHRRSeries = get(try? await appleHRR)
        let measured = derived.recoveries
        heartRateRecovery = measured.last?.result
        if let last = appleHRRSeries.last {
            result.append(Stat(
                id: "hrr", category: .heart, title: "Heart rate recovery", icon: "arrow.down.heart.fill",
                value: fmt(last.value), unit: "bpm", status: HeartRateRecovery.label(oneMinuteDrop: last.value),
                tone: last.value >= 20 ? .good : (last.value >= 12 ? .neutral : .caution),
                gauge: min(1, last.value / 40), series: appleHRRSeries, footnote: "Drop in the first minute after exercise"
            ))
        } else if let latest = measured.last {
            let drop = latest.result.oneMinuteDrop
            result.append(Stat(
                id: "hrr", category: .heart, title: "Heart rate recovery", icon: "arrow.down.heart.fill",
                value: fmt(drop), unit: "bpm", status: HeartRateRecovery.label(oneMinuteDrop: drop),
                tone: drop >= 20 ? .good : (drop >= 12 ? .neutral : .caution),
                gauge: min(1, drop / 40),
                series: measured.map { DatedValue(date: $0.date, value: $0.result.oneMinuteDrop) },
                footnote: latest.result.twoMinuteDrop.map { "−\(fmt($0)) bpm after 2 min. From your last workout's heart rate." }
                    ?? "From your last workout's heart rate."
            ))
        } else {
            result.append(Stat(
                id: "hrr", category: .heart, title: "Heart rate recovery", icon: "arrow.down.heart.fill", unit: "bpm",
                footnote: "Appears after a workout once your watch records heart rate for a couple of minutes afterwards."
            ))
        }

        if let stress = derived.stressToday {
            result.append(Stat(
                id: "stress", category: .heart, title: "Stress (estimate)", icon: "brain.head.profile",
                value: "\(stress.score)", unit: "", status: StressEstimate.label(for: stress.score),
                tone: stress.score < 26 ? .good : (stress.score < 51 ? .neutral : .caution),
                gauge: Double(stress.score) / 100,
                series: derived.stressByDay,
                footnote: "From heart rate above resting outside workouts. Garmin's stress score uses HRV, which it doesn't share with Apple Health."
            ))
        } else {
            result.append(Stat(id: "stress", category: .heart, title: "Stress (estimate)", icon: "brain.head.profile", unit: "",
                               footnote: "Needs about 30 minutes of daytime heart rate."))
        }

        let vo2Series = get(try? await vo2)
        result.append(makeStat(
            "vo2", .heart, "VO₂ max", "lungs.fill", series: vo2Series, unit: "ml/kg/min", digits: 1,
            status: { Biomarkers.vo2MaxLabel($0, age: settings.age, sex: settings.sex) },
            tone: { Biomarkers.vo2MaxLabel($0, age: settings.age, sex: settings.sex) == "Poor" ? .caution : .good }
        ))

        // MARK: Breathing & temperature
        let spo2Series = get(try? await spo2).map { DatedValue(date: $0.date, value: $0.value * 100) }
        bloodOxygen = spo2Series.last?.value
        result.append(makeStat(
            "spo2", .breathing, "Blood oxygen", "drop.fill", series: spo2Series, unit: "%", digits: 0,
            status: { $0 >= 95 ? "Normal" : ($0 >= 90 ? "Low" : "Very low") },
            tone: { $0 >= 95 ? .good : .caution },
            gaugeRange: 85...100
        ))
        result.append(makeStat(
            "respiration", .breathing, "Respiration", "wind", series: get(try? await respiration), unit: "brpm", digits: 1,
            status: { (12...20).contains($0) ? "Normal" : "Unusual" },
            tone: { (12...20).contains($0) ? .good : .caution },
            gaugeRange: 8...24
        ))
        let wrist = get(try? await wristTemp)
        let body = get(try? await bodyTemp)
        if !wrist.isEmpty || body.isEmpty {
            let baseline = wrist.dropLast().suffix(14).map(\.value)
            let mean = baseline.isEmpty ? nil : baseline.reduce(0, +) / Double(baseline.count)
            var temp = makeStat("temperature", .breathing, "Sleeping temperature", "thermometer.medium", series: wrist, unit: "°C", digits: 2)
            if let last = wrist.last, let mean {
                let delta = last.value - mean
                temp.value = (delta >= 0 ? "+" : "−") + fmt(abs(delta), 1)
                temp.unit = "°C vs usual"
                temp.status = abs(delta) < 0.5 ? "Normal" : "Off baseline"
                temp.tone = abs(delta) < 0.5 ? .good : .caution
            }
            result.append(temp)
        } else {
            result.append(makeStat("temperature", .breathing, "Body temperature", "thermometer.medium", series: body, unit: "°C", digits: 1))
        }
        let mindfulSeries = get(try? await mindful)
        var mindfulStat = makeStat("mindful", .breathing, "Mindful minutes", "leaf.fill", series: mindfulSeries, unit: "min", digits: 0)
        if latestToday(mindfulSeries) == nil, !mindfulSeries.isEmpty {
            mindfulStat.value = "0"
            mindfulStat.status = "None today"
        }
        result.append(mindfulStat)

        // MARK: Activity
        let stepSeries = get(try? await steps)
        var stepStat = makeStat("steps", .activity, "Steps", "shoeprints.fill", series: stepSeries, unit: "", digits: 0)
        if let today = latestToday(stepSeries) {
            stepStat.gauge = min(1, today.value / 10_000)
            stepStat.status = today.value >= 10_000 ? "Goal reached" : "\(fmt(10_000 - today.value)) to 10k"
            stepStat.tone = today.value >= 10_000 ? .good : .neutral
        } else {
            stepStat.value = stepSeries.isEmpty ? nil : "0"
        }
        result.append(stepStat)
        result.append(todayStat("distance", "Distance", "map.fill", series: get(try? await distance), unit: "km", digits: 2, today: latestToday))
        result.append(todayStat("floors", "Floors climbed", "stairs", series: get(try? await floors), unit: "floors", digits: 0, today: latestToday))
        let intensity = derived.intensityWeek
        result.append(Stat(
            id: "intensity", category: .activity, title: "Intensity minutes", icon: "bolt.heart.fill",
            value: "\(intensity.total)", unit: "this week",
            status: intensity.total >= IntensityMinutes.weeklyGoal ? "Goal reached" : "\(IntensityMinutes.weeklyGoal - intensity.total) to go",
            tone: intensity.total >= IntensityMinutes.weeklyGoal ? .good : .neutral,
            gauge: min(1, Double(intensity.total) / Double(IntensityMinutes.weeklyGoal)),
            footnote: "\(intensity.moderate) moderate + \(intensity.vigorous) vigorous ×2, from heart rate. Goal 150 a week."
        ))
        result.append(todayStat("active", "Active energy", "flame.fill", series: get(try? await active), unit: "kcal", digits: 0, today: latestToday))
        result.append(todayStat("resting", "Resting energy", "battery.75percent", series: get(try? await resting), unit: "kcal", digits: 0, today: latestToday))

        // MARK: Body
        let unit = settings.weightUnit
        let rawWeight = get(try? await weight)
        let weightSeries = rawWeight.map { DatedValue(date: $0.date, value: unit.display($0.value)) }
        var weightStat = makeStat("weight", .body, "Weight", "scalemass.fill", series: weightSeries, unit: unit.rawValue, digits: 1)
        if !weightSeries.isEmpty {
            weightStat.status = Biomarkers.trend(weightSeries.suffix(30).map(\.value), threshold: 0.005).rawValue.capitalized
        }
        result.append(weightStat)
        let fatSeries = get(try? await fat).map { DatedValue(date: $0.date, value: $0.value * 100) }
        result.append(makeStat(
            "fat", .body, "Body fat", "percent", series: fatSeries, unit: "%", digits: 1,
            status: { Biomarkers.bodyFatLabel($0, sex: settings.sex) },
            tone: { Biomarkers.bodyFatLabel($0, sex: settings.sex) == "High" ? .caution : .good }
        ))
        let bmiSeries = get(try? await bmi)
        result.append(makeStat("bmi", .body, "BMI", "figure.stand", series: bmiSeries, unit: "", digits: 1,
                           status: { $0 < 18.5 ? "Under" : ($0 < 25 ? "Healthy" : ($0 < 30 ? "Over" : "High")) }))
        let leanSeries = get(try? await lean).map { DatedValue(date: $0.date, value: unit.display($0.value)) }
        result.append(makeStat("lean", .body, "Lean mass", "figure.strengthtraining.traditional", series: leanSeries, unit: unit.rawValue, digits: 1))
        let sys = get(try? await systolic)
        let dia = get(try? await diastolic)
        if let s = sys.last, let d = dia.last {
            let elevated = s.value >= 130 || d.value >= 80
            result.append(Stat(
                id: "bp", category: .body, title: "Blood pressure", icon: "waveform.path.ecg.rectangle",
                value: "\(fmt(s.value))/\(fmt(d.value))", unit: "mmHg",
                status: elevated ? "Elevated" : "Normal", tone: elevated ? .caution : .good, series: sys
            ))
        } else {
            result.append(Stat(id: "bp", category: .body, title: "Blood pressure", icon: "waveform.path.ecg.rectangle", unit: "mmHg"))
        }
        result.append(todayStat("water", "Water", "waterbottle.fill", series: get(try? await water), unit: "L", digits: 1, today: latestToday, category: .body))

        stats = result

        // Body age from the same data (30-day averages where it helps).
        func average(_ series: [DatedValue], last days: Int) -> Double? {
            let values = series.suffix(days).map(\.value)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let fullDaySteps = stepSeries.filter { !calendar.isDateInToday($0.date) }
        bodyAge = BodyAge.estimate(BodyAge.Inputs(
            age: settings.age,
            sex: settings.sex,
            vo2Max: vo2Series.last?.value,
            restingHeartRate: average(rhrSeries, last: 14),
            sleepHours: try? await sleepAverage,
            dailySteps: average(fullDaySteps, last: 30),
            bodyFatPercent: fatSeries.last?.value,
            bmi: bmiSeries.last?.value ?? computedBMI(weightKg: rawWeight.last?.value, heightCm: settings.heightCm)
        ))
    }

    private func computedBMI(weightKg: Double?, heightCm: Double) -> Double? {
        guard let weightKg, heightCm > 100 else { return nil }
        let meters = heightCm / 100
        return weightKg / (meters * meters)
    }

    // MARK: - Building stats

    private func makeStat(
        _ id: String, _ category: Category, _ title: String, _ icon: String,
        series: [DatedValue], unit: String, digits: Int,
        status: ((Double) -> String)? = nil,
        tone: ((Double) -> Tone)? = nil,
        gaugeRange: ClosedRange<Double>? = nil
    ) -> Stat {
        guard let last = series.last else {
            return Stat(id: id, category: category, title: title, icon: icon, unit: unit)
        }
        let values = series.map(\.value)
        let range = gaugeRange ?? ((values.min() ?? last.value)...(values.max() ?? last.value))
        let span = range.upperBound - range.lowerBound
        return Stat(
            id: id, category: category, title: title, icon: icon,
            value: last.value.formatted(.number.precision(.fractionLength(digits))),
            unit: unit,
            status: status?(last.value),
            tone: tone?(last.value) ?? .neutral,
            gauge: span > 0 ? min(1, max(0, (last.value - range.lowerBound) / span)) : 0.5,
            series: series,
            footnote: Calendar.current.isDateInToday(last.date) ? nil : "Last reading \(last.date.formatted(.relative(presentation: .named)))"
        )
    }

    /// A daily total that is "0" today until something is recorded.
    private func todayStat(
        _ id: String, _ title: String, _ icon: String, series: [DatedValue], unit: String, digits: Int,
        today: ([DatedValue]) -> DatedValue?, category: Category = .activity
    ) -> Stat {
        var result = makeStat(id, category, title, icon, series: series, unit: unit, digits: digits)
        result.footnote = nil
        if today(series) == nil {
            result.value = series.isEmpty ? nil : "0"
        }
        let earlier = series.dropLast().suffix(14).map(\.value)
        if let value = today(series)?.value, !earlier.isEmpty {
            let average = earlier.reduce(0, +) / Double(earlier.count)
            result.status = value >= average ? "Above average" : "Below average"
            result.tone = value >= average ? .good : .neutral
            result.gauge = min(1, value / max(average * 1.5, 0.001))
        }
        return result
    }

    // MARK: - Heart-rate derived

    nonisolated struct Derived: Sendable {
        nonisolated struct Recovery: Sendable {
            var date: Date
            var result: HeartRateRecovery.Result
        }
        var recoveries: [Recovery] = []
        var stressToday: StressEstimate.Result?
        var stressByDay: [DatedValue] = []
        var intensityWeek = IntensityMinutes.Result(moderate: 0, vigorous: 0)
        var sleepingHeartRate: SleepingHeartRate.Result?
    }

    @concurrent
    nonisolated private static func derive(
        heartRate: [HeartRateSample],
        workouts: [DateInterval],
        sleep: [SleepSample],
        profile: HeartRateProfile,
        today: Date,
        weekStart: Date
    ) async -> Derived {
        let calendar = Calendar.current
        var derived = Derived()
        let sorted = heartRate.sorted { $0.date < $1.date }

        // Recovery after each workout (needs heart rate in the minutes after it ends).
        for workout in workouts.sorted(by: { $0.end < $1.end }) where workout.duration >= 10 * 60 {
            let nearby = sorted.filter { $0.date >= workout.end.addingTimeInterval(-180) && $0.date <= workout.end.addingTimeInterval(150) }
            if let result = HeartRateRecovery.measure(nearby, workoutEnd: workout.end) {
                derived.recoveries.append(.init(date: workout.end, result: result))
            }
        }

        // Stress per day for the last week.
        var day = weekStart
        while day <= today {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let samples = sorted.filter { $0.date >= day && $0.date < next }
            if let estimate = StressEstimate.estimate(samples, profile: profile, excluding: workouts, calendar: calendar) {
                derived.stressByDay.append(DatedValue(date: day, value: Double(estimate.score)))
                if day == today { derived.stressToday = estimate }
            }
            day = next
        }

        derived.intensityWeek = IntensityMinutes.count(sorted.filter { $0.date >= weekStart }, profile: profile)
        derived.sleepingHeartRate = SleepingHeartRate.measure(sorted.filter { $0.date >= today.addingTimeInterval(-8 * 3600) }, during: sleep)
        return derived
    }
}
