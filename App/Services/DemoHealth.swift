import Foundation
import AppCore

// MARK: - Demo mode (visual QA in the Simulator)

/// `-demoData YES` as a launch argument, in the Simulator only: the app opens
/// on a fixed, made-up dataset (`DemoData` for the app's own stores,
/// `DemoHealth` in place of Apple Health), so every screen has content in a
/// Simulator whose Health app is empty. Used by `UITests/ScreenshotTests`.
/// Never on a real iPhone, and off without the argument. Nothing here makes
/// a network request, and nothing is written to Apple Health.
nonisolated enum DemoMode {
    static let isOn: Bool = {
        #if targetEnvironment(simulator)
        return UserDefaults.standard.bool(forKey: "demoData")
        #else
        return false
        #endif
    }()
}

/// Made-up Apple Health data for demo mode, standing in for the HealthKit
/// queries in `HealthKitClient` (each query returns this when `active` is
/// set). Everything is a deterministic function of the day it's created, so
/// the screenshots are the same from run to run (apart from the dates):
///
/// - ~6 weeks of upper/lower lifting sessions (the `sessions` schedule, which
///   `DemoData` turns into logged workouts) with heart rate during them,
/// - runs and an easy ride from "Apple Watch", nightly sleep with stages,
///   HRV (SDNN) and resting heart rate around a steady baseline,
/// - steps, energy, food (four meals a day), vitamins, weight, VO₂ max,
///   blood pressure and the other daily series the app reads.
///
/// The numbers are plausible for a 34-year-old man who lifts, not taken from
/// anyone: demo content only, never shown outside demo mode.
nonisolated final class DemoHealth: Sendable {
    /// Set only in demo mode (`DemoMode.isOn`).
    static let active: DemoHealth? = DemoMode.isOn ? DemoHealth(now: pinnedNow()) : nil

    /// The demo's data stops at 8:10 today, whatever the real time, so every
    /// launch of a screenshot tour shows the same day (after breakfast and the
    /// 8:00 supplements, before the 8:15 commute adds strain).
    static func pinnedNow(calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: .now).addingTimeInterval((8 * 60 + 10) * 60)
    }

    /// The Health quantities the demo can answer, mapped from HealthKit
    /// identifiers in `DemoHealth+HealthKit`. Values are in the units the
    /// app asks for (kg, cm, kcal, g, L, bpm, ms, km, °C, minutes, counts;
    /// oxygen saturation and body fat as fractions, like `HKUnit.percent()`).
    nonisolated enum Metric: Sendable, Hashable {
        case restingHeartRate, hrv, walkingHeartRate, heartRateRecovery, oxygenSaturation, respiratoryRate
        case wristTemperature, breathingDisturbances, vo2Max
        case steps, distanceKm, flights, activeEnergy, basalEnergy, daylightMinutes, exerciseMinutes
        case bodyMass, bodyFat, bmi, leanMass, height, systolic, diastolic
        case dietaryEnergy, protein, carbs, fat, fiber, water, caffeine, alcoholicDrinks
        case vitaminC, vitaminD, zinc, iron, magnesium, potassium, sodium, calcium, vitaminB12, folate, vitaminA, selenium

        /// A different noise stream per metric (stable across runs, unlike `hashValue`).
        var hashSalt: Int {
            switch self {
            case .walkingHeartRate: 1
            case .heartRateRecovery: 2
            case .oxygenSaturation: 3
            case .respiratoryRate: 4
            case .wristTemperature: 5
            case .breathingDisturbances: 6
            case .steps, .distanceKm, .activeEnergy: 7
            case .flights: 8
            case .basalEnergy: 9
            case .daylightMinutes: 10
            case .systolic: 11
            case .diastolic: 12
            default: 0
            }
        }
    }

    /// A logged gym session in the schedule (`DemoData` creates its sets).
    nonisolated struct Session: Sendable {
        let daysAgo: Int
        let focus: WorkoutFocus
        let start: Date
        let end: Date
        let rpe: Int
    }

    /// A watch workout from another app (runs and rides).
    nonisolated struct Cardio: Sendable {
        let daysAgo: Int
        let name: String
        let start: Date
        let end: Date
        let km: Double?
        let kcal: Double
        let bpm: Double
        let id: UUID
    }

    /// One night, dated by the morning it ended.
    nonisolated struct Night: Sendable {
        let daysAgo: Int
        let bedtime: Date
        let asleepAt: Date
        let wake: Date
        let samples: [SleepSample]
    }

    /// One food entry, as a food app would write it to Health.
    nonisolated struct Meal: Sendable {
        let time: Date
        let share: Double
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double
        let water: Double
    }

    let calendar: Calendar
    let now: Date
    /// Start of today.
    let today: Date
    /// How far back the data goes.
    static let historyDays = 181
    var historyDays: Int { Self.historyDays }
    let age = 34
    let heightCm = 180.0
    let sessions: [Session]
    let cardio: [Cardio]
    private let nights: [Int: Night]
    private let sessionsByDay: [Int: [Session]]
    private let cardioByDay: [Int: [Cardio]]

    init(now: Date, calendar: Calendar = .current) {
        self.calendar = calendar
        self.now = now
        let today = calendar.startOfDay(for: now)
        self.today = today
        func at(_ daysAgo: Int, _ minutes: Double) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today.addingTimeInterval(-Double(daysAgo) * 86_400)
            return day.addingTimeInterval(minutes * 60)
        }

        // Upper/lower, four days a week: 7, 5, 3 and 2 days before each
        // "today" slot, so this week's plan has today as an upper day. One
        // session three weeks ago was missed.
        var sessions: [Session] = []
        for daysAgo in 1...42 where [0, 2, 3, 5].contains(daysAgo % 7) && daysAgo != 19 {
            let focus: WorkoutFocus = (daysAgo % 7 == 0 || daysAgo % 7 == 3) ? .upper : .lower
            let startMinutes = 18 * 60 + 5 + 12 * (Self.noise(daysAgo, 1) + 1)
            let length = 62 + 5 * (Self.noise(daysAgo, 2) + 1)
            let start = at(daysAgo, startMinutes)
            sessions.append(Session(daysAgo: daysAgo, focus: focus, start: start,
                                    end: start.addingTimeInterval(length * 60),
                                    rpe: Self.noise(daysAgo, 3) > 0.3 ? 8 : 7))
        }
        self.sessions = sessions
        sessionsByDay = Dictionary(grouping: sessions, by: \.daysAgo)

        // Runs on the two days between lifting days and an easy ride on the third.
        var cardio: [Cardio] = []
        for daysAgo in 1...Self.historyDays {
            let kind = daysAgo % 7
            guard kind == 1 || kind == 4 || kind == 6 else { continue }
            // 7:10 easy run, 9:00 longer run, 17:30 easy ride.
            let startMinutes: Double = kind == 1 ? 430 : (kind == 4 ? 540 : 1050)
            let minutes: Double = kind == 1 ? 34 : (kind == 4 ? 48 : 45)
            let baseKm: Double = kind == 1 ? 5.6 : 8.0
            let km: Double? = kind == 6 ? nil : baseKm + 0.3 * Self.noise(daysAgo, 4)
            let start = at(daysAgo, startMinutes)
            cardio.append(Cardio(daysAgo: daysAgo, name: kind == 6 ? "Ride" : "Run", start: start,
                                 end: start.addingTimeInterval(minutes * 60), km: km,
                                 kcal: kind == 1 ? 390 : (kind == 4 ? 540 : 360),
                                 bpm: kind == 1 ? 150 : (kind == 4 ? 146 : 128), id: Self.uuid(daysAgo)))
        }
        self.cardio = cardio
        cardioByDay = Dictionary(grouping: cardio, by: \.daysAgo)

        // Nights: in bed about 22:50 (later on Friday and Saturday), up about
        // 6:45 (later at the weekend); last night a little short.
        var nights: [Int: Night] = [:]
        for daysAgo in 0...Self.historyDays {
            let morning = at(daysAgo, 0)
            let weekday = calendar.component(.weekday, from: morning) // 1 = Sunday
            let lateNight = weekday == 7 || weekday == 1 // the evenings before were Friday and Saturday
            let bedMinutes = daysAgo == 0 ? -40 : -70 + 25 * Self.noise(daysAgo, 10) + (lateNight ? 45 : 0)
            let wakeMinutes = daysAgo == 0 ? 6 * 60 + 40 : 6 * 60 + 45 + 20 * Self.noise(daysAgo, 11) + (lateNight ? 60 : 0)
            let bedtime = morning.addingTimeInterval(bedMinutes * 60)
            let wake = morning.addingTimeInterval(wakeMinutes * 60)
            let asleepAt = bedtime.addingTimeInterval(14 * 60)
            nights[daysAgo] = Night(daysAgo: daysAgo, bedtime: bedtime, asleepAt: asleepAt, wake: wake,
                                    samples: Self.stages(bed: bedtime, asleep: asleepAt, wake: wake, seed: daysAgo))
        }
        self.nights = nights
    }

    // MARK: Dates and noise

    func day(_ daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today.addingTimeInterval(-Double(daysAgo) * 86_400)
    }

    func daysAgo(of date: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day ?? 0
    }

    /// The days (as days ago) a time range touches, within the history; empty if none.
    private func dayOffsets(from start: Date, to end: Date) -> [Int] {
        let newest = max(0, daysAgo(of: end))
        let oldest = min(historyDays, daysAgo(of: start))
        return newest <= oldest ? Array(newest...oldest) : []
    }

    /// A repeatable number in -1...1 for a day and a purpose (no randomness,
    /// so every run shows the same values).
    static func noise(_ seed: Int, _ salt: Int) -> Double {
        var x = UInt64(bitPattern: Int64(seed &* 7919 &+ salt &* 104_729 &+ 1_013_904_223))
        x ^= x >> 33
        x &*= 0xff51_afd7_ed55_8ccd
        x ^= x >> 33
        x &*= 0xc4ce_b9fe_1a85_ec53
        x ^= x >> 33
        return Double(x % 10_000) / 5_000 - 1
    }

    private static func uuid(_ seed: Int) -> UUID {
        let digits = String(seed)
        let padded = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
        return UUID(uuidString: "D3A0D3A0-0000-4000-8000-" + padded) ?? UUID()
    }

    /// Stages for one night in ~90-minute cycles: more deep sleep early, more
    /// REM late, one short waking around 3 am.
    private static func stages(bed: Date, asleep: Date, wake: Date, seed: Int) -> [SleepSample] {
        var result = [SleepSample(stage: .inBed, start: bed, end: wake.addingTimeInterval(4 * 60))]
        result.append(SleepSample(stage: .awake, start: bed, end: asleep))
        var time = asleep
        var cycle = 0
        let wakingAt = asleep.addingTimeInterval(3.4 * 3600 + 900 * noise(seed, 12))
        var hadWaking = false
        while time < wake && cycle < 8 {
            let plan: [(SleepStage, Double)] = [
                (.core, 22), (.deep, max(6, 38 - Double(cycle) * 9)), (.core, 18), (.rem, 10 + Double(cycle) * 7)
            ]
            for (stage, minutes) in plan where time < wake {
                let length = minutes * 60 * (1 + 0.12 * noise(seed, 20 + cycle))
                let end = min(wake, time.addingTimeInterval(length))
                result.append(SleepSample(stage: stage, start: time, end: end))
                time = end
                if !hadWaking, time >= wakingAt, time < wake {
                    let back = min(wake, time.addingTimeInterval(7 * 60))
                    result.append(SleepSample(stage: .awake, start: time, end: back))
                    time = back
                    hadWaking = true
                }
            }
            cycle += 1
        }
        return result
    }

    // MARK: Vitals

    /// Overnight HRV (SDNN, ms) for the night ending `daysAgo` mornings ago:
    /// about 47 ms, a little lower after lifting, 43 ms last night.
    func hrv(_ daysAgo: Int) -> Double {
        if daysAgo == 0 { return 43 }
        let afterLifting = sessionsByDay[daysAgo + 1] != nil
        // Drinks the evening before lower overnight HRV and raise heart rate
        // (Pietilä et al., JMIR Ment Health 2018, dose-dependent).
        return 47 + 5.5 * Self.noise(daysAgo, 30) - (afterLifting ? 2 : 0) - (drankEvening(daysAgo + 1) ? 4 : 0)
    }

    /// Resting heart rate: about 54 bpm, 56 this morning; +2 after drinks.
    func restingHeartRate(_ daysAgo: Int) -> Double {
        daysAgo == 0 ? 56 : 54 + 1.8 * Self.noise(daysAgo, 31) + (drankEvening(daysAgo + 1) ? 2 : 0)
    }

    /// Two drinks on Friday and Saturday evenings, skipping every third (the
    /// same rule as the drink entries in `timedSamples`).
    func drankEvening(_ daysAgo: Int) -> Bool {
        let weekday = calendar.component(.weekday, from: day(daysAgo))
        return (weekday == 6 || weekday == 7) && daysAgo % 3 != 0
    }

    func nightlyVitals(days: Int, endingOn day: Date) -> [DailyVitals] {
        let last = max(0, daysAgo(of: day))
        guard last <= historyDays else { return [] }
        return (last...min(historyDays, last + days)).map { daysAgo in
            DailyVitals(date: self.day(daysAgo), hrvMilliseconds: hrv(daysAgo), restingHeartRate: restingHeartRate(daysAgo))
        }
    }

    // MARK: Sleep

    func sleepSamples(forNightEnding day: Date) -> [SleepSample] {
        nights[daysAgo(of: day)]?.samples ?? []
    }

    /// Oldest first, like `HealthKitClient.sleepHistory`.
    func sleepHistory(nights count: Int) -> [SleepNight] {
        guard count > 0 else { return [] }
        return (0..<min(count, historyDays + 1)).reversed().compactMap { daysAgo -> SleepNight? in
            guard let night = nights[daysAgo] else { return nil }
            let asleep = night.samples.filter(\.stage.isAsleep).map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
            guard let main = SleepSessions.main(asleep) else { return nil }
            return SleepNight(date: day(daysAgo), hoursAsleep: main.asleep / 3600, bedtime: main.start, wake: main.end,
                              intervals: main.intervals)
        }
    }

    private func isAsleep(_ date: Date, minuteOfDay: Double, daysAgo: Int) -> (Bool, Int) {
        let morning = minuteOfDay >= 12 * 60 ? daysAgo - 1 : daysAgo
        guard let night = nights[morning] else { return (false, morning) }
        return (date >= night.asleepAt && date < night.wake, morning)
    }

    // MARK: Heart rate

    /// Heart rate as a watch records it: every 2 minutes at rest and asleep,
    /// every minute in workouts, walks and the few minutes after a workout.
    func heartRate(from start: Date, to end: Date) -> [HeartRateSample] {
        let first = max(start, day(historyDays))
        let last = min(end, now)
        guard first < last else { return [] }
        var samples: [HeartRateSample] = []
        var minute = (first.timeIntervalSince1970 / 60).rounded(.up)
        let lastMinute = last.timeIntervalSince1970 / 60
        var dayStart = calendar.startOfDay(for: first)
        var daysAgo = self.daysAgo(of: first)
        var nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        while minute < lastMinute {
            let date = Date(timeIntervalSince1970: minute * 60)
            if date >= nextDay {
                dayStart = calendar.startOfDay(for: date)
                daysAgo = self.daysAgo(of: date)
                nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
            }
            if let bpm = bpm(at: date, minuteOfDay: date.timeIntervalSince(dayStart) / 60, daysAgo: daysAgo, index: Int(minute)) {
                samples.append(HeartRateSample(date: date, bpm: bpm))
            }
            minute += 1
        }
        return samples
    }

    func heartRateSources(from start: Date, to end: Date) -> [HeartRateSource] {
        let samples = heartRate(from: start, to: end)
        return samples.isEmpty ? [] : [HeartRateSource(name: "Apple Watch (Health)", samples: samples)]
    }

    private func bpm(at date: Date, minuteOfDay: Double, daysAgo: Int, index: Int) -> Double? {
        let wobble = Self.noise(index, 40)
        if let session = sessionsByDay[daysAgo]?.first(where: { date >= $0.start && date < $0.end }) {
            let minutesIn = date.timeIntervalSince(session.start) / 60
            if minutesIn < 8 { return 96 + 2 * minutesIn + 3 * wobble }
            let set = [136.0, 120, 106][Int(minutesIn) % 3]
            return set + 6 * wobble + (session.focus == .lower ? 6 : 0)
        }
        if let workout = cardioByDay[daysAgo]?.first(where: { date >= $0.start && date < $0.end }) {
            let minutesIn = date.timeIntervalSince(workout.start) / 60
            if minutesIn < 5 { return 100 + (workout.bpm - 100) * minutesIn / 5 }
            return workout.bpm + 4 * wobble
        }
        // Heart-rate recovery: the first minutes after a workout.
        let ends = (sessionsByDay[daysAgo]?.map(\.end) ?? []) + (cardioByDay[daysAgo]?.map(\.end) ?? [])
        if let end = ends.first(where: { date >= $0 && date < $0.addingTimeInterval(6 * 60) }) {
            let after = date.timeIntervalSince(end) / 60
            return max(92, 138 - 23 * after) + 2 * wobble
        }
        let (asleep, night) = isAsleep(date, minuteOfDay: minuteOfDay, daysAgo: daysAgo)
        if asleep {
            guard index % 2 == 0 else { return nil }
            // Lowest in the middle of the night (about 9 bpm under the
            // resting value), averaging ~5 under it, as real nights do.
            let sinceBed = (minuteOfDay - 22 * 60 - 30 + 1440).truncatingRemainder(dividingBy: 1440)
            let progress = min(1, max(0, sinceBed / 500))
            return restingHeartRate(max(0, night)) - 2 - 6 * sin(progress * .pi) + 1.5 * wobble
        }
        let weekday = calendar.component(.weekday, from: date)
        let workday = weekday != 1 && weekday != 7
        let commute: Range<Double> = 495..<513 // 8:15-8:33
        let lunchWalk: Range<Double> = 760..<775 // 12:40-12:55
        if workday, commute.contains(minuteOfDay) || lunchWalk.contains(minuteOfDay) {
            return 101 + 5 * wobble
        }
        guard index % 2 == 0 else { return nil }
        return (minuteOfDay >= 21 * 60 + 30 ? 64 : 71) + 6 * wobble
    }

    /// Minutes the watch counts as exercise: workouts, lifts and brisk walks.
    func exerciseMinutes(from start: Date, to end: Date) -> [Date] {
        let last = min(end, now)
        guard start < last else { return [] }
        var windows: [DateInterval] = cardio.map { DateInterval(start: $0.start, end: $0.end) }
            + sessions.map { DateInterval(start: $0.start, end: $0.end) }
        for daysAgo in dayOffsets(from: start, to: last) {
            let weekday = calendar.component(.weekday, from: day(daysAgo))
            guard weekday != 1 && weekday != 7 else { continue }
            let morning = day(daysAgo).addingTimeInterval((8 * 60 + 15) * 60)
            windows.append(DateInterval(start: morning, duration: 18 * 60))
        }
        var minutes: [Date] = []
        for window in windows where window.end > start && window.start < last {
            var time = max(window.start, start)
            while time < min(window.end, last) {
                minutes.append(time)
                time = time.addingTimeInterval(60)
            }
        }
        return minutes.sorted()
    }

    // MARK: Workouts

    func externalWorkouts(from start: Date, to end: Date) -> [ExternalWorkout] {
        cardio.filter { $0.start < end && $0.end > start && $0.end <= now }
            .sorted { $0.start < $1.start }
            .map { ExternalWorkout(name: $0.name, isStrength: false, start: $0.start, end: $0.end, distanceKm: $0.km,
                                   uuid: $0.id, sourceName: "Apple Watch", activeKcal: $0.kcal) }
    }

    /// Every workout in Health: the watch's and the logged sessions (saved to Health).
    func workoutIntervals(from start: Date, to end: Date) -> [DateInterval] {
        let all = cardio.map { DateInterval(start: $0.start, end: $0.end) } + sessions.map { DateInterval(start: $0.start, end: $0.end) }
        return all.filter { $0.start < end && $0.end > start && $0.end <= now }.sorted { $0.start < $1.start }
    }

    func workoutEnergyPerDay(days: Int) -> [DatedValue] {
        var byDay: [Int: Double] = [:]
        for workout in cardio where workout.daysAgo < days && workout.end <= now {
            byDay[workout.daysAgo, default: 0] += workout.kcal
        }
        return byDay.keys.sorted(by: >).map { DatedValue(date: day($0), value: byDay[$0] ?? 0) }
    }

    func mindfulMinutes(days: Int) -> [DatedValue] {
        (0..<min(days, historyDays)).reversed().filter { $0 % 4 == 2 }.map { DatedValue(date: day($0), value: 6) }
    }

    // MARK: Daily series

    private enum Spread { case waking, allDay, meals, single }

    private func spread(_ metric: Metric) -> Spread {
        switch metric {
        case .steps, .distanceKm, .flights, .activeEnergy, .daylightMinutes, .exerciseMinutes: .waking
        case .basalEnergy: .allDay
        case .dietaryEnergy, .protein, .carbs, .fat, .fiber, .water, .caffeine, .alcoholicDrinks,
             .vitaminC, .vitaminD, .zinc, .iron, .magnesium, .potassium, .sodium, .calcium, .vitaminB12, .folate, .vitaminA, .selenium:
            .meals
        default: .single
        }
    }

    /// A whole day's value (a total for cumulative metrics), or nil when
    /// nothing was recorded that day.
    func dayValue(_ metric: Metric, _ daysAgo: Int) -> Double? {
        guard daysAgo >= 0, daysAgo <= historyDays else { return nil }
        let n = Self.noise(daysAgo, 50 + metric.hashSalt)
        let ran = cardioByDay[daysAgo]?.compactMap(\.km).reduce(0, +) ?? 0
        let lifted = sessionsByDay[daysAgo] != nil
        switch metric {
        case .restingHeartRate: return restingHeartRate(daysAgo)
        case .hrv: return hrv(daysAgo)
        case .walkingHeartRate: return 97 + 3 * n
        case .heartRateRecovery:
            return (lifted || cardioByDay[daysAgo] != nil) ? 24 + 4 * n : nil
        case .oxygenSaturation: return 0.966 + 0.008 * n
        case .respiratoryRate: return 14.6 + 0.4 * n
        case .wristTemperature: return daysAgo == 0 ? 36.25 : 36.1 + 0.12 * n
        case .breathingDisturbances: return 5 + 2 * n
        case .vo2Max: return daysAgo % 7 == 4 ? 44.0 + 1.4 * (1 - Double(daysAgo) / Double(historyDays)) : nil
        case .steps: return 7800 + 2500 * n + ran * 1300
        case .distanceKm: return (7800 + 2500 * n) * 0.00075 + ran
        case .flights: return 7 + 4 * n
        case .activeEnergy:
            let kcal = cardioByDay[daysAgo]?.map(\.kcal).reduce(0, +) ?? 0
            return 420 + 0.03 * (7800 + 2500 * n) + kcal + (lifted ? 250 : 0)
        case .basalEnergy: return 1795 + 15 * n
        case .daylightMinutes: return 45 + 25 * n
        case .exerciseMinutes: return 20 + (lifted ? 60 : 0) + (cardioByDay[daysAgo] != nil ? 40 : 0)
        case .bodyMass: return daysAgo % 5 == 3 ? nil : bodyMass(daysAgo)
        case .bodyFat: return daysAgo % 7 == 1 ? bodyFat(daysAgo) : nil
        case .bmi: return daysAgo % 5 == 3 ? nil : bodyMass(daysAgo) / ((heightCm / 100) * (heightCm / 100))
        case .leanMass: return daysAgo % 7 == 1 ? bodyMass(daysAgo) * (1 - bodyFat(daysAgo)) : nil
        case .height: return heightCm
        // The day's mean of the cuff readings taken by now, so Health's daily
        // value and the readings list agree (none before the 7:30 reading).
        case .systolic:
            let readings = bloodPressurePairs(daysAgo)
            return readings.isEmpty ? nil : readings.map(\.systolic).reduce(0, +) / Double(readings.count)
        case .diastolic:
            let readings = bloodPressurePairs(daysAgo)
            return readings.isEmpty ? nil : readings.map(\.diastolic).reduce(0, +) / Double(readings.count)
        default:
            guard spread(metric) == .meals else { return nil }
            let entries = timedSamples(metric, from: day(daysAgo), to: day(daysAgo).addingTimeInterval(86_400), clip: false)
            return entries.isEmpty ? nil : entries.map(\.value).reduce(0, +)
        }
    }

    /// The newest scale reading (days with no weigh-in are skipped, as in `value`).
    var latestWeightKg: Double {
        let daysAgo = (0...10).first { $0 % 5 != 3 } ?? 0
        return bodyMass(daysAgo)
    }

    private func bodyMass(_ daysAgo: Int) -> Double {
        81.6 + 0.032 * Double(daysAgo) + 0.3 * Self.noise(daysAgo, 60)
    }

    private func bodyFat(_ daysAgo: Int) -> Double {
        0.168 + 0.000_22 * Double(daysAgo)
    }

    /// One value per day for the last `days` days, oldest first; today's
    /// total so far for cumulative metrics.
    func dailySeries(_ metric: Metric?, days: Int) -> [DatedValue] {
        guard let metric, days > 0 else { return [] }
        return (0..<min(days, historyDays + 1)).reversed().compactMap { daysAgo -> DatedValue? in
            let value: Double?
            if daysAgo == 0, spread(metric) != .single {
                value = sum(metric, from: today, to: now)
            } else {
                value = dayValue(metric, daysAgo)
            }
            return value.map { DatedValue(date: day(daysAgo), value: $0) }
        }
    }

    /// A total over a time range (steps, energy, food); nil when nothing was recorded in it.
    func sum(_ metric: Metric?, from start: Date, to end: Date) -> Double? {
        guard let metric else { return nil }
        let last = min(end, now)
        guard start < last else { return nil }
        switch spread(metric) {
        case .single:
            return nil
        case .meals:
            let entries = timedSamples(metric, from: start, to: last)
            return entries.isEmpty ? nil : entries.map(\.value).reduce(0, +)
        case .waking, .allDay:
            let waking = spread(metric) == .waking
            var total = 0.0
            var any = false
            for daysAgo in dayOffsets(from: start, to: last) {
                guard let value = dayValue(metric, daysAgo) else { continue }
                let from = day(daysAgo).addingTimeInterval(waking ? 7 * 3600 : 0)
                let to = day(daysAgo).addingTimeInterval(waking ? 22 * 3600 : 86_400)
                let overlap = min(to, last).timeIntervalSince(max(from, start))
                guard overlap > 0 else { continue }
                total += value * overlap / to.timeIntervalSince(from)
                any = true
            }
            return any ? total : nil
        }
    }

    /// The latest value at or after `since` (body mass, height, VO₂ max…).
    func latest(_ metric: Metric?, since: Date?) -> Double? {
        guard let metric else { return nil }
        for daysAgo in 0...historyDays {
            if let since, day(daysAgo) < calendar.startOfDay(for: since) { return nil }
            if let value = dayValue(metric, daysAgo) { return value }
        }
        return nil
    }

    func overnightRespiratoryRate(forNightEnding day: Date) -> Double? {
        dayValue(.respiratoryRate, daysAgo(of: day))
    }

    // MARK: Food

    /// Meals for a day: breakfast, lunch, a snack and dinner, ~2,450 kcal and
    /// 165 g protein; every 11th day nothing is logged.
    private func meals(_ daysAgo: Int) -> [Meal] {
        guard daysAgo % 11 != 6 else { return [] }
        let base = day(daysAgo)
        let plan: [(minutes: Double, share: Double, kcal: Double, protein: Double, carbs: Double, fat: Double, fiber: Double, water: Double)] = [
            (7 * 60 + 40, 0.24, 590, 35, 68, 18, 8, 0.5),
            (12 * 60 + 45, 0.31, 760, 50, 82, 24, 9, 0.6),
            (16 * 60 + 10, 0.12, 300, 28, 26, 9, 3, 0.4),
            (19 * 60 + 50, 0.33, 800, 52, 80, 28, 10, 0.7),
        ]
        return plan.enumerated().map { index, meal in
            let scale = 1 + 0.08 * Self.noise(daysAgo * 4 + index, 70)
            return Meal(time: base.addingTimeInterval(meal.minutes * 60), share: meal.share, kcal: meal.kcal * scale,
                        protein: meal.protein * scale, carbs: meal.carbs * scale, fat: meal.fat * scale,
                        fiber: meal.fiber * scale, water: meal.water)
        }
    }

    /// Vitamins and minerals a logged day adds up to: vitamin D, magnesium
    /// and zinc a little low, the rest near target.
    private func dailyMicronutrient(_ metric: Metric) -> Double? {
        switch metric {
        case .vitaminC: 92
        case .vitaminD: 3.5
        case .zinc: 9.5
        case .iron: 15
        case .magnesium: 330
        case .potassium: 3200
        case .sodium: 2900
        case .calcium: 880
        case .vitaminB12: 5.2
        case .folate: 410
        case .vitaminA: 760
        case .selenium: 72
        default: nil
        }
    }

    /// Individual entries with their times (food, caffeine, drinks).
    func timedSamples(_ metric: Metric?, from start: Date, to end: Date, clip: Bool = true) -> [DatedValue] {
        guard let metric else { return [] }
        let last = clip ? min(end, now) : end
        guard start < last else { return [] }
        var result: [DatedValue] = []
        for daysAgo in dayOffsets(from: start, to: last) {
            let base = day(daysAgo)
            switch metric {
            case .caffeine:
                result.append(DatedValue(date: base.addingTimeInterval((7 * 60 + 45) * 60), value: 95))
                result.append(DatedValue(date: base.addingTimeInterval((13 * 60 + 20) * 60), value: 80))
            case .alcoholicDrinks:
                if drankEvening(daysAgo) {
                    result.append(DatedValue(date: base.addingTimeInterval((20 * 60 + 30) * 60), value: 2))
                }
            default:
                for meal in meals(daysAgo) {
                    let value: Double?
                    switch metric {
                    case .dietaryEnergy: value = meal.kcal
                    case .protein: value = meal.protein
                    case .carbs: value = meal.carbs
                    case .fat: value = meal.fat
                    case .fiber: value = meal.fiber
                    case .water: value = meal.water
                    default: value = dailyMicronutrient(metric).map { $0 * meal.share }
                    }
                    if let value { result.append(DatedValue(date: meal.time, value: value)) }
                }
            }
        }
        return result.filter { $0.date >= start && $0.date < last }.sorted { $0.date < $1.date }
    }

    func hourlySteps(for date: Date) -> [MovementBreaks.HourSteps] {
        let daysAgo = self.daysAgo(of: date)
        guard let total = dayValue(.steps, daysAgo) else { return [] }
        let shares: [Double] = [0.05, 0.14, 0.05, 0.05, 0.05, 0.12, 0.07, 0.05, 0.05, 0.06, 0.10, 0.08, 0.06, 0.05, 0.02]
        return shares.enumerated().compactMap { index, share in
            let start = day(daysAgo).addingTimeInterval(Double(7 + index) * 3600)
            guard start < now else { return nil }
            return MovementBreaks.HourSteps(start: start, steps: (total * share).rounded())
        }
    }

    // MARK: Records

    /// The cuff readings of one day, taken by now: a full 7-day home check
    /// this week (morning 7:30 and evening 21:00, as ESH 2021 asks), and
    /// every third morning before that. Rounded like a cuff.
    func bloodPressurePairs(_ daysAgo: Int) -> [(date: Date, systolic: Double, diastolic: Double)] {
        guard daysAgo >= 0, daysAgo <= historyDays else { return [] }
        let n = Self.noise(daysAgo, 50 + Metric.systolic.hashSalt)
        let m = Self.noise(daysAgo, 50 + Metric.diastolic.hashSalt)
        var times: [Double] = []
        if daysAgo < 7 {
            times = [7 * 60 + 30, 21 * 60]
        } else if daysAgo % 3 == 0 {
            times = [7 * 60 + 30]
        }
        return times.enumerated().compactMap { index, minutes -> (date: Date, systolic: Double, diastolic: Double)? in
            let date = day(daysAgo).addingTimeInterval(minutes * 60)
            guard date <= now else { return nil }
            let evening = index == 1
            return (date: date, systolic: (121 + 4 * n + (evening ? 3 : 0)).rounded(), diastolic: (76 + 2.5 * m + (evening ? 1 : 0)).rounded())
        }
    }

    /// Home cuff readings, newest first.
    func bloodPressureReadings(days: Int) -> [BloodPressureReading] {
        (0..<min(days, historyDays)).flatMap { daysAgo -> [BloodPressureReading] in
            let readings = bloodPressurePairs(daysAgo).enumerated().map { index, reading in
                BloodPressureReading(id: Self.uuid(5000 + daysAgo * 2 + index), date: reading.date, systolic: reading.systolic,
                                     diastolic: reading.diastolic, source: "Blood pressure cuff", arm: "Left")
            }
            return Array(readings.reversed())
        }
    }

    /// A partly cloudy November day in Lisbon in place of the forecast (no
    /// network in demo mode): about 12° in the morning, a high of 18°.
    func conditions(latitude: Double, longitude: Double) -> Conditions {
        let hour = calendar.component(.hour, from: now)
        let temperature: Double = hour < 10 ? 12 : (hour < 17 ? 17 : 14)
        return Conditions(latitude: latitude, longitude: longitude, fetched: now, temperature: temperature, feelsLike: temperature - 1,
                   humidity: 72, weatherCode: 2, isDay: true, high: 18, low: 11, uvIndexMax: 3,
                   precipitationChance: 10, sunrise: today.addingTimeInterval((7 * 60 + 15) * 60),
                   sunset: today.addingTimeInterval((18 * 60 + 5) * 60), daylightHours: 10.8, usAQI: 28)
    }
}
