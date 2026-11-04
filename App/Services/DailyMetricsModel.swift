import Foundation
import HealthKit
import AppCore

/// Loads today's data from Apple Health, combines it with logged gym sessions,
/// and computes every score shown on Today and Fitness.
@Observable
final class DailyMetricsModel {
    struct DayStrain: Identifiable, Equatable {
        var date: Date
        var strain: Double
        var id: Date { date }
    }

    struct ActivityItem: Identifiable, Equatable {
        var id: String
        var name: String
        var detail: String
        var start: Date
        var strainAdded: Double
        var isStrength: Bool
        var minutes: Int = 0
    }

    private(set) var strain: StrainCalculator.Result?
    private(set) var recovery: RecoveryCalculator.Result?
    private(set) var sleep: SleepCalculator.Result?
    private(set) var restingHeartRate: Double?
    private(set) var hrv: Double?
    private(set) var hrvIsManual = false
    private(set) var baseline: RecoveryCalculator.Baseline?
    // [Recovery research] Where `restingHeartRate` and the baseline come from: the
    // app's sleeping heart rate once there are enough nights, else HealthKit's.
    private(set) var restingHeartRateSource: RestingHeartRateSource = .healthKit
    private(set) var respiratoryRate: Double?
    private(set) var yesterdayStrain: Double?
    private(set) var weekStrain: [DayStrain] = []
    /// What your training days usually reach over the last 4 weeks (nil while calibrating).
    private(set) var usualTrainingStrain: Double?
    /// Days in the last 4 weeks with training (strain 25%+), for heat acclimation.
    private(set) var recentTrainingDays: Set<Date> = []
    /// When you fell asleep on recent nights, for the caffeine cut-off.
    private(set) var recentBedtimes: [Date] = []
    private(set) var cardioLoad: TrainingLoadCalculator.Result?
    private(set) var muscularLoad: TrainingLoadCalculator.Result?
    private(set) var activities: [ActivityItem] = []
    private(set) var nutritionToday: NutritionDay?
    private(set) var nutritionYesterday: NutritionDay?
    private(set) var bodyMassKg: Double?
    private(set) var energy: EnergyCalculator.Result?
    private(set) var steps: Double?
    /// Calories the watch itself reports for today so far (via Apple Health).
    private(set) var deviceRestingToday: Double?
    private(set) var deviceActiveToday: Double?
    /// Average resting calories a day from the watch (recent full days).
    private(set) var watchRestingPerDay: Double?
    /// Maintenance calories from food log + weight trend, once there's enough data.
    private(set) var maintenance: AdaptiveTDEE.Result?
    /// A food-log maintenance that was too low to be real (under 1.4× resting
    /// metabolism), so it wasn't used; shown so the user knows why.
    private(set) var implausibleMaintenance: Double?
    /// The lowest daily target for this body and training (`CalorieSafety`).
    private(set) var calorieMinimum: Double?
    /// How close the maintenance estimate is (fully logged days so far).
    private(set) var maintenanceProgress: AdaptiveTDEE.Progress?
    /// kg per week from the weight trend.
    private(set) var weightTrendWeekly: Double?
    private(set) var goals: Goals?
    private(set) var sex: BiologicalSex = .male
    private(set) var micronutrients: [Micronutrients.Finding] = []
    /// Sleep Regularity Index (0-100) over the last week.
    private(set) var sleepConsistency: Int?
    private(set) var sleepSpreadMinutes: Double?
    /// Hours behind your sleep need over the last 14 nights.
    private(set) var sleepDebt: SleepDebt.Result?
    /// Nightly sleep for the last month (newest last), for history charts.
    private(set) var sleepNights: [SleepNight] = []
    /// "RMSSD" when HRV comes from Garmin, the camera or Apple Watch beat-to-beat
    /// data; "SDNN" when only Apple Health's own HRV is available. Never mixed.
    private(set) var hrvMetric: String?
    /// Sick / rest mode (from settings): strain targets and training nudges pause.
    var restMode = false

    // MARK: Weekly calorie target, weigh-ins and the bed-by window

    /// The target in force this week, set on Mondays from measured maintenance
    /// by at most ±100 kcal (`CalorieBand`; kept in `UserSettings`).
    private(set) var calorieTargetOverride: Double?
    /// "Target adjusted −60 kcal this week: weight moved slower than planned", for the ⓘ sheet.
    private(set) var calorieAdjustmentNote: String?
    /// The last weigh-in in Apple Health (last 35 days), for the weigh-in nudge.
    private(set) var lastWeighIn: Date?
    /// Tonight's bed-by window (`BedtimeWindow`), from sleep need, debt, usual wake time and tomorrow's plan.
    private(set) var bedtimeWindow: BedtimeWindow.Result?
    /// Tomorrow's planned session start from the weekly plan, if any (set by the app before a refresh).
    var plannedSessionTomorrow: Date?

