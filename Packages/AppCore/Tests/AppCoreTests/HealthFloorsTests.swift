import Foundation
import Testing
@testable import AppCore

struct HealthFloorsTests {
    /// A lifter's typical week: strength easily met, cardio and steps short.
    private var lifterWeek: HealthFloors.Week {
        HealthFloors.Week(moderateMinutes: 70, vigorousMinutes: 12, strengthDays: 4, averageSteps: 6_400, stepDays: 7,
                          sleepRegularity: 88, drinks: 2, drinkNightsLogged: 7)
    }

    @Test func theFiveLinesAreThePublishedOnes() {
        #expect(HealthFloors.activeMinutes == 150)        // WHO 2020
        #expect(HealthFloors.strengthDays == 2)           // WHO 2020
        #expect(HealthFloors.dailySteps == 7_000)         // Ding 2025
        #expect(HealthFloors.sleepRegularity == 87)       // Windred 2024 most regular fifth
        #expect(HealthFloors.drinks == 2)                 // CCSA 2023 low-risk tier
        #expect(IntensityMinutes.vigorousWeight == 2)     // WHO's exchange rate, kept on purpose
    }

    @Test func aLiftersWeekPassesStrengthAndMissesCardioAndSteps() {
        let result = HealthFloors.assess(lifterWeek)
        #expect(result.checks.map(\.floor) == [.activeMinutes, .strengthDays, .steps, .sleepRegularity, .drinks])
        #expect(result.check(.strengthDays)?.met == true)
        #expect(result.check(.activeMinutes)?.met == false) // 70 + 2 x 12 = 94
        #expect(result.check(.activeMinutes)?.valueText == "94 min")
        #expect(result.check(.steps)?.met == false)
        #expect(result.check(.steps)?.valueText == "6,400 a day")
        #expect(result.check(.sleepRegularity)?.met == true)
        #expect(result.check(.drinks)?.met == true)
        #expect(result.summary == "3 of 5")
        #expect(result.firstUnmet == .activeMinutes)
        #expect(result.unmet == [.activeMinutes, .steps])
    }

    @Test func boundariesSitOnTheLine() {
        func met(_ floor: HealthFloors.Floor, _ change: (inout HealthFloors.Week) -> Void) -> Bool? {
            var week = lifterWeek
            change(&week)
            return HealthFloors.assess(week).check(floor)?.met
        }
        #expect(met(.activeMinutes) { $0.moderateMinutes = 150; $0.vigorousMinutes = 0 } == true)
        #expect(met(.activeMinutes) { $0.moderateMinutes = 149; $0.vigorousMinutes = 0 } == false)
        #expect(met(.activeMinutes) { $0.moderateMinutes = 0; $0.vigorousMinutes = 75 } == true)   // vigorous counts double
        #expect(met(.activeMinutes) { $0.moderateMinutes = 0; $0.vigorousMinutes = 74 } == false)
        #expect(met(.strengthDays) { $0.strengthDays = 2 } == true)
        #expect(met(.strengthDays) { $0.strengthDays = 1 } == false)
        #expect(met(.strengthDays) { $0.strengthDays = 0 } == false)
        #expect(met(.steps) { $0.averageSteps = 7_000 } == true)
        #expect(met(.steps) { $0.averageSteps = 6_999 } == false)
        #expect(met(.sleepRegularity) { $0.sleepRegularity = 87 } == true)
        #expect(met(.sleepRegularity) { $0.sleepRegularity = 86 } == false)
        #expect(met(.drinks) { $0.drinks = 2 } == true)
        #expect(met(.drinks) { $0.drinks = 2.5 } == false)
        #expect(met(.drinks) { $0.drinks = 0 } == true)
    }

