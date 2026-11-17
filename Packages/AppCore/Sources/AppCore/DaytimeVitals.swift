import Foundation

/// Vitals while awake: the daytime counterpart of the overnight numbers
/// (`OvernightHRV`, `SleepingHeartRate`). One day's heart rate, HRV and blood
/// oxygen from the minutes the wearer was awake and still, each compared with
/// the same hours of their own previous four weeks.
///
/// Why this exists: an Apple Watch Series 12 records heart rate every five
/// seconds and HRV as often as every five minutes all day, and Apple's own
/// Vitals app shows a daytime view beside the overnight one (Apple Newsroom, 9
/// Sep 2026, as recorded in docs/research/watch-features.md §6; not
/// re-verified here). Apple offers no API for that view, only the readings.
///
/// What it is not: a stress score. A 2025 systematic review judged wearable
/// stress algorithms built on daytime HRV to have poor accuracy and
/// reliability (Shterev 2025, watch-features.md [B20]). Daytime heart rate and
/// HRV move with posture, meals, caffeine, movement and the time of day
/// (Laborde, Mosley & Thayer, Front Psychol 2017;8:213, who ask for no meal or
/// caffeine in the 2 h before a recording, 5 minutes in one posture, and the
/// same time of day on every occasion). A free-living watch controls none of
/// the first three, so the output is a description ("inside or outside your
/// usual range"), never a verdict, and it is always a whole-day centre, never
/// one reading.
///
/// The work is in two steps so finished days can be cached: `day` reduces a
/// day's raw readings to 24 hourly buckets (`Day`, Codable), and `summary`
/// compares one `Day` with the `Day`s before it.
public enum DaytimeVitals {
    // MARK: - Rules and constants

    /// Minutes after a workout ends that do not count as rest. In trained (not
    /// elite) runners HRV was back to its pre-exercise level only 90 minutes or
    /// more after an interval session; in highly trained runners after about 30
    /// (Seiler, Haugen & Kuffel, Med Sci Sports Exerc 2007;39(8):1366-73,
    /// abstract). Endurance exercise only: nothing comparable was found for
    /// lifting, so the same margin is used for it (app's choice). Full
    /// autonomic recovery after a hard session can take 24-48 h (Stanley, Peake
    /// & Buchheit, Sports Med 2013;43:1259-77; not re-verified here), which no
    /// margin covers: a lower evening HRV after a hard session is expected,
    /// and the screen says so.
    public static let workoutRecoveryMinutes = 90.0

    /// Minutes after a minute the watch counted as exercise (about a brisk walk
    /// or harder) that do not count as rest. Exercise below the first
    /// ventilatory threshold disturbs autonomic balance little (Seiler 2007,
    /// abstract); the 10 minutes itself is the app's choice.
    public static let exerciseSettleMinutes = 10.0

    /// Minutes after a minute of walking that do not count as rest. Heart rate
    /// settled in most of 433 adults after 4 minutes of inactivity (Speed et
    /// al., PLOS Digit Health 2023;2(4):e0000236), and HRV recordings ask for 5
    /// minutes in one posture first (Laborde 2017). Rounded up to 5.
    public static let settleMinutes = 5.0

    /// Steps in one minute from which the minute counts as moving. 1-19
    /// steps/min is "incidental" stepping and 20-39 "sporadic" in the cadence
    /// bands of Tudor-Locke et al. (Br J Sports Med 2018;52:776-88; the bands
    /// were checked, the page numbers not), so 20 is the first band that is
    /// more than shifting in a chair.
    public static let movingStepsPerMinute = 20.0

    /// Where "resting while awake" sits among the day's still minutes: the
    /// 10th percentile (app's choice, not research). The lowest minute is what
    /// Speed 2023 used, but a minimum falls the longer the watch is worn and
    /// one bad reading or an unrecorded nap sets it; the median is the typical
    /// sitting heart rate, coffee and meetings included. A low percentile is
    /// the level the heart rate settles to when the wearer is calm, and it
    /// does not depend on how many minutes there are.
    public static let restingPercentile = 0.10

    /// Still, awake minutes with heart rate before a resting value is shown
    /// (app's choice; the same half hour `StressEstimate` asks for).
    public static let minimumRestingMinutes = 30
    /// Awake minutes with heart rate before an average is shown (app's choice).
    public static let minimumAwakeMinutes = 30