    // MARK: Energy availability (body & nutrition measures)

    /// (intake − workout energy) / fat-free mass over the last 7 logged days;
    /// nil without body fat or 5 logged days (`EnergyAvailability`, IOC REDs 2023).
    private(set) var energyAvailability: EnergyAvailability.Result?

    /// Daily calorie target from your goal (or maintenance when no goal is set).
    var calorieTarget: Double? {
        let target: Double
        if let calorieTargetOverride, goals != nil, maintenance != nil {
            // This week's target (Monday-updated) wins while there's measured maintenance behind it.
            target = calorieTargetOverride
        } else {
            guard let base = maintenance?.maintenance ?? calories?.projected else { return nil }
            guard let goals, let weight = bodyMassKg else { return base }
            target = GoalPlanner.calorieTarget(maintenance: base, bodyMassKg: weight, goals: goals, sex: sex)
        }
        // Never below what this body needs after training (`CalorieSafety`, IOC REDs 2023).
        return max(target, calorieMinimum ?? 0)
    }

    /// True when the target is being held up by the safety minimum.
    var targetHeldAtMinimum: Bool {
        guard let minimum = calorieMinimum, let target = calorieTarget else { return false }
        return abs(target - minimum) < 1
    }

    /// One consistent set of calorie numbers for the Home card.
    struct CalorieSummary: Equatable {
        var eaten: Double?
        var restingSoFar: Double
        var activeSoFar: Double
        var burnedSoFar: Double { restingSoFar + activeSoFar }
        /// Burned so far plus resting calories still to come before midnight.
        var projected: Double
        /// Projected burn minus food eaten: positive = room left to maintain weight.
        var left: Double { projected - (eaten ?? 0) }
        var fromWatch: Bool
    }

    var calories: CalorieSummary? {
        let now = Date.now
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        let minutesLeft = max(0, midnight.timeIntervalSince(now) / 60)
        let eaten = nutritionToday?.calories
        // Prefer what the watch measured so the numbers match Garmin.
        if let resting = deviceRestingToday, let active = deviceActiveToday, resting > 0 {
            let perMinute = (watchRestingPerDay ?? energy?.restingFullDay ?? resting * 1440 / max(1, 1440 - minutesLeft)) / 1440
            return CalorieSummary(eaten: eaten, restingSoFar: resting, activeSoFar: active,
                                  projected: resting + active + perMinute * minutesLeft, fromWatch: true)
        }
        guard let energy else { return nil }
        return CalorieSummary(eaten: eaten, restingSoFar: energy.restingSoFar,
                              activeSoFar: energy.exercise + energy.everydayMovement + energy.digestion,
                              projected: energy.projectedTotal, fromWatch: false)
    }
    private(set) var heartRateProfile: HeartRateProfile?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?

    @ObservationIgnored private let strainCalculator = StrainCalculator()
    /// Finished days don't change, so their strain is kept between refreshes.
    @ObservationIgnored private var dayCache: [Date: (key: String, result: StrainCalculator.Result)] = [:]
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshQueued = false
    /// The newest arguments passed while a refresh was running, so the queued
    /// pass includes a just-finished workout or a newly typed HRV.
    @ObservationIgnored private var queuedSessions: [StrengthSessionSummary] = []
    @ObservationIgnored private var queuedManualHRV: [Date: Double] = [:]
    @ObservationIgnored private let recoveryCalculator = RecoveryCalculator()
    @ObservationIgnored private let sleepCalculator = SleepCalculator()

    @ObservationIgnored private var todaysHeartRate: [HeartRateSample] = []
    /// Stretches today where two heart-rate sources read far apart; the
    /// preferred one (ear sensor while lifting, steadier series otherwise)
    /// was kept (`HeartRateMerge`).
    private(set) var todaysDisagreements: [HeartRateMerge.Disagreement] = []

    /// 1.6 g/kg, raised by some medications (see MedicationsModel).
    var proteinGramsPerKg = 1.6
    /// A medication's protein floor (g/kg), if any.
    var medicationProteinPerKg: Double?
    private(set) var bodyFatPercent: Double?
    private(set) var heightCm: Double?
    /// Daily protein from the goal: lean mass when losing and body fat is known,
    /// goal or adjusted weight otherwise (see `GoalPlanner.proteinGrams`).
    var proteinTarget: Double? {
        guard goals != nil else { return NutritionTargets.proteinGrams(bodyMassKg: bodyMassKg, gramsPerKg: proteinGramsPerKg) }
        return GoalPlanner.proteinGrams(goals: goals, bodyMassKg: bodyMassKg, bodyFatPercent: bodyFatPercent,
                                        heightCm: heightCm, minimumPerKg: medicationProteinPerKg)
    }

