import Foundation
import AppCore

nonisolated extension HealthKitClient {
    /// Average heart rate during each night's main sleep, keyed by the morning
    /// it ended, from the watch's per-minute heart rate: any source but the
    /// Oura ring, and one source for every night (`OneDeviceBaseline.oneWatchSource`,
    /// the one with the most nights), so two devices never share a baseline.
    /// Nights with fewer than 60 minutes of readings are left out (the same
    /// rule as the Biology tab's sleeping heart rate).
    ///
    /// With the ring's own nights (`sleepingHeartRate(nights:today:days:)`), this
    /// is the resting heart rate fed to the recovery baseline and the illness
    /// watch, with HealthKit's `restingHeartRate` as the fallback (see
    /// `RecoveryCalculator.preferSleepingHeartRate`): sleep-period heart rate
    /// is steadier than Apple's daytime estimate and is what the illness
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
        // Each night's value per source (empty: read, nothing there).
        var known = useCache ? sleepingHeartRateCache.sourceValues(for: nights) : [:]
        let toRead = nights.filter { known[$0.date] == nil }
        if let first = toRead.map(\.bedtime).min(), let last = toRead.map(\.wake).max() {
            // Per source, so Oura's own minutes in Apple Health are never averaged with the watch's.
            let sources = ((try? await heartRatePerMinuteBySource(from: first, to: last)) ?? []).map(\.mergeSource)
            var finished: [(night: SleepNight, bySource: [String: Double])] = []
            for night in toRead {
                let values = OneDeviceBaseline.watchSleepingHeartRates(sources, from: night.bedtime, to: night.wake)
                known[night.date] = values
                let settledNight = !values.isEmpty ? night.date < settled : night.date < settledEmpty
                if settledNight {
                    finished.append((night: night, bySource: values))
                }
            }
            if useCache { sleepingHeartRateCache.storeSourceValues(finished) }
        }
        return OneDeviceBaseline.oneWatchSource(known)
    }

    /// Sleeping heart rate from one device (`OneDeviceBaseline`): the Oura
    /// ring's average sleeping heart rate (direct link, `OuraCache`) when it
    /// carries the baseline, else the watch's (`nightlySleepingHeartRate`).
    /// The ring is first because its nocturnal heart rate agreed with ECG at
    /// CCC 0.98 (Dial et al., Physiol Rep 2025), against a 3.7 bpm mean error
    /// for Apple Watch resting heart rate (O'Grady et al., Sensors 2024).
    ///
    /// - Parameter days: the baseline's window; the ring's nights are cut to
    ///   it (`OneDeviceBaseline.recent`), as the watch's are by `nights`, so
    ///   up to 120 days of Oura download don't fill a 30-night baseline or
    ///   meet its 15-night threshold with old nights.
    @concurrent
    func sleepingHeartRate(nights: [SleepNight], today: Date, days: Int) async -> OneDeviceBaseline.Choice {
        let ring = DemoHealth.active == nil
            ? OneDeviceBaseline.recent(OuraCache.shared.nightlySleepingHeartRate(), days: days, today: today) : [:]
        return OneDeviceBaseline.choose(ring: ring, watch: await nightlySleepingHeartRate(nights: nights), latest: today)
    }

    /// Overnight HRV (RMSSD) from one device (`OneDeviceBaseline`): the Oura
    /// ring's night average (direct link, whatever the sleep-source setting)
    /// when it carries the baseline, else the watch's (`nightlyRMSSD`). Oura
    /// Gen 4 agreed with ECG at CCC 0.99, MAPE 6.0% (Dial et al., Physiol Rep
    /// 2025); Apple Watch HRV (SDNN) was off by a mean 29% against a chest
    /// strap (O'Grady et al., Sensors 2024). Oura doesn't write HRV to Apple
    /// Health, so the ring's nights come only from the direct link.
    ///
    /// - Parameter days: the baseline's window; the ring's nights are cut to
    ///   it (`OneDeviceBaseline.recent`), as the watch's are by `nights`.
    @concurrent
    func overnightRMSSD(nights: [SleepNight], today: Date, days: Int) async -> OneDeviceBaseline.Choice {
        let ring = DemoHealth.active == nil ? OneDeviceBaseline.recent(OuraCache.shared.nightlyRMSSD(), days: days, today: today) : [:]
        return OneDeviceBaseline.choose(ring: ring, watch: await nightlyRMSSD(nights: nights), latest: today)
    }
}