    /// Daytime HRV readings, awake and still, before a value is shown (app's
    /// choice, not research: an hour's worth of five-minute readings). A single
    /// one-minute reading is too noisy to show: ultra-short HRV values are not
    /// interchangeable with longer recordings and depend on the conditions
    /// they were taken in (Shaffer & Ginsberg, Front Public Health 2017;5:258;
    /// not re-verified here). A watch older than the Series 12 takes
    /// a reading every few hours, so it stays under this on most days and the
    /// screen says "not enough readings" instead of a number.
    public static let minimumHRVReadings = 12
    /// Clock hours those readings must come from, so the value is not one
    /// sitting (app's choice).
    public static let minimumHRVHours = 3

    /// Awake blood-oxygen readings before a value is shown (app's choice; the
    /// same count as `OvernightHRV.minimumReadings`).
    public static let minimumOxygenReadings = 3

    /// Days before the one shown that make up "your usual": four whole weeks,
    /// so every weekday counts the same number of times (app's choice inside
    /// the 2-4 weeks personal baselines are usually built from; Plews et al.,
    /// Sports Med 2013).
    public static let baselineWindowDays = 28
    /// Days with a comparable value before a usual range is shown (app's
    /// choice; the same 14 as `PersonalBaseline.minimumPoints`).
    public static let minimumBaselineDays = 14

    /// Share of the shown day's hours an earlier day must also cover to be
    /// compared with it (app's choice). See `summary` for why hours are matched.
    public static let minimumHourCoverage = 2.0 / 3.0

    /// The usual range runs from the 16th to the 84th percentile of the
    /// earlier days: the middle two thirds, which is mean ± 1 SD for a normal
    /// distribution (the band `PersonalBaseline` draws) without assuming one.
    /// App's choice.
    public static let usualRangePercentiles = 0.16...0.84

    /// A value this close to the edge of the usual range still counts as
    /// inside it: half of the whole number shown (app's choice).
    public static let standingTolerance = 0.5

    /// Earlier days an hour needs before the chart draws "your usual" for it
    /// (app's choice).
    public static let minimumHourlyDays = 7
    /// Minutes asleep from which an hour is drawn as asleep (half of it), and
    /// minutes of workout from which it is drawn as a workout hour (app's choice).
    public static let asleepHourMinutes = 30
    public static let workoutHourMinutes = 10

    /// Readings outside these are dropped as sensor errors (app's choice).
    static let plausibleHeartRate = 25.0...240.0
    static let plausibleHRV = 1.0...300.0
    static let plausibleOxygen = 70.0...100.0

    // MARK: - Inputs

    /// One timed reading: HRV in milliseconds, or blood oxygen in percent.
    public struct Reading: Sendable, Equatable {
        public var date: Date
        public var value: Double

        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// Steps counted in the minute starting at `start`.
    public struct StepMinute: Sendable, Equatable {
        public var start: Date
        public var steps: Double

        public init(start: Date, steps: Double) {
            self.start = start
            self.steps = steps
        }
    }

    /// Raw readings covering one or more days. `day` picks out its own day, so
    /// the same input can be reduced once per day it spans.
    public struct Input: Sendable {
        /// Heart rate averaged per minute (HealthKit's statistics), not raw samples.
        public var heartRate: [HeartRateSample]
        /// Apple Health's SDNN readings, any time of day.
        public var sdnn: [Reading]
        /// Apple Health's RMSSD readings (iOS 27), any time of day; empty without them.
        public var rmssd: [Reading]
        /// Blood oxygen in percent (0-100).
        public var bloodOxygen: [Reading]
        /// Every stretch to treat as asleep: each night's main sleep from
        /// bedtime to waking, and naps.
        public var sleep: [DateInterval]
        public var workouts: [DateInterval]
        /// Start of each minute the watch counted as exercise.
        public var exerciseMinutes: [Date]
        public var steps: [StepMinute]

        public init(
            heartRate: [HeartRateSample] = [],
            sdnn: [Reading] = [],
            rmssd: [Reading] = [],
            bloodOxygen: [Reading] = [],
            sleep: [DateInterval] = [],
            workouts: [DateInterval] = [],
            exerciseMinutes: [Date] = [],
            steps: [StepMinute] = []
        ) {
            self.heartRate = heartRate
            self.sdnn = sdnn
            self.rmssd = rmssd
            self.bloodOxygen = bloodOxygen
            self.sleep = sleep
            self.workouts = workouts
            self.exerciseMinutes = exerciseMinutes
            self.steps = steps
        }
    }

