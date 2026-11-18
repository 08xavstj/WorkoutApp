import Foundation
import Testing
@testable import AppCore

struct WeeklyIntensityTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()
    // Resting 60, maximum 187 (Tanaka at 30): moderate 111-135 bpm, vigorous 136+.
    let profile = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 60)
    var scheme: HeartRateZoneScheme { .reserve(resting: 60, maximum: profile.maxHeartRate) }

    func monday() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 16))!
    }

    /// One reading a minute for `minutes` minutes from `start`.
    func minutes(_ minutes: Int, at bpm: Double, from start: Date) -> [HeartRateSample] {
        (0..<minutes).map { HeartRateSample(date: start.addingTimeInterval(Double($0) * 60), bpm: bpm) }
    }

    @Test func weekStartsEndWithTheCurrentWeek() {
        let starts = WeeklyIntensity.weekStarts(endingWith: monday().addingTimeInterval(3 * 86_400), count: 12, calendar: calendar)
        #expect(starts.count == 12)
        #expect(starts.last == monday())
        #expect(zip(starts, starts.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 7 * 86_400 })
        #expect(WeeklyIntensity.weekStarts(endingWith: monday(), count: 0, calendar: calendar).isEmpty)
    }

    @Test func vigorousMinutesCountDouble() {
        let start = monday().addingTimeInterval(8 * 3600)
        // 40 min moderate (125 bpm) then, an hour later, 30 min vigorous (150 bpm).
        let readings = minutes(40, at: 125, from: start) + minutes(30, at: 150, from: start.addingTimeInterval(7200))
        let week = WeeklyIntensity.week(start: monday(), end: monday().addingTimeInterval(7 * 86_400),
                                        heartRate: readings, lifting: [], profile: profile, scheme: scheme)
        #expect(week.moderate == 40)
        #expect(week.vigorous == 30)
        #expect(week.moderateEquivalent == 100)
        #expect(week.standing == .below)
        #expect(week.zoneMinutes.count == 5)
        // 150 bpm is zone 3 (149-162), 125 bpm zone 1 (124-136).
        #expect(abs(week.zoneMinutes[2] - 29) < 1.01)
        #expect(abs(week.zoneMinutes[0] - 39) < 1.01)
        #expect(week.hasHeartRate)
    }

    @Test func liftingIsLeftOut() {
        let start = monday().addingTimeInterval(18 * 3600)
        let readings = minutes(60, at: 140, from: start)
        let lifting = [DateInterval(start: start, duration: 3600)]
        let week = WeeklyIntensity.week(start: monday(), end: monday().addingTimeInterval(7 * 86_400),
                                        heartRate: readings, lifting: lifting, profile: profile, scheme: scheme)
        #expect(week.moderateEquivalent == 0)
        #expect(week.zoneMinutes.reduce(0, +) == 0)
        #expect(week.hasHeartRate)
    }

    @Test func weeksSplitAtTheirStarts() {
        let starts = WeeklyIntensity.weekStarts(endingWith: monday(), count: 2, calendar: calendar)
        let readings = minutes(160, at: 125, from: starts[0].addingTimeInterval(86_400))
            + minutes(20, at: 160, from: starts[1].addingTimeInterval(86_400))
        let weeks = WeeklyIntensity.weeks(starts: starts, heartRate: readings, lifting: [], profile: profile, scheme: scheme, calendar: calendar)
        #expect(weeks.map(\.moderateEquivalent) == [160, 40])
        #expect(weeks.map(\.standing) == [.within, .below])
        #expect(WeeklyIntensity.weeksMet(weeks) == (1, 2))
    }

    @Test func noHeartRateIsAnEmptyWeek() {
        let week = WeeklyIntensity.week(start: monday(), end: monday().addingTimeInterval(7 * 86_400),
                                        heartRate: [], lifting: [], profile: profile, scheme: scheme)
        #expect(!week.hasHeartRate)
        #expect(week.zoneMinutes == [0, 0, 0, 0, 0])
        #expect(WeeklyIntensity.weeksMet([week]) == (0, 0))
    }

    @Test func standingBand() {
        #expect(WeeklyIntensity.standing(149) == .below)
        #expect(WeeklyIntensity.standing(150) == .within)
        #expect(WeeklyIntensity.standing(300) == .within)
        #expect(WeeklyIntensity.standing(301) == .above)
    }

    @Test func signatureChangesWithTheZones() {
        let other = HeartRateZoneScheme.reserve(resting: 55, maximum: profile.maxHeartRate)
        #expect(WeeklyIntensity.signature(profile: profile, scheme: scheme) != WeeklyIntensity.signature(profile: profile, scheme: other))
    }

    @Test func zoneMinutesNeedFortyPercentOfReserve() throws {
        // Apple Health zones with no floor: zone 1 is everything under 120.
        let noFloor = try #require(HeartRateZoneScheme.appleHealth(floor: nil, boundaries: [120, 135, 150, 165],
                                                                   easyBand: scheme.easyBand))
        let start = monday().addingTimeInterval(8 * 3600)
        // Ten hours at the desk (70 bpm, 8% of reserve), then 30 min at
        // 115 bpm (43%): only the 30 count.
        let readings = minutes(600, at: 70, from: start) + minutes(30, at: 115, from: start.addingTimeInterval(600 * 60))
        let week = WeeklyIntensity.week(start: monday(), end: monday().addingTimeInterval(7 * 86_400),
                                        heartRate: readings, lifting: [], profile: profile, scheme: noFloor)
        #expect(abs(week.zoneMinutes[0] - 29) < 1.01)
        #expect(week.zoneMinutes.reduce(0, +) < 31)
        #expect(WeeklyIntensity.signature(profile: profile, scheme: scheme).hasPrefix("v\(WeeklyIntensity.countingVersion)|"))
    }

    @Test func weekStartsStayAtMidnightAcrossADaylightSavingChange() throws {
        // Santiago moves its clocks from 00:00 to 01:00 in September, so the
        // Sunday of the change starts at 01:00.
        var santiago = Calendar(identifier: .gregorian)
        santiago.timeZone = try #require(TimeZone(identifier: "America/Santiago"))
        santiago.firstWeekday = 1
        let change = try #require(santiago.timeZone.nextDaylightSavingTimeTransition(after: monday().addingTimeInterval(-200 * 86_400)))
        let changeDay = santiago.startOfDay(for: change)
        try #require(santiago.component(.hour, from: changeDay) == 1)
        // From five weeks after the change, back past it, and from its own week.
        for end in [changeDay.addingTimeInterval(35 * 86_400), changeDay.addingTimeInterval(3600)] {
            let starts = WeeklyIntensity.weekStarts(endingWith: end, count: 12, calendar: santiago)
            #expect(starts.count == 12)
            for start in starts {
                #expect(start == santiago.dateInterval(of: .weekOfYear, for: start)?.start)
                #expect(start == santiago.startOfDay(for: start))
            }
        }
    }

    @Test func liftingFingerprintsChangeWhenASessionIsEdited() {
        let starts = WeeklyIntensity.weekStarts(endingWith: monday(), count: 2, calendar: calendar)
        let session = DateInterval(start: starts[0].addingTimeInterval(86_400 + 18 * 3600), duration: 3600)
        let longer = DateInterval(start: session.start, duration: 4200)
        let before = WeeklyIntensity.liftingFingerprints([session], weekStarts: starts, calendar: calendar)
        let after = WeeklyIntensity.liftingFingerprints([longer], weekStarts: starts, calendar: calendar)
        #expect(before[starts[0]] != after[starts[0]])
        #expect(before[starts[1]] == "" && after[starts[1]] == "")
        // The same sessions in another order give the same key.
        let other = DateInterval(start: starts[0].addingTimeInterval(3 * 86_400), duration: 1800)
        #expect(WeeklyIntensity.liftingFingerprints([session, other], weekStarts: starts, calendar: calendar)
            == WeeklyIntensity.liftingFingerprints([other, session], weekStarts: starts, calendar: calendar))
    }

    @Test func weekRoundTripsThroughJSON() throws {
        let week = WeeklyIntensity.Week(start: monday(), zoneMinutes: [1, 2, 3, 4, 5], moderate: 10, vigorous: 5, hasHeartRate: true)
        #expect(try JSONDecoder().decode(WeeklyIntensity.Week.self, from: JSONEncoder().encode(week)) == week)
    }
}
