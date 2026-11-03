import Foundation
import AppCore

nonisolated extension HealthKitClient {
    /// Average heart rate during each night's main sleep, keyed by the morning
    /// it ended, from per-minute heart rate. Nights with fewer than 60 minutes
    /// of readings are left out (the same rule as the Biology tab's sleeping
    /// heart rate).
    ///
    /// This is the resting heart rate fed to the recovery baseline and the
    /// illness watch, with HealthKit's `restingHeartRate` as the fallback
    /// (see `RecoveryCalculator.preferSleepingHeartRate`): sleep-period heart
    /// rate is steadier than Apple's daytime estimate and is what the illness
    /// studies used (Mishra et al., Nat Biomed Eng 2020; Natarajan et al., npj
    /// Digit Med 2020).
    @concurrent
    func nightlySleepingHeartRate(nights: [SleepNight]) async -> [Date: Double] {
        guard let first = nights.map(\.bedtime).min(), let last = nights.map(\.wake).max() else { return [:] }
        let samples = ((try? await heartRatePerMinute(from: first, to: last)) ?? []).sorted { $0.date < $1.date }
        var result: [Date: Double] = [:]
        for night in nights {
            let asleep = samples.filter { $0.date >= night.bedtime && $0.date <= night.wake }.map(\.bpm)
            // ≥ 60 per-minute readings, as in VitalsModel's sleeping heart rate.
            if asleep.count >= 60 {
                result[night.date] = asleep.reduce(0, +) / Double(asleep.count)
            }
        }
        return result
    }
}
