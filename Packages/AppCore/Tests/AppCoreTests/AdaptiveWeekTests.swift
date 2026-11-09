import Foundation
import Testing
@testable import AppCore

struct AdaptiveWeekTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    /// Monday 2 November 2026, 00:00 UTC.
    var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))! }

    /// Day `offset` of the week (0 = Monday) at `hour`.
    func day(_ offset: Int, hour: Int = 0) -> Date {
        calendar.date(byAdding: .hour, value: offset * 24 + hour, to: monday)!
    }

    func plan(_ days: [(Int, WorkoutFocus)]) -> WeeklyPlan {
        WeeklyPlan(weekStart: monday, plannedDays: days.map { PlannedDay(weekday: $0.0, time: 18 * 60, focus: $0.1, minutes: 60) })
    }

    /// Mon Upper, Tue Lower, Thu Upper, Fri Lower.
    var upperLower: WeeklyPlan { plan([(2, .upper), (3, .lower), (5, .upper), (6, .lower)]) }

    func week(_ plan: WeeklyPlan, done: [AdaptiveWeek.DoneSession] = [], now: Date,
              soreness: [AdaptiveWeek.SoreSignal] = [], swaps: [AdaptiveWeek.Swap] = []) -> AdaptiveWeek.Result {
        AdaptiveWeek.make(plan: plan, done: done, now: now, soreness: soreness, swaps: swaps, calendar: calendar)!
    }

    func focuses(_ result: AdaptiveWeek.Result) -> [WorkoutFocus] { result.slots.map(\.focus) }
    func weekdays(_ result: AdaptiveWeek.Result) -> [Int] { result.slots.map(\.session.weekday) }

    // MARK: The queue

    @Test func onPlanWeekFollowsTheCalendar() {
        let result = week(upperLower, now: day(0, hour: 8))
        #expect(focuses(result) == [.upper, .lower, .upper, .lower])
        #expect(weekdays(result) == [2, 3, 5, 6])
        #expect(result.today?.focus == .upper)
        #expect(result.slots.allSatisfy { !$0.isMoved })
    }

    @Test func missedSessionIsNextNotLost() {
        // Monday's Upper didn't happen: Tuesday takes it, and Lower follows on Wednesday.
        let result = week(upperLower, now: day(1, hour: 8))
        #expect(result.today?.focus == .upper)
        #expect(result.today?.isMoved == true)
        #expect(focuses(result) == [.upper, .lower, .upper, .lower])
        #expect(weekdays(result) == [3, 4, 5, 6])
        #expect(result.stillToDo.isEmpty)
    }

    @Test func doneFocusTicksTheMatchingSessionNotTheWeekday() {
        // Lower done on Monday ticks Tuesday's Lower; Upper is still to do.
        let result = week(upperLower, done: [.init(date: day(0, hour: 18), focus: .lower)], now: day(0, hour: 20))
        #expect(result.doneWeekdays == [3])
        #expect(result.liftedToday)
        #expect(result.today == nil)
        #expect(result.next?.focus == .upper)
        #expect(result.next?.session.weekday == 3)
    }

    @Test func legsTicksLowerAndPushTicksUpper() {
        let done: [AdaptiveWeek.DoneSession] = [.init(date: day(0, hour: 9), focus: .push), .init(date: day(1, hour: 9), focus: .legs)]
        let result = week(upperLower, done: done, now: day(1, hour: 20))
        #expect(result.doneWeekdays == [2, 3])
    }

    @Test func watchOnlyDayTicksNoLiftingSession() {
        let result = week(upperLower, done: [.init(date: day(0, hour: 7), focus: nil, isLifting: false)], now: day(0, hour: 20))
        #expect(result.done.isEmpty)
        #expect(result.otherSessions == 1)
        #expect(result.today?.focus == .upper)
    }

    @Test func gymSessionOfUnknownFocusTicksThatDaysSession() {
        let result = week(upperLower, done: [.init(date: day(1, hour: 9), focus: nil)], now: day(1, hour: 20))
        #expect(result.doneWeekdays == [3])
    }

    @Test func swappedOrderJustSwapsTheQueue() {
        // "Just prefer it": Lower on Monday, then Upper on Tuesday, plan stays two of each.
        let done: [AdaptiveWeek.DoneSession] = [.init(date: day(0, hour: 18), focus: .lower), .init(date: day(1, hour: 18), focus: .upper)]
        let result = week(upperLower, done: done, now: day(1, hour: 20))
        #expect(result.done.count == 2)
        #expect(focuses(result) == [.upper, .lower])
        #expect(weekdays(result) == [5, 6])
    }

    @Test func neverMoreThanThePlansSessions() {
        let result = week(upperLower, now: day(0, hour: 8))
        #expect(result.slots.count == 4)
        let done = (0..<4).map { AdaptiveWeek.DoneSession(date: day($0, hour: 9), focus: $0 % 2 == 0 ? .upper : .lower) }
        let after = week(upperLower, done: done, now: day(3, hour: 20))
        #expect(after.slots.isEmpty)
        #expect(after.remaining == 0)
    }

    @Test func extraDayIsSkippedAfterTwoInARowWhenThereIsRoom() {
        // Three-day plan Mon/Wed/Fri. Monday missed; Tue and Wed trained. Thursday is free, Friday planned.
        let p = plan([(2, .push), (4, .pull), (6, .legs)])
        let done: [AdaptiveWeek.DoneSession] = [.init(date: day(1, hour: 9), focus: .push), .init(date: day(2, hour: 9), focus: .pull)]
        let result = week(p, done: done, now: day(3, hour: 8))
        #expect(result.today == nil)
        #expect(result.next?.focus == .legs)
        #expect(result.next?.session.weekday == 6)
    }

    // MARK: The user's week

    @Test func usersCaseLowerIsTomorrow() {
        // Plan: Upper yesterday (Monday, missed) and Lower today (Tuesday). Upper logged today.
        let p = plan([(2, .upper), (3, .lower)])
        let done = [AdaptiveWeek.DoneSession(date: day(1, hour: 18), focus: AdaptiveWeek.inferFocus(name: "Upper Body", exerciseIDs: []))]
        let result = week(p, done: done, now: day(1, hour: 20))
        #expect(result.doneWeekdays == [2])
        #expect(result.next?.focus == .lower)
        #expect(result.next?.date == day(2))
        #expect(result.stillToDo.isEmpty)
        let guidance = TrainingDayPlanner.adaptiveGuidance(week: result, past: [], lowRecovery: false, usualTrainingStrain: 65, calendar: calendar)
        #expect(guidance.reason.contains("Next: Lower tomorrow."))
    }

    @Test func usersCaseWithLegsSoreStillLowerTomorrowWithAWayOut() {
        let p = upperLower
        let swap = AdaptiveWeek.Swap(day: day(1), planned: .lower, chosen: .upper, reason: .sore, soreAreas: [.legs], recordedAt: day(1, hour: 17))
        let done = [AdaptiveWeek.DoneSession(date: day(1, hour: 18), focus: .upper)]
        let result = week(p, done: done, now: day(1, hour: 20), soreness: AdaptiveWeek.signals(fromSwaps: [swap]), swaps: [swap])
        #expect(result.next?.focus == .lower)
        #expect(result.next?.date == day(2))
        #expect(result.next?.note == "Legs still sore? Do Upper first and Lower the day after.")
    }

    @Test func legsStillSoreNextMorningMovesLowerToThursday() {
        // Wednesday's check-in says legs are still sore. Upper was yesterday, so neither
        // session suits today: rest, and Lower goes to Thursday.
        var checkIn = MorningCheckIn(day: day(2, hour: 7))
        checkIn.soreness = 6
        checkIn.soreAreas = [.legs]
        let done = [AdaptiveWeek.DoneSession(date: day(1, hour: 18), focus: .upper)]
        let result = week(upperLower, done: done, now: day(2, hour: 8), soreness: AdaptiveWeek.signals(from: checkIn))
        #expect(result.today == nil)
        #expect(result.moveNote == "Lower moved to Thu: legs still sore.")
        #expect(result.next?.focus == .lower)
        #expect(result.next?.date == day(3))
        let guidance = TrainingDayPlanner.adaptiveGuidance(week: result, past: [], lowRecovery: false, usualTrainingStrain: 65, calendar: calendar)
        #expect(guidance.kind == .rest)
        #expect(guidance.reason.contains("Lower moved to Thu: legs still sore."))
    }

    @Test func soreLegsPutAnotherSessionFirst() {
        // Pull Mon (done), Legs Tue, Push Thu. Legs sore on Tuesday: Push moves up, Legs to Thursday.
        let p = plan([(2, .pull), (3, .legs), (5, .push)])
        let done = [AdaptiveWeek.DoneSession(date: day(0, hour: 18), focus: .pull)]
        let sore = [AdaptiveWeek.SoreSignal(area: .legs, day: day(1, hour: 7), source: .checkIn)]
        let result = week(p, done: done, now: day(1, hour: 8), soreness: sore)
        #expect(result.today?.focus == .push)
        #expect(result.moveNote == "Legs moved to Thu: legs still sore.")
        #expect(result.today?.note == result.moveNote)
        #expect(result.slot(on: day(3), calendar: calendar)?.focus == .legs)
    }

    @Test func sameMusclesNotTwoDaysRunningWhenAnotherSessionCanGoFirst() {
        // Upper on Tue (for Mon) and Upper again Wed: Thursday takes Lower first.
        let done: [AdaptiveWeek.DoneSession] = [.init(date: day(1, hour: 9), focus: .lower), .init(date: day(2, hour: 9), focus: .upper)]
        let result = week(upperLower, done: done, now: day(3, hour: 8))
        #expect(focuses(result) == [.lower, .upper])
    }

    @Test func mildCheckInSorenessDoesNothing() {
        var checkIn = MorningCheckIn(day: day(1, hour: 7))
        checkIn.soreness = 3
        checkIn.soreAreas = [.legs]
        #expect(AdaptiveWeek.signals(from: checkIn).isEmpty)
    }

    @Test func soreWithNoAlternativeRestsWhenThereIsRoom() {
        let p = plan([(3, .lower), (6, .lower)])
        let sore = [AdaptiveWeek.SoreSignal(area: .legs, day: day(1), source: .checkIn)]
        let result = week(p, now: day(1, hour: 8), soreness: sore)
        #expect(result.today == nil)
        #expect(result.next?.focus == .lower)
        #expect(result.moveNote?.hasPrefix("Lower moved to") == true)
        let guidance = TrainingDayPlanner.adaptiveGuidance(week: result, past: [], lowRecovery: false, usualTrainingStrain: 65, calendar: calendar)
        #expect(guidance.kind == .rest)
    }

    @Test func soreWithNoRoomGoesEasy() {
        // Saturday, two Lowers to go and two days left: no room to wait.
        let p = plan([(7, .lower), (1, .lower)])
        let sore = [AdaptiveWeek.SoreSignal(area: .legs, day: day(5), source: .reported)]
        let result = week(p, now: day(5, hour: 8), soreness: sore)
        #expect(result.today?.focus == .lower)
        #expect(result.today?.easy == true)
        let guidance = TrainingDayPlanner.adaptiveGuidance(week: result, past: [], lowRecovery: false, usualTrainingStrain: 65, calendar: calendar)
        #expect(guidance.kind == .easyTraining)
    }

    @Test func estimatedFatigueCountsOnlyAsGiven() {
        var states: [Muscle: MuscleRecovery.State] = [:]
        for muscle in Muscle.allCases {
            states[muscle] = MuscleRecovery.State(muscle: muscle, recovery: muscle.isLowerBody ? 30 : 95, weeklySets: 0, lastTrained: nil)
        }
        let signals = AdaptiveWeek.fatiguedAreas(states, day: day(1))
        #expect(Set(signals.map(\.area)) == [.legs, .glutes])
    }

    // MARK: Reasons

    @Test func equipmentBusyKeepsThePlannedSessionTomorrow() {
        // Mon Lower, Thu Upper. Upper done Monday (equipment busy): Lower goes to Tuesday, a rest day.
        let p = plan([(2, .lower), (5, .upper)])
        let swap = AdaptiveWeek.Swap(day: day(0), planned: .lower, chosen: .upper, reason: .equipment)
        let done = [AdaptiveWeek.DoneSession(date: day(0, hour: 18), focus: .upper)]
        let result = week(p, done: done, now: day(0, hour: 20), swaps: [swap])
        #expect(result.next?.focus == .lower)
        #expect(result.next?.date == day(1))
    }

    @Test func tiredOrShortOnTimeOffersTheShortVersion() {
        let tired = AdaptiveWeek.Swap(day: day(0), planned: .upper, chosen: .lower, reason: .tired)
        let result = week(upperLower, now: day(0, hour: 8), swaps: [tired])
        #expect(result.today?.short == true)
        #expect(result.today?.easy == true)
        let busy = AdaptiveWeek.Swap(day: day(0), planned: .upper, chosen: .lower, reason: .shortOnTime)
        let other = week(upperLower, now: day(0, hour: 8), swaps: [busy])
        #expect(other.today?.short == true)
        #expect(other.today?.easy == false)
    }

    @Test func swapLabel() {
        let swap = AdaptiveWeek.Swap(day: day(1), planned: .lower, chosen: .upper, reason: .sore, soreAreas: [.legs, .back])
        #expect(swap.label == "Upper for Lower · legs and back sore")
        #expect(AdaptiveWeek.Swap(day: day(1), planned: .lower, chosen: .upper, reason: nil).label == "Upper for Lower")
    }

    // MARK: End of the week

    @Test func sessionsThatDontFitRollIntoStillToDo() {
        // Saturday with all four sessions to go: two fit, two are still to do.
        let result = week(upperLower, now: day(5, hour: 8))
        #expect(result.slots.count == 2)
        #expect(result.stillToDo.map(\.focus) == [.upper, .lower])
        #expect(result.stillToDoNote?.contains("didn't fit this week") == true)
        #expect(result.stillToDoNote?.contains("missed") == false)
    }

    @Test func weekDoneSaysSo() {
        let p = plan([(2, .fullBody)])
        let result = week(p, done: [.init(date: day(0, hour: 9), focus: .fullBody)], now: day(2, hour: 8))
        let guidance = TrainingDayPlanner.adaptiveGuidance(week: result, past: [], lowRecovery: false, usualTrainingStrain: 65, calendar: calendar)
        #expect(guidance.kind == .rest)
        #expect(guidance.reason.contains("plan done"))
    }

    // MARK: Guidance

    @Test func lowRecoveryMakesTheNextSessionEasy() {
        let result = week(upperLower, now: day(0, hour: 8))
        let guidance = TrainingDayPlanner.adaptiveGuidance(week: result, past: [], lowRecovery: true, usualTrainingStrain: 65, calendar: calendar)
        #expect(guidance.kind == .easyTraining)
        #expect(guidance.focus == .upper)
    }

    @Test func movedSessionIsAMakeUpOnARestDay() {
        // Mon and Tue missed: Wednesday (a rest day) takes Upper.
        let result = week(upperLower, now: day(2, hour: 8))
        #expect(result.today?.focus == .upper)
        let guidance = TrainingDayPlanner.adaptiveGuidance(week: result, past: [], lowRecovery: false, usualTrainingStrain: 65, calendar: calendar)
        #expect(guidance.kind == .makeUp)
        #expect(guidance.reason.contains("planned Mon"))
        #expect(guidance.movedFrom == day(0))
    }

    @Test func hardUnplannedDayStillMeansEasyNext() {
        // Wednesday was a rest day in the queue and turned hard (a long ride): Thursday's Upper goes easy.
        let done: [AdaptiveWeek.DoneSession] = [.init(date: day(0, hour: 9), focus: .upper), .init(date: day(1, hour: 9), focus: .lower),
                                                .init(date: day(2, hour: 9), focus: nil, isLifting: false)]
        let result = week(upperLower, done: done, now: day(3, hour: 8))
        #expect(result.yesterdayWasSlot == false)
        let past = [TrainingDayPlanner.PastDay(date: day(2, hour: 12), plannedFocus: nil, strain: 70, trained: true)]
        let guidance = TrainingDayPlanner.adaptiveGuidance(week: result, past: past, lowRecovery: false, usualTrainingStrain: 65, calendar: calendar)
        #expect(guidance.kind == .easyTraining)
        #expect(guidance.focus == .upper)
    }

    @Test func hardMakeUpDayIsNotARestDayTurnedHard() {
        // Wednesday took Monday's missed Upper (a queue slot): a hard Wednesday is just training.
        let done: [AdaptiveWeek.DoneSession] = [.init(date: day(1, hour: 9), focus: .lower), .init(date: day(2, hour: 9), focus: .upper)]
        let result = week(upperLower, done: done, now: day(3, hour: 8))
        #expect(result.yesterdayWasSlot == true)
        let past = [TrainingDayPlanner.PastDay(date: day(2, hour: 12), plannedFocus: nil, strain: 70, trained: true)]
        let guidance = TrainingDayPlanner.adaptiveGuidance(week: result, past: past, lowRecovery: false, usualTrainingStrain: 65, calendar: calendar)
        #expect(guidance.kind != .easyTraining && guidance.kind != .recovery)
    }

    @Test func flexibleWeeksAreLeftToTheirOwnRule() {
        var p = upperLower
        p.mode = .flexible
        #expect(AdaptiveWeek.make(plan: p, done: [], now: day(0), calendar: calendar) == nil)
        // flexibleGuidance is unchanged.
        let progress = WeeklyPlan.Progress(target: 3, done: 1, daysLeft: 5, trainedToday: false)
        let guidance = TrainingDayPlanner.flexibleGuidance(week: progress, nextFocus: .pull, past: [], lowRecovery: false,
                                                           usualTrainingStrain: 65, calendar: calendar)
        #expect(guidance.kind == .training)
        #expect(guidance.focus == .pull)
    }

    // MARK: Focus from a session

    @Test func inferFocusFromNameOrExercises() {
        #expect(AdaptiveWeek.inferFocus(name: "Upper A", exerciseIDs: []) == .upper)
        #expect(AdaptiveWeek.inferFocus(name: "Lower Body", exerciseIDs: []) == .lower)
        #expect(AdaptiveWeek.inferFocus(name: "Leg Day", exerciseIDs: []) == .legs)
        #expect(AdaptiveWeek.inferFocus(name: "Full body", exerciseIDs: []) == .fullBody)
        #expect(AdaptiveWeek.inferFocus(name: "Morning", exerciseIDs: []) == nil)
        #expect(AdaptiveWeek.isSameSession(.legs, .lower))
        #expect(!AdaptiveWeek.isSameSession(.upper, .lower))
    }
}
