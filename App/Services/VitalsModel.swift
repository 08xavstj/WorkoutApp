import Foundation
import HealthKit
import AppCore
import os

/// Every health stat the app can read from Apple Health, grouped for the
/// Biology tab. Garmin Connect writes some of these, scales and food apps
/// write others; anything missing shows as "No data".
@Observable
final class VitalsModel {
    enum Tone: Equatable { case good, neutral, caution }

    enum Category: String, CaseIterable, Identifiable {
        case heart = "Heart"
        case sleep = "Sleep"
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

        // For the history view.
        enum ChartStyle: Equatable { case line, bars, sleepWindows }
        var chart: ChartStyle = .line
        var digits = 0
        /// Values are hours, shown as "7h 12m".
        var isHours = false
        /// A second line (e.g. diastolic) or raw readings behind a trend.
        var secondary: [DatedValue] = []
        var secondaryLabel: String?
        var secondaryAsPoints = false
        /// Sleep start/end per night, for the consistency chart.
        var nights: [SleepNight] = []
        /// Typical healthy range, shaded on the chart.
        var normalRange: ClosedRange<Double>?
        var goal: Double?
        /// What this stat is and why it matters, in plain words.
        var about: String?
        /// Days shown when the history opens.
        var defaultDays = 30
        /// Unit for one day's value when it differs from the headline (e.g. "min" vs "this week").
        var historyUnit: String?
    }

    private(set) var stats: [Stat] = []
    private(set) var heartRateRecovery: HeartRateRecovery.Result?
    private(set) var stress: StressEstimate.Result?
    private(set) var bloodOxygen: Double?
    private(set) var intensityMinutes: IntensityMinutes.Result?
    private(set) var bodyAge: BodyAge.Result?
    /// Waist / height from a reading in the last 90 days (set by the app from
    /// `BodyMeasurementsStore`); body age uses it instead of BMI (Ashwell 2012).
    var waistToHeightRatio: Double?
    @ObservationIgnored private var respirationHistory: [DatedValue] = []
    @ObservationIgnored private var wristTemperatureHistory: [DatedValue] = []
    /// Daily resting heart rate (HealthKit) and the app's own sleeping heart
    /// rate by night, kept for the illness watch's two-day check.
    @ObservationIgnored private var restingHeartRateHistory: [DatedValue] = []
    @ObservationIgnored private var sleepingHeartRateHistory: [DatedValue] = []
    // iOS 17/18 reads (HealthKitClient+iOS26), for Biology and the coach.
    /// Nights in the last 30 on which the watch flagged possible sleep apnoea.
    private(set) var apnoeaNights30: [Date] = []
    /// Minutes in daylight today (Apple Watch), nil without the data.
    private(set) var daylightMinutesToday: Double?
    // Builder B (watch-features.md 1.1, 1.2, 4.5): nightly breathing disturbances,
    // symptoms logged in Health by other apps, the watch's hypertension notification.
    @ObservationIgnored private var breathingDisturbanceHistory: [DatedValue] = []
    /// Days in the last 3 with a symptom logged in Health outside this app.
    private(set) var healthSymptomDays: [Date] = []
    /// A hypertension notification still waiting for the 7-day home check
    /// (`HomeBloodPressure.pendingHypertensionEvent`); nil when none.
    private(set) var hypertensionPromptDate: Date?
    /// One line for the Health tab when a core read (resting heart rate, VO₂
    /// max, heart rate, steps, weight) threw on the last refresh; nil when
    /// they all answered (an empty answer is not a failure). The extras added
    /// later (breathing disturbances, symptoms, blood pressure, hearing) only
    /// log: none of them may empty the stats.
    private(set) var readProblem: String?
    /// Diagnostics for reads that fail (Console: category "vitals").
    private static let log = Logger(subsystem: "com.lontraindustries.workoutapp", category: "vitals")
    private(set) var isLoading = false
    @ObservationIgnored private var isRefreshing = false
    /// Per-minute heart rate before `heartRateCacheEdge` (start of yesterday at the
    /// last read), so a refresh reads only the last day or two. The full 14 days
    /// are read again at most hourly, for watch apps that sync late (the app's choice).
    @ObservationIgnored private var heartRateCache: [HeartRateSample] = []
    @ObservationIgnored private var heartRateCacheEdge: Date?
    @ObservationIgnored private var lastFullHeartRateRead: Date?

    func stats(in category: Category) -> [Stat] {
        stats.filter { $0.category == category }
    }

    func stat(_ id: String) -> Stat? {
        stats.first { $0.id == id }
    }

    /// VO₂ max readings from Apple Health (last 180 days), for the Fitness
    /// headline's 90-day trend (`CardioFitness.trend`).
    var vo2MaxHistory: [DatedValue] { stat("vo2")?.series ?? [] }

    /// - Parameters:
    ///   - profile: today's heart-rate profile (from the main refresh), if known.
    ///   - sessions: gym sessions logged in this app.
    func refresh(health: HealthKitClient, settings: UserSettings, profile: HeartRateProfile?, sessions: [StrengthSessionSummary],
                 sleepConsistency: Int? = nil, sleepSpreadMinutes: Double? = nil) async {
        guard health.isAvailable else { return }
        // Don't stack refreshes, but don't drop one either: if a refresh is
        // running (e.g. right after a Garmin sync), run once more with the
        // newest arguments when it finishes.
        let request = RefreshRequest(profile: profile, sessions: sessions,
                                     sleepConsistency: sleepConsistency, sleepSpreadMinutes: sleepSpreadMinutes)
        if isRefreshing {
            queuedRefresh = request
            return
        }
        isRefreshing = true
        isLoading = true
        defer {
            isRefreshing = false
            isLoading = false
        }
        await performRefresh(health: health, settings: settings, request)
        while let next = queuedRefresh {
            queuedRefresh = nil
            await performRefresh(health: health, settings: settings, next)
        }
    }