    // MARK: - One reduced day

    /// Count, sum, lowest and highest of a set of heart-rate minutes.
    public struct Tally: Sendable, Equatable, Codable {
        public var count = 0
        public var sum = 0.0
        public var low = 0.0
        public var high = 0.0

        public init() {}

        public var mean: Double? { count > 0 ? sum / Double(count) : nil }

        mutating func add(_ value: Double) {
            low = count == 0 ? value : min(low, value)
            high = count == 0 ? value : max(high, value)
            count += 1
            sum += value
        }

        mutating func add(_ other: Tally) {
            guard other.count > 0 else { return }
            low = count == 0 ? other.low : min(low, other.low)
            high = count == 0 ? other.high : max(high, other.high)
            count += other.count
            sum += other.sum
        }
    }

    public enum HourState: String, Sendable, Equatable {
        case asleep, awake, workout
    }

    /// One clock hour of a day.
    public struct Hour: Sendable, Equatable, Codable {
        /// 0-23.
        public var hour: Int
        /// Heart rate of each minute awake and at rest (the rule is in `day`).
        public var resting: [Double] = []
        /// Every awake minute, workouts and walks included.
        public var awake = Tally()
        /// Every minute, asleep or awake (for the chart).
        public var all = Tally()
        /// HRV readings taken awake and at rest.
        public var sdnn: [Double] = []
        public var rmssd: [Double] = []
        /// Blood-oxygen readings taken awake and outside workouts, in percent.
        public var bloodOxygen: [Double] = []
        /// Median of every HRV reading in the hour, asleep or awake (for the chart).
        public var chartSDNN: Double?
        public var chartRMSSD: Double?
        public var asleepMinutes = 0
        public var workoutMinutes = 0

        public init(hour: Int) {
            self.hour = hour
        }

        /// How the chart marks the hour.
        public var state: HourState {
            if workoutMinutes >= DaytimeVitals.workoutHourMinutes { return .workout }
            return asleepMinutes >= DaytimeVitals.asleepHourMinutes ? .asleep : .awake
        }
    }

    /// One calendar day reduced to 24 hourly buckets. Small enough to keep on
    /// disk for finished days, and all `summary` needs.
    public struct Day: Sendable, Equatable, Codable {
        /// Start of the day.
        public var date: Date
        /// Always 24, by clock hour (on a 23- or 25-hour day one is empty or doubled).
        public var hours: [Hour]
        /// Sleep and workouts inside the day, merged and cut to it.
        public var sleep: [DateInterval]
        public var workouts: [DateInterval]

        public init(date: Date, hours: [Hour], sleep: [DateInterval] = [], workouts: [DateInterval] = []) {
            self.date = date
            self.hours = hours
            self.sleep = sleep
            self.workouts = workouts
        }

        public var hasHeartRate: Bool { hours.contains { $0.all.count > 0 } }
        var isWellFormed: Bool { hours.count == 24 }
    }

