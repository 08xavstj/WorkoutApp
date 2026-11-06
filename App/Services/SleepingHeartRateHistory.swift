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
    ///
    /// Finished nights are kept on disk (`sleepingHeartRateCache`), so a
    /// refresh reads per-minute heart rate only for recent or changed nights:
    /// a value is kept once the night is 2+ days old (a watch app can sync a
    /// day late) and "no data" once it is a week old. Both cut-offs are the app's.
    @concurrent
    func nightlySleepingHeartRate(nights: [SleepNight]) async -> [Date: Double] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let settled = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let settledEmpty = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        // Demo mode (`DemoHealth`) never touches the real cache.
        let useCache = DemoHealth.active == nil
        var known = useCache ? sleepingHeartRateCache.values(for: nights) : [:]
        let toRead = nights.filter { known[$0.date] == nil }
        if let first = toRead.map(\.bedtime).min(), let last = toRead.map(\.wake).max() {
            let samples = ((try? await heartRatePerMinute(from: first, to: last)) ?? []).sorted { $0.date < $1.date }
            var finished: [(night: SleepNight, value: Double?)] = []
            for night in toRead {
                let asleep = samples.filter { $0.date >= night.bedtime && $0.date <= night.wake }.map(\.bpm)
                // ≥ 60 per-minute readings, as in VitalsModel's sleeping heart rate.
                let value: Double? = asleep.count >= 60 ? asleep.reduce(0, +) / Double(asleep.count) : nil
                known[night.date] = .some(value)
                let settledNight = value != nil ? night.date < settled : night.date < settledEmpty
                if settledNight {
                    finished.append((night, value))
                }
            }
            if useCache { sleepingHeartRateCache.store(finished) }
        }
        return known.compactMapValues { $0 }
    }
}
