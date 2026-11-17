import Foundation
import Testing
@testable import AppCore

/// Daytime vitals (`DaytimeVitals`) on realistic days: a desk day, a lift at
/// 6 pm, a night-shift sleeper, an older watch with a handful of HRV
/// readings, and a day with the watch off for some hours.
@Suite struct DaytimeVitalsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Midnight UTC of the day shown.
    private var today: Date {
        Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 86_400))
    }

    private func day(_ back: Int) -> Date { today.addingTimeInterval(-Double(back) * 86_400) }

    /// One made-up day, in hours from its midnight (negative = the evening before).
    private struct Plan {
        /// Asleep 23:00 to 07:00 by default: the night before and the next one.
        var sleep: [ClosedRange<Double>] = [-1...7, 23...31]
        var workouts: [ClosedRange<Double>] = []
        /// Brisk walks: 100 steps a minute, counted as exercise.
        var walks: [ClosedRange<Double>] = []
        /// Hours with the watch off: nothing recorded.
        var offWrist: [ClosedRange<Double>] = []
        /// The day's readings stop here (a day still in progress).
        var until = 24.0
        /// Minutes between heart-rate values (1 = a Series 12's per-minute averages).
        var heartRateEvery = 1
        /// Minutes between HRV readings; nil for none.
        var hrvEvery: Int? = 5
        var rmssd = false
        /// Minutes between blood-oxygen readings; nil for none.
        var oxygenEvery: Int? = 60
        /// Sitting heart rate and awake HRV by hour of day.
        var sitting: @Sendable (Double) -> Double = { _ in 66 }
        var awakeHRV: @Sendable (Double) -> Double = { _ in 40 }
        var asleepHeartRate = 52.0
        var asleepHRV = 62.0
    }

    /// A repeatable wobble in -1...1.
    private func wobble(_ index: Int) -> Double {
        Double((index &* 37 &+ 11) % 21 - 10) / 10
    }

    private func input(_ plan: Plan, on start: Date) -> DaytimeVitals.Input {
        func inside(_ ranges: [ClosedRange<Double>], _ hour: Double) -> Bool {
            ranges.contains { hour >= $0.lowerBound && hour < $0.upperBound }
        }
        func intervals(_ ranges: [ClosedRange<Double>]) -> [DateInterval] {
            ranges.map { DateInterval(start: start.addingTimeInterval($0.lowerBound * 3600), end: start.addingTimeInterval($0.upperBound * 3600)) }
        }
        var result = DaytimeVitals.Input(sleep: intervals(plan.sleep), workouts: intervals(plan.workouts))
        for minute in 0..<Int(plan.until * 60) {
            let hour = Double(minute) / 60
            let date = start.addingTimeInterval(Double(minute) * 60)
            guard !inside(plan.offWrist, hour) else { continue }
            let asleep = inside(plan.sleep, hour)
            let working = inside(plan.workouts, hour)
            let walking = inside(plan.walks, hour)
            if walking {
                result.exerciseMinutes.append(date)
                result.steps.append(.init(start: date, steps: 100))
            }
            if minute % plan.heartRateEvery == 0 {
                let bpm: Double
                if working {
                    bpm = 132 + 10 * wobble(minute)
                } else if walking {
                    bpm = 102 + 4 * wobble(minute)
                } else if asleep {
                    bpm = plan.asleepHeartRate + 2 * wobble(minute)
                } else {
                    bpm = plan.sitting(hour) + 5 * wobble(minute)
                }
                result.heartRate.append(HeartRateSample(date: date, bpm: bpm))
            }
            if let every = plan.hrvEvery, minute % every == 0 {
                let value: Double
                if working {
                    value = 9
                } else if asleep {
                    value = plan.asleepHRV + 6 * wobble(minute)
                } else {
                    value = plan.awakeHRV(hour) + 6 * wobble(minute)
                }
                let reading = DaytimeVitals.Reading(date: date, value: value)
                if plan.rmssd { result.rmssd.append(reading) } else { result.sdnn.append(reading) }
            }
            if let every = plan.oxygenEvery, minute % every == 30 {
                result.bloodOxygen.append(.init(date: date, value: asleep ? 95 : 97))
            }
        }
        return result
    }

    private func reduced(_ plan: Plan, back: Int = 0) -> DaytimeVitals.Day {
        DaytimeVitals.day(input(plan, on: day(back)), on: day(back), calendar: calendar)
    }

    /// `count` earlier days of the same plan, each shifted a little so the
    /// usual range has some width.
    private func history(_ plan: Plan, days count: Int = 28, shift: (Int) -> Double = { Double($0 % 5) - 2 }) -> [DaytimeVitals.Day] {
        (1...count).map { back in
            var earlier = plan
            earlier.until = 24
            let sitting = plan.sitting
            let offset = shift(back)
            earlier.sitting = { sitting($0) + offset }
            let variability = plan.awakeHRV
            earlier.awakeHRV = { variability($0) - offset }
            return reduced(earlier, back: back)
        }
    }

    private func summary(_ plan: Plan, history days: [DaytimeVitals.Day]) -> DaytimeVitals.Summary {
        DaytimeVitals.summary(for: reduced(plan), history: days, calendar: calendar)
    }

    // MARK: A desk day

    @Test func deskDayReportsRestingAverageRangeAndHRV() throws {
        var plan = Plan()
        plan.walks = [12.5...12.75]
        let result = summary(plan, history: history(plan))

        // Sitting heart rate is 66 ± 5, so the calmest tenth sits near 61-62.
        let resting = try #require(result.restingLevel.value)
        #expect(resting > 60 && resting < 63.5)
        #expect(result.restingLevel.standing == .within)
        #expect(result.restingLevel.usual?.days == 28)

        // The average takes in the lunch walk, so it is above the resting level.
        let average = try #require(result.awakeAverage.value)
        #expect(average > 65.5 && average < 68)
        #expect(average > resting)

        // Lowest and highest awake minute: sitting low, walking high; sleep (52) is not in it.
        let range = try #require(result.awakeRange)
        #expect(range.lowerBound >= 60 && range.lowerBound < 62)
        #expect(range.upperBound > 100 && range.upperBound < 108)

        #expect(result.hrvMetric == .sdnn)
        let hrv = try #require(result.hrv.value)
        #expect(abs(hrv - 40) < 2)
        // 16 awake hours of five-minute readings, less the walk and its settle time.
        #expect(result.hrv.count > 170 && result.hrv.count < 192)
        #expect(result.hrv.standing == .within)

        #expect(result.bloodOxygen.value == 97)
        #expect(result.lowestBloodOxygen == 97)
    }

    @Test func restingIsHigherAwakeThanAsleepAndIgnoresSleep() {
        let plan = Plan()
        let result = summary(plan, history: [])
        // The night's 52 bpm never enters the daytime numbers.
        #expect((result.restingLevel.value ?? 0) > 58)
        #expect((result.awakeRange?.lowerBound ?? 0) > 58)
        // The chart still shows the night.
        #expect(result.profile[3].state == .asleep)
        #expect(abs((result.profile[3].heartRate ?? 0) - 52) < 1.5)
        #expect(abs((result.profile[3].hrv ?? 0) - 62) < 4)
        #expect(result.profile[10].state == .awake)
    }

    @Test func walkingMinutesAndTheMinutesAfterAreNotRest() {
        var plan = Plan()
        plan.walks = [12.5...12.75]
        let reducedDay = reduced(plan)
        // 12:30-12:45 walking, then 10 minutes to settle (exercise minutes): rest resumes at 12:55.
        #expect(reducedDay.hours[12].resting.count == 30 + 5)
        #expect(reducedDay.hours[12].awake.count == 60)
        #expect((reducedDay.hours[12].resting.max() ?? 0) < 80)
        // HRV readings at 12:30...12:50 are left out: 12 in the hour, 5 dropped.
        #expect(reducedDay.hours[12].sdnn.count == 7)
    }

    @Test func stepsAloneCountAsMovingWithAShorterSettle() {
        var raw = input(Plan(), on: today)
        // A slow stroll 15:00-15:10 the watch never counted as exercise.
        for minute in 0..<10 {
            raw.steps.append(.init(start: today.addingTimeInterval(15 * 3600 + Double(minute) * 60), steps: 45))
        }
        // Shifting in a chair is not moving.
        raw.steps.append(.init(start: today.addingTimeInterval(16 * 3600), steps: 8))
        let reducedDay = DaytimeVitals.day(raw, on: today, calendar: calendar)
        // 10 minutes strolling + 5 to settle.
        #expect(reducedDay.hours[15].resting.count == 45)
        #expect(reducedDay.hours[16].resting.count == 60)
    }

    // MARK: A lift at 6 pm

    @Test func eveningLiftAndItsRecoveryStayOutOfTheRestingNumbers() {
        var plan = Plan()
        plan.workouts = [18...19]
        let reducedDay = reduced(plan)
        // In the workout, then 90 minutes after it: nothing at rest until 20:30.
        #expect(reducedDay.hours[18].resting.isEmpty)
        #expect(reducedDay.hours[19].resting.isEmpty)
        #expect(reducedDay.hours[20].resting.count == 30)
        #expect(reducedDay.hours[18].sdnn.isEmpty)
        #expect(reducedDay.hours[19].sdnn.isEmpty)
        #expect(reducedDay.hours[18].workoutMinutes == 60)
        #expect(reducedDay.workouts.count == 1)

        let desk = summary(Plan(), history: [])
        let lifted = summary(plan, history: history(Plan()))
        // The resting level is the same as on a day without the lift...
        #expect(abs((lifted.restingLevel.value ?? 0) - (desk.restingLevel.value ?? 99)) < 0.6)
        #expect(lifted.restingLevel.standing == .within)
        // ...while the average and the top of the range show it.
        #expect((lifted.awakeAverage.value ?? 0) > (desk.awakeAverage.value ?? 99) + 3)
        #expect((lifted.awakeRange?.upperBound ?? 0) > 135)
        // The 9 ms readings inside the workout don't pull the day's HRV down.
        #expect(abs((lifted.hrv.value ?? 0) - 40) < 2)
        // The chart marks the hour, and draws no "usual" through it.
        #expect(lifted.profile[18].state == .workout)
        #expect(lifted.profile[18].usualHeartRate == nil)
        #expect(lifted.profile[10].usualHeartRate != nil)
    }

    @Test func aWorkoutThatEndedLateLastNightStillBlocksTheFirstMinutes() {
        var raw = input(Plan(sleep: [1...8, 23...31]), on: today)
        // 22:30-23:45 the evening before: recovery runs to 01:15.
        raw.workouts = [DateInterval(start: today.addingTimeInterval(-1.5 * 3600), end: today.addingTimeInterval(-0.25 * 3600))]
        let reducedDay = DaytimeVitals.day(raw, on: today, calendar: calendar)
        // Awake 00:00-01:00 but recovering the whole hour.
        #expect(reducedDay.hours[0].awake.count == 60)
        #expect(reducedDay.hours[0].resting.isEmpty)
        #expect(reducedDay.workouts.isEmpty)
    }

    // MARK: A night-shift sleeper

    @Test func nightShiftSleeperIsMeasuredInTheirOwnAwakeHours() throws {
        var plan = Plan()
        // Asleep 08:00-16:00, awake through the night.
        plan.sleep = [-16...(-8), 8...16, 32...40]
        let result = summary(plan, history: history(plan))

        #expect(result.profile[3].state == .awake)
        #expect(result.profile[11].state == .asleep)
        #expect(result.profile[20].state == .awake)
        // 16 awake hours on either side of the sleep.
        #expect(result.restingLevel.count == 16 * 60)
        #expect(result.restingLevel.hours == 16)
        let resting = try #require(result.restingLevel.value)
        #expect(resting > 60 && resting < 63.5)
        #expect(result.restingLevel.standing == .within)
        #expect(result.hrv.standing == .within)
        // 03:00 awake is set against earlier 03:00s awake.
        #expect(abs((result.profile[3].usualHeartRate ?? 0) - 66) < 3)
        #expect(abs((result.profile[11].usualHeartRate ?? 0) - 52) < 2)
    }

    @Test func anHourSleptThroughIsNotSetAgainstTheSameHourAwake() {
        // Usually up at 07:00; today asleep until 10:00.
        var late = Plan()
        late.sleep = [-1...10, 23...31]
        let result = summary(late, history: history(Plan()))
        #expect(result.profile[8].state == .asleep)
        // Earlier days were awake at 08:00, so there is no like-for-like usual for it.
        #expect(result.profile[8].usualHeartRate == nil)
        #expect(result.profile[3].usualHeartRate != nil)
        #expect(result.profile[14].usualHeartRate != nil)
    }

    // MARK: An older watch

    @Test func aHandfulOfHRVReadingsGivesNoNumber() {
        var plan = Plan()
        // A reading about every 3 hours and heart rate every 5 minutes.
        plan.hrvEvery = 180
        plan.heartRateEvery = 5
        plan.oxygenEvery = nil
        let result = summary(plan, history: history(plan))

        #expect(result.hrv.value == nil)
        #expect(result.hrv.standing == .notEnoughReadings)
        // 09:00, 12:00, 15:00, 18:00, 21:00 (the 06:00 one is asleep).
        #expect(result.hrv.count == 5)
        #expect(result.hrv.needed == DaytimeVitals.minimumHRVReadings)
        #expect(result.hrvMetric == .sdnn)
        // The readings still show as dots on the chart.
        #expect(result.profile[9].hrv != nil)
        #expect(result.profile[9].usualHRV != nil)

        // Heart rate every 5 minutes is plenty: 12 an hour over 16 hours.
        #expect(result.restingLevel.count == 16 * 12)
        #expect(result.restingLevel.value != nil)
        #expect(result.restingLevel.standing == .within)

        #expect(result.bloodOxygen.value == nil)
        #expect(result.bloodOxygen.standing == .notEnoughReadings)
        #expect(result.lowestBloodOxygen == nil)
    }

    @Test func twelveReadingsInOneSittingAreNotADay() {
        var raw = input(Plan(hrvEvery: nil), on: today)
        // Twelve readings in 55 minutes: one meditation, not a day.
        raw.sdnn = (0..<12).map { .init(date: today.addingTimeInterval(10 * 3600 + Double($0) * 300), value: 70) }
        let result = DaytimeVitals.summary(for: DaytimeVitals.day(raw, on: today, calendar: calendar), history: [], calendar: calendar)
        #expect(result.hrv.count == 12)
        #expect(result.hrv.hours == 1)
        #expect(result.hrv.neededHours == DaytimeVitals.minimumHRVHours)
        #expect(result.hrv.value == nil)
    }

    @Test func earlierDaysOnTheOldWatchDoNotCountTowardsTheUsualHRV() {
        let series12 = Plan()
        var older = Plan()
        older.hrvEvery = 180
        // Ten days on the new watch, the rest on the old one.
        let days = history(series12, days: 10) + (11...28).map { reduced(older, back: $0) }
        let result = summary(series12, history: days)
        #expect(result.hrv.value != nil)
        #expect(result.hrv.baselineDays == 10)
        #expect(result.hrv.usual == nil)
        #expect(result.hrv.standing == .buildingUsual(daysLeft: 4))
        // Heart rate has all 28.
        #expect(result.restingLevel.usual?.days == 28)
    }

    // MARK: Gaps

    /// Sitting heart rate that climbs through the day, as it does after meals and coffee.
    private static let climbing: @Sendable (Double) -> Double = { hour in hour < 12 ? 60 : 74 }

    @Test func watchOffForTheAfternoonIsComparedWithTheSameHours() {
        var usual = Plan()
        usual.sitting = Self.climbing
        usual.awakeHRV = { $0 < 12 ? 46 : 34 }
        var gap = usual
        // Off the wrist from noon to 21:00: only the morning and late evening were recorded.
        gap.offWrist = [12...21]
        let result = summary(gap, history: history(usual))

        #expect(result.restingLevel.hours == 7)
        #expect(result.profile[14].heartRate == nil)
        #expect(result.profile[14].hrv == nil)
        // Set against the same 7 hours of earlier days, today is ordinary...
        #expect(result.restingLevel.standing == .within)
        #expect(result.awakeAverage.standing == .within)
        #expect(result.hrv.standing == .within)
        #expect(result.restingLevel.usual?.days == 28)

        // ...where whole earlier days would have made the average look low and the HRV high.
        let whole = summary(usual, history: history(usual))
        #expect((result.awakeAverage.value ?? 99) < (whole.awakeAverage.usual?.low ?? 0) - 2)
        #expect((result.hrv.value ?? 0) > (whole.hrv.usual?.high ?? 99) + 2)
    }

    @Test func aMorningInProgressIsComparedWithEarlierMornings() {
        var usual = Plan()
        usual.sitting = Self.climbing
        usual.awakeHRV = { $0 < 12 ? 46 : 34 }
        var morning = usual
        morning.until = 10
        let result = summary(morning, history: history(usual))
        // 07:00-10:00 only.
        #expect(result.restingLevel.count == 180)
        #expect(result.restingLevel.standing == .within)
        #expect(result.hrv.standing == .within)
        #expect(abs((result.hrv.usual?.median ?? 0) - 46) < 2)
        // Nothing is drawn for hours that have not happened yet.
        #expect(result.profile[15].heartRate == nil)
        #expect(result.hasHeartRate)
    }

    @Test func earlierDaysMissingMostOfTheHoursAreLeftOut() {
        let plan = Plan()
        var mostlyOff = Plan()
        // Earlier days with the watch on only until 11:00: 4 of today's 16 hours.
        mostlyOff.offWrist = [11...24]
        let days = history(plan, days: 14) + (15...28).map { reduced(mostlyOff, back: $0) }
        let result = summary(plan, history: days)
        #expect(result.restingLevel.baselineDays == 14)
        #expect(result.restingLevel.usual?.days == 14)
    }

    @Test func aDayWithNoHeartRateSaysSo() {
        let empty = DaytimeVitals.day(.init(), on: today, calendar: calendar)
        let result = DaytimeVitals.summary(for: empty, history: [], calendar: calendar)
        #expect(!result.hasHeartRate)
        #expect(result.restingLevel.standing == .notEnoughReadings)
        #expect(result.awakeRange == nil)
        #expect(result.hrvMetric == nil)
        #expect(result.profile.count == 24)
    }

    @Test func underHalfAnHourOfStillMinutesGivesNoRestingValue() {
        var plan = Plan()
        // Up at 07:00, and it is 07:20.
        plan.until = 7 + 20.0 / 60
        let result = summary(plan, history: history(Plan()))
        #expect(result.restingLevel.count == 20)
        #expect(result.restingLevel.value == nil)
        #expect(result.restingLevel.standing == .notEnoughReadings)
        #expect(result.awakeAverage.value == nil)
    }

    // MARK: Your usual

    @Test func aUsualRangeNeedsFourteenComparableDays() {
        let plan = Plan()
        let short = summary(plan, history: history(plan, days: 9))
        #expect(short.restingLevel.value != nil)
        #expect(short.restingLevel.usual == nil)
        #expect(short.restingLevel.standing == .buildingUsual(daysLeft: 5))

        let enough = summary(plan, history: history(plan, days: 14))
        #expect(enough.restingLevel.usual?.days == 14)
    }

    @Test func daysOlderThanFourWeeksAreNotPartOfTheUsual() {
        let plan = Plan()
        let result = summary(plan, history: history(plan, days: 40))
        #expect(result.restingLevel.usual?.days == DaytimeVitals.baselineWindowDays)
    }

    @Test func aDayWellOffTheUsualIsNamedWithoutAVerdict() throws {
        let plan = Plan()
        var raised = plan
        raised.sitting = { _ in 76 }
        raised.awakeHRV = { _ in 28 }
        let result = summary(raised, history: history(plan))
        #expect(result.restingLevel.standing == .above)
        #expect(result.awakeAverage.standing == .above)
        #expect(result.hrv.standing == .below)
        // The usual range is the middle two thirds of the earlier days.
        let usual = try #require(result.restingLevel.usual)
        #expect(usual.low < usual.median && usual.median < usual.high)
        #expect(usual.high - usual.low < 5)
    }

    @Test func oneLowAfternoonReadingDoesNotMoveTheDay() {
        let plan = Plan()
        var raw = input(plan, on: today)
        let index = raw.sdnn.firstIndex { $0.date >= today.addingTimeInterval(15 * 3600) }!
        raw.sdnn[index].value = 8
        let odd = DaytimeVitals.summary(for: DaytimeVitals.day(raw, on: today, calendar: calendar), history: history(plan), calendar: calendar)
        let plain = summary(plan, history: history(plan))
        #expect(abs((odd.hrv.value ?? 0) - (plain.hrv.value ?? 99)) < 0.5)
        #expect(odd.hrv.standing == .within)
    }

    @Test func aValueOnTheEdgeOfTheRangeCountsAsInside() {
        let usual = DaytimeVitals.Usual(low: 60, median: 62, high: 64, days: 20)
        func standing(_ value: Double) -> DaytimeVitals.Standing {
            DaytimeVitals.Measure(value: value, count: 100, needed: 30, usual: usual, baselineDays: 20).standing
        }
        #expect(standing(59.6) == .within)
        #expect(standing(64.4) == .within)
        #expect(standing(59.4) == .below)
        #expect(standing(64.6) == .above)
    }

    // MARK: HRV measure, naps, blood oxygen

    @Test func rmssdIsUsedWhenTheDayHasEnoughAndNeverMixedWithSDNN() {
        var plan = Plan()
        plan.rmssd = true
        plan.awakeHRV = { _ in 30 }
        // Earlier days hold SDNN only (around 40): not comparable.
        let sdnnDays = history(Plan())
        let mixed = summary(plan, history: sdnnDays)
        #expect(mixed.hrvMetric == .rmssd)
        #expect(abs((mixed.hrv.value ?? 0) - 30) < 2)
        #expect(mixed.hrv.baselineDays == 0)
        #expect(mixed.hrv.usual == nil)

        let same = summary(plan, history: history(plan))
        #expect(same.hrv.standing == .within)
        #expect(same.profile[10].usualHRV != nil)
    }

    @Test func aRecordedNapIsNotDaytime() {
        var plan = Plan()
        plan.sleep = [-1...7, 14...15, 23...31]
        let reducedDay = reduced(plan)
        #expect(reducedDay.hours[14].awake.count == 0)
        #expect(reducedDay.hours[14].resting.isEmpty)
        #expect(reducedDay.hours[14].state == .asleep)
        #expect(reducedDay.sleep.count == 3)
        // The nap's 52 bpm stays out of the awake range.
        let result = DaytimeVitals.summary(for: reducedDay, history: [], calendar: calendar)
        #expect((result.awakeRange?.lowerBound ?? 0) > 58)
    }

    @Test func bloodOxygenUsesAwakeReadingsOnly() {
        var raw = input(Plan(oxygenEvery: nil), on: today)
        raw.bloodOxygen = [
            .init(date: today.addingTimeInterval(3 * 3600), value: 91),   // asleep: overnight, not here
            .init(date: today.addingTimeInterval(9 * 3600), value: 98),
            .init(date: today.addingTimeInterval(13 * 3600), value: 96),
            .init(date: today.addingTimeInterval(17 * 3600), value: 97),
            .init(date: today.addingTimeInterval(18 * 3600), value: 40),  // a sensor error
        ]
        let result = DaytimeVitals.summary(for: DaytimeVitals.day(raw, on: today, calendar: calendar), history: [], calendar: calendar)
        #expect(result.bloodOxygen.count == 3)
        #expect(result.bloodOxygen.value == 97)
        #expect(result.lowestBloodOxygen == 96)
    }

    @Test func impossibleHeartRatesAreDropped() {
        var raw = input(Plan(), on: today)
        raw.heartRate.append(HeartRateSample(date: today.addingTimeInterval(10 * 3600 + 30), bpm: 0))
        raw.heartRate.append(HeartRateSample(date: today.addingTimeInterval(11 * 3600 + 30), bpm: 400))
        let result = DaytimeVitals.summary(for: DaytimeVitals.day(raw, on: today, calendar: calendar), history: [], calendar: calendar)
        #expect((result.awakeRange?.lowerBound ?? 0) > 58)
        #expect((result.awakeRange?.upperBound ?? 999) < 75)
    }

    // MARK: Storage and pieces

    @Test func aReducedDaySurvivesBeingStored() throws {
        var plan = Plan()
        plan.workouts = [18...19]
        plan.walks = [12.5...12.75]
        let original = reduced(plan)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(DaytimeVitals.Day.self, from: data)
        #expect(restored == original)
        // Small enough to keep a month of days on disk.
        #expect(data.count < 40_000)
        let before = DaytimeVitals.summary(for: original, history: [], calendar: calendar)
        let after = DaytimeVitals.summary(for: restored, history: [], calendar: calendar)
        #expect(before == after)
    }

    @Test func inputSpanningSeveralDaysIsCutToEachDay() {
        var both = input(Plan(), on: day(1))
        let second = input(Plan(), on: today)
        both.heartRate += second.heartRate
        both.sdnn += second.sdnn
        both.bloodOxygen += second.bloodOxygen
        both.sleep += second.sleep
        let fromBoth = DaytimeVitals.day(both, on: today, calendar: calendar)
        #expect(fromBoth == reduced(Plan()))
    }

    @Test func clippedMergesOverlapsAndCutsToTheDay() {
        let end = today.addingTimeInterval(86_400)
        let intervals = [
            DateInterval(start: today.addingTimeInterval(-3600), end: today.addingTimeInterval(7 * 3600)),
            DateInterval(start: today.addingTimeInterval(6 * 3600), end: today.addingTimeInterval(7.5 * 3600)),
            DateInterval(start: today.addingTimeInterval(23 * 3600), end: today.addingTimeInterval(31 * 3600)),
            DateInterval(start: today.addingTimeInterval(40 * 3600), end: today.addingTimeInterval(41 * 3600)),
        ]
        let result = DaytimeVitals.clipped(intervals, from: today, to: end)
        #expect(result == [
            DateInterval(start: today, end: today.addingTimeInterval(7.5 * 3600)),
            DateInterval(start: today.addingTimeInterval(23 * 3600), end: end),
        ])
    }

    @Test func percentileInterpolates() {
        #expect(DaytimeVitals.percentile([], 0.5) == nil)
        #expect(DaytimeVitals.percentile([7], 0.1) == 7)
        #expect(DaytimeVitals.percentile([1, 2, 3, 4, 5], 0.5) == 3)
        #expect(DaytimeVitals.percentile([10, 20], 0.25) == 12.5)
        #expect(DaytimeVitals.median([4, 1, 3, 2]) == 2.5)
    }

    @Test func clockHoursFollowTheCalendarOnAShortDay() {
        // 30 March 2025 in Berlin has no 02:00.
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = berlin.date(from: DateComponents(year: 2025, month: 3, day: 30))!
        let end = berlin.date(byAdding: .day, value: 1, to: start)!
        #expect(end.timeIntervalSince(start) == 23 * 3600)
        var raw = DaytimeVitals.Input()
        var date = start
        while date < end {
            raw.heartRate.append(HeartRateSample(date: date, bpm: 65))
            date = date.addingTimeInterval(60)
        }
        let reducedDay = DaytimeVitals.day(raw, on: start.addingTimeInterval(12 * 3600), calendar: berlin)
        #expect(reducedDay.hours.count == 24)
        #expect(reducedDay.hours[2].all.count == 0)
        #expect(reducedDay.hours[1].all.count == 60)
        #expect(reducedDay.hours[3].all.count == 60)
        #expect(reducedDay.hours[23].all.count == 60)
    }
}