    /// Reduces the readings of one calendar day.
    ///
    /// A minute counts as **daytime and at rest** when all of these hold:
    /// - awake: it does not touch any interval in `input.sleep`;
    /// - not in a workout, nor within `workoutRecoveryMinutes` after one;
    /// - the watch did not count it, or any of the `exerciseSettleMinutes`
    ///   before it, as exercise;
    /// - it and the `settleMinutes` before it each had fewer than
    ///   `movingStepsPerMinute` steps.
    ///
    /// Both movement signals are used because each misses something: exercise
    /// minutes start at about a brisk walk, so a stroll never appears in them,
    /// and steps miss cycling and anything done with the arms. None of it
    /// needs the wearer's heart-rate zones, so a day reduced once stays valid
    /// when their resting or maximum heart rate changes.
    ///
    /// Limits, stated rather than hidden: sitting and standing still look the
    /// same to these rules, as do the hour after a coffee or a meal and any
    /// other hour, and a nap the watch did not record counts as awake.
    public static func day(_ input: Input, on date: Date, calendar: Calendar = .current) -> Day {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let count = max(1, Int((end.timeIntervalSince(start) / 60).rounded()))

        func slot(_ instant: Date) -> Int {
            Int((instant.timeIntervalSince(start) / 60).rounded(.down))
        }
        /// Marks every minute the stretch touches.
        func mark(_ flags: inout [Bool], _ from: Date, _ to: Date) {
            guard to > from, to > start, from < end else { return }
            let low = max(0, slot(from))
            let high = min(count, Int((to.timeIntervalSince(start) / 60).rounded(.up)))
            guard low < high else { return }
            for minute in low..<high { flags[minute] = true }
        }

        // The clock hour of each minute, asked of the calendar every 15
        // minutes so a daylight-saving change lands in the right bucket.
        var hourOf = [Int](repeating: 0, count: count)
        var minute = 0
        while minute < count {
            let hour = calendar.component(.hour, from: start.addingTimeInterval(Double(minute) * 60))
            for index in minute..<min(count, minute + 15) { hourOf[index] = min(23, max(0, hour)) }
            minute += 15
        }

        var asleep = [Bool](repeating: false, count: count)
        var inWorkout = [Bool](repeating: false, count: count)
        /// Moving, settling after moving, or recovering after a workout.
        var unsettled = [Bool](repeating: false, count: count)
        for interval in input.sleep {
            mark(&asleep, interval.start, interval.end)
        }
        for workout in input.workouts {
            mark(&inWorkout, workout.start, workout.end)
            mark(&unsettled, workout.end, workout.end.addingTimeInterval(workoutRecoveryMinutes * 60))
        }
        for instant in input.exerciseMinutes {
            mark(&unsettled, instant, instant.addingTimeInterval((1 + exerciseSettleMinutes) * 60))
        }
        for step in input.steps where step.steps >= movingStepsPerMinute {
            mark(&unsettled, step.start, step.start.addingTimeInterval((1 + settleMinutes) * 60))
        }

        var hours = (0..<24).map { Hour(hour: $0) }
        for index in 0..<count {
            if asleep[index] { hours[hourOf[index]].asleepMinutes += 1 }
            if inWorkout[index] { hours[hourOf[index]].workoutMinutes += 1 }
        }

        for sample in input.heartRate where sample.date >= start && sample.date < end {
            guard sample.bpm.isFinite, plausibleHeartRate.contains(sample.bpm) else { continue }
            let index = min(count - 1, slot(sample.date))
            let hour = hourOf[index]
            hours[hour].all.add(sample.bpm)
            guard !asleep[index] else { continue }
            hours[hour].awake.add(sample.bpm)
            if !inWorkout[index], !unsettled[index] {
                hours[hour].resting.append(tenth(sample.bpm))
            }
        }

        var everySDNN = [[Double]](repeating: [], count: 24)
        var everyRMSSD = [[Double]](repeating: [], count: 24)
        for reading in input.sdnn where reading.date >= start && reading.date < end {
            guard reading.value.isFinite, plausibleHRV.contains(reading.value) else { continue }
            let index = min(count - 1, slot(reading.date))
            everySDNN[hourOf[index]].append(reading.value)
            if !asleep[index], !inWorkout[index], !unsettled[index] {
                hours[hourOf[index]].sdnn.append(tenth(reading.value))
            }
        }
        for reading in input.rmssd where reading.date >= start && reading.date < end {
            guard reading.value.isFinite, plausibleHRV.contains(reading.value) else { continue }
            let index = min(count - 1, slot(reading.date))
            everyRMSSD[hourOf[index]].append(reading.value)
            if !asleep[index], !inWorkout[index], !unsettled[index] {
                hours[hourOf[index]].rmssd.append(tenth(reading.value))
            }
        }
        for hour in 0..<24 {
            hours[hour].chartSDNN = median(everySDNN[hour]).map(tenth)
            hours[hour].chartRMSSD = median(everyRMSSD[hour]).map(tenth)
        }
        // Blood oxygen: awake and outside workouts. The recovery and settle
        // margins are not applied; they are about heart rate and HRV.
        for reading in input.bloodOxygen where reading.date >= start && reading.date < end {
            guard reading.value.isFinite, plausibleOxygen.contains(reading.value) else { continue }
            let index = min(count - 1, slot(reading.date))
            if !asleep[index], !inWorkout[index] {
                hours[hourOf[index]].bloodOxygen.append(tenth(reading.value))
            }
        }

        return Day(
            date: start,
            hours: hours,
            sleep: clipped(input.sleep, from: start, to: end),
            workouts: clipped(input.workouts, from: start, to: end)
        )
    }

