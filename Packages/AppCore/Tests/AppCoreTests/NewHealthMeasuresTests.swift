import Foundation
import Testing
@testable import AppCore

/// Walking speed, Apple's heart events, DEXA fields, waist-to-hip, waist
/// readings from Health, the social connection check and the mindful factor.
struct NewHealthMeasuresTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9))! }

    func daysAgo(_ days: Int, hour: Int = 12) -> Date {
        calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!.addingTimeInterval(Double(hour) * 3600)
    }

    // MARK: Walking speed

    @Test func walkingSpeedIsGradedOnlyFromSixty() {
        #expect(WalkingSpeed.grade(metersPerSecond: 0.7, age: 59) == nil)
        #expect(WalkingSpeed.grade(metersPerSecond: 0.7, age: 60) == .slower)
        #expect(WalkingSpeed.grade(metersPerSecond: 0.8, age: 70) == .typical)
        #expect(WalkingSpeed.grade(metersPerSecond: 0.99, age: 70) == .typical)
        #expect(WalkingSpeed.grade(metersPerSecond: 1.0, age: 70) == .brisk)
    }

    @Test func walkingSpeedTrendComparesTheEndsOfNinetyDays() throws {
        let early = (62...89).map { DayValue(date: daysAgo($0), value: 1.30) }
        let late = (0...27).map { DayValue(date: daysAgo($0), value: 1.38) }
        let trend = try #require(WalkingSpeed.trend(early + late, now: now, calendar: calendar))
        #expect(abs(trend.change - 0.08) < 0.0001)
        #expect(trend.isSteady == false)
        let flat = (0...89).map { DayValue(date: daysAgo($0), value: 1.3) }
        #expect(WalkingSpeed.trend(flat, now: now, calendar: calendar)?.isSteady == true)
        // Too few readings at one end: no trend.
        #expect(WalkingSpeed.trend(late, now: now, calendar: calendar) == nil)
    }

    @Test func walkingSpeedStatusSaysTrackedUnderSixty() {
        #expect(WalkingSpeed.status(average: 1.4, trend: nil, age: 34, miles: false) == "Tracked, not graded under 60")
        #expect(WalkingSpeed.status(average: 1.4, trend: .init(change: 0.01), age: 34, miles: false) == "Steady over 3 months")
        #expect(WalkingSpeed.status(average: 1.4, trend: .init(change: -0.1), age: 34, miles: false) == "−0.4 km/h over 3 months")
        #expect(WalkingSpeed.status(average: 0.75, trend: .init(change: 0), age: 66, miles: false) == "Slower range")
        #expect(WalkingSpeed.status(average: nil, trend: nil, age: 34, miles: false) == nil)
    }

    @Test func recentAverageUsesTheLastWeek() {
        let series = [DayValue(date: daysAgo(10), value: 2.0), DayValue(date: daysAgo(3), value: 1.2), DayValue(date: daysAgo(0), value: 1.4)]
        #expect(abs((WalkingSpeed.recentAverage(series, now: now, calendar: calendar) ?? 0) - 1.3) < 0.0001)
        #expect(abs(WalkingSpeed.display(1.0, miles: false) - 3.6) < 0.0001)
    }

    // MARK: Heart events

    @Test func heartEventLineIsHiddenAtZero() {
        #expect(HeartEvents.Counts(high: 0, low: 0, irregular: 0).line == nil)
    }

    @Test func heartEventLineCountsEachKind() {
        #expect(HeartEvents.Counts(high: 1, low: 0, irregular: 0).line
            == "Apple flagged 1 high alert in the last 30 days; see the Health app.")
        #expect(HeartEvents.Counts(high: 2, low: 0, irregular: 1).line
            == "Apple flagged 2 high and 1 irregular rhythm alerts in the last 30 days; see the Health app.")
        #expect(HeartEvents.Counts(high: 2, low: 1, irregular: 1).line
            == "Apple flagged 2 high, 1 low and 1 irregular rhythm alerts in the last 30 days; see the Health app.")
    }

    @Test func heartEventsOutsideThirtyDaysDontCount() {
        let counts = HeartEvents.counts(high: [daysAgo(2), daysAgo(40)], low: [], irregular: [daysAgo(29)], now: now)
        #expect(counts == HeartEvents.Counts(high: 1, low: 0, irregular: 1))
    }

    // MARK: DEXA

    @Test func almiIsLeanMassOverHeightSquared() throws {
        let almi = try #require(DexaMeasures.almi(appendicularLeanKg: 27.0, heightCm: 180))
        #expect(abs(almi - 8.333) < 0.001)
        #expect(DexaMeasures.reading(almi: almi, sex: .male) == .above)
        #expect(DexaMeasures.reading(almi: 6.9, sex: .male) == .below)
        #expect(DexaMeasures.reading(almi: 6.0, sex: .female) == .above)
        #expect(DexaMeasures.almi(appendicularLeanKg: 27, heightCm: 70) == nil)
        #expect(DexaMeasures.almi(appendicularLeanKg: 270, heightCm: 180) == nil)
    }

    @Test func vatIsShownAsChangeNotGraded() {
        #expect(DexaMeasures.vatChange(latest: 480, previous: 600, unit: .grams) == "−120 g since your last scan")
        #expect(DexaMeasures.vatChange(latest: 90, previous: 85, unit: .squareCentimeters) == "+5 cm² since your last scan")
        #expect(DexaMeasures.vatChange(latest: 480, previous: nil, unit: .grams) == nil)
        #expect(DexaMeasures.vatText.contains("no agreed cut-off"))
    }

    // MARK: Waist and hip

    @Test func waistToHipUsesTheWHOLines() throws {
        let ratio = try #require(WaistToHipRatio.ratio(waistCm: 86, hipCm: 100))
        #expect(abs(ratio - 0.86) < 0.0001)
        #expect(WaistToHipRatio.isRaised(ratio, sex: .male) == false)
        #expect(WaistToHipRatio.isRaised(ratio, sex: .female) == true)
        #expect(WaistToHipRatio.ratio(waistCm: 86, hipCm: 30) == nil)
    }

    @Test func healthWaistReadingsAreMergedWithoutDuplicates() {
        let typed = [WaistReadings.Reading(date: daysAgo(4, hour: 8), centimeters: 86, fromHealth: false)]
        let health = [
            // The same tape reading, written by another app the same day.
            WaistReadings.Reading(date: daysAgo(4, hour: 9), centimeters: 86.4, fromHealth: true),
            WaistReadings.Reading(date: daysAgo(40), centimeters: 88, fromHealth: true),
        ]
        let merged = WaistReadings.merge(typed: typed, health: health, calendar: calendar)
        #expect(merged.map(\.centimeters) == [88, 86])
        #expect(merged.map(\.fromHealth) == [true, false])
    }

    // MARK: Social connection

    @Test func uclaThreeItemScoresThreeToNine() {
        let low = SocialConnectionCheck.Result(date: now, answers: [1, 1, 1])
        #expect(low.score == 3)
        #expect(low.suggestsLoneliness == false)
        let five = SocialConnectionCheck.Result(date: now, answers: [2, 2, 1])
        #expect(five.suggestsLoneliness == false)
        let six = SocialConnectionCheck.Result(date: now, answers: [2, 2, 2])
        #expect(six.score == 6)
        #expect(six.suggestsLoneliness)
        #expect(SocialConnectionCheck.Result(date: now, answers: [3, 3, 3]).score == 9)
        #expect(SocialConnectionCheck.Result(date: now, answers: [0, 2, 2]).isComplete == false)
        #expect(SocialConnectionCheck.Result(date: now, answers: [2, 2]).isComplete == false)
        #expect(!six.meaning.lowercased().contains("diagnos"))
    }

    @Test func socialCheckIsOffByDefaultAndQuarterly() {
        #expect(SocialConnectionCheck.isDue(enabled: false, lastTaken: nil, now: now, calendar: calendar) == false)
        #expect(SocialConnectionCheck.isDue(enabled: true, lastTaken: nil, now: now, calendar: calendar))
        #expect(SocialConnectionCheck.isDue(enabled: true, lastTaken: daysAgo(90), now: now, calendar: calendar) == false)
        #expect(SocialConnectionCheck.isDue(enabled: true, lastTaken: daysAgo(91), now: now, calendar: calendar))
    }

    // MARK: Mindful minutes

    @Test func mindfulSessionIsAFactorOnlyForPeopleWhoLogThem() throws {
        let factor = try #require(CheckInInsights.factors.first { $0.id == "mindful" })
        func day(_ minutes: Double?) -> CheckInDay {
            CheckInDay(morning: now, evening: nil, checkIn: nil, hrv: 50, restingHeartRate: nil, sleepScore: nil, mindfulMinutesYesterday: minutes)
        }
        #expect(factor.test(day(nil)) == nil)
        #expect(factor.test(day(0)) == false)
        #expect(factor.test(day(10)) == true)
    }

    @Test func mindfulDaysCanShowAPattern() {
        // HRV runs higher the morning after a session, with normal noise.
        let days = (0..<28).map { index -> CheckInDay in
            let mindful = index % 2 == 0
            let noise = Double(index % 5) - 2
            return CheckInDay(morning: now.addingTimeInterval(Double(index) * 86_400), evening: nil, checkIn: nil,
                              hrv: (mindful ? 60 : 48) + noise, restingHeartRate: nil, sleepScore: nil,
                              mindfulMinutesYesterday: mindful ? 12 : 0)
        }
        let insight = CheckInInsights.analyze(days).first { $0.factor == "A mindful session" }
        #expect(insight?.outcome == .hrv)
        #expect(insight?.isGood == true)
    }
}
