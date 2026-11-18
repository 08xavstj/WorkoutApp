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

    /// A night's readings run from 6 pm to noon on the morning they are
    /// filed under; later ones (an afternoon reading) aren't the night's.
    /// The window is the app's choice, the one used before the ring was split out.
    public static let nightEndHour = 12

    /// The mean of each night's readings, split by device, for sources that
    /// write many readings a night (the watch's breathing rate) and the
    /// ring's one nightly value. Readings are filed under the morning the
    /// app files nights under (`Oura.morning(of:)`), from 6 pm to noon
    /// (`nightEndHour`).
    public static func nightlyMeans(
        _ readings: [(date: Date, value: Double, device: BaselineDevice)],
        calendar: Calendar = .current
    ) -> (ring: [Date: Double], watch: [Date: Double]) {
        var sums: [BaselineDevice: [Date: (total: Double, count: Int)]] = [:]
        for reading in readings where reading.value.isFinite && reading.value > 0 {
            let morning = Oura.morning(of: reading.date, calendar: calendar)
            let nightEnd = calendar.date(byAdding: .hour, value: nightEndHour, to: morning) ?? morning.addingTimeInterval(Double(nightEndHour) * 3600)
            guard reading.date < nightEnd else { continue }
            let current = sums[reading.device]?[morning] ?? (0, 0)
            sums[reading.device, default: [:]][morning] = (current.total + reading.value, current.count + 1)
        }
        func means(_ device: BaselineDevice) -> [Date: Double] {
            (sums[device] ?? [:]).mapValues { $0.total / Double($0.count) }
        }
        return (means(.ring), means(.watch))
    }

    /// `nightlyMeans` with the source each reading came from (its Apple
    /// Health bundle ID, say). The watch side is one device too: only the
    /// non-ring source with the most nights is kept (`dominantSource`), so
    /// two watches, or a watch and a phone app, are never averaged.
    public static func nightlyMeans(
        _ readings: [(date: Date, value: Double, device: BaselineDevice, source: String)],
        calendar: Calendar = .current
    ) -> (ring: [Date: Double], watch: [Date: Double]) {
        let ring = nightlyMeans(readings.filter { $0.device == .ring }.map { (date: $0.date, value: $0.value, device: $0.device) },
                                calendar: calendar).ring
        var bySource: [String: [Date: Double]] = [:]
        for (source, group) in Dictionary(grouping: readings.filter { $0.device == .watch }, by: { $0.source }) {
            bySource[source] = nightlyMeans(group.map { (date: $0.date, value: $0.value, device: $0.device) }, calendar: calendar).watch
        }
        return (ring, dominantSource(bySource)?.nights ?? [:])
    }

    /// The one source with the most nights, and its nights (ties: the
    /// alphabetically first source, so the pick is the same every time).
    public static func dominantSource(_ bySource: [String: [Date: Double]]) -> (source: String, nights: [Date: Double])? {
        bySource.filter { !$0.value.isEmpty }
            .min { a, b in a.value.count != b.value.count ? a.value.count > b.value.count : a.key < b.key }
            .map { (source: $0.key, nights: $0.value) }
    }

    /// Per-minute readings a night needs before its sleeping heart rate
    /// counts (the Biology tab's rule; the app's choice).
    public static let minimumSleepingReadings = 60

    /// Each non-ring source's sleeping heart rate for one night: the mean of
    /// its per-minute readings between `start` and `end`, once it has
    /// `minimumReadings`, keyed by `HeartRateMerge.Source.identity`. Oura
    /// writes its own 1-minute heart rate to Apple Health
    /// (docs/research/oura-ring-2026-11.md §2); averaging its minutes with
    /// the watch's would mix two devices in one value, so ring sources
    /// (`SleepSource.tracker`) are skipped and the ring's night comes from
    /// its own sleep average instead (`Oura.nightlySleepingHeartRate`).
    /// `oneWatchSource` then keeps one source for the whole window.
    public static func watchSleepingHeartRates(
        _ sources: [HeartRateMerge.Source],
        from start: Date,
        to end: Date,
        minimumReadings: Int = OneDeviceBaseline.minimumSleepingReadings
    ) -> [String: Double] {
        var result: [String: (mean: Double, count: Int)] = [:]
        for source in sources where SleepSource.tracker(bundleID: source.bundleID, sourceName: source.name, deviceModel: nil) != .ring {
            let minutes = source.samples.filter { $0.date >= start && $0.date <= end && $0.bpm > 0 }.map(\.bpm)
            guard minutes.count >= max(1, minimumReadings) else { continue }
            // Two series with one identity (rare) keep the longer one.
            if let current = result[source.identity], current.count >= minutes.count { continue }
            result[source.identity] = (minutes.reduce(0, +) / Double(minutes.count), minutes.count)
        }
        return result.mapValues(\.mean)
    }

    /// One watch source for every night in the window: the source with the
    /// most nights (`dominantSource`), so a night where another source had
    /// more minutes doesn't bring a second device into the baseline.
    public static func oneWatchSource(_ nights: [Date: [String: Double]]) -> [Date: Double] {
        var bySource: [String: [Date: Double]] = [:]
        for (night, values) in nights {
            for (source, value) in values where value.isFinite && value > 0 { bySource[source, default: [:]][night] = value }
        }
        return dominantSource(bySource)?.nights ?? [:]
    }

    /// Only the nights from the `days` mornings ending on `today`, so a
    /// baseline meant to cover 30 nights doesn't reach back into the 120 days
    /// the Oura download keeps.
    public static func recent(_ nights: [Date: Double], days: Int, today: Date, calendar: Calendar = .current) -> [Date: Double] {
        let anchor = calendar.startOfDay(for: today)
        let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: anchor) ?? anchor
        return nights.filter { calendar.startOfDay(for: $0.key) >= start && calendar.startOfDay(for: $0.key) <= anchor }
    }

    /// What `DailyVitals.resolvingHRV` gets, from one device.
    public struct HRVInputs: Sendable, Equatable {
        /// Apple Health's vitals, with their HRV (SDNN) taken out when the ring is used.
        public var vitals: [DailyVitals]
        /// The chosen device's overnight RMSSD by morning.
        public var overnightRMSSD: [Date: Double]
        /// The device whose HRV this is; nil when neither has any.
        public var device: BaselineDevice?
    }

    /// The HRV inputs for `resolvingHRV` from one device. `resolvingHRV`
    /// converts between RMSSD and SDNN to fill gaps, so it must never see
    /// the ring's RMSSD and the watch's SDNN together:
    /// - the watch chosen: Health's vitals as they are, and the watch's RMSSD;
    /// - the ring chosen: the ring's RMSSD with Health's SDNN taken out, unless
    ///   the ring isn't established (`Choice.isEstablished`) and the watch's
    ///   SDNN has more nights in the window (`DailyVitals.hrvWindowNights`),
    ///   in which case only the watch's SDNN is used.
    public static func hrvInputs(_ vitals: [DailyVitals], choice: Choice, today: Date,
                                 calendar: Calendar = .current) -> HRVInputs {
        guard choice.device == .ring else {
            return HRVInputs(vitals: vitals, overnightRMSSD: choice.nights, device: choice.device ?? (vitals.contains { ($0.hrvMilliseconds ?? 0) > 0 } ? .watch : nil))
        }
        let ringOnly = HRVInputs(vitals: DailyVitals.removingHRV(vitals), overnightRMSSD: choice.nights, device: .ring)
        guard !choice.isEstablished else { return ringOnly }
        let anchor = calendar.startOfDay(for: today)
        let start = calendar.date(byAdding: .day, value: -(DailyVitals.hrvWindowNights - 1), to: anchor) ?? anchor
        func inWindow(_ date: Date) -> Bool {
            let night = calendar.startOfDay(for: date)
            return night >= start && night <= anchor
        }
        let ringNights = Set(choice.nights.filter { $0.value > 0 }.keys.filter(inWindow).map { calendar.startOfDay(for: $0) }).count
        let watchNights = Set(vitals.filter { ($0.hrvMilliseconds ?? 0) > 0 && inWindow($0.date) }.map { calendar.startOfDay(for: $0.date) }).count
        return watchNights > ringNights ? HRVInputs(vitals: vitals, overnightRMSSD: [:], device: .watch) : ringOnly
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