    private struct RefreshRequest {
        var profile: HeartRateProfile?
        var sessions: [StrengthSessionSummary]
        var sleepConsistency: Int?
        var sleepSpreadMinutes: Double?
    }

    @ObservationIgnored private var queuedRefresh: RefreshRequest?

    private func performRefresh(health: HealthKitClient, settings: UserSettings, _ request: RefreshRequest) async {
        let profile = request.profile
        let sessions = request.sessions
        let sleepConsistency = request.sleepConsistency
        let sleepSpreadMinutes = request.sleepSpreadMinutes

        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let vo2Unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

        async let rhr = health.dailySeries(.restingHeartRate, unit: bpm, days: 90, cumulative: false)
        async let walkingHR = health.dailySeries(.walkingHeartRateAverage, unit: bpm, days: 90, cumulative: false)
        async let appleHRR = health.dailySeries(.heartRateRecoveryOneMinute, unit: bpm, days: 60, cumulative: false)
        async let spo2 = health.dailySeries(.oxygenSaturation, unit: .percent(), days: 90, cumulative: false)
        async let respiration = health.dailySeries(.respiratoryRate, unit: bpm, days: 90, cumulative: false)
        async let wristTemp = health.dailySeries(.appleSleepingWristTemperature, unit: .degreeCelsius(), days: 90, cumulative: false)
        async let bodyTemp = health.dailySeries(.bodyTemperature, unit: .degreeCelsius(), days: 90, cumulative: false)
        async let steps = health.dailySeries(.stepCount, unit: .count(), days: 90, cumulative: true)
        async let distance = health.dailySeries(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), days: 90, cumulative: true)
        async let floors = health.dailySeries(.flightsClimbed, unit: .count(), days: 90, cumulative: true)
        async let active = health.dailySeries(.activeEnergyBurned, unit: .kilocalorie(), days: 90, cumulative: true)
        async let resting = health.dailySeries(.basalEnergyBurned, unit: .kilocalorie(), days: 90, cumulative: true)
        async let vo2 = health.dailySeries(.vo2Max, unit: vo2Unit, days: 180, cumulative: false)
        async let weight = health.dailySeries(.bodyMass, unit: .gramUnit(with: .kilo), days: 90, cumulative: false)
        async let fat = health.dailySeries(.bodyFatPercentage, unit: .percent(), days: 90, cumulative: false)
        async let bmi = health.dailySeries(.bodyMassIndex, unit: .count(), days: 90, cumulative: false)
        async let lean = health.dailySeries(.leanBodyMass, unit: .gramUnit(with: .kilo), days: 90, cumulative: false)
        async let systolic = health.dailySeries(.bloodPressureSystolic, unit: .millimeterOfMercury(), days: 90, cumulative: false)
        async let diastolic = health.dailySeries(.bloodPressureDiastolic, unit: .millimeterOfMercury(), days: 90, cumulative: false)
        async let water = health.dailySeries(.dietaryWater, unit: .liter(), days: 90, cumulative: true)
        async let mindful = health.mindfulMinutes(days: 90)
        async let workouts = health.workoutIntervals(from: twoWeeksAgo, to: now)
        let fullHeartRateRead = heartRateCacheEdge == nil
            || lastFullHeartRateRead.map { now.timeIntervalSince($0) >= 3600 } ?? true
        let heartRateFrom = fullHeartRateRead ? twoWeeksAgo : max(twoWeeksAgo, heartRateCacheEdge ?? twoWeeksAgo)
        async let perMinute = health.heartRatePerMinute(from: heartRateFrom, to: now)
        async let lastNight = health.sleepSamples(forNightEnding: today)
        async let sleepHistory = health.sleepHistory(nights: 90)
        // iOS 17/18 types (HealthKitClient+iOS26; competitors.md §1g).
        async let daylight = health.timeInDaylight(days: 90)
        async let apnoea = health.sleepApneaNights(days: 30)
        // Builder B (watch-features.md 1.1, 1.2, 4.5).
        // Read as samples with a unit check, never as a statistics collection (see `breathingDisturbances`).
        async let breathing = health.breathingDisturbances(days: 90)
        async let healthSymptoms = health.reportedSymptoms(from: calendar.date(byAdding: .day, value: -3, to: today) ?? today, to: now)
        async let hypertension = health.hypertensionEvents(since: calendar.date(byAdding: .day, value: -HomeBloodPressure.hypertensionPromptDays, to: today) ?? today)
        async let cuffReadings = health.bloodPressureReadings(days: 90)

        func get(_ value: [DatedValue]?) -> [DatedValue] { value ?? [] }
        // Reads that throw are logged; the core ones also set `readProblem`.
        // Every read stays non-fatal, so `stats` is assigned whatever fails.
        var coreFailures: [String] = []
        func failed(_ name: String, _ error: any Error, core: Bool = false) {
            Self.log.error("\(name, privacy: .public) read failed: \(error.localizedDescription, privacy: .public)")
            if core { coreFailures.append(name) }
        }
        let rhrSeries: [DatedValue]
        do { rhrSeries = try await rhr } catch { failed("resting heart rate", error, core: true); rhrSeries = [] }
        let resolvedProfile = profile ?? settings.heartRateProfile(restingHeartRate: rhrSeries.last?.value)

