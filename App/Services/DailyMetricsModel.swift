import Foundation
import HealthKit
import AppCore
import os

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
        /// No heart rate during it, so `strainAdded` is unknown, not zero (show "—").
        var noHeartRate = false
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
    /// The 7 completed days before today (today's partial day left out), for the weekly review.
    private(set) var completedWeekStrain: [DayStrain] = []
    /// What your training days usually reach over the last 4 weeks (nil while calibrating).
    private(set) var usualTrainingStrain: Double?
    /// Days in the last 4 weeks with a workout or logged session and strain 35%+
    /// (`TrainingDayPlanner.isWatchTrainingDay`), for plan ticks and heat acclimation.
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
    /// The HRV measure behind `hrvMetric`, for `hrvMetricNote` (`DailyVitals.resolvingHRV`).
    private(set) var hrvSelection: HRVMetric?
    /// True between midnight and waking: today's night isn't over, so
    /// `recovery`, `hrv` and `restingHeartRate` are yesterday's (`RecoveryTiming`).
    private(set) var recoveryIsFromYesterday = false
    /// Minutes today at 30-50% of heart-rate reserve, below zone 1 (`HeartRateProfile.lightBand`).
    private(set) var todaysLightMinutes: Double = 0
    /// Per-minute heart-rate readings today (all sources, merged), so the
    /// zones page can tell "no readings" from "readings below zone 1".
    private(set) var todaysHeartRateReadings = 0
    /// Sick / rest mode (from settings): strain targets and training nudges pause.
    var restMode = false

    /// Remembers the resting-heart-rate source between launches (hysteresis in
    /// `RecoveryCalculator.preferSleepingHeartRate`).
    private static let rhrSourceKey = "recoveryRestingHeartRateSource"

    /// A short label for the recovery ring instead of the usual one, when it
    /// needs explaining: yesterday's score before you wake, or sleep only.
    var recoveryNote: String? {
        guard let recovery else { return nil }
        if recoveryIsFromYesterday { return "Yesterday · updates when you wake" }
        if recovery.isSleepOnly { return "Sleep-only estimate" }
        return nil
    }

    /// One line on which HRV measure recovery uses (`DailyVitals.resolvingHRV`).
    var hrvMetricNote: String? {
        switch hrvSelection {
        case .rmssd: "HRV is overnight RMSSD (Apple Watch beat-to-beat data or your watch app's value). Nights without it use Apple Health's SDNN, scaled to your own RMSSD."
        case .sdnn: "HRV is Apple Health's SDNN. Once overnight RMSSD covers 14 of the last 30 nights, the app switches to it."
        case .morningRMSSD: "HRV is your morning camera reading. It isn't mixed with overnight HRV, which is measured asleep."
        case nil: nil
        }
    }

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
    /// What the weekly plan had on each of the last 8 days and today (start of
    /// day → focus; rest days are absent), and whether there's a plan this
    /// week at all. Set by the app before a refresh (`TrainingDayPlanner`).
    var plannedFocusByDay: [Date: WorkoutFocus] = [:]
    var hasWeeklyPlan = false
    /// Of those days, the ones whose week had a fixed-day plan (not none, not
    /// flexible): only they can be a planned rest day or a missed session.
    var fixedPlanDays: Set<Date> = []
    /// Start-of-day dates with a logged gym session (`WeeklyPlanStore.trainingDays(sessions:)`).
    var loggedSessionDays: Set<Date> = []
    // MARK: Flexible weeks (WeeklyPlanStore builder)
    /// In a flexible week (`WeeklyPlan.Mode.flexible`): sessions done against
    /// the quota, days left, trained today, and the coverage rule's next focus.
    /// Set by the app before a refresh; nil in a fixed-day week or without a plan.
    var flexibleWeek: WeeklyPlan.Progress?
    var flexibleNextFocus: WorkoutFocus?
    /// A fixed-day week run as a queue (`AdaptiveWeek`, `WeeklyPlanStore.refreshAdaptive`):
    /// set from Today and Fitness › This week; used by `dayGuidance` on its day.
    var adaptiveWeek: AdaptiveWeek.Result?

    // MARK: Energy availability (body & nutrition measures)

    /// (intake − workout energy) / fat-free mass over the last 7 logged days;
    /// nil without body fat or 5 logged days (`EnergyAvailability`, IOC REDs 2023).
    private(set) var energyAvailability: EnergyAvailability.Result?

    // MARK: Personal calorie numbers (docs/research/calories.md)

    /// From the lifting log and the reported experience (`TrainingStatus.resolve`), set by the app before a refresh.
    /// Picks the resting-energy equation and the fastest useful gain.
    var trainingStatus: TrainingStatus?
    /// Age used for the personal limits (from settings / Apple Health).
    private(set) var age: Int = 30

    /// Body fat for the pace limit: the Apple Health reading, else a rough
    /// estimate from BMI (Deurenberg 1991), flagged as estimated.
    var paceBodyFat: (percent: Double, estimated: Bool)? {
        if let bodyFatPercent { return (bodyFatPercent, false) }
        guard let weight = bodyMassKg,
              let estimate = GoalPlanner.estimatedBodyFatPercent(weightKg: weight, heightCm: heightCm, age: age, sex: sex) else { return nil }
        return (estimate, true)
    }

    /// The fastest weekly rate for these goals and this person (`GoalPlanner.maximumWeeklyRate`).
    func rateLimit(for goals: Goals) -> GoalPlanner.RateLimit {
        let fat = paceBodyFat
        return GoalPlanner.maximumWeeklyRate(goals: goals, sex: sex, age: age, bodyFatPercent: fat?.percent,
                                             trainingStatus: trainingStatus, bodyFatIsEstimate: fat?.estimated ?? false)
    }

    /// The goals with the weekly rate held at the personal maximum.
    var personalGoals: Goals? {
        goals.map { GoalPlanner.cappedGoals($0, limit: rateLimit(for: $0)) }
    }

    /// Daily calorie target from your goal (or maintenance when no goal is set).
    var calorieTarget: Double? {
        let target: Double
        if let calorieTargetOverride, goals != nil, maintenance != nil {
            // This week's target (Monday-updated) wins while there's measured maintenance behind it.
            target = calorieTargetOverride
        } else {
            guard let base = maintenance?.maintenance ?? calories?.projected else { return nil }
            guard let goals = personalGoals, let weight = bodyMassKg else { return base }
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
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
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
    /// Set when both heart-rate reads threw on the last refresh, so a day
    /// with workouts but no zones can say why (ZonesDetailView). A read that
    /// answers with no samples is not a failure. Zone minutes come only from
    /// heart rate; exercise minutes and session RPE add strain without zones.
    private(set) var heartRateReadError: String?
    /// Diagnostics: heart-rate samples per source and zone minutes after each
    /// refresh (Console: category "strain").
    private static let log = Logger(subsystem: "com.lontraindustries.workoutapp", category: "strain")

    @ObservationIgnored private let strainCalculator = StrainCalculator()
    /// Finished days don't change, so their strain is kept between refreshes.
    @ObservationIgnored private var dayCache: [Date: (key: String, result: StrainCalculator.Result)] = [:]
    /// Days with a workout in Apple Health, kept like `dayCache` (refetched
    /// from the first recomputed day on), for `TrainingDayPlanner.isWatchTrainingDay`.
    @ObservationIgnored private var workoutDays: Set<Date> = []
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var refreshQueued = false
    /// The newest arguments passed while a refresh was running, so the queued
    /// pass includes a just-finished workout or a newly typed HRV.
    @ObservationIgnored private var queuedSessions: [StrengthSessionSummary] = []
    @ObservationIgnored private var queuedManualHRV: [Date: Double] = [:]
    @ObservationIgnored private var queuedMorningHRV: [Date: Double] = [:]
    /// When the last 7 days' heart rate was last read in full (see `performRefresh`).
    @ObservationIgnored private var lastWideHeartRateRead: Date?
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
    /// Daily protein from the goal before the calorie cap: lean mass when losing
    /// and body fat is known, goal or adjusted weight otherwise (see
    /// `GoalPlanner.proteinGrams`).
    var proteinTargetUncapped: Double? {
        guard goals != nil else { return NutritionTargets.proteinGrams(bodyMassKg: bodyMassKg, gramsPerKg: proteinGramsPerKg) }
        return GoalPlanner.proteinGrams(goals: goals, bodyMassKg: bodyMassKg, bodyFatPercent: bodyFatPercent,
                                        heightCm: heightCm, minimumPerKg: medicationProteinPerKg)
    }

    /// Protein, carbs and fat that fit inside the calorie target (`MacroSplit`:
    /// fat ≥ 0.7 g/kg, carbs ≥ 2 g/kg when lifting, protein capped to fit;
    /// Helms 2014, Morton 2018). Nil without a goal, weight or calorie target.
    var macroSplit: MacroSplit? {
        guard goals != nil else { return nil }
        return MacroSplit.make(calorieTarget: calorieTarget, bodyMassKg: bodyMassKg, bodyFatPercent: bodyFatPercent,
                               heightCm: heightCm, goals: goals, sex: sex, trainingStatus: trainingStatus,
                               minimumProteinPerKg: medicationProteinPerKg)
    }

    /// Daily protein: the goal's target, lowered when it doesn't leave room for
    /// enough carbs and fat in the calorie target (`macroSplit`).
    var proteinTarget: Double? {
        macroSplit?.proteinGrams ?? proteinTargetUncapped
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
        profile: HeartRateProfile,
        exerciseMinutes: [Date]
    ) async -> [Date: StrainCalculator.Result] {
        let calendar = Calendar.current
        var byDay: [Date: [HeartRateSample]] = [:]
        for sample in heartRate {
            byDay[calendar.startOfDay(for: sample.date), default: []].append(sample)
        }
        var minutesByDay: [Date: [Date]] = [:]
        for minute in exerciseMinutes {
            minutesByDay[calendar.startOfDay(for: minute), default: []].append(minute)
        }
        let calculator = StrainCalculator()
        var results: [Date: StrainCalculator.Result] = [:]
        for day in days {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            results[day] = calculator.dailyStrain(
                heartRate: byDay[day] ?? [],
                strengthSessions: sessions.filter { $0.start >= day && $0.start < next },
                profile: profile,
                movementMinutes: minutesByDay[day] ?? []
            )
        }
        return results
    }

    /// Today's strain target, scaled to what your training days usually reach.
    /// When the 7-day HRV average is below your normal range, it's capped at an
    /// easy day (HRV-guided training).
    var targetStrain: ClosedRange<Double>? {
        guard !restMode, let recovery else { return nil }
        // With a weekly plan, the plan decides the kind of day (rest days aim low).
        if let guidance = dayGuidance {
            return HeatAdvice.adjustTarget(guidance.strainRange, by: heatAdjustment)
        }
        let target = StrainCalculator.targetStrain(forRecovery: recovery.score, usualTrainingStrain: usualTrainingStrain)
        let base = trainEasyToday ? min(target.lowerBound, 20)...min(target.upperBound, 45) : target
        return HeatAdvice.adjustTarget(base, by: heatAdjustment)
    }

    /// HRV-guided training: the 7-day HRV average is below your normal range.
    var trainEasyToday: Bool { recovery?.hrvTrend?.status == .below }

    /// Today's kind of day from the weekly plan, recovery and the last few days
    /// (`TrainingDayPlanner`): a rest day aims low, a missed session moves to
    /// the next free day, and a rest day that turned hard is followed by an
    /// easy one. Nil without a plan this week, in rest mode, or before recovery.
    var dayGuidance: TrainingDayPlanner.Guidance? {
        guard hasWeeklyPlan, !restMode, let recovery else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let past = weekStrain
            .filter { calendar.startOfDay(for: $0.date) < today }
            .map { day in
                let start = calendar.startOfDay(for: day.date)
                // Done or missed from logged sessions and watch workout days, not strain alone.
                return TrainingDayPlanner.PastDay(
                    date: day.date,
                    plannedFocus: plannedFocusByDay[start],
                    strain: day.strain,
                    planKnown: fixedPlanDays.contains(start),
                    trained: loggedSessionDays.contains(start) || recentTrainingDays.contains(start)
                )
            }
        // Flexible week: a quota on any days, no planned day to miss (`TrainingDayPlanner.flexibleGuidance`).
        if let flexibleWeek {
            return TrainingDayPlanner.flexibleGuidance(
                week: flexibleWeek, nextFocus: flexibleNextFocus, past: past,
                lowRecovery: recovery.score < 34 || trainEasyToday,
                usualTrainingStrain: usualTrainingStrain, calendar: calendar
            )
        }
        // Fixed week as a queue: the next session not done yet (`TrainingDayPlanner.adaptiveGuidance`).
        if let adaptiveWeek, calendar.isDate(adaptiveWeek.day, inSameDayAs: today) {
            return TrainingDayPlanner.adaptiveGuidance(
                week: adaptiveWeek, past: past, lowRecovery: recovery.score < 34 || trainEasyToday,
                usualTrainingStrain: usualTrainingStrain, calendar: calendar
            )
        }
        return TrainingDayPlanner.guidance(
            plannedToday: plannedFocusByDay[today],
            past: past,
            lowRecovery: recovery.score < 34 || trainEasyToday,
            usualTrainingStrain: usualTrainingStrain,
            calendar: calendar
        )
    }

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
    ///   - manualHRV: overnight HRV (RMSSD) the user typed in, keyed by morning.
    ///   - morningHRV: camera readings (morning RMSSD), kept apart from overnight HRV.
    func refresh(
        health: HealthKitClient,
        settings: UserSettings,
        sessions: [StrengthSessionSummary],
        manualHRV: [Date: Double] = [:],
        morningHRV: [Date: Double] = [:],
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
            queuedMorningHRV = morningHRV
            return
        }
        isRefreshing = true
        isLoading = true
        defer {
            isRefreshing = false
            isLoading = false
        }
        await performRefresh(health: health, settings: settings, sessions: sessions, manualHRV: manualHRV, morningHRV: morningHRV, now: now)
        while refreshQueued {
            refreshQueued = false
            await performRefresh(health: health, settings: settings, sessions: queuedSessions, manualHRV: queuedManualHRV,
                                 morningHRV: queuedMorningHRV, now: .now)
        }
    }

    private func performRefresh(
        health: HealthKitClient,
        settings: UserSettings,
        sessions: [StrengthSessionSummary],
        manualHRV: [Date: Double],
        morningHRV: [Date: Double],
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
            let fetchedNights = try? await nightsTask
            let nights = fetchedNights ?? []
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

            // One HRV measure for every night (`DailyVitals.resolvingHRV`): overnight
            // RMSSD (Apple Watch beat-to-beat, typed-in Garmin values; typed wins per
            // night) once it covers 14 of the last 30 nights, else Apple Health's SDNN,
            // with gaps filled from the other via your own ratio. Camera readings are
            // taken awake in the morning, so they only stand in when there's no overnight HRV.
            let beatToBeat = await health.nightlyRMSSD(nights: nights)
            let rmssd = beatToBeat.merging(manualHRV.filter { $0.value > 0 }) { _, typed in typed }
            let selection = DailyVitals.resolvingHRV(healthVitals, overnightRMSSD: rmssd, morningHRV: morningHRV,
                                                     today: today, calendar: calendar)
            hrvSelection = selection.metric
            hrvMetric = selection.metric.map { $0 == .sdnn ? "SDNN" : "RMSSD" }
            // [Recovery research] Sleeping heart rate as the resting heart rate, all nights or none
            // (HealthKit RHR as the fallback); see RecoveryCalculator.preferSleepingHeartRate.
            // Once in use it stays until fewer than 10 nights have it, so the baseline doesn't flip.
            let sleepingHeartRate = await health.nightlySleepingHeartRate(nights: nights)
            let previousSource = UserDefaults.standard.string(forKey: Self.rhrSourceKey).flatMap(RestingHeartRateSource.init(rawValue:))
            let (vitals, rhrSource) = RecoveryCalculator.preferSleepingHeartRate(
                selection.vitals,
                sleeping: sleepingHeartRate, minimumNights: recoveryCalculator.minimumBaselineDays + 1,
                current: previousSource, calendar: calendar)
            UserDefaults.standard.set(rhrSource.rawValue, forKey: Self.rhrSourceKey)
            restingHeartRateSource = rhrSource
            // Between midnight and waking, today's "night" is only the evening's
            // HRV before bed: show yesterday's recovery until the night is over.
            let tracksSleep = nights.contains { $0.date >= (calendar.date(byAdding: .day, value: -7, to: today) ?? today) }
            let tonight = self.sleepCalculator.score(samples: sleepSamples)
            let nightOver = RecoveryTiming.nightIsOver(now: now, wake: tonight?.asleepEnd, asleepHours: tonight.map { $0.asleep / 3600 },
                                                       tracksSleep: tracksSleep,
                                                       usualWakeMinutes: BedtimeWindow.usualWakeMinutes(nights.suffix(14).map(\.wake), calendar: calendar),
                                                       calendar: calendar)
            recoveryIsFromYesterday = !nightOver
            let scoredDay = nightOver ? today : yesterday
            // Today's HRV is the typed one when you entered a value for today
            // (typed values replace Health's, see `merging`).
            let typedValues = selection.metric == .morningRMSSD ? morningHRV : manualHRV
            let typedToday = typedValues.contains { calendar.isDate($0.key, inSameDayAs: scoredDay) && $0.value > 0 }
            let todayVitals = vitals.first { calendar.isDate($0.date, inSameDayAs: scoredDay) }
                ?? DailyVitals(date: scoredDay, hrvMilliseconds: nil, restingHeartRate: nil)
            let history = vitals.filter { calendar.startOfDay(for: $0.date) < scoredDay }
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
            // The last 7 days are recomputed: Garmin Connect can sync several days
            // late, and cached days wouldn't see the new heart rate. That per-minute,
            // per-source read is heavy, so in between (every 5 minutes while open)
            // only today and yesterday are read; the full week at most every 30
            // minutes (the app's choice).
            let wideDue = lastWideHeartRateRead.map { now.timeIntervalSince($0) >= 30 * 60 || $0 < yesterday } ?? true
            let recentStart = wideDue ? (calendar.date(byAdding: .day, value: -6, to: today) ?? yesterday) : yesterday
            if wideDue { lastWideHeartRateRead = now }
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
                var sourceSeries: [HeartRateSource] = []
                var heartRateError: String?
                do {
                    sourceSeries = try await health.heartRatePerMinuteBySource(from: firstNeeded, to: now)
                } catch {
                    heartRateError = error.localizedDescription
                    Self.log.error("Heart rate by source failed: \(error.localizedDescription, privacy: .public)")
                }
                if sourceSeries.allSatisfy({ $0.samples.isEmpty }) {
                    do {
                        let combined = try await health.heartRatePerMinute(from: firstNeeded, to: now)
                        sourceSeries = combined.isEmpty ? [] : [HeartRateSource(name: "Apple Health", samples: combined)]
                        if !combined.isEmpty { heartRateError = nil }
                    } catch {
                        heartRateError = heartRateError ?? error.localizedDescription
                        Self.log.error("Heart rate per minute failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                heartRateReadError = heartRateError
                let mergeSources = sourceSeries.map(\.mergeSource)
                let fetchedWorkouts = (try? await health.externalWorkouts(from: firstNeeded, to: now)) ?? []
                workoutDays = workoutDays.filter { $0 < firstNeeded }
                    .union(fetchedWorkouts.map { calendar.startOfDay(for: $0.start) })
                let liftingWindows = sessions.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
                    + fetchedWorkouts.filter(\.isStrength).map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
                let merged = await Self.mergeHeartRate(mergeSources, liftingWindows: liftingWindows)
                let heartRate = merged.samples
                // Learn max heart rate from workouts only (used from the next refresh).
                let workoutWindows = liftingWindows
                    + fetchedWorkouts.filter { !$0.isStrength }.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
                let peak = await Self.workoutPeak(merged, sources: mergeSources, windows: workoutWindows)
                settings.noteHeartRatePeak(peak)
                // Apple Watch exercise minutes fill the gaps between its sparse
                // all-day heart-rate readings (`StrainCalculator.movementReserveFraction`).
                let exerciseMinutes = (try? await health.exerciseMinutes(from: firstNeeded, to: now)) ?? []
                let computed = await Self.computeDays(needed, heartRate: heartRate, sessions: sessions, profile: profile,
                                                      exerciseMinutes: exerciseMinutes)
                for (date, result) in computed {
                    dayCache[date] = (key(for: date), result)
                }
                todaysHeartRate = heartRate.filter { $0.date >= today }
                todaysHeartRateReadings = todaysHeartRate.count
                todaysLightMinutes = profile.lightMinutes(todaysHeartRate)
                todaysDisagreements = merged.disagreements.filter { $0.start >= today }
                // Why a workout day shows no zones: no samples from any source, every minute
                // dropped by the merge, or readings below zone 1 for this profile.
                let todayZones = computed[today]?.zoneMinutes ?? []
                let todayMovement = computed[today]?.movementMinutes ?? 0
                let sourceCounts = sourceSeries.map { "\($0.name): \($0.samples.count)" }.joined(separator: ", ")
                let zoneText = todayZones.map { String(Int($0.rounded())) }.joined(separator: "/")
                let report = "Heart rate since \(firstNeeded.formatted(.iso8601)): sources [\(sourceCounts)], "
                    + "merged \(heartRate.count) min (\(todaysHeartRate.count) today), exercise minutes \(exerciseMinutes.count), "
                    + "profile rest \(Int(profile.restingHeartRate)) max \(Int(profile.maxHeartRate)); "
                    + "today zones Z1-5 [\(zoneText)] min, movement credit \(Int(todayMovement)) min"
                Self.log.info("\(report, privacy: .public)")
            }
            dayCache = dayCache.filter { $0.key >= historyStart }
            let days: [(Date, StrainCalculator.Result)] = allDays.map { ($0, dayCache[$0]?.result ?? .empty) }
            let todayResult = days.last?.1 ?? .empty
            strain = todayResult
            yesterdayStrain = days.first { calendar.isDate($0.0, inSameDayAs: yesterday) }?.1.strain
            weekStrain = days.suffix(7).map { DayStrain(date: $0.0, strain: $0.1.strain) }
            completedWeekStrain = days.dropLast().suffix(7).map { DayStrain(date: $0.0, strain: $0.1.strain) }
            usualTrainingStrain = StrainCalculator.usualTrainingStrain(days.dropLast().map(\.1.strain))
            // A workout (or logged session) and strain at least 35%, not strain alone (`TrainingDayPlanner.isWatchTrainingDay`).
            let sessionDays = Set(sessions.map { calendar.startOfDay(for: $0.start) })
            recentTrainingDays = Set(days.filter { entry in
                TrainingDayPlanner.isWatchTrainingDay(hadWorkout: workoutDays.contains(entry.0) || sessionDays.contains(entry.0), strain: entry.1.strain)
            }.map(\.0))
            let loadCalculator = TrainingLoadCalculator()
            // Completed days only: today isn't over, so it would make this week read low.
            let completeDays = days.dropLast()
            cardioLoad = loadCalculator.evaluate(dailyLoads: completeDays.map(\.1.cardioLoad))
            // Muscular load counts only from the first lift: earlier days are unknown, not rest,
            // so a new user's weeks 2-3 don't read as "much more than usual" (calibrating until 14 days).
            let firstLiftDay = min(loggedSessionDays.min() ?? .distantFuture,
                                   completeDays.first { $0.1.liftingLoad > 0 }?.0 ?? .distantFuture)
            muscularLoad = loadCalculator.evaluate(dailyLoads: completeDays.map(\.1.liftingLoad),
                                                   knownDays: completeDays.filter { $0.0 >= firstLiftDay }.count)

            var sleepCalculator = self.sleepCalculator
            sleepCalculator.baseSleepNeedHours = settings.sleepNeedHours
            sleepCalculator.age = settings.age // [Recovery research] age-scaled deep + REM target
            sleep = sleepCalculator.score(samples: sleepSamples, previousDayStrain: yesterdayStrain, consistency: sleepConsistency)
            // [Recovery research] Sleep is compared with your own last 30 scores; RHR source as above.
            SleepScoreLog.record(sleep?.score, on: today)
            if let fetchedNights {
                await backfillSleepScores(health: health, nights: fetchedNights, calculator: sleepCalculator,
                                          strainByDay: Dictionary(days.map { ($0.0, $0.1.strain) }, uniquingKeysWith: { _, last in last }),
                                          today: today, calendar: calendar)
            }
            // Before the night is over, yesterday's score with yesterday's sleep (`recoveryIsFromYesterday`).
            let scoredSleep = nightOver ? sleep?.score : SleepScoreLog.recentScores(before: today, days: 1).last
            recovery = recoveryCalculator.score(today: todayVitals, history: history, sleepScore: scoredSleep,
                                                sleepScoreHistory: SleepScoreLog.recentScores(before: scoredDay),
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
            age = settings.age

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
            // Loading is ~20 g a day; the dose text is read in grams (`DoseText`), so "120 mg" isn't loading.
            let loading = creatine.map { DoseText.isCreatineLoading($0.dose) } ?? false
            let expected = calories?.projected
            let measured = AdaptiveTDEE.estimate(intake: intake, weights: weights, now: now,
                                                 creatineStart: creatine?.startDate, creatineLoading: loading,
                                                 expectedExpenditure: expected)
            // A maintenance under 1.4× resting metabolism isn't physically believable
            // (FAO/WHO/UNU 2004): the food log is incomplete, so it isn't used
            // (`CalorieSafety`). The watch estimate stands in until it looks complete.
            // Mifflin-St Jeor on purpose (no training status): the athlete equation runs
            // ~200 kcal higher and would reject real but low maintenances in a long cut.
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
            weightTrendWeekly = WeightTrend.weeklyChange(weights.filter { $0.date >= (calendar.date(byAdding: .day, value: -28, to: today) ?? today) })
            lastWeighIn = weights.map(\.date).max()
            // Energy availability: the last 7 logged days against workout calories (`EnergyAvailability`).
            let workoutEnergy = (try? await health.workoutEnergyPerDay(days: 8)) ?? []
            // The lowest safe target for this body and training (`CalorieSafety`, IOC REDs 2023).
            let exercisePerDay = workoutEnergy.filter { $0.date < today }.map(\.value).reduce(0, +) / 7
            calorieMinimum = bodyMassKg.map { weight in
                CalorieSafety.minimumTarget(sex: settings.sex, weightKg: weight, heightCm: heightCm,
                                            bodyFatPercent: bodyFatPercent, exerciseKcalPerDay: exercisePerDay)
            }
            updateWeeklyCalorieTarget(settings: settings, now: now)
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
            energyAvailability = EnergyAvailability.assess(
                days: intake.filter { $0.date >= weekAgo }.map { day in
                    EnergyAvailability.Day(date: day.date, intakeKcal: day.value,
                                           exerciseKcal: workoutEnergy.first { calendar.isDate($0.date, inSameDayAs: day.date) }?.value ?? 0)
                },
                fatFreeMassKg: EnergyAvailability.fatFreeMass(bodyMassKg: bodyMassKg, bodyFatPercent: bodyFatPercent)
            )
            if let nutrients = try? await nutrientTask {
                micronutrients = Micronutrients.assess(averages: nutrients.averages, supplements: SupplementNutrients.dailyAverages(now: now),
                                                       daysLogged: nutrients.daysLogged, sex: settings.sex, age: settings.age)
            }
            let stepResult = try? await stepCounts
            steps = stepResult?.total

            if let bodyMassKg {
                let body = EnergyCalculator.Body(
                    weightKg: bodyMassKg, heightCm: heightCm, age: settings.age,
                    sex: settings.sex, bodyFatPercent: bodyFatPercent,
                    trainingStatus: trainingStatus // ten Haaf for trained 18-35s (calories.md)
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

    // MARK: Sleep score history

    /// Mornings already tried by `backfillSleepScores` (no main sleep to score), so they aren't re-read every refresh.
    @ObservationIgnored private var sleepBackfillTried: Set<Date> = []

    /// Keeps the last week of `SleepScoreLog` in step with Apple Health: a
    /// morning with sleep but no score (the app wasn't opened that day) is
    /// scored now, and a score whose sleep is no longer in Health (deleted) is
    /// dropped. Only after a successful sleep read, and never drops anything
    /// when Health returned no nights at all (a revoked read looks the same).
    private func backfillSleepScores(health: HealthKitClient, nights: [SleepNight], calculator: SleepCalculator,
                                     strainByDay: [Date: Double], today: Date, calendar: Calendar) async {
        guard let windowStart = calendar.date(byAdding: .day, value: -SleepScoreLog.backfillDays, to: today) else { return }
        let tracked = Set(nights.map { calendar.startOfDay(for: $0.date) }.filter { $0 >= windowStart && $0 < today })
        let scored = SleepScoreLog.scoredMornings(from: windowStart, before: today)
        let gone = nights.isEmpty ? [] : Array(scored.subtracting(tracked))
        var added: [Date: Int] = [:]
        for morning in tracked.subtracting(scored).subtracting(sleepBackfillTried).sorted() {
            sleepBackfillTried.insert(morning)
            guard let samples = try? await health.sleepSamples(forNightEnding: morning) else { continue }
            let previous = calendar.date(byAdding: .day, value: -1, to: morning).flatMap { strainByDay[$0] }
            if let score = calculator.score(samples: samples, previousDayStrain: previous, consistency: sleepConsistency)?.score {
                added[morning] = score
            }
        }
        sleepBackfillTried = sleepBackfillTried.filter { $0 >= windowStart }
        if !added.isEmpty || !gone.isEmpty { SleepScoreLog.update(adding: added, removing: gone) }
    }

    // MARK: Weekly calorie target

    /// Keeps the week's target in `UserSettings`: seeded from measured
    /// maintenance and the goal, then moved on Mondays by `CalorieBand`
    /// (at most ±100 kcal, guarded by the 1%/week loss and 0.5%/week gain
    /// limits). Cleared when there's no measured maintenance or goal, so the
    /// target floats with the watch estimate as before.
    private func updateWeeklyCalorieTarget(settings: UserSettings, now: Date) {
        // The rate is held at the personal maximum (`GoalPlanner.maximumWeeklyRate`), so the
        // key below changes, and the target is re-seeded, when that maximum changes.
        guard let maintenance, let goals = personalGoals, let weight = bodyMassKg else {
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
            let workoutHeartRate = heartRate.filter { $0.date >= workout.start && $0.date <= workout.end }
            let load = strainCalculator.dailyStrain(
                heartRate: workoutHeartRate,
                strengthSessions: [], profile: profile
            ).cardioLoad
            var detail = "\(workout.minutes) min"
            if let km = workout.distanceKm, km > 0.1 {
                detail += " · \(km.formatted(.number.precision(.fractionLength(1)))) km"
            }
            // No heart rate (e.g. a Garmin workout synced without it): strain can't
            // be measured, so say so rather than show +0 as if it were easy.
            let noHeartRate = workoutHeartRate.count < 2
            if noHeartRate { detail += " · no heart rate" }
            items.append(ActivityItem(
                id: "w\(workout.uuid.uuidString)",
                name: workout.name, detail: detail, start: workout.start,
                strainAdded: contribution(load), isStrength: workout.isStrength,
                minutes: workout.minutes, noHeartRate: noHeartRate
            ))
        }
        return items.sorted { $0.start < $1.start }
    }
}
