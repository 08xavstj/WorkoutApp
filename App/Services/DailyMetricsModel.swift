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
    /// kg per week from the weight trend.
    private(set) var weightTrendWeekly: Double?
    private(set) var goals: Goals?
    private(set) var sex: BiologicalSex = .male
    private(set) var micronutrients: [Micronutrients.Finding] = []
    private(set) var sleepConsistency: Int?
    private(set) var sleepSpreadMinutes: Double?

    /// Daily calorie target from your goal (or maintenance when no goal is set).
    var calorieTarget: Double? {
        guard let base = maintenance?.maintenance ?? calories?.projected else { return nil }
        guard let goals, let weight = bodyMassKg else { return base }
        return GoalPlanner.calorieTarget(maintenance: base, bodyMassKg: weight, goals: goals, sex: sex)
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

    /// Highest sustained heart rate inside workouts, computed off the main thread.
    @concurrent
    nonisolated private static func workoutPeak(_ heartRate: [HeartRateSample], windows: [DateInterval]) async -> Double? {
        guard !windows.isEmpty else { return nil }
        let inside = heartRate.filter { sample in windows.contains { $0.contains(sample.date) } }
        return ObservedMaxHeartRate.peak(inside)
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
        guard let recovery else { return nil }
        let target = StrainCalculator.targetStrain(forRecovery: recovery.score, usualTrainingStrain: usualTrainingStrain)
        let base = trainEasyToday ? min(target.lowerBound, 20)...min(target.upperBound, 45) : target
        return HeatAdvice.adjustTarget(base, by: heatAdjustment)
    }

    /// HRV-guided training: the 7-day HRV average is below your normal range.
    var trainEasyToday: Bool { recovery?.hrvTrend?.status == .below }

    /// Recovery to plan workouts with (lowered on HRV-guided easy days).
    var recoveryForTraining: Int? {
        guard let score = recovery?.score else { return nil }
        return trainEasyToday ? min(score, 30) : score
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
            async let nightsTask = health.sleepNights(nights: 7)
            let (healthVitals, sleepSamples, externalWorkouts) = try await (vitalsTask, sleepTask, workoutsTask)
            let nights = (try? await nightsTask) ?? []
            sleepConsistency = SleepConsistency.score(nights)
            recentBedtimes = nights.map(\.bedtime)
            sleepSpreadMinutes = SleepConsistency.spreadMinutes(nights)

            // Typed-in Garmin HRV (RMSSD) and Apple Health HRV (SDNN) aren't
            // comparable, so once you enter HRV, only entered values are used.
            let vitals = DailyVitals.merging(healthVitals, manualHRV: manualHRV, manualOnlyHRV: true, calendar: calendar)
            // Today's HRV is the typed one when you entered a value for today
            // (typed values replace Health's, see `merging`).
            let typedToday = manualHRV.contains { calendar.isDate($0.key, inSameDayAs: today) && $0.value > 0 }
            let todayVitals = vitals.first { calendar.isDate($0.date, inSameDayAs: today) }
                ?? DailyVitals(date: today, hrvMilliseconds: nil, restingHeartRate: nil)
            let history = vitals.filter { !calendar.isDate($0.date, inSameDayAs: today) }
            let base = recoveryCalculator.baseline(from: history)
            baseline = base

            restingHeartRate = todayVitals.restingHeartRate
            hrv = todayVitals.hrvMilliseconds
            hrvIsManual = hrv != nil && typedToday
            let profile = settings.heartRateProfile(restingHeartRate: todayVitals.restingHeartRate ?? base.meanRHR)
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
                let heartRate = try await health.heartRatePerMinute(from: firstNeeded, to: now)
                // Learn max heart rate from workouts only (used from the next refresh).
                let fetchedWorkouts = (try? await health.externalWorkouts(from: firstNeeded, to: now)) ?? []
                let workoutWindows = sessions.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
                    + fetchedWorkouts.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
                let peak = await Self.workoutPeak(heartRate, windows: workoutWindows)
                settings.noteHeartRatePeak(peak)
                let computed = await Self.computeDays(needed, heartRate: heartRate, sessions: sessions, profile: profile)
                for (date, result) in computed {
                    dayCache[date] = (key(for: date), result)
                }
                todaysHeartRate = heartRate.filter { $0.date >= today }
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
            cardioLoad = loadCalculator.evaluate(dailyLoads: days.map(\.1.cardioLoad))
            muscularLoad = loadCalculator.evaluate(dailyLoads: days.map(\.1.liftingLoad))

            sleep = sleepCalculator.score(samples: sleepSamples, previousDayStrain: yesterdayStrain, consistency: sleepConsistency)
            recovery = recoveryCalculator.score(today: todayVitals, history: history, sleepScore: sleep?.score)

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
            let intake = ((try? await intakeSeries) ?? []).filter { $0.date < today }.map { DayValue(date: $0.date, value: $0.value) }
            let weights = ((try? await weightSeries) ?? []).map { DayValue(date: $0.date, value: $0.value) }
            maintenance = AdaptiveTDEE.estimate(intake: intake, weights: weights, now: now)
            weightTrendWeekly = WeightTrend.weeklyChange(weights.filter { $0.date >= today.addingTimeInterval(-28 * 86_400) })
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
            items.append(ActivityItem(
                id: "s\(session.start.timeIntervalSince1970)",
                name: session.name ?? "Strength",
                detail: "\(minutes) min · \(session.workingSets) sets",
                start: session.start,
                strainAdded: contribution(load),
                isStrength: true,
                minutes: minutes
            ))
        }
        for workout in external {
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
