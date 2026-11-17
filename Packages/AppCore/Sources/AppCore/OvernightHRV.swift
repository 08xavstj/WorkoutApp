import Foundation

/// One heart-rate-variability reading from a watch (Apple Health's SDNN or
/// RMSSD), in milliseconds.
public struct OvernightReading: Sendable, Equatable {
    public var date: Date
    public var milliseconds: Double

    public init(date: Date, milliseconds: Double) {
        self.date = date
        self.milliseconds = milliseconds
    }
}

/// One value per night from a watch's HRV readings: the mean of the readings
/// taken inside that night's main sleep.
///
/// Why inside sleep, and not a clock window: Apple Watch Series 12 and Ultra 4
/// take an HRV reading as often as every five minutes, all day ("24x more
/// frequently"; Apple Newsroom, "Introducing Apple Watch Series 12", 9 Sep
/// 2026). Earlier watches took one every few hours, so an evening-to-noon
/// window was nearly all sleep. With the dense readings the same window holds
/// hours of awake readings, and HRV awake is lower and follows posture, meals
/// and movement, so the night's number would drop on the day the watch changed
/// with nothing changed in the wearer.
///
/// Research: nocturnal HRV averaged over the sleep period is the form with
/// published reliability for following training load (Nuuttila et al., Int J
/// Sports Physiol Perform 2022;17(8):1296-1303), and five-minute segments
/// averaged over the night agree with ECG (Kinnunen et al., Physiol Meas
/// 2020;41(4):04NT01, a ring against medical-grade ECG). Neither study used an
/// Apple Watch; Apple has not published how its "Recovery HRV" is computed.
public enum OvernightHRV {
    /// One night's main sleep, keyed by the morning it ended.
    public struct Night: Sendable, Equatable {
        public var date: Date
        public var bedtime: Date
        public var wake: Date

        public init(date: Date, bedtime: Date, wake: Date) {
            self.date = date
            self.bedtime = bedtime
            self.wake = wake
        }
    }

    /// Fewest in-sleep readings for a night's RMSSD (app's choice, not
    /// research: the same count the beat-to-beat estimate needs).
    public static let minimumReadings = 3

    /// The most beat-to-beat recordings read per night (app's choice, for
    /// speed: a Series 12 may store one every five minutes, and the night's
    /// median barely moves past a few dozen).
    public static let maximumRecordingsPerNight = 36

    /// The mean of the readings inside each night's main sleep, keyed by the
    /// night's date. Nights with fewer than `minimumReadings` are left out.
    public static func nightly(
        _ readings: [OvernightReading],
        nights: [Night],
        minimumReadings: Int = OvernightHRV.minimumReadings
    ) -> [Date: Double] {
        let ordered = nights.filter { $0.wake > $0.bedtime }.sorted { $0.bedtime < $1.bedtime }
        guard !ordered.isEmpty else { return [:] }
        var sums: [Date: (total: Double, count: Int)] = [:]
        for reading in readings where reading.milliseconds > 0 && reading.milliseconds.isFinite {
            // The last night that had started by this reading (binary search).
            var low = 0
            var high = ordered.count
            while low < high {
                let middle = (low + high) / 2
                if ordered[middle].bedtime <= reading.date { low = middle + 1 } else { high = middle }
            }
            guard low > 0 else { continue }
            let night = ordered[low - 1]
            guard reading.date <= night.wake else { continue }
            let current = sums[night.date] ?? (0, 0)
            sums[night.date] = (current.total + reading.milliseconds, current.count + 1)
        }
        var result: [Date: Double] = [:]
        for (date, sum) in sums where sum.count >= max(1, minimumReadings) {
            result[date] = sum.total / Double(sum.count)
        }
        return result
    }

    /// Most readings a night's evening-to-noon window may hold and still be
    /// used when none fell inside the sleep. Older watches take a few a night,
    /// nearly all asleep; a Series 12 takes about 200 in that window, most of
    /// them awake (the watch worn in the evening and morning, charged
    /// overnight). Past this the night has no HRV rather than an awake one.
    /// App's choice: twice the most an older watch was seen to take.
    public static let maximumWindowReadings = 12

    /// Like `nightly`, for a type whose cadence Apple hasn't documented
    /// (Health's RMSSD, iOS 27): a night with fewer than `minimumReadings`
    /// inside the sleep still gets a value from the one or two readings
    /// timed from bedtime to `wakeGrace` after waking, in case the watch
    /// writes one summary per night, stamped at or just after wake.
    /// The hour is the app's choice.
    public static func nightlyAllowingSummaries(
        _ readings: [OvernightReading],
        nights: [Night],
        minimumReadings: Int = OvernightHRV.minimumReadings,
        wakeGrace: TimeInterval = 3600
    ) -> [Date: Double] {
        var result = nightly(readings, nights: nights, minimumReadings: minimumReadings)
        let widened = nights.map { Night(date: $0.date, bedtime: $0.bedtime, wake: $0.wake.addingTimeInterval(max(0, wakeGrace))) }
        for (date, value) in nightly(readings, nights: widened, minimumReadings: 1) where result[date] == nil {
            result[date] = value
        }
        return result
    }

    /// `vitals` with each night's HRV replaced by its in-sleep value where
    /// there is one. A night without one keeps the value it had (no sleep
    /// recorded, or no reading inside it), so no night is lost, unless its
    /// window held more than `maximumWindowReadings` readings
    /// (`windowCounts`): then most of them were taken awake and the night's
    /// HRV is left empty.
    public static func preferringSleep(
        _ vitals: [DailyVitals],
        asleep: [Date: Double],
        windowCounts: [Date: Int] = [:],
        calendar: Calendar = .current
    ) -> [DailyVitals] {
        var counts: [Date: Int] = [:]
        for (date, count) in windowCounts { counts[calendar.startOfDay(for: date), default: 0] += count }
        let vitals = vitals.map { vital -> DailyVitals in
            let day = calendar.startOfDay(for: vital.date)
            guard !asleep.keys.contains(where: { calendar.isDate($0, inSameDayAs: day) }),
                  (counts[day] ?? 0) > maximumWindowReadings else { return vital }
            var changed = vital
            changed.hrvMilliseconds = nil
            return changed
        }
        guard !asleep.isEmpty else { return vitals }
        var byDay: [Date: Double] = [:]
        for (date, value) in asleep where value > 0 && value.isFinite {
            byDay[calendar.startOfDay(for: date)] = value
        }
        var seen: Set<Date> = []
        var result = vitals.map { vital -> DailyVitals in
            let day = calendar.startOfDay(for: vital.date)
            seen.insert(day)
            guard let value = byDay[day] else { return vital }
            var changed = vital
            changed.hrvMilliseconds = value
            return changed
        }
        // A night with sleep and readings that the clock window missed (a day sleeper).
        for (day, value) in byDay where !seen.contains(day) {
            result.append(DailyVitals(date: day, hrvMilliseconds: value, restingHeartRate: nil))
        }
        return result.sorted { $0.date > $1.date }
    }

    /// At most `limit` of `items`, spread evenly from first to last, in order.
    public static func evenlySpaced<Item>(_ items: [Item], limit: Int) -> [Item] {
        guard limit > 0 else { return [] }
        guard items.count > limit else { return items }
        guard limit > 1 else { return [items[0]] }
        let step = Double(items.count - 1) / Double(limit - 1)
        return (0..<limit).map { items[Int((Double($0) * step).rounded())] }
    }
}
