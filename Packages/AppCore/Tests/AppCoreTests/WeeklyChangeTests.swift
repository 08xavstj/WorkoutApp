import Foundation
import Testing
@testable import AppCore

struct WeeklyChangeTests {
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Monday 2 November 2026, 00:00 UTC: the week being reviewed.
    var monday: Date { utc.date(from: DateComponents(year: 2026, month: 11, day: 2))! }

    typealias Day = WeeklyChangeReview.Day

    func day(_ offset: Int, _ fill: (inout Day) -> Void = { _ in }) -> Day {
        var day = Day(date: utc.date(byAdding: .day, value: offset, to: monday)!)
        fill(&day)
        return day
    }

    /// Last week (offsets 0...6) and the four weeks before (-28 ... -1).
    func weeks(_ fill: (Int, inout Day) -> Void) -> (week: [Day], earlier: [Day]) {
        let week = (0..<7).map { offset in day(offset) { fill(offset, &$0) } }
        let earlier = (-28..<0).map { offset in day(offset) { fill(offset, &$0) } }
        return (week, earlier)
    }

    // MARK: The model

    @Test func plansSavedWithPlainStringsDecodeAsFreeText() throws {
        let json = """
        {"weekStart": 0, "plannedDays": [], "changes": ["Bed by 11", "Protein at breakfast"]}
        """
        let plan = try JSONDecoder().decode(WeeklyPlan.self, from: Data(json.utf8))
        #expect(plan.changes.count == 2)
        #expect(plan.changes[0] == WeeklyChange(text: "Bed by 11"))
        #expect(plan.changes[0].kind == .custom)
        #expect(!plan.changes[0].isMeasured)
        #expect(plan.changes.map(\.title) == ["Bed by 11", "Protein at breakfast"])
        // A plan saved before changes existed at all.
        let bare = try JSONDecoder().decode(WeeklyPlan.self, from: Data(#"{"weekStart": 0}"#.utf8))
        #expect(bare.changes.isEmpty)
    }

    @Test func typedChangesRoundTripAndSitBesideOldStrings() throws {
        let plan = WeeklyPlan(weekStart: monday, changes: [
            .caffeineCutoff(byMinutes: 14 * 60), .bedBy(minutes: 23 * 60, nights: 4), "Phone out of the bedroom",
        ])
        let decoded = try JSONDecoder().decode(WeeklyPlan.self, from: JSONEncoder().encode(plan))
        #expect(decoded == plan)
        #expect(decoded.changes[0].kind == .caffeineCutoff)
        #expect(decoded.changes[0].target == 840)
        #expect(decoded.changes[1].days == 4)
        #expect(decoded.changes[2].kind == .custom)
        // A file with both shapes in one list (written across an update).
        let mixed = """
        {"weekStart": 0, "changes": ["A walk after lunch", {"kind": "stepsAverage", "title": "Average 7,000 steps a day", "target": 7000}]}
        """
        let both = try JSONDecoder().decode(WeeklyPlan.self, from: Data(mixed.utf8))
        #expect(both.changes.map(\.kind) == [.custom, .stepsAverage])
        #expect(both.changes[1].target == 7_000)
    }

    @Test func aKindFromALaterVersionKeepsItsWordsAsFreeText() throws {
        let json = #"[{"kind": "daylight", "title": "30 minutes outside before noon", "target": 30}]"#
        let changes = try JSONDecoder().decode([WeeklyChange].self, from: Data(json.utf8))
        #expect(changes.count == 1)
        #expect(changes[0].kind == .custom)
        #expect(changes[0].title == "30 minutes outside before noon")
    }

    @Test func oneOfEachMeasuredKindAndFreeTextByItsWords() {
        #expect(WeeklyChange.stepsAverage().id == WeeklyChange.stepsAverage(9_000).id)
        #expect(WeeklyChange(text: "A").id != WeeklyChange(text: "B").id)
        #expect(WeeklyChange.defaultCount == 1)
        #expect(WeeklyChange.maximumCount == 3)
        #expect(WeeklyChange.bedBy(minutes: 1380, nights: 9).days == 7)
        #expect(WeeklyChange.bedBy(minutes: 1380, nights: 1).days == 3)
        #expect(WeeklyChange.bedBy(minutes: 1380).days == 5)
        #expect(WeeklyChange.bedBy(minutes: 1380, nights: 7).title.hasSuffix("every night"))
        #expect(WeeklyChange.drinksLimit(4).title == "Up to 4 drinks this week")
        #expect(WeeklyChange.drinksLimit(1).title == "Up to 1 drink this week")
        #expect(WeeklyChange.drinksLimit(0).title == "No drinks this week")
        #expect(WeeklyChange.stepsAverage().title == "Average 7,000 steps a day")
        // "Cardio", not "active": the minutes leave lifting out (evidence audit M1).
        #expect(WeeklyChange.activeMinutes.title == "150 cardio minutes")
        #expect(WeeklyChange.strengthDays.title == "Strength training on 2 days")
    }

    @Test func eveningMinutesRunPastMidnight() {
        let evening = utc.date(byAdding: .minute, value: 22 * 60 + 30, to: monday)!
        let afterMidnight = utc.date(byAdding: .minute, value: 24 * 60 + 20, to: monday)!
        #expect(WeeklyChange.eveningMinutes(evening, calendar: utc) == 1350)
        #expect(WeeklyChange.eveningMinutes(afterMidnight, calendar: utc) == 1460)
    }

    // MARK: Kept, day by day

    @Test func caffeineIsKeptUpToTheMinuteAndUnknownWithoutData() {
        let change = WeeklyChange.caffeineCutoff(byMinutes: 14 * 60)
        #expect(WeeklyChangeReview.kept(change, on: day(0) { $0.lastCaffeineMinutes = 14 * 60 }) == true)
        #expect(WeeklyChangeReview.kept(change, on: day(0) { $0.lastCaffeineMinutes = 14 * 60 + 1 }) == false)
        #expect(WeeklyChangeReview.kept(change, on: day(0) { $0.lastCaffeineMinutes = 8 * 60 }) == true)
        #expect(WeeklyChangeReview.kept(change, on: day(0) { $0.noCaffeine = true }) == true)
        #expect(WeeklyChangeReview.kept(change, on: day(0)) == nil)
    }

    @Test func bedByCountsBedtimesAfterMidnightAsLater() {
        let change = WeeklyChange.bedBy(minutes: 23 * 60 + 30)
        #expect(WeeklyChangeReview.kept(change, on: day(0) { $0.bedtimeMinutes = 23 * 60 }) == true)
        #expect(WeeklyChangeReview.kept(change, on: day(0) { $0.bedtimeMinutes = 23 * 60 + 30 }) == true)
        #expect(WeeklyChangeReview.kept(change, on: day(0) { $0.bedtimeMinutes = 1440 + 15 }) == false) // 00:15
        // A window that itself ends after midnight.
        let late = WeeklyChange.bedBy(minutes: 1440 + 30)
        #expect(WeeklyChangeReview.kept(late, on: day(0) { $0.bedtimeMinutes = 1440 + 15 }) == true)
        #expect(WeeklyChangeReview.kept(late, on: day(0) { $0.bedtimeMinutes = 1440 + 45 }) == false)
        #expect(WeeklyChangeReview.kept(late, on: day(0)) == nil)
    }

    @Test func wakeTimeHasAnHourEitherSide() {
        let change = WeeklyChange.wakeTime(minutes: 6 * 60 + 30)
        #expect(change.title.hasPrefix("Up within an hour of "))
        #expect(WeeklyChangeReview.wakeToleranceMinutes == 60)
        #expect(WeeklyChangeReview.kept(change, on: day(0) { $0.wakeMinutes = 5 * 60 + 30 }) == true)
        #expect(WeeklyChangeReview.kept(change, on: day(0) { $0.wakeMinutes = 7 * 60 + 30 }) == true)
        #expect(WeeklyChangeReview.kept(change, on: day(0) { $0.wakeMinutes = 7 * 60 + 31 }) == false)
        #expect(WeeklyChangeReview.kept(change, on: day(0) { $0.wakeMinutes = 5 * 60 + 29 }) == false)
        // Round the clock: a 00:40 wake against a 23:50 target is 50 minutes away.
        let night = WeeklyChange.wakeTime(minutes: 23 * 60 + 50)
        #expect(WeeklyChangeReview.kept(night, on: day(0) { $0.wakeMinutes = 40 }) == true)
    }

    @Test func proteinMealsNeedMealTimes() {
        let change = WeeklyChange.proteinMeals()
        #expect(WeeklyChangeReview.kept(change, on: day(0) { $0.proteinMeals = 3 }) == true)
        #expect(WeeklyChangeReview.kept(change, on: day(0) { $0.proteinMeals = 2 }) == false)
        #expect(WeeklyChangeReview.kept(change, on: day(0)) == nil)
        // Weekly kinds and free text are never judged per day.
        #expect(WeeklyChangeReview.kept(.stepsAverage(), on: day(0) { $0.steps = 9_000 }) == nil)
        #expect(WeeklyChangeReview.kept("Phone out of the bedroom", on: day(0)) == nil)
    }

    // MARK: The report

    @Test func freeTextIsReportedAsNotMeasured() {
        let reports = WeeklyChangeReview.report(changes: ["Phone out of the bedroom"], week: weeks { _, _ in }.week, earlier: [])
        #expect(reports.count == 1)
        #expect(reports[0].kept == "Not measured")
        #expect(reports[0].wasKept == nil)
        #expect(reports[0].moved == nil)
        #expect(reports[0].verdict == .notMeasured)
    }

    /// The first week of a change: five days kept, two not. Seven kept days
    /// don't exist yet, so nothing is claimed about sleep.
    @Test func oneWeekOfACaffeineCutoffReportsDaysKeptAndRefusesAVerdict() {
        let change = WeeklyChange.caffeineCutoff(byMinutes: 14 * 60)
        // Before the change: caffeine at 16:00 most days, none logged at weekends.
        let data = weeks { offset, day in
            let late = offset < 0 || offset == 3 || offset == 5
            day.lastCaffeineMinutes = late ? 16 * 60 : 13 * 60
            day.sleepHours = late ? 6.8 : 7.3
        }
        let report = WeeklyChangeReview.report(changes: [change], week: data.week, earlier: data.earlier)[0]
        #expect(report.kept == "Kept on 5 of 7 days")
        #expect(report.wasKept == false) // "every day" and two days missed it
        #expect(report.verdict == .tooFewDays)
        #expect(report.moved?.contains("Sleep averaged") == true)
        #expect(report.moved?.contains("5 kept and 30 not") == true)
        #expect(report.moved?.contains("needs 7 of each") == true)
    }

    /// A change the owner already kept on some days: across five weeks there
    /// are enough days each way, and sleep is clearly longer on the kept ones.
    @Test func withEnoughDaysEachWayAClearGapIsReportedAsAPatternNotProof() {
        let change = WeeklyChange.caffeineCutoff(byMinutes: 14 * 60)
        let data = weeks { offset, day in
            let index = offset + 28
            let kept = offset >= 0 || index % 3 == 0 // all of last week, a third of the days before
            day.lastCaffeineMinutes = kept ? 13 * 60 : 16 * 60
            // Kept nights about 40 minutes longer, with ordinary scatter.
            let scatter = Double((index * 7) % 5 - 2) * 0.1
            day.sleepHours = (kept ? 7.5 : 6.8) + scatter
        }
        let report = WeeklyChangeReview.report(changes: [change], week: data.week, earlier: data.earlier)[0]
        #expect(report.kept == "Kept on 7 of 7 days")
        #expect(report.wasKept == true)
        #expect(report.verdict == .clearDifference)
        #expect(report.moved?.contains("longer") == true)
        #expect(report.moved?.contains("not proof") == true)
    }

    @Test func enoughDaysButNoRealGapSaysItMayBeChance() {
        let change = WeeklyChange.wakeTime(minutes: 6 * 60 + 30)
        let data = weeks { offset, day in
            let index = offset + 28
            day.wakeMinutes = index % 2 == 0 ? 6 * 60 + 30 : 8 * 60
            // The same sleep either way, with scatter that doesn't follow the wake time.
            day.sleepHours = 7.0 + Double((index * 5) % 7 - 3) * 0.15
        }
        let report = WeeklyChangeReview.report(changes: [change], week: data.week, earlier: data.earlier)[0]
        #expect(report.verdict == .noClearDifference)
        #expect(report.moved?.contains("may be chance") == true)
    }

    @Test func bedByOnNNightsIsMetAtN() {
        let change = WeeklyChange.bedBy(minutes: 23 * 60, nights: 5)
        let five = weeks { offset, day in day.bedtimeMinutes = offset >= 0 && offset < 5 ? 22 * 60 + 45 : 23 * 60 + 40 }
        let report = WeeklyChangeReview.report(changes: [change], week: five.week, earlier: [])[0]
        #expect(report.kept == "Kept on 5 of 7 nights")
        #expect(report.wasKept == true)
        let four = weeks { offset, day in day.bedtimeMinutes = offset >= 0 && offset < 4 ? 22 * 60 + 45 : 23 * 60 + 40 }
        #expect(WeeklyChangeReview.report(changes: [change], week: four.week, earlier: [])[0].wasKept == false)
    }

    @Test func daysWithoutDataAreLeftOutNotCountedAsMissed() {
        let change = WeeklyChange.caffeineCutoff(byMinutes: 14 * 60)
        let partial = weeks { offset, day in if offset >= 0 && offset < 4 { day.lastCaffeineMinutes = 12 * 60 } }
        let report = WeeklyChangeReview.report(changes: [change], week: partial.week, earlier: [])[0]
        #expect(report.kept == "Kept on 4 of 4 days with data")
        #expect(report.wasKept == true)
        let none = WeeklyChangeReview.report(changes: [change], week: weeks { _, _ in }.week, earlier: [])[0]
        #expect(none.kept == "No data last week")
        #expect(none.wasKept == nil)
        #expect(none.verdict == .noData)
        #expect(none.moved?.contains("food app") == true)
    }

    @Test func stepsAreJudgedAsTheWeeksAverage() {
        // Two long days carry a week with five short ones over the line.
        let data = weeks { offset, day in
            if offset >= 0 { day.steps = offset < 2 ? 14_000 : 4_300 } else { day.steps = 6_000 }
        }
        let report = WeeklyChangeReview.report(changes: [.stepsAverage()], week: data.week, earlier: data.earlier)[0]
        #expect(report.kept == "Averaged 7,100 steps a day")
        #expect(report.wasKept == true)
        #expect(report.moved == "Up from 6,000 over the four weeks before.")
        #expect(report.verdict == .numbersOnly)
        let flat = weeks { _, day in day.steps = 6_500 }
        let same = WeeklyChangeReview.report(changes: [.stepsAverage()], week: flat.week, earlier: flat.earlier)[0]
        #expect(same.wasKept == false)
        #expect(same.moved?.hasPrefix("About the same") == true)
        // Three days of counts isn't a week.
        let thin = weeks { offset, day in if (0..<3).contains(offset) { day.steps = 9_000 } }
        #expect(WeeklyChangeReview.report(changes: [.stepsAverage()], week: thin.week, earlier: [])[0].verdict == .noData)
    }

    @Test func aHardCardioSessionIsFoundInRecordedWorkouts() {
        #expect(WeeklyChangeReview.hardSessionVigorousMinutes == 15)
        let data = weeks { offset, day in
            guard offset >= 0 else { return }
            day.vigorousMinutes = offset == 2 ? 19 : 2
            if offset == 2 { day.cardioVigorousMinutes = 17 }  // Wednesday's intervals
            if offset == 5 { day.cardioVigorousMinutes = 6 }   // Saturday's easy ride
        }
        let report = WeeklyChangeReview.report(changes: [.hardCardio], week: data.week, earlier: [])[0]
        #expect(report.kept == "1 hard session: 17 vigorous minutes in the longest")
        #expect(report.wasKept == true)
        #expect(report.moved == "Vigorous minutes last week: 31.")
        // A week of easy cardio only: heart rate, but no session at the line.
        let easy = weeks { offset, day in
            guard offset >= 0 else { return }
            day.vigorousMinutes = 3
            if offset == 1 { day.cardioVigorousMinutes = 14 }
        }
        let none = WeeklyChangeReview.report(changes: [.hardCardio], week: easy.week, earlier: [])[0]
        #expect(none.kept == "No hard session recorded")
        #expect(none.wasKept == false)
        // No heart rate at all: unknown, not missed.
        let blank = WeeklyChangeReview.report(changes: [.hardCardio], week: weeks { _, _ in }.week, earlier: [])[0]
        #expect(blank.wasKept == nil)
        #expect(blank.verdict == .noData)
    }

    @Test func drinksAreCountedAgainstTheLimitOnceEnoughEveningsAreLogged() {
        let data = weeks { offset, day in
            if offset >= 0 { day.drinks = offset == 4 ? 2 : (offset == 5 ? 1.5 : 0) } else { day.drinks = offset % 7 == 0 ? 3 : 0.5 }
        }
        let report = WeeklyChangeReview.report(changes: [.drinksLimit(4)], week: data.week, earlier: data.earlier)[0]
        #expect(report.kept == "3.5 against a limit of 4")
        #expect(report.wasKept == true)
        #expect(report.moved?.hasPrefix("The four weeks before averaged") == true)
        #expect(WeeklyChangeReview.report(changes: [.drinksLimit(3)], week: data.week, earlier: [])[0].wasKept == false)
        // Three evenings logged: no verdict.
        let thin = weeks { offset, day in if (0..<3).contains(offset) { day.drinks = 0 } }
        let unknown = WeeklyChangeReview.report(changes: [.drinksLimit(4)], week: thin.week, earlier: [])[0]
        #expect(unknown.wasKept == nil)
        #expect(unknown.verdict == .noData)
        // Five of seven logged says so.
        let five = weeks { offset, day in if (0..<5).contains(offset) { day.drinks = 1 } }
        #expect(WeeklyChangeReview.report(changes: [.drinksLimit(6)], week: five.week, earlier: [])[0].kept == "5 against a limit of 6 (5 of 7 evenings logged)")
    }

    @Test func activeMinutesAndStrengthDaysUseTheSharedFloors() {
        let data = weeks { offset, day in
            day.moderateMinutes = 15
            day.vigorousMinutes = offset == 2 ? 20 : 0
            day.strengthSession = [0, 2, 3, 5].contains((offset + 28) % 7)
        }
        let reports = WeeklyChangeReview.report(changes: [.activeMinutes, .strengthDays], week: data.week, earlier: data.earlier)
        #expect(reports[0].kept == "145 cardio minutes") // 105 + 2 x 20; renamed by evidence audit M1
        #expect(reports[0].wasKept == false)
        #expect(reports[0].moved == "105 moderate and 20 vigorous, which count double.")
        #expect(reports[1].kept == "4 strength days")
        #expect(reports[1].wasKept == true)
        #expect(reports[1].moved == "The four weeks before averaged 4 a week.")
    }

    /// Three changes at once: each keeps its own report, in the order chosen.
    @Test func aRealisticMondayWithThreeChanges() {
        let changes: [WeeklyChange] = [.stepsAverage(), .bedBy(minutes: 23 * 60), "Keep the first session of the week easy"]
        let data = weeks { offset, day in
            day.steps = offset >= 0 ? 7_600 : 6_200
            day.bedtimeMinutes = offset >= 0 && offset < 5 ? 22 * 60 + 50 : 23 * 60 + 35
            day.sleepHours = offset >= 0 && offset < 5 ? 7.6 : 6.9
        }
        let reports = WeeklyChangeReview.report(changes: changes, week: data.week, earlier: data.earlier)
        #expect(reports.map(\.id) == changes.map(\.id))
        #expect(reports[0].wasKept == true)
        #expect(reports[1].kept == "Kept on 5 of 7 nights")
        #expect(reports[1].wasKept == true)
        #expect(reports[1].verdict == .tooFewDays) // five kept nights so far
        #expect(reports[2].verdict == .notMeasured)
        #expect(WeeklyChangeReview.caveat.contains("One week can't prove anything"))
    }

    /// The comparison uses the patterns engine's own rules: a gap inside the
    /// usual night-to-night spread is not a pattern however many days there are.
    @Test func aGapSmallerThanTheUsualSwingIsNeverAPattern() {
        let change = WeeklyChange.bedBy(minutes: 23 * 60, nights: 7)
        let data = weeks { offset, day in
            let index = offset + 28
            let kept = index % 2 == 0
            day.bedtimeMinutes = kept ? 22 * 60 + 30 : 23 * 60 + 45
            // Kept nights 6 minutes longer on average against an hour of scatter.
            day.sleepHours = 7.0 + (kept ? 0.1 : 0) + Double((index / 2) % 5 - 2) * 0.5
        }
        let report = WeeklyChangeReview.report(changes: [change], week: data.week, earlier: data.earlier)[0]
        #expect(report.verdict == .noClearDifference)
    }

    // MARK: Building the days

    @Test func lastCaffeineComesFromTheFoodAppThenTheCheckIn() {
        let nine = utc.date(byAdding: .hour, value: 9, to: monday)!
        let three = utc.date(byAdding: .minute, value: 15 * 60 + 10, to: monday)!
        var evening = EveningCheckIn(day: monday)
        evening.caffeineMg = 200
        evening.lastCaffeineMinutes = 13 * 60
        // Timed entries from the food app win.
        let timed = WeeklyChangeReview.caffeine(samples: [(nine, 95), (three, 63)], timesAreReal: true, evening: evening,
                                                foodLogged: true, foodLogHasCaffeine: true, calendar: utc)
        #expect(timed.lastMinutes == 15 * 60 + 10)
        #expect(!timed.none)
        // A food app that stamps everything at one time: fall back to the check-in.
        let stamped = WeeklyChangeReview.caffeine(samples: [(nine, 158)], timesAreReal: false, evening: evening,
                                                  foodLogged: true, foodLogHasCaffeine: true, calendar: utc)
        #expect(stamped.lastMinutes == 13 * 60)
        // "0 mg" in the check-in is a known caffeine-free day.
        var zero = EveningCheckIn(day: monday)
        zero.caffeineMg = 0
        #expect(WeeklyChangeReview.caffeine(samples: [], timesAreReal: true, evening: zero, foodLogged: false, foodLogHasCaffeine: false, calendar: utc).none)
        // Food logged, no caffeine entry, and the log does record caffeine on other days.
        #expect(WeeklyChangeReview.caffeine(samples: [], timesAreReal: true, evening: nil, foodLogged: true, foodLogHasCaffeine: true, calendar: utc).none)
        // The same day from a log that never records caffeine is unknown.
        let unknown = WeeklyChangeReview.caffeine(samples: [], timesAreReal: true, evening: nil, foodLogged: true, foodLogHasCaffeine: false, calendar: utc)
        #expect(unknown.lastMinutes == nil)
        #expect(!unknown.none)
    }

    @Test func vigorousMinutesAreCountedInsideTheWorkoutOnly() {
        let profile = HeartRateProfile(age: 34, sex: .male, restingHeartRate: 55)
        let start = utc.date(byAdding: .hour, value: 18, to: monday)!
        // A 30-minute ride: 8 easy, 18 hard, 4 easy. Then a hard minute an hour later, outside it.
        let bpm: [Double] = Array(repeating: 110, count: 8) + Array(repeating: 165, count: 18) + Array(repeating: 110, count: 4)
        var samples = bpm.enumerated().map { HeartRateSample(date: start.addingTimeInterval(Double($0.offset) * 60), bpm: $0.element) }
        samples += (0..<10).map { HeartRateSample(date: start.addingTimeInterval(5_400 + Double($0) * 60), bpm: 170) }
        let ride = DateInterval(start: start, duration: 30 * 60)
        #expect(WeeklyChangeReview.cardioVigorousMinutes(workouts: [ride], heartRate: samples, profile: profile) == 18)
        // Too short to be looked at, and a workout with no heart rate.
        let short = DateInterval(start: start, duration: 9 * 60)
        #expect(WeeklyChangeReview.cardioVigorousMinutes(workouts: [short], heartRate: samples, profile: profile) == nil)
        let later = DateInterval(start: start.addingTimeInterval(86_400), duration: 40 * 60)
        #expect(WeeklyChangeReview.cardioVigorousMinutes(workouts: [later], heartRate: samples, profile: profile) == nil)
        #expect(WeeklyChangeReview.cardioVigorousMinutes(workouts: [], heartRate: samples, profile: profile) == nil)
        // The watch's record of a logged lifting session is not cardio.
        let session = DateInterval(start: start.addingTimeInterval(-600), duration: 50 * 60)
        #expect(WeeklyChangeReview.cardioVigorousMinutes(workouts: [ride], lifting: [session], heartRate: samples, profile: profile) == nil)
        let morningLift = DateInterval(start: start.addingTimeInterval(-10 * 3600), duration: 3600)
        #expect(WeeklyChangeReview.cardioVigorousMinutes(workouts: [ride], lifting: [morningLift], heartRate: samples, profile: profile) == 18)
    }

    // MARK: Suggestions

    @Test func theUnmetFloorIsTheFirstSuggestion() {
        var context = WeeklyChangeSuggestions.Context()
        context.usualWakeMinutes = 6 * 60 + 30
        context.caffeineCutoffMinutes = 14 * 60
        context.bedByMinutes = 23 * 60
        context.vigorousMinutes = 12
        let basics = HealthFloors.assess(HealthFloors.Week(moderateMinutes: 70, vigorousMinutes: 12, strengthDays: 4, averageSteps: 6_400,
                                                           stepDays: 7, sleepRegularity: 76, drinks: 1, drinkNightsLogged: 7))
        let suggested = WeeklyChangeSuggestions.suggested(basics: basics, context: context)
        #expect(suggested.first == .activeMinutes)
        #expect(Array(suggested.prefix(3).map(\.kind)) == [.activeMinutes, .stepsAverage, .wakeTime])
        #expect(suggested.contains(.hardCardio)) // offered, further down
        #expect(Set(suggested.map(\.id)).count == suggested.count)
    }

    @Test func withEveryFloorMetTheOtherNumbersLead() {
        var context = WeeklyChangeSuggestions.Context()
        context.bedByMinutes = 23 * 60
        context.sleepDebtExtraMinutes = 30
        context.proteinLow = true
        context.hasMealTimes = true
        let basics = HealthFloors.assess(HealthFloors.Week(moderateMinutes: 200, vigorousMinutes: 30, strengthDays: 4, averageSteps: 9_000,
                                                           stepDays: 7, sleepRegularity: 88, drinks: 0, drinkNightsLogged: 7))
        let suggested = WeeklyChangeSuggestions.suggested(basics: basics, context: context)
        #expect(suggested.prefix(2).map(\.kind) == [.bedByWindow, .proteinMeals])
        #expect(!suggested.contains(.hardCardio)) // 30 vigorous minutes already
        // With nothing to go on, the plain ideas the review always had.
        let plain = WeeklyChangeSuggestions.suggested(basics: nil, context: WeeklyChangeSuggestions.Context())
        #expect(plain == WeeklyChangeSuggestions.plainIdeas)
        #expect(plain.allSatisfy { !$0.isMeasured })
    }

    @Test func onlyChoicesTheDataCanCheckAreOffered() {
        let bare = WeeklyChangeSuggestions.measurable(WeeklyChangeSuggestions.Context())
        #expect(bare.map(\.kind) == [.stepsAverage, .hardCardio, .activeMinutes, .strengthDays])
        var context = WeeklyChangeSuggestions.Context()
        context.caffeineCutoffMinutes = 14 * 60
        context.bedByMinutes = 23 * 60
        context.usualWakeMinutes = 7 * 60
        context.hasMealTimes = true
        context.logsDrinks = true
        let full = WeeklyChangeSuggestions.measurable(context)
        #expect(Set(full.map(\.kind)) == Set(WeeklyChange.Kind.allCases).subtracting([.custom]))
        #expect(full.allSatisfy { $0.isMeasured })
    }

    @Test func aDrinksChangeStartsFromTheOwnersLimitOrOneTierDown() {
        var context = WeeklyChangeSuggestions.Context()
        context.lastWeekDrinks = 9
        #expect(WeeklyChangeSuggestions.drinkLimit(context) == 6)
        context.lastWeekDrinks = 4
        #expect(WeeklyChangeSuggestions.drinkLimit(context) == 2)
        context.drinkLimit = 5
        #expect(WeeklyChangeSuggestions.drinkLimit(context) == 5)
        #expect(WeeklyChangeSuggestions.change(for: .drinks, context: context)?.target == 5)
        // No sleep data: nothing to hold a wake time to.
        #expect(WeeklyChangeSuggestions.change(for: .sleepRegularity, context: WeeklyChangeSuggestions.Context()) == nil)
    }
}