    /// Heat-day change to the strain target's upper end (negative on hot days).
    var heatAdjustment: Double = 0

    /// Highest sustained heart rate inside workouts, computed off the main
    /// thread. Only minutes another source confirms (within 5 bpm) or a clean
    /// run supports count (`HeartRateMerge.peakSupport`); the sustained-run
    /// and plausibility rules in `ObservedMaxHeartRate` still apply after.
    @concurrent
    nonisolated private static func workoutPeak(
        _ merged: HeartRateMerge.Result, sources: [HeartRateMerge.Source], windows: [DateInterval]
    ) async -> Double? {
        guard !windows.isEmpty else { return nil }
        return ObservedMaxHeartRate.peak(HeartRateMerge.peakSupport(merged, sources: sources, windows: windows))
    }

    /// One per-minute series from several sources (AirPods via this app, a
    /// watch, Garmin), off the main thread: no minute counts twice, and the
    /// ear sensor wins while lifting (`HeartRateMerge`; Spierer 2015; Bunn 2019).
    @concurrent
    nonisolated private static func mergeHeartRate(
        _ sources: [HeartRateMerge.Source], liftingWindows: [DateInterval]
    ) async -> HeartRateMerge.Result {
        HeartRateMerge.merge(sources: sources, liftingWindows: liftingWindows)
    }

    /// Strain per day, computed off the main thread.
    @concurrent
    nonisolated private static func computeDays(
        _ days: [Date],
        heartRate: [HeartRateSample],
        sessions: [StrengthSessionSummary],
        profile: HeartRateProfile
    ) async -> [Date: StrainCalculator.Result] {
        let calendar = Calendar.current
        var byDay: [Date: [HeartRateSample]] = [:]
        for sample in heartRate {
            byDay[calendar.startOfDay(for: sample.date), default: []].append(sample)
        }
        let calculator = StrainCalculator()
        var results: [Date: StrainCalculator.Result] = [:]
        for day in days {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            results[day] = calculator.dailyStrain(
                heartRate: byDay[day] ?? [],
                strengthSessions: sessions.filter { $0.start >= day && $0.start < next },
                profile: profile
            )
        }
        return results
    }

    /// Today's strain target, scaled to what your training days usually reach.
    /// When the 7-day HRV average is below your normal range, it's capped at an
    /// easy day (HRV-guided training).
    var targetStrain: ClosedRange<Double>? {
        guard !restMode, let recovery else { return nil }
        let target = StrainCalculator.targetStrain(forRecovery: recovery.score, usualTrainingStrain: usualTrainingStrain)
        let base = trainEasyToday ? min(target.lowerBound, 20)...min(target.upperBound, 45) : target
        return HeatAdvice.adjustTarget(base, by: heatAdjustment)
    }

    /// HRV-guided training: the 7-day HRV average is below your normal range.
    var trainEasyToday: Bool { recovery?.hrvTrend?.status == .below }

    /// Recovery to plan workouts with (lowered on HRV-guided easy days).
    var recoveryForTraining: Int? {
        guard let score = recovery?.score else { return nil }
        if restMode { return min(score, 20) }
        return trainEasyToday ? min(score, 30) : score
    }

    /// What moved recovery: the score's own inputs plus context the score
    /// doesn't include (sleep debt, yesterday's training, drinks, illness signs).
    func recoveryContributors(drinksLastNight: Int?, illness: IllnessWatch.Alert?) -> [RecoveryContributor] {
        var items = recovery?.contributors ?? []
        if let debt = sleepDebt, debt.level == .moderate || debt.level == .high {
            items.append(RecoveryContributor(
                id: "sleepDebt", name: "Sleep debt",
                detail: "\(debt.hours.formatted(.number.precision(.fractionLength(1)))) h behind your sleep need over the last two weeks. Sleep debt builds up slowly and you feel it less than it affects you.",
                effect: .lowers
            ))
        }
        if let strain = yesterdayStrain, strain >= 70 {
            items.append(RecoveryContributor(
                id: "yesterday", name: "Yesterday's training",
                detail: "Strain \(Int(strain.rounded()))%: a hard day usually lowers HRV and raises resting heart rate the next morning.",
                effect: .lowers
            ))
        }
        if let drinks = drinksLastNight, drinks >= 1 {
            items.append(RecoveryContributor(
                id: "alcohol", name: "Alcohol",
                detail: "\(drinks) drink\(drinks == 1 ? "" : "s") last night. Alcohol lowers overnight HRV and raises heart rate, more with each drink (Pietilä et al., JMIR Ment Health 2018).",
                effect: .lowers
            ))
        }
        if let illness, illness.level == .major {
            items.append(RecoveryContributor(
                id: "illness", name: "Illness signs",
                detail: illness.signals.joined(separator: ", ") + ".",
                effect: .lowers
            ))
        }
        return items
    }

