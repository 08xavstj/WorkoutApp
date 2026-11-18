import Foundation

/// The wearable a personal baseline is built from, when an Oura ring and an
/// Apple Watch both measure the night.
public enum BaselineDevice: String, Sendable, Codable, Equatable {
    /// An Oura ring (its Apple Health samples or the direct link's download).
    case ring
    /// Apple Watch, or any other source that isn't the ring.
    case watch
}

/// One device per baseline, for overnight HRV, sleeping heart rate and
/// breathing rate.
///
/// Why the ring comes first: in the one independent study that checked both
/// against ECG over many nights, Oura Gen 4 agreed with ECG at CCC 0.99 for
/// overnight RMSSD (MAPE 6.0%) and 0.98 for nocturnal resting heart rate
/// (MAPE 1.9%) (Dial et al., Physiol Rep 2025;13(16):e70527; 13 adults, 536
/// nights, no industry funding). Apple Watch morning HRV (SDNN) was off by a
/// mean 29% against a chest strap and RHR by 3.7 bpm (O'Grady et al., Sensors
/// 2024). See docs/research/oura-ring-2026-11.md §5-7.
///
/// Why never mix: the same night reads differently on two devices (a ring
/// averages the whole sleep, a watch a few recordings), so a baseline built
/// from both reads a device switch as a change in the body. Each day's
/// baseline therefore comes from one device only:
///
/// 1. The device that has the newest night is tried first (the ring on a tie),
///    so today is compared with the same device's history.
/// 2. A device is used only once it has `minimumNights` of the last
///    `windowNights` (the recovery baseline's 14 of 30, `RecoveryCalculator`);
///    otherwise the other one is tried.
/// 3. If neither has that many, the one with more nights in the window is
///    used (the ring on a tie).
///
/// So a night without the ring (or before Oura has synced) is scored against
/// the watch's own baseline, and the ring takes over again with the next
/// night it has. The rule is the app's; the device order follows the
/// evidence above.
public enum OneDeviceBaseline {
    /// The recovery baseline's window (`RecoveryCalculator.baselineDays`).
    public static let windowNights = 30
    /// Nights a device needs in the window before it carries the baseline
    /// (`RecoveryCalculator.minimumBaselineDays`).
    public static let minimumNights = 14

    public struct Choice: Sendable, Equatable {
        /// The device used, nil when neither has a night.
        public var device: BaselineDevice?
        /// That device's nights only, keyed by the morning.
        public var nights: [Date: Double]
        /// True when the device has `minimumNights` in the window.
        public var isEstablished: Bool

        public init(device: BaselineDevice?, nights: [Date: Double], isEstablished: Bool) {
            self.device = device
            self.nights = nights
            self.isEstablished = isEstablished
        }
    }

    /// - Parameters:
    ///   - ring: the ring's value by morning.
    ///   - watch: the watch's (or any non-ring source's) value by morning.
    ///   - latest: the newest morning that counts (today); later nights are dropped.
    public static func choose(
        ring: [Date: Double],
        watch: [Date: Double],
        latest: Date,
        windowNights: Int = OneDeviceBaseline.windowNights,
        minimumNights: Int = OneDeviceBaseline.minimumNights,
        calendar: Calendar = .current
    ) -> Choice {
        let anchor = calendar.startOfDay(for: latest)
        func byMorning(_ values: [Date: Double]) -> [Date: Double] {
            var result: [Date: Double] = [:]
            // Oldest first, so with two values on one morning the later one wins every time.
            for (date, value) in values.sorted(by: { $0.key < $1.key }) where value.isFinite && value > 0 {
                let morning = calendar.startOfDay(for: date)
                if morning <= anchor { result[morning] = value }
            }
            return result
        }
        let devices: [(device: BaselineDevice, nights: [Date: Double])] = [(.ring, byMorning(ring)), (.watch, byMorning(watch))]
        let windowStart = calendar.date(byAdding: .day, value: -(windowNights - 1), to: anchor) ?? anchor
        func recent(_ nights: [Date: Double]) -> Int { nights.keys.filter { $0 >= windowStart }.count }

        guard let newest = devices.flatMap({ $0.nights.keys }).max() else {
            return Choice(device: nil, nights: [:], isEstablished: false)
        }
        // Devices with the newest night first; the ring first otherwise (a stable sort keeps the order).
        let ordered = devices.filter { $0.nights[newest] != nil } + devices.filter { $0.nights[newest] == nil }
        if let established = ordered.first(where: { recent($0.nights) >= minimumNights }) {
            return Choice(device: established.device, nights: established.nights, isEstablished: true)
        }
        let ringCount = recent(devices[0].nights)
        let watchCount = recent(devices[1].nights)
        let pick = ringCount >= watchCount && !devices[0].nights.isEmpty ? devices[0] : devices[1]
        return Choice(device: pick.nights.isEmpty ? nil : pick.device, nights: pick.nights, isEstablished: false)
    }