    /// A missing value is "not known": no tick either way, and it is left out
    /// of the count rather than counted as a miss.
    @Test func missingDataIsNotAMiss() {
        var week = lifterWeek
        week.drinks = 1
        week.drinkNightsLogged = 3 // under 4 evenings logged
        week.moderateMinutes = nil
        week.vigorousMinutes = nil
        week.stepDays = 3
        let result = HealthFloors.assess(week)
        #expect(result.check(.drinks)?.met == nil)
        #expect(result.check(.drinks)?.valueText == "No data")
        #expect(result.check(.activeMinutes)?.met == nil)
        #expect(result.check(.steps)?.met == nil)
        #expect(result.knownCount == 2)
        #expect(result.summary == "2 of 2")
        #expect(result.firstUnmet == nil)
        #expect(HealthFloors.assess(HealthFloors.Week()).summary == "No data yet")
    }

    /// The summary is a count with the numbers beside it, never a percentage.
    @Test func noPercentagesAnywhere() {
        let result = HealthFloors.assess(lifterWeek)
        #expect(!result.summary.contains("%"))
        for check in result.checks {
            #expect(!check.valueText.contains("%"), "\(check.floor)")
            #expect(!check.targetText.contains("%"), "\(check.floor)")
        }
    }

    @Test func vigorousMinutesGetTheirOwnLineWithTheCohortLabel() {
        let note = HealthFloors.assess(lifterWeek).check(.activeMinutes)?.note ?? ""
        #expect(note.hasPrefix("Vigorous: 12 min."))
        #expect(note.contains("15-20 a week"))
        #expect(note.contains("Ahmadi 2022"))
        #expect(note.contains("one wearable cohort"))
        #expect(note.contains("not proof"))
        #expect(IntensityMinutes.vigorousReferenceMinutes == 15...20)
        #expect(IntensityMinutes.vigorousLowestRiskMinutes == 54)
        #expect(IntensityMinutes.vigorousLine(0).hasPrefix("Vigorous: 0 min."))
    }