    /// The strain a planned session would add on top of today's strain.
    func strainGain(addedLoad: Double) -> Double {
        StrainPlanner().strainGain(current: strain?.strain ?? 0, addedLoad: addedLoad)
    }

    /// - Parameters:
    ///   - sessions: finished gym sessions from the last 28 days.
    ///   - manualHRV: HRV the user typed in, keyed by morning.
    func refresh(
        health: HealthKitClient,
        settings: UserSettings,
        sessions: [StrengthSessionSummary],
        manualHRV: [Date: Double] = [:],
        now: Date = .now
    ) async {
        guard health.isAvailable else {
            errorMessage = "Apple Health isn't available on this device."
            return
        }
        // Don't stack refreshes: if one is running, run once more when it finishes.
        if isRefreshing {
            refreshQueued = true
            queuedSessions = sessions
            queuedManualHRV = manualHRV
            return
        }
        isRefreshing = true
        isLoading = true
        defer {
            isRefreshing = false
            isLoading = false
        }
        await performRefresh(health: health, settings: settings, sessions: sessions, manualHRV: manualHRV, now: now)
        while refreshQueued {
            refreshQueued = false
            await performRefresh(health: health, settings: settings, sessions: queuedSessions, manualHRV: queuedManualHRV, now: .now)
        }
    }