        // Heart-rate derived stats are computed off the main thread.
        let workoutWindows = ((try? await workouts) ?? [])
            + sessions.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        let nights = (try? await sleepHistory) ?? []
        let heartRateMinutes: [HeartRateSample]
        do {
            let fresh = try await perMinute
            let kept = fullHeartRateRead ? [] : heartRateCache.filter { $0.date >= twoWeeksAgo && $0.date < heartRateFrom }
            heartRateMinutes = (kept + fresh).sorted { $0.date < $1.date }
            let edge = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            heartRateCache = heartRateMinutes.filter { $0.date < edge }
            heartRateCacheEdge = edge
            if fullHeartRateRead { lastFullHeartRateRead = now }
        } catch {
            failed("heart rate", error, core: true)
            heartRateMinutes = []
        }
        let derived = await Self.derive(
            heartRate: heartRateMinutes,
            workouts: workoutWindows,
            sleep: (try? await lastNight) ?? [],
            nights: nights,
            profile: resolvedProfile,
            today: today,
            weekStart: weekAgo
        )
        stress = derived.stressToday
        intensityMinutes = derived.intensityWeek
        restingHeartRateHistory = rhrSeries
        sleepingHeartRateHistory = derived.sleepingHeartRateByNight

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
                series: derived.sleepingHeartRateByNight,
                footnote: "Average while asleep last night"
            ))
        } else {
            result.append(Stat(id: "sleepingHR", category: .heart, title: "Sleeping heart rate", icon: "bed.double.fill", unit: "bpm",
                               series: derived.sleepingHeartRateByNight))
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
                id: "stress", category: .heart, title: "Heart rate above resting", icon: "heart.text.square",
                value: "\(stress.score)", unit: "/ 100", status: StressEstimate.label(for: stress.score),
                tone: .neutral,
                gauge: Double(stress.score) / 100,
                series: derived.stressByDay,
                footnote: "Experimental. Garmin's stress score uses HRV, which it doesn't share with Apple Health."
            ))
        } else {
            result.append(Stat(id: "stress", category: .heart, title: "Heart rate above resting", icon: "heart.text.square", unit: "/ 100",
                               footnote: "Needs about 30 minutes of daytime heart rate."))
        }

        let vo2Series: [DatedValue]
        do { vo2Series = try await vo2 } catch { failed("VO₂ max", error, core: true); vo2Series = [] }
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
        // Apnoea beside blood oxygen, and daylight (iOS 18 / iOS 17 types; see the extension below).
        let apnoeaNights = (try? await apnoea) ?? []
        apnoeaNights30 = apnoeaNights
        result.append(Self.apnoeaStat(nights: apnoeaNights, today: today))
        // Builder B: the nightly series behind the apnoea flags (VitalsModel+Breathing),
        // Health symptoms for the illness watch, and the hypertension prompt.
        let breathingSeries: [DatedValue]
        do { breathingSeries = try await breathing } catch { failed("breathing disturbances", error); breathingSeries = [] }
        breathingDisturbanceHistory = breathingSeries
        result.append(Self.breathingDisturbancesStat(series: breathingSeries, today: today))
        do { healthSymptomDays = try await healthSymptoms } catch { failed("Health symptoms", error); healthSymptomDays = [] }
        let hypertensionDates: [Date]
        do { hypertensionDates = try await hypertension } catch { failed("hypertension events", error); hypertensionDates = [] }
        let cuff: [BloodPressureReading]
        do { cuff = try await cuffReadings } catch { failed("blood pressure readings", error); cuff = [] }
        hypertensionPromptDate = HomeBloodPressure.pendingHypertensionEvent(
            events: hypertensionDates,
            readings: cuff.map(\.asCore)
        )
        let daylightSeries = get(try? await daylight)
        daylightMinutesToday = daylightSeries.isEmpty ? nil : (latestToday(daylightSeries)?.value ?? 0)
        result.append(Self.daylightStat(series: daylightSeries, today: today))
        let respirationSeries = get(try? await respiration)
        respirationHistory = Array(respirationSeries.suffix(31))
        result.append(makeStat(
            "respiration", .breathing, "Breathing rate", "wind", series: respirationSeries, unit: "/min", digits: 1,
            status: { (12...20).contains($0) ? "Normal" : "Unusual" },
            tone: { (12...20).contains($0) ? .good : .caution },
            gaugeRange: 8...24
        ))
        let wrist = get(try? await wristTemp)
        let body = get(try? await bodyTemp)
        wristTemperatureHistory = wrist
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
        let stepSeries: [DatedValue]
        do { stepSeries = try await steps } catch { failed("steps", error, core: true); stepSeries = [] }
        var stepStat = makeStat("steps", .activity, "Steps", "shoeprints.fill", series: stepSeries, unit: "", digits: 0)
        // The goal grows (or eases) with your usual day; see StepGoal.
        let stepGoal = StepGoal.personal(dailySteps: stepSeries.filter { !calendar.isDateInToday($0.date) }.suffix(28).map(\.value), age: settings.age)
        stepStat.goal = stepGoal
        if let today = latestToday(stepSeries) {
            stepStat.gauge = min(1, today.value / stepGoal)
            stepStat.status = today.value >= stepGoal ? "Goal reached" : "\(fmt(stepGoal - today.value)) to your \(fmt(stepGoal)) goal"
            stepStat.tone = today.value >= stepGoal ? .good : .neutral
        } else {
            stepStat.value = stepSeries.isEmpty ? nil : "0"
        }
        result.append(stepStat)
        // Miles alongside pounds, kilometres alongside kilograms (Health stores km).
        let distanceKm = get(try? await distance)
        let miles = settings.weightUnit == .pounds
        let distanceSeries = miles ? distanceKm.map { DatedValue(date: $0.date, value: $0.value / 1.609344) } : distanceKm
        result.append(todayStat("distance", "Distance", "map.fill", series: distanceSeries, unit: miles ? "mi" : "km", digits: 2, today: latestToday))
        result.append(todayStat("floors", "Floors climbed", "stairs", series: get(try? await floors), unit: "floors", digits: 0, today: latestToday))
        let intensity = derived.intensityWeek
        result.append(Stat(
            id: "intensity", category: .activity, title: "Intensity minutes", icon: "bolt.heart.fill",
            value: "\(intensity.total)", unit: "this week",
            status: intensity.total >= IntensityMinutes.weeklyGoal ? "Goal reached" : "\(IntensityMinutes.weeklyGoal - intensity.total) to go",
            tone: intensity.total >= IntensityMinutes.weeklyGoal ? .good : .neutral,
            gauge: min(1, Double(intensity.total) / Double(IntensityMinutes.weeklyGoal)),
            series: derived.intensityByDay,
            footnote: "\(intensity.moderate) moderate + \(intensity.vigorous) vigorous ×2, from heart rate. Goal 150 a week."
        ))
        result.append(Self.strengthDaysStat(sessions: sessions, now: now))
        result.append(todayStat("active", "Active energy", "flame.fill", series: get(try? await active), unit: "kcal", digits: 0, today: latestToday))
        result.append(todayStat("resting", "Resting energy", "battery.75percent", series: get(try? await resting), unit: "kcal", digits: 0, today: latestToday))
        // Hearing (HealthKitClient+Hearing; watch-features.md §1.6): headphone dB(A) against the WHO weekly budget.
        let hearing: HearingExposure.Result?
        do { hearing = try await health.weeklyHeadphoneExposure() } catch { failed("headphone exposure", error); hearing = nil }
        result.append(Self.hearingStat(hearing, today: today))

        // MARK: Body
        let unit = settings.weightUnit
        let rawWeight: [DatedValue]
        do { rawWeight = try await weight } catch { failed("weight", error, core: true); rawWeight = [] }
        let weightSeries = rawWeight.map { DatedValue(date: $0.date, value: unit.display($0.value)) }
        // Weight as a smoothed trend: daily readings swing 1-2 kg with water and food.
        let trendKg = WeightTrend.smooth(rawWeight.map { DayValue(date: $0.date, value: $0.value) })
        let trendSeries = trendKg.map { DatedValue(date: $0.date, value: unit.display($0.value)) }
        var weightStat = makeStat("weight", .body, "Weight trend", "scalemass.fill", series: trendSeries, unit: unit.rawValue, digits: 1)
        let monthAgo = now.addingTimeInterval(-28 * 86_400)
        if let weekly = WeightTrend.weeklyChange(rawWeight.filter { $0.date >= monthAgo }.map { DayValue(date: $0.date, value: $0.value) }) {
            let shown = unit.display(abs(weekly))
            weightStat.status = abs(weekly) < 0.05 ? "Steady" : "\(weekly < 0 ? "−" : "+")\(shown.formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue)/week"
        }
        if let lastReading = weightSeries.last {
            weightStat.footnote = "Smoothed trend. Last scale reading: \(lastReading.value.formatted(.number.precision(.fractionLength(1)))) \(unit.rawValue). Daily weight swings 1-2 kg with water and food, so the trend is the number to watch."
        }
        weightStat.secondary = weightSeries
        weightStat.secondaryLabel = "Scale reading"
        weightStat.secondaryAsPoints = true
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
            // ACC/AHA 2017 categories.
            let status = s.value >= 130 || d.value >= 80 ? "High" : (s.value >= 120 ? "Elevated" : "Normal")
            var bp = Stat(
                id: "bp", category: .body, title: "Blood pressure", icon: "waveform.path.ecg.rectangle",
                value: "\(fmt(s.value))/\(fmt(d.value))", unit: "mmHg",
                status: status, tone: status == "Normal" ? .good : .caution, series: sys
            )
            bp.secondary = dia
            bp.secondaryLabel = "Diastolic"
            result.append(bp)
        } else {
            result.append(Stat(id: "bp", category: .body, title: "Blood pressure", icon: "waveform.path.ecg.rectangle", unit: "mmHg"))
        }
        result.append(todayStat("water", "Water", "waterbottle.fill", series: get(try? await water), unit: "L", digits: 1, today: latestToday, category: .body))

        // MARK: Sleep
        let weekStartNight = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let lastWeek = nights.filter { $0.date > weekStartNight }.map(\.hoursAsleep)
        let averageSleep: Double? = lastWeek.isEmpty ? nil : lastWeek.reduce(0, +) / Double(lastWeek.count)
        var sleepStat = Stat(
            id: "sleepAverage", category: .sleep, title: "Sleep, 7-night average", icon: "bed.double.fill",
            value: averageSleep.map { Duration.seconds($0 * 3600).formatted(.units(allowed: [.hours, .minutes], width: .narrow)) },
            unit: "", status: averageSleep.map { $0 >= 7 ? "Enough" : "Short" }, tone: (averageSleep ?? 8) >= 7 ? .good : .caution,
            gauge: averageSleep.map { min(1, $0 / 9) },
            series: nights.map { DatedValue(date: $0.date, value: $0.hoursAsleep) }
        )
        sleepStat.chart = .bars
        sleepStat.isHours = true
        sleepStat.goal = 7
        sleepStat.defaultDays = 7
        sleepStat.nights = nights
        result.append(sleepStat)

        // Sleep debt each night: the running deficit over the 14 nights before it.
        let need = settings.sleepNeedHours
        let hours = nights.map(\.hoursAsleep)
        var debtSeries: [DatedValue] = []
        for index in nights.indices {
            let window = Array(hours[max(0, index - 13)...index])
            if let debt = SleepDebt.compute(nightlyHours: window, needHours: need) {
                debtSeries.append(DatedValue(date: nights[index].date, value: debt.hours))
            }
        }
        let currentDebt = SleepDebt.compute(nightlyHours: hours, needHours: need)
        var debtStat = Stat(
            id: "sleepDebt", category: .sleep, title: "Sleep debt", icon: "hourglass",
            value: currentDebt.map { Duration.seconds($0.hours * 3600).formatted(.units(allowed: [.hours, .minutes], width: .narrow)) },
            unit: "", status: currentDebt.map { $0.level == .none ? "Caught up" : $0.level.rawValue },
            tone: (currentDebt?.hours ?? 0) < 3 ? .good : .caution,
            gauge: currentDebt.map { min(1, $0.hours / 10) },
            series: debtSeries,
            footnote: currentDebt?.plan
        )
        debtStat.isHours = true
        debtStat.defaultDays = 30
        result.append(debtStat)
        var consistencyStat = Stat(
            id: "consistency", category: .sleep, title: "Sleep consistency", icon: "clock.arrow.circlepath",
            value: sleepConsistency.map { "\($0)" }, unit: "/ 100",
            status: sleepSpreadMinutes.map { "Bed & wake times vary ~\(Int($0.rounded())) min" },
            tone: (sleepConsistency ?? 100) >= 70 ? .good : .caution,
            gauge: sleepConsistency.map { Double($0) / 100 },
            footnote: "Sleep Regularity Index over the last week. It's 15% of your sleep score."
        )
        consistencyStat.chart = .sleepWindows
        consistencyStat.nights = nights
        consistencyStat.defaultDays = 7
        result.append(consistencyStat)

        stats = result.map(Self.describe)
        readProblem = coreFailures.isEmpty
            ? nil
            : "Some health data couldn't be read from Apple Health (\(coreFailures.joined(separator: ", "))). Pull down to try again."

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
            sleepHours: averageSleep,
            dailySteps: average(fullDaySteps, last: 30),
            bodyFatPercent: fatSeries.last?.value,
            bmi: bmiSeries.last?.value ?? computedBMI(weightKg: rawWeight.last?.value, heightCm: settings.heightCm),
            vo2MaxAgeDays: vo2Series.last.map { calendar.dateComponents([.day], from: $0.date, to: now).day ?? 0 },
            bodyCompositionAgeDays: (fatSeries.last ?? bmiSeries.last ?? rawWeight.last).map { calendar.dateComponents([.day], from: $0.date, to: now).day ?? 0 },
            waistToHeightRatio: waistToHeightRatio
        ))
    }

    private func computedBMI(weightKg: Double?, heightCm: Double) -> Double? {
        guard let weightKg, heightCm > 100 else { return nil }
        let meters = heightCm / 100
        return weightKg / (meters * meters)
    }

    // MARK: - Illness watch

    /// Compares today's resting heart rate, breathing rate and temperature
    /// with your normal, and with yesterday's, so a sign has to last two days
    /// before it counts as "major" without symptoms (Mishra et al., Nat Biomed
    /// Eng 2020; Quer et al., Nat Med 2021). The resting heart rate is whatever
    /// `DailyMetricsModel` used for the recovery baseline (sleeping heart rate
    /// when there are enough nights, HealthKit's otherwise), so the two never
    /// mix sources.
    ///
    /// - Parameter daysSinceLastPeriod: from `CheckInStore.daysSinceLastPeriod()`;
    ///   within 16 days of a logged period the temperature and heart-rate bars
    ///   are higher (luteal rise). Nil when the cycle isn't tracked.
    func illnessAlert(metrics: DailyMetricsModel, drinksLastNight: Int?, reportedSymptoms: Bool,
                      daysSinceLastPeriod: Int? = nil) -> IllnessWatch.Alert? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let respiration = respirationHistory.filter { !calendar.isDateInToday($0.date) }.map(\.value)
        let respirationBaseline = Self.meanSD(respiration)
        let rhrBaseline: (mean: Double, sd: Double)? = {
            guard let mean = metrics.baseline?.meanRHR, let sd = metrics.baseline?.sdRHR, (metrics.baseline?.nights ?? 0) >= 7 else { return nil }
            return (mean, sd)
        }()
        // Yesterday's values from the same sources as today's.
        let rhrHistory = metrics.baseline?.restingHeartRateSource == .sleeping ? sleepingHeartRateHistory : restingHeartRateHistory
        let previousDay = IllnessWatch.PreviousDay(
            restingHeartRate: rhrHistory.last { calendar.isDate($0.date, inSameDayAs: yesterday) }?.value,
            respiratoryRate: respirationHistory.last { calendar.isDate($0.date, inSameDayAs: yesterday) }?.value,
            temperatureDelta: temperatureDelta(on: yesterday)
        )
        return IllnessWatch.evaluate(.init(
            restingHeartRate: metrics.restingHeartRate,
            rhrBaseline: rhrBaseline,
            respiratoryRate: metrics.respiratoryRate,
            respiratoryBaseline: respiration.count >= 7 ? respirationBaseline : nil,
            temperatureDelta: temperatureDelta(on: today),
            hrvChangePercent: metrics.recovery?.hrvChangePercent,
            drinksLastNight: drinksLastNight,
            yesterdayStrain: metrics.yesterdayStrain,
            // Builder B: symptoms logged in Health by other apps count too (watch-features.md 4.5).
            reportedSymptoms: reportedSymptoms || !healthSymptomDays.isEmpty,
            previousDay: previousDay,
            daysSinceLastPeriod: daysSinceLastPeriod,
            // Builder B: temperature as a z-score against the 30-night baseline, and the
            // week's breathing-disturbance trend (watch-features.md §1 note, 1.2).
            temperatureBaselineSD: temperatureBaselineSD(on: today),
            breathingDisturbancesRising: IllnessWatch.breathingDisturbancesRising(nightly: breathingDisturbanceHistory.map(\.value))
        ))
    }

    /// Nights of sleeping wrist temperature used as the baseline (Builder B:
    /// 14 → 30, matching the resting heart rate baseline; TemPredict, Mason
    /// et al., Sci Rep 2022, used per-person baselines of several weeks).
    private static let temperatureBaselineNights = 30

    /// Sleeping wrist temperature on `day` minus the mean of the 30 nights
    /// before it (needs 5); nil without a reading that day (Smarr et al., Sci
    /// Rep 2020: fever onset shows as a rise against your own baseline).
    private func temperatureDelta(on day: Date) -> Double? {
        let calendar = Calendar.current
        guard let index = wristTemperatureHistory.lastIndex(where: { calendar.isDate($0.date, inSameDayAs: day) }) else { return nil }
        let previous = wristTemperatureHistory[..<index].suffix(Self.temperatureBaselineNights).map(\.value)
        guard previous.count >= 5 else { return nil }
        return wristTemperatureHistory[index].value - previous.reduce(0, +) / Double(previous.count)
    }

    /// Night-to-night SD of the same baseline (needs 7 nights), for the
    /// illness watch's z-score bar (`IllnessWatch.temperatureBar`).
    private func temperatureBaselineSD(on day: Date) -> Double? {
        let calendar = Calendar.current
        guard let index = wristTemperatureHistory.lastIndex(where: { calendar.isDate($0.date, inSameDayAs: day) }) else { return nil }
        let previous = wristTemperatureHistory[..<index].suffix(Self.temperatureBaselineNights).map(\.value)
        guard previous.count >= 7 else { return nil }
        return Self.meanSD(previous)?.sd
    }

    private static func meanSD(_ values: [Double]) -> (mean: Double, sd: Double)? {
        guard values.count >= 2 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count - 1)
        return (mean, sqrt(variance))
    }

    // MARK: - Explanations

    /// What each stat means, its typical range, and how it's charted.
    private static func describe(_ stat: Stat) -> Stat {
        var stat = stat
        switch stat.id {
        case "rhr":
            stat.about = "Your heart rate at full rest, measured overnight. It drops as aerobic fitness improves. A rise of 5 or more bpm above your normal can mean illness, stress, alcohol or not enough recovery."
        case "sleepingHR":
            stat.about = "Average heart rate between falling asleep and waking. It's lower when you're fit and well recovered, and rises after alcohol, late meals, illness or hard training."
        case "walkingHR":
            stat.about = "Average heart rate while walking. It falls as your aerobic fitness improves."
        case "hrr":
            stat.chart = .bars
            stat.about = "How many beats your heart rate drops in the first minute after exercise. Bigger drops mean better fitness; a drop of 12 bpm or less was linked with higher mortality (Cole et al., N Engl J Med 1999)."
        case "stress":
            stat.chart = .bars
            stat.about = "Experimental: how far your heart rate sits above your resting rate while you're awake and not exercising (0 = at resting, 100 = far above). Caffeine, heat, digestion, standing and stress all raise it, and no study has validated heart rate alone as a stress score, so read it as a rough trend."
        case "vo2":
            stat.about = "How much oxygen your body can use at full effort: the best single measure of aerobic fitness. Higher fitness is strongly linked with longer life (Mandsager et al., JAMA Netw Open 2018). Watches estimate it from runs and walks with heart rate."
            stat.defaultDays = 90
        case "spo2":
            stat.normalRange = 95...100
            stat.about = "Oxygen in your blood. 95-100% is normal near sea level. Wrist readings are least reliable while moving or with cold hands."
        case "respiration":
            stat.normalRange = 12...20
            stat.about = "Breaths per minute while asleep. 12-20 is typical for adults. What matters most is change: a rise of 1-2 above your normal can be an early sign of illness."
        case "temperature":
            stat.about = "Your temperature while asleep. Compare it with your own normal: a rise of about 0.5 °C over a night or two can come before illness, and it also shifts across a menstrual cycle."
        case "mindful":
            stat.chart = .bars
            stat.about = "Minutes logged in mindfulness or breathing apps."
        case "steps":
            stat.about = "Steps each day. 7,000 a day was linked with about half the risk of death of 2,000, with smaller gains beyond (Ding et al., Lancet Public Health 2025); risk kept falling to about 8,000-10,000 for adults under 60 (Paluch et al., 2022). Your goal starts at 8,000 (7,000 from age 60) and then follows your usual day, never below 7,000."
        case "distance":
            stat.about = "Walking and running distance each day."
        case "floors":
            stat.about = "Flights of stairs climbed each day (about 3 m of height each)."
        case "intensity":
            stat.chart = .bars
            stat.historyUnit = "min"
            stat.about = "Minutes at moderate (40-59% of heart-rate reserve) or vigorous intensity (60%+, counted double). Guidelines recommend 150 a week (WHO 2020). Bars show each day; the number is the last 7 days."
        case "active":
            stat.about = "Calories burned by movement and exercise each day, as reported by your watch."
        case "resting":
            stat.about = "Calories your body burns at rest each day, as estimated by your watch."
        case "weight":
            stat.about = "The line is your smoothed weight trend; dots are actual scale readings. Daily weight swings 1-2 kg with water, salt and food, so the trend is what to watch."
            stat.defaultDays = 90
        case "fat":
            stat.about = "Body fat percentage from your scale or other app. Smart-scale readings vary with hydration, so watch the trend over weeks."
            stat.defaultDays = 90
        case "bmi":
            stat.normalRange = 18.5...24.9
            stat.about = "Weight relative to height. 18.5-24.9 is the standard healthy range, but BMI can't tell muscle from fat, so muscular people often read 'over'."
            stat.defaultDays = 90
        case "lean":
            stat.about = "Everything that isn't fat: muscle, bone, organs and water."
            stat.defaultDays = 90
        case "bp":
            stat.about = "Top line systolic, bottom line diastolic. Under 120/80 is normal, 120-129 over less than 80 is elevated, and 130/80 or higher is high (ACC/AHA 2017 guideline)."
            stat.defaultDays = 90
        case "water":
            stat.chart = .bars
            stat.about = "Water you log in Cronometer each day."
        case "sleepAverage":
            stat.about = "Hours actually asleep each night (not time in bed). Adults need 7 or more hours a night (Watson et al., Sleep 2015, AASM/SRS consensus). The dashed line is the average for the range you pick."
        case "consistency":
            stat.about = "The Sleep Regularity Index: the chance you're in the same state (asleep or awake) at any moment as at the same time the day before. 100 means identical days. Each bar is one night, from falling asleep to waking; the more they line up, the higher it is. A higher index predicted lower mortality more strongly than sleep length in 61,000 UK Biobank adults (Windred et al., Sleep 2024)."
        case "sleepDebt":
            stat.chart = .bars
            stat.about = "How far behind your sleep need you are over the last 14 nights. Short nights add to it and longer nights pay it back. Two weeks of 6-hour nights impaired attention as much as a night without sleep, while people felt only a little sleepy (Van Dongen et al., Sleep 2003). Set your sleep need in Settings."
        default:
            break
        }
        return stat
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
            var empty = Stat(id: id, category: category, title: title, icon: icon, unit: unit)
            empty.digits = digits
            return empty
        }
        let values = series.map(\.value)
        let range = gaugeRange ?? ((values.min() ?? last.value)...(values.max() ?? last.value))
        let span = range.upperBound - range.lowerBound
        var stat = Stat(
            id: id, category: category, title: title, icon: icon,
            value: last.value.formatted(.number.precision(.fractionLength(digits))),
            unit: unit,
            status: status?(last.value),
            tone: tone?(last.value) ?? .neutral,
            gauge: span > 0 ? min(1, max(0, (last.value - range.lowerBound) / span)) : 0.5,
            series: series,
            footnote: Calendar.current.isDateInToday(last.date) ? nil : "Last reading \(last.date.formatted(.relative(presentation: .named)))"
        )
        stat.digits = digits
        return stat
    }

    /// A daily total that is "0" today until something is recorded.
    private func todayStat(
        _ id: String, _ title: String, _ icon: String, series: [DatedValue], unit: String, digits: Int,
        today: ([DatedValue]) -> DatedValue?, category: Category = .activity
    ) -> Stat {
        var result = makeStat(id, category, title, icon, series: series, unit: unit, digits: digits)
        result.footnote = nil
        result.chart = .bars
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
        var sleepingHeartRateByNight: [DatedValue] = []
        var intensityByDay: [DatedValue] = []
    }

    @concurrent
    nonisolated private static func derive(
        heartRate: [HeartRateSample],
        workouts: [DateInterval],
        sleep: [SleepSample],
        nights: [SleepNight],
        profile: HeartRateProfile,
        today: Date,
        weekStart: Date
    ) async -> Derived {
        let calendar = Calendar.current
        var derived = Derived()
        let sorted = heartRate.sorted { $0.date < $1.date }

        // Recovery after each workout (needs heart rate in the minutes after it ends).
        for workout in workouts.sorted(by: { $0.end < $1.end }) where workout.duration >= 10 * 60 {
            // A logged session and the watch's own workout often end together: measure once.
            if let last = derived.recoveries.last, abs(last.date.timeIntervalSince(workout.end)) < 5 * 60 { continue }
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

        // Daily intensity minutes and average heart rate asleep each night, for history charts.
        if let first = sorted.first {
            var day = calendar.startOfDay(for: first.date)
            while day <= today {
                let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
                let samples = sorted.filter { $0.date >= day && $0.date < next }
                if !samples.isEmpty {
                    derived.intensityByDay.append(DatedValue(date: day, value: Double(IntensityMinutes.count(samples, profile: profile).total)))
                }
                day = next
            }
        }
        for night in nights {
            let asleep = sorted.filter { $0.date >= night.bedtime && $0.date <= night.wake }.map(\.bpm)
            if asleep.count >= 60 {
                derived.sleepingHeartRateByNight.append(DatedValue(date: night.date, value: asleep.reduce(0, +) / Double(asleep.count)))
            }
        }
        derived.sleepingHeartRate = SleepingHeartRate.measure(sorted.filter { $0.date >= today.addingTimeInterval(-8 * 3600) }, during: sleep)
        return derived
    }
}

