import Foundation
import Testing
@testable import AppCore

struct StretchingTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// Thursday 12 November 2026, 20:30 UTC.
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 20, minute: 30))! }
    func daysAgo(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now)! }

    func routine(done: [Stretching.Done] = [], lifts: [Stretching.Lift] = [], focus: Set<StretchArea> = []) -> Stretching.Routine {
        Stretching.routine(done: done, lifts: lifts, focus: focus, now: now, calendar: calendar)
    }

    @Test func aRoutineIsFiveOneMinuteStretches() {
        let routine = routine()
        #expect(routine.items.count == 5)
        #expect(routine.items.allSatisfy { $0.seconds == 60 })
        #expect(routine.minutes == Stretching.sessionMinutes)
        #expect(Set(routine.items.map(\.stretch.area)).count == 5)
        #expect(routine.coveredByLifting.isEmpty)
    }

    @Test func everyAreaHasTwoStretchesWithACue() {
        for area in StretchArea.allCases {
            let options = Stretching.stretches(for: area)
            #expect(options.count == 2, "\(area)")
            #expect(options.allSatisfy { !$0.cue.isEmpty })
        }
        #expect(Set(Stretching.catalog.map(\.id)).count == Stretching.catalog.count)
    }

    @Test func areasBehindOnTheirWeekComeFirst() {
        // Everything but the hamstrings and inner thighs had its 5 minutes this week.
        let covered: [StretchArea] = [.calves, .chest, .lats, .hipFlexors, .glutes]
        let done = covered.map { Stretching.Done(date: daysAgo(1), area: $0, seconds: 300) }
        let areas = routine(done: done).items.map(\.stretch.area)
        #expect(areas.contains(.hamstrings))
        #expect(areas.contains(.adductors))
    }

    @Test func aWeekOfDailyRoutinesGivesEveryAreaItsFiveMinutes() {
        var done: [Stretching.Done] = []
        for day in (0..<7).reversed() {
            let date = daysAgo(day)
            let today = Stretching.routine(done: done, lifts: [], focus: [], now: date, calendar: calendar)
            done += today.items.map { Stretching.Done(date: date, area: $0.stretch.area, seconds: $0.seconds) }
        }
        let week = Stretching.week(done: done, lifts: [], focus: [], now: now, calendar: calendar)
        #expect(week.allSatisfy { $0.stretched >= 5 }, "\(week.map { "\($0.area): \($0.stretched)" })")
        #expect(Stretching.weekMinutes(done: done, now: now, calendar: calendar).done == 35)
    }

    @Test func focusAreasGetMoreOfTheWeek() {
        let focus: Set<StretchArea> = [.hamstrings, .hipFlexors]
        var done: [Stretching.Done] = []
        for day in (0..<7).reversed() {
            let date = daysAgo(day)
            let today = Stretching.routine(done: done, lifts: [], focus: focus, now: date, calendar: calendar)
            done += today.items.map { Stretching.Done(date: date, area: $0.stretch.area, seconds: $0.seconds) }
        }
        let week = Stretching.week(done: done, lifts: [], focus: focus, now: now, calendar: calendar)
        for entry in week {
            if focus.contains(entry.area) {
                #expect(entry.stretched >= 7, "\(entry.area): \(entry.stretched)")
            } else {
                #expect(entry.stretched >= 3, "\(entry.area): \(entry.stretched)")
            }
        }
    }

    // Lifting through a long range builds flexibility too (Afonso 2021), so those areas wait.
    @Test func areasLiftedThroughALongRangeNeedLess() {
        #expect(Stretching.areas(for: .hinge) == [.hamstrings])
        #expect(Stretching.areas(forExerciseIDs: ["Romanian_Deadlift", "Barbell_Squat", "Barbell_Curl"]) == [.hamstrings, .glutes, .adductors])
        let legDay = Stretching.Lift(date: daysAgo(1), areas: [.hamstrings, .glutes, .adductors])
        let week = Stretching.week(done: [], lifts: [legDay, legDay], focus: [], now: now, calendar: calendar)
        // Two sessions would be 4 minutes; the credit stops at half the 5-minute target.
        #expect(week.first { $0.area == .hamstrings }?.lifted == 2.5)
        #expect(week.first { $0.area == .chest }?.lifted == 0)
        let routine = routine(lifts: [legDay])
        let areas = Set(routine.items.map(\.stretch.area))
        #expect(areas.isSuperset(of: [.calves, .chest, .lats, .hipFlexors]))
        #expect(routine.coveredByLifting.count == 2)
        #expect(routine.reason.contains("lifted them through a long range"))
    }

    @Test func eachAreaAlternatesItsTwoStretches() {
        let first = routine().items.first { $0.stretch.area == .calves }?.stretch.id
        // Every area stretched once yesterday: calves are back in today's five, on their other stretch.
        let done = StretchArea.allCases.map { Stretching.Done(date: daysAgo(1), area: $0, seconds: 60) }
        let second = routine(done: done).items.first { $0.stretch.area == .calves }?.stretch.id
        #expect(first == "calf-wall")
        #expect(second == "calf-bent-knee")
    }

    @Test func stepsAreAChangeThenTwoThirtySecondHolds() {
        let routine = routine()
        let steps = Stretching.steps(for: routine)
        #expect(steps.count == 15)
        #expect(steps.filter { $0.kind == .hold }.allSatisfy { $0.seconds == 30 })
        #expect(steps.filter { $0.kind == .hold }.reduce(0) { $0 + $1.seconds } == 300)
        // The wall calf stretch is one side at a time; the doorway chest stretch isn't.
        #expect(Array(steps.prefix(3)).map(\.label) == ["Get into position", "Left side", "Right side"])
        let chest = try? #require(routine.items.firstIndex { $0.stretch.id == "chest-doorway" })
        if let chest {
            #expect(steps.filter { $0.item == chest && $0.kind == .hold }.map(\.label) == ["Hold", "Once more"])
        }
    }

    @Test func aPartFinishedSessionLogsWhatWasHeld() {
        let routine = routine()
        let log = Stretching.log(routine: routine, completedHolds: [0: 2, 1: 1], at: now)
        #expect(log.map(\.seconds) == [60, 30])
        #expect(log.map(\.area) == Array(routine.items.prefix(2)).map(\.stretch.area))
        #expect(Stretching.stretchedToday(log, now: now, calendar: calendar))
        #expect(!Stretching.stretchedToday(log, now: daysAgo(-1), calendar: calendar))
    }

    // Not just before lifting: long static holds lower strength for a while (Behm 2016).
    @Test func theReminderKeepsClearOfAPlannedSession() {
        let evening = Stretching.defaultReminderMinutes
        #expect(Stretching.reminderMinutes(preferred: evening, sessionStart: nil, sessionLength: nil) == evening)
        // Session at 18:00: already over by 20:30.
        #expect(Stretching.reminderMinutes(preferred: evening, sessionStart: 18 * 60, sessionLength: 60) == evening)
        // Session at 21:00: the reminder waits until an hour after it ends (capped at 23:00).
        #expect(Stretching.reminderMinutes(preferred: evening, sessionStart: 21 * 60, sessionLength: 60) == 23 * 60)
        #expect(Stretching.reminderMinutes(preferred: 7 * 60, sessionStart: 7 * 60 + 30, sessionLength: 45) == 9 * 60 + 15)
        // Session three hours later: far enough.
        #expect(Stretching.reminderMinutes(preferred: 7 * 60, sessionStart: 10 * 60, sessionLength: 60) == 7 * 60)
    }

    @Test func targetsFollowTheFocus() {
        #expect(Stretching.target(for: .chest, focus: []) == 5)
        #expect(Stretching.target(for: .chest, focus: [.chest]) == 8)
        #expect(Stretching.target(for: .calves, focus: [.chest]) == 3)
    }
}