    private func performRefresh(
        health: HealthKitClient,
        settings: UserSettings,
        sessions: [StrengthSessionSummary],
        manualHRV: [Date: Double],
        now: Date
    ) async {

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let historyStart = calendar.date(byAdding: .day, value: -27, to: today) ?? today

        do {
            async let vitalsTask = health.nightlyVitals(days: 31, endingOn: today)
            async let sleepTask = health.sleepSamples(forNightEnding: today)
            async let workoutsTask = health.externalWorkouts(from: today, to: now)
            async let nightsTask = health.sleepHistory(nights: 31)
            let (healthVitals, sleepSamples, externalWorkouts) = try await (vitalsTask, sleepTask, workoutsTask)
            let nights = (try? await nightsTask) ?? []
            sleepNights = nights
            let lastWeek = Array(nights.suffix(8))
            sleepConsistency = lastWeek.regularityScore
            sleepSpreadMinutes = SleepConsistency.spreadMinutes(lastWeek.map { SleepConsistency.Night(bedtime: $0.bedtime, wake: $0.wake) })
            restMode = settings.isRestMode
            sleepDebt = SleepDebt.compute(nightlyHours: nights.map(\.hoursAsleep), needHours: settings.sleepNeedHours)
            recentBedtimes = nights.map(\.bedtime)
            bedtimeWindow = BedtimeWindow.compute(
                sleepNeedHours: settings.sleepNeedHours, sleepDebt: sleepDebt,
                usualWakeMinutes: BedtimeWindow.usualWakeMinutes(nights.suffix(14).map(\.wake)),
                regularity: sleepConsistency, plannedSessionStart: plannedSessionTomorrow, now: now
            )

            // RMSSD (typed-in Garmin values, camera readings, Apple Watch
            // beat-to-beat) and Apple Health's SDNN aren't comparable, so once
            // any RMSSD exists, only RMSSD is used; typed values win per night.
            let beatToBeat = await health.nightlyRMSSD(nights: nights)
            let rmssd = beatToBeat.merging(manualHRV.filter { $0.value > 0 }) { _, typed in typed }
            hrvMetric = rmssd.isEmpty ? (healthVitals.contains { $0.hrvMilliseconds != nil } ? "SDNN" : nil) : "RMSSD"
            // [Recovery research] Sleeping heart rate as the resting heart rate, all nights or none
            // (HealthKit RHR as the fallback); see RecoveryCalculator.preferSleepingHeartRate.
            let sleepingHeartRate = await health.nightlySleepingHeartRate(nights: nights)
            let (vitals, rhrSource) = RecoveryCalculator.preferSleepingHeartRate(
                DailyVitals.merging(healthVitals, manualHRV: rmssd, manualOnlyHRV: true, calendar: calendar),
                sleeping: sleepingHeartRate, minimumNights: recoveryCalculator.minimumBaselineDays + 1, calendar: calendar)
            restingHeartRateSource = rhrSource
            // Today's HRV is the typed one when you entered a value for today
            // (typed values replace Health's, see `merging`).
            let typedToday = manualHRV.contains { calendar.isDate($0.key, inSameDayAs: today) && $0.value > 0 }
            let todayVitals = vitals.first { calendar.isDate($0.date, inSameDayAs: today) }
                ?? DailyVitals(date: today, hrvMilliseconds: nil, restingHeartRate: nil)
            let history = vitals.filter { !calendar.isDate($0.date, inSameDayAs: today) }
            let base = recoveryCalculator.baseline(from: history, restingHeartRateSource: rhrSource)
            baseline = base

            restingHeartRate = todayVitals.restingHeartRate
            hrv = todayVitals.hrvMilliseconds
            hrvIsManual = hrv != nil && typedToday
            // Heart-rate reserve uses your baseline resting heart rate (whole
            // bpm), not today's: a high reading after a bad night or a drink
            // shouldn't shrink every past day's strain, and a steady value
            // keeps the 28-day cache valid.
            let profile = settings.heartRateProfile(restingHeartRate: base.meanRHR.map { $0.rounded() } ?? todayVitals.restingHeartRate)
            heartRateProfile = profile

            // Strain for each of the last 28 days (today last). Past days come from
            // the cache unless their inputs changed; today and yesterday are always
            // recomputed because the watch can sync late.
            var allDays: [Date] = []
            var day = historyStart
            while day <= today {
                allDays.append(day)
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            }
            let profileKey = "\(Int(profile.restingHeartRate))-\(Int(profile.maxHeartRate))-\(profile.sex.rawValue)"
            func key(for day: Date) -> String {
                let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                let daySessions = sessions.filter { $0.start >= day && $0.start < next }
                return profileKey + daySessions.map { "|\($0.start.timeIntervalSince1970)-\($0.end.timeIntervalSince1970)-\($0.sessionRPE ?? 0)" }.joined()
            }
            // The last 7 days are always recomputed: Garmin Connect can sync
            // several days late, and cached days wouldn't see the new heart rate.
            let recentStart = calendar.date(byAdding: .day, value: -6, to: today) ?? yesterday
            let needed = allDays.filter { day in
                day >= recentStart || dayCache[day]?.key != key(for: day)
            }
            if let firstNeeded = needed.first {
                // Per-minute heart rate from every source, merged so each minute is counted
                // once from the better sensor (`HeartRateMerge`): ear over wrist during logged
                // lifts and external strength workouts, the steadier series during cardio.
                // If the per-source query fails or comes back empty, fall back to the plain
                // per-minute average, so heart rate can never stop the rest of the refresh
                // (strain, recovery, sleep and calories all come after this).
                var sourceSeries = (try? await health.heartRatePerMinuteBySource(from: firstNeeded, to: now)) ?? []
                if sourceSeries.allSatisfy({ $0.samples.isEmpty }) {
                    let combined = (try? await health.heartRatePerMinute(from: firstNeeded, to: now)) ?? []
                    sourceSeries = combined.isEmpty ? [] : [HeartRateSource(name: "Apple Health", samples: combined)]
                }
                let mergeSources = sourceSeries.map(\.mergeSource)
                let fetchedWorkouts = (try? await health.externalWorkouts(from: firstNeeded, to: now)) ?? []
                let liftingWindows = sessions.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
                    + fetchedWorkouts.filter(\.isStrength).map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
                let merged = await Self.mergeHeartRate(mergeSources, liftingWindows: liftingWindows)
                let heartRate = merged.samples
                // Learn max heart rate from workouts only (used from the next refresh).
                let workoutWindows = liftingWindows
                    + fetchedWorkouts.filter { !$0.isStrength }.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
                let peak = await Self.workoutPeak(merged, sources: mergeSources, windows: workoutWindows)
                settings.noteHeartRatePeak(peak)
                let computed = await Self.computeDays(needed, heartRate: heartRate, sessions: sessions, profile: profile)
                for (date, result) in computed {
                    dayCache[date] = (key(for: date), result)
                }
                todaysHeartRate = heartRate.filter { $0.date >= today }
                todaysDisagreements = merged.disagreements.filter { $0.start >= today }
            }
            dayCache = dayCache.filter { $0.key >= historyStart }
            let days: [(Date, StrainCalculator.Result)] = allDays.map { ($0, dayCache[$0]?.result ?? .empty) }
            let todayResult = days.last?.1 ?? .empty
            strain = todayResult
            yesterdayStrain = days.first { calendar.isDate($0.0, inSameDayAs: yesterday) }?.1.strain
            weekStrain = days.suffix(7).map { DayStrain(date: $0.0, strain: $0.1.strain) }
            usualTrainingStrain = StrainCalculator.usualTrainingStrain(days.dropLast().map(\.1.strain))
            recentTrainingDays = Set(days.filter { $0.1.strain >= 25 }.map(\.0))
            let loadCalculator = TrainingLoadCalculator()
            // Completed days only: today isn't over, so it would make this week read low.
            let completeDays = days.dropLast()
            cardioLoad = loadCalculator.evaluate(dailyLoads: completeDays.map(\.1.cardioLoad))
            muscularLoad = loadCalculator.evaluate(dailyLoads: completeDays.map(\.1.liftingLoad))

            var sleepCalculator = self.sleepCalculator
            sleepCalculator.baseSleepNeedHours = settings.sleepNeedHours
            sleepCalculator.age = settings.age // [Recovery research] age-scaled deep + REM target
            sleep = sleepCalculator.score(samples: sleepSamples, previousDayStrain: yesterdayStrain, consistency: sleepConsistency)
            // [Recovery research] Sleep is compared with your own last 30 scores; RHR source as above.
            SleepScoreLog.record(sleep?.score, on: today)
            recovery = recoveryCalculator.score(today: todayVitals, history: history, sleepScore: sleep?.score,
                                                sleepScoreHistory: SleepScoreLog.recentScores(before: today),
                                                restingHeartRateSource: rhrSource)

            // Today's activities: logged lifts plus workouts from other apps.
            let todaysHR = todaysHeartRate
            let todaysSessions = sessions.filter { $0.start >= today }
            activities = makeActivities(
                sessions: todaysSessions, external: externalWorkouts,
                heartRate: todaysHR, profile: profile, totalLoad: todayResult.totalLoad
            )

            // Extras that shouldn't block the scores if they fail.
            async let todayFood = health.nutrition(on: today)
            async let yesterdayFood = health.nutrition(on: yesterday)
            async let weight = health.latestBodyMassKg()
            async let height = health.latest(.height, unit: .meterUnit(with: .centi))
            async let bodyFat = health.latest(.bodyFatPercentage, unit: .percent())
            async let respiratory = health.overnightRespiratoryRate(forNightEnding: today)
            async let recentRespiratory = health.latest(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), since: calendar.date(byAdding: .day, value: -3, to: today))
            async let measuredResting = health.restingEnergyPerDay()
            async let deviceEnergy = health.deviceEnergy(from: today, to: now)
            let windows = todaysSessions.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
                + externalWorkouts.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
            async let stepCounts = health.steps(from: today, to: now, excluding: windows)

            nutritionToday = try? await todayFood
            nutritionYesterday = try? await yesterdayFood
            let healthWeight = try? await weight
            bodyMassKg = healthWeight ?? (settings.weightKg > 0 ? settings.weightKg : nil)
            let heightCm = (try? await height) ?? (settings.heightCm > 0 ? settings.heightCm : nil)
            let bodyFatPercent = (try? await bodyFat).map { $0 * 100 }
            self.bodyFatPercent = bodyFatPercent
            self.heightCm = heightCm
            // Last night's average, or the latest reading if the watch logs it at other times.
            let overnight = try? await respiratory
            let latestRespiratory = try? await recentRespiratory
            respiratoryRate = overnight ?? latestRespiratory
            let device = try? await deviceEnergy
            deviceRestingToday = device?.resting
            deviceActiveToday = device?.active
            let watchResting = try? await measuredResting
            watchRestingPerDay = watchResting
            goals = settings.goalsSet ? settings.goals : nil
            sex = settings.sex

            // Real maintenance from the food log and weight trend.
            async let intakeSeries = health.dailySeries(.dietaryEnergyConsumed, unit: .kilocalorie(), days: 35, cumulative: true)
            async let weightSeries = health.dailySeries(.bodyMass, unit: .gramUnit(with: .kilo), days: 35, cumulative: false)
            async let nutrientTask = health.nutrientAverages(days: 7)
            let rawIntake = ((try? await intakeSeries) ?? []).filter { $0.date < today }.map { DayValue(date: $0.date, value: $0.value) }
            // Quick-estimate meals: a day logged only as this app's estimates
            // counts as a partial day, not a measured one (`EstimatedIntake`;
            // O'Hara 2025; nutrition.md "how accurate").
            let estimatedDays = (try? await health.estimateOnlyDays(days: 35)) ?? []
            let intake = EstimatedIntake.downWeight(rawIntake, estimatedOnlyDays: estimatedDays)
            let weights = ((try? await weightSeries) ?? []).map { DayValue(date: $0.date, value: $0.value) }
            // Water from starting creatine isn't tissue, so it's taken out of the trend.
            let creatine = MedicationStore.medications().first {
                $0.isActive && MedicationKnowledge.match($0.name)?.id == "creatine"
            }
            let loading = creatine.map { $0.dose.contains("20") } ?? false
            let expected = calories?.projected
            let measured = AdaptiveTDEE.estimate(intake: intake, weights: weights, now: now,
                                                 creatineStart: creatine?.startDate, creatineLoading: loading,
                                                 expectedExpenditure: expected)
            // A maintenance under 1.4× resting metabolism isn't physically believable
            // (FAO/WHO/UNU 2004): the food log is incomplete, so it isn't used
            // (`CalorieSafety`). The watch estimate stands in until it looks complete.
            let restingKcal = bodyMassKg.map { weight in
                EnergyCalculator().bmr(EnergyCalculator.Body(weightKg: weight, heightCm: heightCm, age: settings.age, sex: settings.sex)).kcal
            }
            if let measured, let restingKcal, !CalorieSafety.isPlausibleMaintenance(measured.maintenance, bmr: restingKcal) {
                maintenance = nil
                implausibleMaintenance = measured.maintenance
            } else {
                maintenance = measured
                implausibleMaintenance = nil
            }
            maintenanceProgress = AdaptiveTDEE.progress(intake: intake, weights: weights, now: now, expectedExpenditure: expected)
            weightTrendWeekly = WeightTrend.weeklyChange(weights.filter { $0.date >= today.addingTimeInterval(-28 * 86_400) })
            lastWeighIn = weights.map(\.date).max()
            // Energy availability: the last 7 logged days against workout calories (`EnergyAvailability`).
            let workoutEnergy = (try? await health.workoutEnergyPerDay(days: 8)) ?? []
            // The lowest safe target for this body and training (`CalorieSafety`, IOC REDs 2023).
            let exercisePerDay = workoutEnergy.map(\.value).reduce(0, +) / 7
            calorieMinimum = bodyMassKg.map { weight in
                CalorieSafety.minimumTarget(sex: settings.sex, weightKg: weight, heightCm: heightCm,
                                            bodyFatPercent: bodyFatPercent, exerciseKcalPerDay: exercisePerDay)
            }
            updateWeeklyCalorieTarget(settings: settings, now: now)
            let weekAgo = today.addingTimeInterval(-7 * 86_400)
            energyAvailability = EnergyAvailability.assess(
                days: intake.filter { $0.date >= weekAgo }.map { day in
                    EnergyAvailability.Day(date: day.date, intakeKcal: day.value,
                                           exerciseKcal: workoutEnergy.first { calendar.isDate($0.date, inSameDayAs: day.date) }?.value ?? 0)
                },
                fatFreeMassKg: EnergyAvailability.fatFreeMass(bodyMassKg: bodyMassKg, bodyFatPercent: bodyFatPercent)
            )
            if let nutrients = try? await nutrientTask {
                micronutrients = Micronutrients.assess(averages: nutrients.averages, daysLogged: nutrients.daysLogged, sex: settings.sex)
            }
            let stepResult = try? await stepCounts
            steps = stepResult?.total

            if let bodyMassKg {
                let body = EnergyCalculator.Body(
                    weightKg: bodyMassKg, heightCm: heightCm, age: settings.age,
                    sex: settings.sex, bodyFatPercent: bodyFatPercent
                )
                energy = EnergyCalculator().estimate(
                    body: body, profile: profile, heartRate: todaysHR,
                    strengthSessions: todaysSessions,
                    stepsOutsideWorkouts: stepResult?.outside ?? 0,
                    intake: nutritionToday?.calories,
                    macros: nutritionToday.flatMap { EnergyCalculator.Macros($0) },
                    dayStart: today, now: now,
                    measuredRestingPerDay: watchResting
                )
            } else {
                energy = nil
            }

            errorMessage = nil
            lastUpdated = now
        } catch {
            errorMessage = "Couldn't read Apple Health: \(error.localizedDescription)"
        }
    }

    // MARK: Weekly calorie target

    /// Keeps the week's target in `UserSettings`: seeded from measured
    /// maintenance and the goal, then moved on Mondays by `CalorieBand`
    /// (at most ±100 kcal, guarded by the 1%/week loss and 0.5%/week gain
    /// limits). Cleared when there's no measured maintenance or goal, so the
    /// target floats with the watch estimate as before.
    private func updateWeeklyCalorieTarget(settings: UserSettings, now: Date) {
        guard let maintenance, let goals, let weight = bodyMassKg else {
            calorieTargetOverride = nil
            calorieAdjustmentNote = nil
            return
        }
        let goalKey = "\(goals.weight.rawValue)|\(goals.weeklyRatePercent)"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let thisMonday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: today) ?? today
        // The goal's target from today's measured maintenance. When the stored weekly
        // target has drifted far from it (maintenance was re-measured, e.g. once
        // partly logged days were left out), start again from it: the weekly
        // ±100 kcal nudges are for small drift, not for catching up on a new estimate.
        let fromMaintenance = GoalPlanner.calorieTarget(maintenance: maintenance.maintenance, bodyMassKg: weight, goals: goals, sex: sex)
        let drifted = settings.calorieTargetOverride.map { abs($0 - fromMaintenance) > 250 } ?? false
        if settings.calorieTargetOverride == nil || settings.calorieTargetOverrideGoal != goalKey || drifted {
            settings.calorieTargetOverride = fromMaintenance
            settings.calorieTargetOverrideGoal = goalKey
            settings.calorieTargetOverrideDate = today
            settings.calorieAdjustmentNote = ""
        } else if let current = settings.calorieTargetOverride, (settings.calorieTargetOverrideDate ?? .distantPast) < thisMonday {
            let adjustment = CalorieBand.weeklyAdjustment(
                measuredMaintenance: maintenance.maintenance, currentTarget: current, goals: goals, bodyMassKg: weight,
                weeklyChangeKg: maintenance.weeklyChangeKg, loggedDays: maintenance.loggedDays, sex: sex
            )
            if let adjustment {
                settings.calorieTargetOverride = adjustment.newTarget
            }
            settings.calorieAdjustmentNote = adjustment?.note ?? ""
            settings.calorieTargetOverrideDate = today
        }
        calorieTargetOverride = settings.calorieTargetOverride
        calorieAdjustmentNote = settings.calorieAdjustmentNote.isEmpty ? nil : settings.calorieAdjustmentNote
    }

    private func makeActivities(
        sessions: [StrengthSessionSummary],
        external: [ExternalWorkout],
        heartRate: [HeartRateSample],
        profile: HeartRateProfile,
        totalLoad: Double
    ) -> [ActivityItem] {
        func contribution(_ load: Double) -> Double {
            let without = strainCalculator.strain(forLoad: max(0, totalLoad - load))
            let with = strainCalculator.strain(forLoad: totalLoad)
            return max(0, ((with - without) * 10).rounded() / 10)
        }
        var items: [ActivityItem] = []
        for session in sessions {
            let hrLoad = strainCalculator.dailyStrain(
                heartRate: heartRate.filter { session.contains($0.date) }, strengthSessions: [], profile: profile
            ).cardioLoad
            let load = max(hrLoad, strainCalculator.rpeLoad(for: session))
            let minutes = Int(session.duration / 60)
            // The watch workout linked to this session (`WorkoutLinker`) lends its source and calories.
            var detail = "\(minutes) min · \(session.workingSets) sets"
            if let source = session.linkedWorkoutSource {
                detail += " · \(source)"
                if let kcal = external.first(where: { $0.uuid == session.linkedWorkoutUUID })?.activeKcal, kcal > 0 {
                    detail += " · \(whole(kcal)) kcal"
                }
            }
            items.append(ActivityItem(
                id: "s\(session.start.timeIntervalSince1970)",
                name: session.name ?? "Strength",
                detail: detail,
                start: session.start,
                strainAdded: contribution(load),
                isStrength: true,
                minutes: minutes
            ))
        }
        for workout in external {
            // A workout linked to a logged session is shown as that session, not twice.
            if sessions.contains(where: { $0.linkedWorkoutUUID == workout.uuid }) { continue }
            // Skip watch strength workouts that overlap a logged session (same workout).
            if workout.isStrength, sessions.contains(where: { $0.start < workout.end && $0.end > workout.start }) { continue }
            let load = strainCalculator.dailyStrain(
                heartRate: heartRate.filter { $0.date >= workout.start && $0.date <= workout.end },
                strengthSessions: [], profile: profile
            ).cardioLoad
            var detail = "\(workout.minutes) min"
            if let km = workout.distanceKm, km > 0.1 {
                detail += " · \(km.formatted(.number.precision(.fractionLength(1)))) km"
            }
            items.append(ActivityItem(
                id: "w\(workout.uuid.uuidString)",
                name: workout.name, detail: detail, start: workout.start,
                strainAdded: contribution(load), isStrength: workout.isStrength,
                minutes: workout.minutes
            ))
        }
        return items.sorted { $0.start < $1.start }
    }
}
