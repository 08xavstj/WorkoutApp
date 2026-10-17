import Foundation
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
    private(set) var cardioLoad: TrainingLoadCalculator.Result?
    private(set) var muscularLoad: TrainingLoadCalculator.Result?
    private(set) var activities: [ActivityItem] = []
    private(set) var nutritionToday: NutritionDay?
    private(set) var nutritionYesterday: NutritionDay?
    private(set) var bodyMassKg: Double?
    private(set) var energy: EnergyCalculator.Result?
    private(set) var steps: Double?
    private(set) var heartRateProfile: HeartRateProfile?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?

    @ObservationIgnored private let strainCalculator = StrainCalculator()
    @ObservationIgnored private let recoveryCalculator = RecoveryCalculator()
    @ObservationIgnored private let sleepCalculator = SleepCalculator()

    var proteinTarget: Double? { NutritionTargets.proteinGrams(bodyMassKg: bodyMassKg) }

    var targetStrain: ClosedRange<Double>? {
        recovery.map { StrainCalculator.targetStrain(forRecovery: $0.score) }
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
        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let historyStart = calendar.date(byAdding: .day, value: -27, to: today) ?? today

        do {
            async let vitalsTask = health.nightlyVitals(days: 31, endingOn: today)
            async let sleepTask = health.sleepSamples(forNightEnding: today)
            async let heartRateTask = health.heartRateSamples(from: historyStart, to: now)
            async let workoutsTask = health.externalWorkouts(from: today, to: now)
            let (healthVitals, sleepSamples, heartRate, externalWorkouts) = try await (vitalsTask, sleepTask, heartRateTask, workoutsTask)

            let vitals = DailyVitals.merging(healthVitals, manualHRV: manualHRV, calendar: calendar)
            let healthHadHRVToday = healthVitals.contains {
                calendar.isDate($0.date, inSameDayAs: today) && $0.hrvMilliseconds != nil
            }
            let todayVitals = vitals.first { calendar.isDate($0.date, inSameDayAs: today) }
                ?? DailyVitals(date: today, hrvMilliseconds: nil, restingHeartRate: nil)
            let history = vitals.filter { !calendar.isDate($0.date, inSameDayAs: today) }
            let base = recoveryCalculator.baseline(from: history)
            baseline = base

            restingHeartRate = todayVitals.restingHeartRate
            hrv = todayVitals.hrvMilliseconds
            hrvIsManual = hrv != nil && !healthHadHRVToday
            let profile = settings.heartRateProfile(restingHeartRate: todayVitals.restingHeartRate ?? base.meanRHR)
            heartRateProfile = profile

            // Strain for each of the last 28 days (today last).
            var byDay: [Date: [HeartRateSample]] = [:]
            for sample in heartRate {
                byDay[calendar.startOfDay(for: sample.date), default: []].append(sample)
            }
            var days: [(Date, StrainCalculator.Result)] = []
            var day = historyStart
            while day <= today {
                let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
                let result = strainCalculator.dailyStrain(
                    heartRate: byDay[day] ?? [],
                    strengthSessions: sessions.filter { $0.start >= day && $0.start < next },
                    profile: profile
                )
                days.append((day, result))
                day = next
            }
            let todayResult = days.last?.1 ?? .empty
            strain = todayResult
            yesterdayStrain = days.first { calendar.isDate($0.0, inSameDayAs: yesterday) }?.1.strain
            weekStrain = days.suffix(7).map { DayStrain(date: $0.0, strain: $0.1.strain) }
            let loadCalculator = TrainingLoadCalculator()
            cardioLoad = loadCalculator.evaluate(dailyLoads: days.map(\.1.cardioLoad))
            muscularLoad = loadCalculator.evaluate(dailyLoads: days.map(\.1.liftingLoad))

            sleep = sleepCalculator.score(samples: sleepSamples, previousDayStrain: yesterdayStrain)
            recovery = recoveryCalculator.score(today: todayVitals, history: history, sleepScore: sleep?.score)

            // Today's activities: logged lifts plus workouts from other apps.
            let todaysHR = byDay[today] ?? []
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
            let windows = todaysSessions.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
                + externalWorkouts.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
            async let stepCounts = health.steps(from: today, to: now, excluding: windows)

            nutritionToday = try? await todayFood
            nutritionYesterday = try? await yesterdayFood
            let healthWeight = try? await weight
            bodyMassKg = healthWeight ?? (settings.weightKg > 0 ? settings.weightKg : nil)
            let heightCm = (try? await height) ?? (settings.heightCm > 0 ? settings.heightCm : nil)
            let bodyFatPercent = (try? await bodyFat).map { $0 * 100 }
            respiratoryRate = try? await respiratory
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
                    dayStart: today, now: now
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
                isStrength: true
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
                id: "w\(workout.start.timeIntervalSince1970)",
                name: workout.name, detail: detail, start: workout.start,
                strainAdded: contribution(load), isStrength: workout.isStrength
            ))
        }
        return items.sorted { $0.start < $1.start }
    }
}
