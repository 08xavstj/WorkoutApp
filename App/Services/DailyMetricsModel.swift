import Foundation
import AppCore

/// Loads today's data from Apple Health, combines it with logged gym sessions,
/// and computes strain, recovery and sleep.
@Observable
final class DailyMetricsModel {
    private(set) var strain: StrainCalculator.Result?
    private(set) var recovery: RecoveryCalculator.Result?
    private(set) var sleep: SleepCalculator.Result?
    private(set) var restingHeartRate: Double?
    private(set) var hrv: Double?
    /// True when today's HRV came from a manual entry rather than Apple Health.
    private(set) var hrvIsManual = false
    private(set) var yesterdayStrain: Double?
    private(set) var nutritionToday: NutritionDay?
    private(set) var nutritionYesterday: NutritionDay?
    private(set) var bodyMassKg: Double?

    var proteinTarget: Double? { NutritionTargets.proteinGrams(bodyMassKg: bodyMassKg) }
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastUpdated: Date?

    @ObservationIgnored private let strainCalculator = StrainCalculator()
    @ObservationIgnored private let recoveryCalculator = RecoveryCalculator()
    @ObservationIgnored private let sleepCalculator = SleepCalculator()

    var targetStrain: ClosedRange<Double>? {
        recovery.map { StrainCalculator.targetStrain(forRecovery: $0.score) }
    }

    /// - Parameter sessions: gym sessions from roughly the last two days.
    /// - Parameter manualHRV: HRV the user typed in, keyed by morning.
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

        do {
            async let vitalsTask = health.nightlyVitals(days: 31, endingOn: today)
            async let sleepTask = health.sleepSamples(forNightEnding: today)
            async let heartRateTask = health.heartRateSamples(from: yesterday, to: now)
            let (healthVitals, sleepSamples, heartRate) = try await (vitalsTask, sleepTask, heartRateTask)
            let vitals = DailyVitals.merging(healthVitals, manualHRV: manualHRV, calendar: calendar)
            let healthHadHRVToday = healthVitals.contains {
                calendar.isDate($0.date, inSameDayAs: today) && $0.hrvMilliseconds != nil
            }

            let todayVitals = vitals.first { calendar.isDate($0.date, inSameDayAs: today) }
                ?? DailyVitals(date: today, hrvMilliseconds: nil, restingHeartRate: nil)
            let history = vitals.filter { !calendar.isDate($0.date, inSameDayAs: today) }
            let baseline = recoveryCalculator.baseline(from: history)

            restingHeartRate = todayVitals.restingHeartRate
            hrv = todayVitals.hrvMilliseconds
            hrvIsManual = hrv != nil && !healthHadHRVToday
            let profile = settings.heartRateProfile(restingHeartRate: todayVitals.restingHeartRate ?? baseline.meanRHR)

            let yesterdayResult = strainCalculator.dailyStrain(
                heartRate: heartRate.filter { $0.date < today },
                strengthSessions: sessions.filter { $0.start >= yesterday && $0.start < today },
                profile: profile
            )
            yesterdayStrain = yesterdayResult.strain

            strain = strainCalculator.dailyStrain(
                heartRate: heartRate.filter { $0.date >= today },
                strengthSessions: sessions.filter { $0.start >= today },
                profile: profile
            )

            sleep = sleepCalculator.score(samples: sleepSamples, previousDayStrain: yesterdayResult.strain)
            recovery = recoveryCalculator.score(today: todayVitals, history: history, sleepScore: sleep?.score)

            // Food data (e.g. from Cronometer). Missing nutrition shouldn't block the other scores.
            async let todayFood = health.nutrition(on: today)
            async let yesterdayFood = health.nutrition(on: yesterday)
            async let weight = health.latestBodyMassKg()
            nutritionToday = try? await todayFood
            nutritionYesterday = try? await yesterdayFood
            bodyMassKg = try? await weight

            errorMessage = nil
            lastUpdated = now
        } catch {
            errorMessage = "Couldn't read Apple Health: \(error.localizedDescription)"
        }
    }
}