    /// `intervals` merged where they overlap and cut to `start..<end`, in
    /// time order. Also how the app checks that a cached day still matches
    /// the sleep and workouts in Apple Health.
    public static func clipped(_ intervals: [DateInterval], from start: Date, to end: Date) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            let from = max(interval.start, start)
            let to = min(interval.end, end)
            guard to > from else { continue }
            if let last = result.last, from <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, to))
            } else {
                result.append(DateInterval(start: from, end: to))
            }
        }
        return result
    }

    // MARK: - Summary

    /// Where the earlier days' values fell.
    public struct Usual: Sendable, Equatable {
        public var low: Double
        public var median: Double
        public var high: Double
        /// Earlier days it is built from.
        public var days: Int

        public init(low: Double, median: Double, high: Double, days: Int) {
            self.low = low
            self.median = median
            self.high = high
            self.days = days
        }
    }

    public enum Standing: Sendable, Equatable {
        /// Too few readings on the day shown for a value.
        case notEnoughReadings
        /// A value, but too few earlier days to say what is usual.
        case buildingUsual(daysLeft: Int)
        case below, within, above
    }

    /// One daytime value with what it is built from and the wearer's usual.
    public struct Measure: Sendable, Equatable {
        /// Nil when there are too few readings.
        public var value: Double?
        /// Readings (HRV, blood oxygen) or minutes (heart rate) behind it.
        public var count: Int
        /// How many of them a value needs.
        public var needed: Int
        /// Clock hours they come from, and how many a value needs.
        public var hours: Int
        public var neededHours: Int
        /// Nil until `minimumBaselineDays` earlier days are comparable.
        public var usual: Usual?
        /// Earlier days that were comparable.
        public var baselineDays: Int

        public init(value: Double? = nil, count: Int = 0, needed: Int, hours: Int = 0, neededHours: Int = 1,
                    usual: Usual? = nil, baselineDays: Int = 0) {
            self.value = value
            self.count = count
            self.needed = needed
            self.hours = hours
            self.neededHours = neededHours
            self.usual = usual
            self.baselineDays = baselineDays
        }

        public var standing: Standing {
            guard let value else { return .notEnoughReadings }
            guard let usual else {
                return .buildingUsual(daysLeft: max(1, DaytimeVitals.minimumBaselineDays - baselineDays))
            }
            if value < usual.low - DaytimeVitals.standingTolerance { return .below }
            if value > usual.high + DaytimeVitals.standingTolerance { return .above }
            return .within
        }
    }

    /// One hour of the chart.
    public struct HourPoint: Sendable, Equatable, Identifiable {
        /// 0-23.
        public var hour: Int
        public var start: Date
        public var state: HourState
        /// Mean, lowest and highest minute, asleep or awake; nil without readings.
        public var heartRate: Double?
        public var lowHeartRate: Double?
        public var highHeartRate: Double?
        /// Median of the hour's HRV readings, asleep or awake.
        public var hrv: Double?
        public var hrvReadings: Int
        /// The median of the same hour on earlier days in the same state
        /// (asleep or awake); nil for a workout hour or with too few days.
        public var usualHeartRate: Double?
        public var usualHRV: Double?

        public var id: Int { hour }
    }

    public struct Summary: Sendable, Equatable {
        /// Start of the day shown.
        public var date: Date
        /// Heart rate at rest while awake (`restingPercentile` of the still minutes).
        public var restingLevel: Measure
        /// Mean of every awake minute, workouts and walks included.
        public var awakeAverage: Measure
        /// Lowest and highest awake minute.
        public var awakeRange: ClosedRange<Double>?
        /// Median of the HRV readings taken awake and at rest.
        public var hrv: Measure
        /// Which HRV measure `hrv` and the chart carry; nil with no readings at all.
        public var hrvMetric: HRVMetric?
        /// Median of the awake blood-oxygen readings, in percent.
        public var bloodOxygen: Measure
        public var lowestBloodOxygen: Double?
        /// Always 24.
        public var profile: [HourPoint]
        public var sleep: [DateInterval]
        public var workouts: [DateInterval]

        /// False when the watch recorded no heart rate that day.
        public var hasHeartRate: Bool { profile.contains { $0.heartRate != nil } }
    }

    /// Compares `day` with the days before it.
    ///
    /// **Time of day.** Heart rate and HRV follow the clock: HRV in 8 million
    /// wearers peaked in the early morning and fell through the day, and the
    /// authors advise reading it at the same time each day (Natarajan et al.,
    /// Lancet Digit Health 2020;2(12):e650-7; from the abstract and press
    /// coverage, hourly values not re-verified). So each value is compared like
    /// with like: an earlier day's value is worked out from the **same clock
    /// hours** the shown day has readings in. At 10 am, today's morning is set
    /// against earlier mornings, not earlier whole days; with the watch off
    /// from 10 to 3, those hours are left out of the earlier days too. An
    /// earlier day counts only if it covers `minimumHourCoverage` of those
    /// hours with enough readings of its own.
    ///
    /// What matching hours does not do: it does not know whether an hour was
    /// spent sitting or standing, fed or fasted, before or after coffee. Those
    /// stay in the spread of the usual range.
    ///
    /// Blood oxygen is not matched by hour: there are too few awake readings
    /// a day to split (app's choice).
    public static func summary(for day: Day, history: [Day], calendar: Calendar = .current) -> Summary {
        let day = day.isWellFormed ? day : Day(date: day.date, hours: (0..<24).map { Hour(hour: $0) })
        let windowStart = calendar.date(byAdding: .day, value: -baselineWindowDays, to: day.date)
            ?? day.date.addingTimeInterval(-Double(baselineWindowDays) * 86_400)
        let baseline = history.filter { $0.isWellFormed && $0.date >= windowStart && $0.date < day.date && $0.hasHeartRate }

        let resting = measure(day, baseline, needed: minimumRestingMinutes) { day, mask in
            let picked = values(day, mask, \.resting)
            let value = picked.values.count >= minimumRestingMinutes ? percentile(picked.values.sorted(), restingPercentile) : nil
            return Sample(value: value, count: picked.values.count, hours: picked.hours)
        }

        let average = measure(day, baseline, needed: minimumAwakeMinutes) { day, mask in
            var tally = Tally()
            var hours: Set<Int> = []
            for hour in day.hours where hour.awake.count > 0 && (mask?.contains(hour.hour) ?? true) {
                tally.add(hour.awake)
                hours.insert(hour.hour)
            }
            return Sample(value: tally.count >= minimumAwakeMinutes ? tally.mean : nil, count: tally.count, hours: hours)
        }
        var awake = Tally()
        for hour in day.hours { awake.add(hour.awake) }

        // One HRV measure for the day and its usual, never a mix: RMSSD when
        // the day has enough of it (the measure the overnight numbers prefer,
        // `DailyVitals.resolvingHRV`), else SDNN.
        func hrvSample(_ path: KeyPath<Hour, [Double]>) -> (Day, Set<Int>?) -> Sample {
            { day, mask in
                let picked = values(day, mask, path)
                // An earlier day is held to the hours of the day shown (the
                // coverage rule), not to a spread of its own.
                let spread = mask != nil || picked.hours.count >= minimumHRVHours
                let value = picked.values.count >= minimumHRVReadings && spread ? median(picked.values) : nil
                return Sample(value: value, count: picked.values.count, hours: picked.hours)
            }
        }
        let rmssd = measure(day, baseline, needed: minimumHRVReadings, neededHours: minimumHRVHours, evaluate: hrvSample(\.rmssd))
        let sdnn = measure(day, baseline, needed: minimumHRVReadings, neededHours: minimumHRVHours, evaluate: hrvSample(\.sdnn))
        let metric: HRVMetric?
        if rmssd.value != nil {
            metric = .rmssd
        } else if sdnn.value != nil {
            metric = .sdnn
        } else if rmssd.count > sdnn.count {
            metric = .rmssd
        } else {
            metric = sdnn.count > 0 ? .sdnn : nil
        }

        let oxygen = measure(day, baseline, needed: minimumOxygenReadings, matchHours: false) { day, _ in
            let picked = values(day, nil, \.bloodOxygen)
            let value = picked.values.count >= minimumOxygenReadings ? median(picked.values) : nil
            return Sample(value: value, count: picked.values.count, hours: picked.hours)
        }

        return Summary(
            date: day.date,
            restingLevel: resting,
            awakeAverage: average,
            awakeRange: awake.count > 0 ? awake.low...awake.high : nil,
            hrv: metric == .rmssd ? rmssd : sdnn,
            hrvMetric: metric,
            bloodOxygen: oxygen,
            lowestBloodOxygen: day.hours.flatMap(\.bloodOxygen).min(),
            profile: profile(day, baseline, metric: metric, calendar: calendar),
            sleep: day.sleep,
            workouts: day.workouts
        )
    }

    // MARK: - Pieces

    private struct Sample {
        var value: Double?
        var count: Int
        var hours: Set<Int>
    }

    /// The values of one kind in a day, from every hour or only the masked ones.
    private static func values(_ day: Day, _ mask: Set<Int>?, _ path: KeyPath<Hour, [Double]>) -> (values: [Double], hours: Set<Int>) {
        var result: [Double] = []
        var hours: Set<Int> = []
        for hour in day.hours where !hour[keyPath: path].isEmpty && (mask?.contains(hour.hour) ?? true) {
            result += hour[keyPath: path]
            hours.insert(hour.hour)
        }
        return (result, hours)
    }

    /// The day's own value, then the same value on each earlier day from the
    /// same hours, and the range those fell in.
    private static func measure(
        _ day: Day,
        _ baseline: [Day],
        needed: Int,
        neededHours: Int = 1,
        matchHours: Bool = true,
        evaluate: (Day, Set<Int>?) -> Sample
    ) -> Measure {
        let own = evaluate(day, nil)
        var result = Measure(value: own.value, count: own.count, needed: needed, hours: own.hours.count, neededHours: neededHours)
        guard own.value != nil else { return result }
        let mask: Set<Int>? = matchHours ? own.hours : nil
        var earlier: [Double] = []
        for other in baseline {
            let sample = evaluate(other, mask)
            guard let value = sample.value else { continue }
            if let mask, Double(sample.hours.count) < Double(mask.count) * minimumHourCoverage { continue }
            earlier.append(value)
        }
        result.baselineDays = earlier.count
        if earlier.count >= minimumBaselineDays {
            let sorted = earlier.sorted()
            if let low = percentile(sorted, usualRangePercentiles.lowerBound),
               let middle = percentile(sorted, 0.5),
               let high = percentile(sorted, usualRangePercentiles.upperBound) {
                result.usual = Usual(low: low, median: middle, high: high, days: earlier.count)
            }
        }
        return result
    }

    private static func profile(_ day: Day, _ baseline: [Day], metric: HRVMetric?, calendar: Calendar) -> [HourPoint] {
        func hrv(_ hour: Hour) -> Double? { metric == .rmssd ? hour.chartRMSSD : hour.chartSDNN }
        return day.hours.map { own in
            let state = own.state
            var usualHeartRate: Double?
            var usualHRV: Double?
            if state != .workout {
                // The same hour on earlier days when the wearer was in the
                // same state: an hour slept through is not set against the
                // same hour awake.
                let matching = baseline.map { $0.hours[own.hour] }.filter { $0.state == state }
                let rates = matching.compactMap(\.all.mean)
                if rates.count >= minimumHourlyDays { usualHeartRate = median(rates) }
                let variabilities = matching.compactMap(hrv)
                if variabilities.count >= minimumHourlyDays { usualHRV = median(variabilities) }
            }
            return HourPoint(
                hour: own.hour,
                start: calendar.date(bySettingHour: own.hour, minute: 0, second: 0, of: day.date)
                    ?? day.date.addingTimeInterval(Double(own.hour) * 3600),
                state: state,
                heartRate: own.all.mean,
                lowHeartRate: own.all.count > 0 ? own.all.low : nil,
                highHeartRate: own.all.count > 0 ? own.all.high : nil,
                hrv: hrv(own),
                hrvReadings: metric == .rmssd ? own.rmssd.count : own.sdnn.count,
                usualHeartRate: usualHeartRate,
                usualHRV: usualHRV
            )
        }
    }

    // MARK: - Small statistics

    /// The value at fraction `p` (0-1) of an ascending list, interpolated.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double? {
        guard let first = sorted.first else { return nil }
        guard sorted.count > 1 else { return first }
        let position = min(1, max(0, p)) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(sorted.count - 1, lower + 1)
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    static func median(_ values: [Double]) -> Double? {
        percentile(values.sorted(), 0.5)
    }

    /// One decimal is all a per-minute average or a reading is good for, and
    /// it keeps a stored day small.
    private static func tenth(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