    /// The review's tick and Longevity's "on target" are the same rule, for
    /// every value either side of every line (a goal that isn't stamina).
    @Test func theReviewAndLongevityNeverDisagree() {
        func longevity(_ id: Longevity.MeasureID, _ change: (inout Longevity.Inputs) -> Void) -> Bool {
            var inputs = Longevity.Inputs(age: 34, sex: .male, goals: Goals(weight: .lose, focuses: [.muscle, .strength]))
            change(&inputs)
            return Longevity.assess(inputs).measure(id)?.status == .onTarget
        }
        func review(_ floor: HealthFloors.Floor, _ week: HealthFloors.Week) -> Bool {
            HealthFloors.assess(week).check(floor)?.met == true
        }
        for steps in stride(from: 3_000.0, through: 12_000, by: 250) + [6_999, 7_000, 7_001, 7_999, 8_000] {
            #expect(review(.steps, HealthFloors.Week(averageSteps: steps, stepDays: 7)) == longevity(.steps) { $0.dailySteps = steps }, "steps \(steps)")
        }
        for moderate in stride(from: 0, through: 320, by: 10) {
            for vigorous in [0, 5, 14, 15, 37, 38, 75, 76] {
                let week = HealthFloors.Week(moderateMinutes: moderate, vigorousMinutes: vigorous)
                let page = longevity(.activeMinutes) { $0.moderateMinutes = moderate; $0.vigorousMinutes = vigorous }
                #expect(review(.activeMinutes, week) == page, "minutes \(moderate)+\(vigorous)")
            }
        }
        for days in 0...7 {
            #expect(review(.strengthDays, HealthFloors.Week(strengthDays: days)) == longevity(.strengthDays) { $0.strengthDaysByWeek = [days, days, days, days] }, "strength \(days)")
        }
        for index in 50...100 {
            #expect(review(.sleepRegularity, HealthFloors.Week(sleepRegularity: index)) == longevity(.sleepRegularity) { $0.sleepRegularity = index }, "regularity \(index)")
        }
        for half in 0...24 {
            let drinks = Double(half) / 2
            for nights in [3, 4, 7] {
                let week = HealthFloors.Week(drinks: drinks, drinkNightsLogged: nights)
                let page = longevity(.alcohol) { $0.drinksPerWeek = drinks; $0.drinkNightsLogged = nights }
                #expect(review(.drinks, week) == page, "drinks \(drinks), \(nights) nights")
            }
        }
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Seven days as the app reads them, into one week's numbers: unknown
    /// days are left out, never counted as zero.
    @Test func aWeekIsBuiltFromItsDays() {
        let monday = utc.date(from: DateComponents(year: 2026, month: 11, day: 9))!
        let days = (0..<7).map { offset -> WeeklyChangeReview.Day in
            var day = WeeklyChangeReview.Day(date: utc.date(byAdding: .day, value: offset, to: monday)!)
            if offset < 6 { // the watch was off on Sunday
                day.moderateMinutes = 12
                day.vigorousMinutes = offset == 2 ? 20 : 0
            }
            day.strengthSession = [0, 2, 4, 5].contains(offset)
            day.steps = offset == 6 ? 0 : 6_000 + Double(offset) * 300 // Sunday's 0 is a missing count
            if offset != 3 { day.drinks = offset == 5 ? 3 : 0 }
            return day
        }
        let week = HealthFloors.week(from: days, sleepRegularity: 77)
        #expect(week.moderateMinutes == 72)
        #expect(week.vigorousMinutes == 20)
        #expect(week.strengthDays == 4)
        #expect(week.stepDays == 6)
        #expect(week.averageSteps == 6_750)
        #expect(week.drinks == 3)
        #expect(week.drinkNightsLogged == 6)
        #expect(week.sleepRegularity == 77)
        let result = HealthFloors.assess(week)
        #expect(result.summary == "1 of 5") // strength only: 112 min, 6,750 steps, 77, 3 drinks
        #expect(result.firstUnmet == .activeMinutes)

        // Heart rate on four days is too thin to judge the week's minutes.
        let thin = days.enumerated().map { index, day -> WeeklyChangeReview.Day in
            var day = day
            if index >= 4 { day.moderateMinutes = nil; day.vigorousMinutes = nil }
            return day
        }
        #expect(HealthFloors.week(from: thin, sleepRegularity: nil).moderateMinutes == nil)
        // Sessions not known at all: no number, not zero.
        let unknown = days.map { day -> WeeklyChangeReview.Day in var day = day; day.strengthSession = nil; return day }
        #expect(HealthFloors.week(from: unknown, sleepRegularity: nil).strengthDays == nil)
    }

    /// The week's regularity compares each of its seven nights with the one before.
    @Test func sleepRegularityCoversTheWeeksSevenNights() {
        let monday = utc.date(from: DateComponents(year: 2026, month: 11, day: 9))!
        func night(_ offset: Int, bed: Double, hours: Double) -> DateInterval {
            let evening = utc.date(byAdding: .day, value: offset, to: monday)!
            return DateInterval(start: evening.addingTimeInterval(bed * 3600), duration: hours * 3600)
        }
        // Sunday night before the week through Sunday night: 23:00-07:00 every night.
        let steady = (-1...6).map { night($0, bed: 23, hours: 8) }
        #expect(HealthFloors.sleepRegularity(asleep: steady, weekStart: monday, calendar: utc) == 100)
        // Monday, Wednesday and Friday nights three hours later: six of the
        // seven pairs differ by six hours, so about 57.
        let shifted = (-1...6).map { night($0, bed: [0, 2, 4].contains($0) ? 26 : 23, hours: 8) }
        let score = HealthFloors.sleepRegularity(asleep: shifted, weekStart: monday, calendar: utc) ?? 0
        #expect(score < HealthFloors.sleepRegularity && score > 50)
        // Three nights is too few.
        #expect(HealthFloors.sleepRegularity(asleep: Array(steady.prefix(3)), weekStart: monday, calendar: utc) == nil)
    }

    /// The one stated difference: a stamina goal raises Longevity's line to
    /// 300; the floor stays 150 for everyone.
    @Test func aStaminaGoalRaisesLongevitysLineNotTheFloor() {
        let stamina = Goals(weight: .maintain, focuses: [.endurance])
        #expect(Longevity.activeMinutesTarget(goals: stamina) == 300)
        #expect(Longevity.activeMinutesTarget(goals: nil) == HealthFloors.activeMinutes)
        #expect(HealthFloors.activeMinutesMet(moderate: 200, vigorous: 0))
    }
}