// MARK: - Apnoea and daylight (iOS 18 / iOS 17 types)

extension VitalsModel {
    /// 2 hours a day is the anchor, not a proven dose: more daytime light
    /// tracked with lower depression risk in 86,772 UK Biobank adults (Burns et
    /// al., Nature Mental Health 2023; observational, one cohort), and the
    /// 2-hour figure comes from children's outdoor-time trials for eyesight
    /// (health-metrics.md "Light exposure", "Eye health": weak in adults).
    static let daylightAnchorMinutes = 120.0

    /// Nights Apple flagged possible breathing disturbances, as a Biology
    /// stat beside blood oxygen (competitors.md §1g; Series 9+/Ultra 2 only).
    static func apnoeaStat(nights: [Date], today: Date) -> Stat {
        let calendar = Calendar.current
        let flagged = Set(nights.map { calendar.startOfDay(for: $0) })
        let series: [DatedValue] = (0..<30).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return DatedValue(date: day, value: flagged.contains(day) ? 1 : 0)
        }
        var stat = Stat(
            id: "apnoea", category: .breathing, title: "Breathing disturbances", icon: "lungs",
            value: "\(nights.count)", unit: "nights in 30",
            status: nights.isEmpty ? "None flagged" : "Possible apnoea flagged",
            tone: nights.isEmpty ? .good : .caution,
            gauge: min(1, Double(nights.count) / 5),
            series: series,
            footnote: nights.isEmpty
                ? "From Apple Watch sleep-apnoea notifications (Series 9+/Ultra 2). None flagged doesn't rule it out."
                : "Apple flagged possible breathing disturbances on \(nights.count) night\(nights.count == 1 ? "" : "s") in 30; talk to a doctor."
        )
        stat.chart = .bars
        stat.historyUnit = "flag"
        stat.defaultDays = 30
        stat.about = "Nights on which your Apple Watch's sleep-apnoea feature flagged breathing disturbances. The notification catches about two thirds of moderate-to-severe cases, so a quiet month isn't an all-clear; a flag is a reason to talk to a doctor, not a diagnosis. The STOP-Bang screen below is the other check."
        return stat
    }

    /// Minutes in daylight today against the 2-hour anchor (Apple Watch only).
    static func daylightStat(series: [DatedValue], today: Date) -> Stat {
        let calendar = Calendar.current
        var stat = Stat(id: "daylight", category: .breathing, title: "Time in daylight", icon: "sun.max.fill", unit: "min", series: series)
        stat.chart = .bars
        stat.goal = daylightAnchorMinutes
        stat.defaultDays = 14
        stat.about = "Minutes outdoors in daylight, measured by an Apple Watch. More daytime light went with lower risk of depression in a large UK cohort (Burns 2023; observational, so not proof), and daylight anchors your body clock. The 2-hour line is an anchor rather than a tested dose: it comes from outdoor-time studies in children's eyesight, not adults, so treat it as a rough aim."
        guard !series.isEmpty else {
            stat.footnote = "Needs an Apple Watch (watchOS 10+). Garmin doesn't share daylight."
            return stat
        }
        let todayMinutes = series.last.flatMap { calendar.isDate($0.date, inSameDayAs: today) ? $0.value : nil } ?? 0
        stat.value = todayMinutes.formatted(.number.precision(.fractionLength(0)))
        stat.gauge = min(1, todayMinutes / daylightAnchorMinutes)
        if todayMinutes >= daylightAnchorMinutes {
            stat.status = "2-hour anchor reached"
            stat.tone = .good
        } else {
            stat.status = "\(Int((daylightAnchorMinutes - todayMinutes).rounded())) min to the 2-hour anchor"
            stat.tone = .neutral
        }
        stat.footnote = "About 2 hours a day is the anchor (Burns 2023; evidence is observational)."
        return stat
    }
}