    /// The mean of each night's readings, split by device, for sources that
    /// write many readings a night (the watch's breathing rate) and the
    /// ring's one nightly value. Readings are filed under the morning the
    /// app files nights under (`Oura.morning(of:)`).
    public static func nightlyMeans(
        _ readings: [(date: Date, value: Double, device: BaselineDevice)],
        calendar: Calendar = .current
    ) -> (ring: [Date: Double], watch: [Date: Double]) {
        var sums: [BaselineDevice: [Date: (total: Double, count: Int)]] = [:]
        for reading in readings where reading.value.isFinite && reading.value > 0 {
            let morning = Oura.morning(of: reading.date, calendar: calendar)
            let current = sums[reading.device]?[morning] ?? (0, 0)
            sums[reading.device, default: [:]][morning] = (current.total + reading.value, current.count + 1)
        }
        func means(_ device: BaselineDevice) -> [Date: Double] {
            (sums[device] ?? [:]).mapValues { $0.total / Double($0.count) }
        }
        return (means(.ring), means(.watch))
    }

    /// Per-minute readings a night needs before its sleeping heart rate
    /// counts (the Biology tab's rule; the app's choice).
    public static let minimumSleepingReadings = 60

    /// The watch's sleeping heart rate for one night: the mean of the
    /// per-minute readings between `start` and `end` from the one source,
    /// other than the ring, with the most readings there, once it has
    /// `minimumReadings`. Oura writes its own 1-minute heart rate to Apple
    /// Health (docs/research/oura-ring-2026-11.md §2); averaging its minutes
    /// with the watch's would mix two devices in one value, so ring sources
    /// (`SleepSource.tracker`) are skipped and the ring's night comes from
    /// its own sleep average instead (`Oura.nightlySleepingHeartRate`).
    public static func watchSleepingHeartRate(
        _ sources: [HeartRateMerge.Source],
        from start: Date,
        to end: Date,
        minimumReadings: Int = OneDeviceBaseline.minimumSleepingReadings
    ) -> Double? {
        let candidates = sources
            .filter { SleepSource.tracker(bundleID: nil, sourceName: $0.name, deviceModel: nil) != .ring }
            .map { source in source.samples.filter { $0.date >= start && $0.date <= end && $0.bpm > 0 }.map(\.bpm) }
            .filter { $0.count >= max(1, minimumReadings) }
        guard let best = candidates.max(by: { $0.count < $1.count }) else { return nil }
        return best.reduce(0, +) / Double(best.count)
    }
}

extension DailyVitals {
    /// The vitals with Apple Health's HRV (SDNN) taken out, for when the
    /// ring's overnight RMSSD carries the HRV baseline: otherwise
    /// `resolvingHRV` would fill the ring's missing nights with the watch's
    /// SDNN scaled by a ratio, mixing two devices in one baseline
    /// (`OneDeviceBaseline`). Resting heart rate is kept.
    public static func removingHRV(_ vitals: [DailyVitals]) -> [DailyVitals] {
        vitals.map { DailyVitals(date: $0.date, hrvMilliseconds: nil, restingHeartRate: $0.restingHeartRate) }
    }
}

/// Workouts two devices recorded at the same time.
public enum WorkoutOverlap {
    /// A ring workout is a duplicate when another source's workout covers at
    /// least this share of the shorter of the two. The share is the app's
    /// choice; any real overlap between an auto-detected workout and a
    /// recorded one is almost always the same exercise.
    public static let duplicateShare = 0.5

    /// The workouts without the ring's ones that another source also
    /// recorded. Oura auto-detects workouts from motion and heart rate and
    /// writes them to Apple Health; a watch records the same session, so
    /// counting both doubles its calories. The watch's recording is kept:
    /// it measures heart rate during exercise, where the ring has no published
    /// validation (docs/research/oura-ring-2026-11.md §5, "Workouts").
    /// Order is kept.
    public static func removingRingDuplicates<Workout>(
        _ workouts: [Workout],
        isRing: (Workout) -> Bool,
        interval: (Workout) -> DateInterval
    ) -> [Workout] {
        let others = workouts.filter { !isRing($0) }.map(interval)
        guard !others.isEmpty else { return workouts }
        return workouts.filter { workout in
            guard isRing(workout) else { return true }
            let own = interval(workout)
            return !others.contains { other in
                guard let shared = own.intersection(with: other) else { return false }
                let shorter = min(own.duration, other.duration)
                return shorter > 0 ? shared.duration / shorter >= duplicateShare : own.start == other.start
            }
        }
    }
}