// MARK: - Hearing (HealthKitClient+Hearing; AppCore HearingExposure)

extension VitalsModel {
    /// Headphone sound this week as a share of the WHO/ITU weekly budget
    /// (80 dB(A) for 40 h; WHO-ITU H.870 2019, WHO 2019), with the nudge
    /// when it is used up. Nil exposure: Health has no headphone levels.
    static func hearingStat(_ exposure: HearingExposure.Result?, today: Date) -> Stat {
        let calendar = Calendar.current
        var stat = Stat(id: "hearing", category: .activity, title: "Headphone sound", icon: "headphones", unit: "% of weekly budget")
        stat.chart = .bars
        stat.defaultDays = 7
        stat.historyUnit = "%"
        stat.about = "How much of the WHO/ITU weekly safe-listening budget your headphones have used in the last 7 days: 80 dB(A) for 40 hours, and every 3 dB louder halves the time (WHO-ITU H.870, 2019; WHO 2019). The budget comes from workplace hearing limits with a safety margin, so it is a guideline rather than a measured line between safe and harmful. Levels come from your iPhone or Apple Watch (Health › Hearing)."
        guard let exposure, exposure.hours > 0 else {
            stat.footnote = "Needs headphone levels from an iPhone or Apple Watch (Health › Hearing)."
            return stat
        }
        stat.value = "\(exposure.percentOfBudget)"
        stat.gauge = min(1, exposure.budgetFraction)
        stat.series = (-6...0).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map {
                DatedValue(date: $0, value: (exposure.dailyFractions[$0] ?? 0) * 100)
            }
        }
        let hours = exposure.hours.formatted(.number.precision(.fractionLength(1)))
        let level = exposure.equivalentLevel.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "--"
        stat.status = "\(hours) h at about \(level) dB(A) this week"
        stat.tone = exposure.isOverBudget ? .caution : .good
        stat.footnote = HearingExposure.nudge(for: exposure)
            ?? "Budget: 80 dB(A) for 40 h a week (WHO-ITU H.870); every 3 dB louder halves the time."
        return stat
    }
}
