import Foundation
import Testing
@testable import AppCore

/// Easy cardio around lifting (`CardioPlanner`): rest days first, never on a
/// heavy lower day for a strength goal, the bike for muscle goals, inside a
/// rest day's strain range, and never part of the lifting quota.
struct CardioPlannerTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Monday 2 March 2026, 00:00 UTC.
    var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))! }

    let strength = Goals(focuses: [.strength])
    let muscle = Goals(focuses: [.muscle])
    let health = Goals(focuses: [.health])

    func plan(_ days: [(Int, WorkoutFocus)], cardio: Int, mode: WeeklyPlan.Mode = .fixedDays) -> WeeklyPlan {
        WeeklyPlan(weekStart: monday,
                   plannedDays: days.map { PlannedDay(weekday: $0.0, time: 1080, focus: $0.1, minutes: 60) },
                   mode: mode, sessionsPerWeek: mode == .flexible ? days.count : nil,
                   cardio: EasyCardio(sessionsPerWeek: cardio, kind: .bike))
    }

    @Test func noneWhenTheWeekHasNone() {
        #expect(CardioPlanner.slots(for: plan([(2, .upper)], cardio: 0), goals: nil).isEmpty)
        var noCardio = plan([(2, .upper)], cardio: 1)
        noCardio.cardio = nil
        #expect(CardioPlanner.slots(for: noCardio, goals: nil).isEmpty)
        // The count is kept to 0-2.
        #expect(EasyCardio(sessionsPerWeek: 5).sessionsPerWeek == 2)
        #expect(EasyCardio(sessionsPerWeek: -1).sessionsPerWeek == 0)
    }

    @Test func restDaysFirstAndNotTheDayBeforeLegs() {
        // Mon upper, Tue lower, Thu upper, Fri lower: Wed, Sat and Sun are rest days, none before a lower day.
        let week = plan([(2, .upper), (3, .lower), (5, .upper), (6, .lower)], cardio: 2)
        let slots = CardioPlanner.slots(for: week, goals: strength)
        // Wednesday first, then Saturday (Sunday is as good; the earlier day wins). Lower days are out for strength.
        #expect(slots.map(\.weekday) == [4, 7])
        #expect(slots.allSatisfy { $0.kind == .bike && $0.minutes == 30 })
        #expect(slots.map(\.index) == [0, 1])
    }

    @Test func spreadsSlotsApart() {
        // Mon/Wed/Fri push-pull-push: Tue, Thu, Sat and Sun are free; Tue first, then Thu (not next to Tue).
        let week = plan([(2, .push), (4, .pull), (6, .push)], cardio: 2)
        let slots = CardioPlanner.slots(for: week, goals: muscle)
        #expect(slots.map(\.weekday) == [3, 5])
        // Back to back only when nothing else is as good: six lifting days leave Sunday, then an upper day.
        let busy = plan([(2, .upper), (3, .upper), (4, .upper), (5, .upper), (6, .upper), (7, .upper)], cardio: 2)
        #expect(CardioPlanner.slots(for: busy, goals: muscle).map(\.weekday) == [2, 1])
    }

    @Test func strengthGoalNeverGetsCardioOnAHeavyLowerDay() {
        let allLower = plan([(2, .legs), (3, .lower), (4, .fullBody), (5, .legs), (6, .lower), (7, .fullBody)], cardio: 2)
        // Strength: Sunday only (the day before Monday's legs, still a rest day).
        #expect(CardioPlanner.slots(for: allLower, goals: strength).map(\.weekday) == [1])
        // Other goals may use a lower day when nothing else is left.
        let other = CardioPlanner.slots(for: allLower, goals: health).map(\.weekday)
        #expect(other.count == 2)
        #expect(other.contains(1))
        #expect(CardioPlanner.isHeavyLower(.fullBody))
        #expect(!CardioPlanner.isHeavyLower(.push))
    }

    @Test func restDayBeforeLegsBeatsAnUpperDay() {
        // Mon-Sat alternate legs and upper; Sunday, a rest day before Monday's legs, still beats an upper day.
        let week = plan([(2, .legs), (3, .upper), (4, .legs), (5, .upper), (6, .legs), (7, .upper)], cardio: 1)
        #expect(CardioPlanner.slots(for: week, goals: muscle).map(\.weekday) == [1])
    }

    @Test func flexibleWeeksHaveAnyDaySlots() {
        let week = plan([(2, .upper), (4, .lower), (6, .upper)], cardio: 2, mode: .flexible)
        let slots = CardioPlanner.slots(for: week, goals: strength)
        #expect(slots.count == 2)
        #expect(slots.allSatisfy { $0.weekday == nil })
        // Cardio never counts toward the lifting quota.
        #expect(week.sessionTarget == 3)
    }

    @Test func bikeForMuscleAndStrengthGoals() {
        #expect(CardioPlanner.recommendedKind(goals: muscle) == .bike)
        #expect(CardioPlanner.recommendedKind(goals: strength) == .bike)
        #expect(CardioPlanner.recommendedKind(goals: health) == .inclineWalk)
        #expect(CardioPlanner.recommendedKind(goals: nil) == .inclineWalk)
        #expect(EasyCardio(sessionsPerWeek: 1).title == "Easy ride · 30 min")
    }

    @Test func easyHalfHourFitsARestDay() {
        // About 15% on the app's scale; within the 0-25% rest-day range for either curve and up to 55% of reserve.
        let typical = CardioPlanner.estimatedStrain(minutes: 30)
        #expect((12...18).contains(typical))
        for fraction in [0.40, 0.45, 0.55] {
            for sex in [BiologicalSex.male, .female] {
                let strain = CardioPlanner.estimatedStrain(minutes: 30, reserveFraction: fraction, sex: sex)
                #expect(strain <= TrainingDayPlanner.restDayRange.upperBound, "\(fraction) \(sex): \(strain)")
            }
        }
        #expect(CardioPlanner.plannedMinutes(EasyCardio(sessionsPerWeek: 2)) == 60)
        #expect(CardioPlanner.plannedMinutes(nil) == 0)
        #expect(CardioPlanner.bandLine(EasyCardio(sessionsPerWeek: 2), goals: muscle)?.hasPrefix("60 planned minutes toward your 150") == true)
        #expect(CardioPlanner.bandLine(EasyCardio(sessionsPerWeek: 0), goals: muscle) == nil)
    }

    @Test func doneFromHealthWorkoutsOfThatType() {
        let workouts = [
            CardioPlanner.Workout(name: "Ride", start: monday.addingTimeInterval(2 * 86_400 + 3600), minutes: 32),  // Wed
            CardioPlanner.Workout(name: "Run", start: monday.addingTimeInterval(5 * 86_400), minutes: 30),          // wrong type
            CardioPlanner.Workout(name: "Ride", start: monday.addingTimeInterval(6 * 86_400), minutes: 10),         // too short
            CardioPlanner.Workout(name: "Ride", start: monday.addingTimeInterval(-86_400), minutes: 40),            // last week
        ]
        let days = CardioPlanner.doneDays(kind: .bike, workouts: workouts, weekStart: monday, calendar: calendar)
        #expect(days == [calendar.startOfDay(for: monday.addingTimeInterval(2 * 86_400))])
        let fixed = [CardioPlanner.Slot(index: 0, weekday: 4, kind: .bike, minutes: 30),
                     CardioPlanner.Slot(index: 1, weekday: 7, kind: .bike, minutes: 30)]
        #expect(CardioPlanner.done(slots: fixed, doneDays: days, weekStart: monday, calendar: calendar) == [0])
        let flexible = [CardioPlanner.Slot(index: 0, weekday: nil, kind: .bike, minutes: 30),
                        CardioPlanner.Slot(index: 1, weekday: nil, kind: .bike, minutes: 30)]
        #expect(CardioPlanner.done(slots: flexible, doneDays: days, weekStart: monday, calendar: calendar) == [0])
        #expect(EasyCardio.Kind.inclineWalk.workoutNames.contains("Walk"))
    }

    @Test func todaysRow() throws {
        let fixed = [CardioPlanner.Slot(index: 0, weekday: 4, kind: .bike, minutes: 30)]
        let wednesday = try #require(CardioPlanner.today(slots: fixed, doneSlots: [], doneToday: false, weekday: 4, goals: muscle,
                                                         lowRecovery: false, liftedHeavyLowerToday: false,
                                                         strainRange: TrainingDayPlanner.restDayRange))
        #expect(wednesday.title == "Easy ride · 30 min")
        #expect(wednesday.minutes == 30)
        // Not today's day, already done, or done today: no row.
        #expect(CardioPlanner.today(slots: fixed, doneSlots: [], doneToday: false, weekday: 3, goals: muscle,
                                    lowRecovery: false, liftedHeavyLowerToday: false) == nil)
        #expect(CardioPlanner.today(slots: fixed, doneSlots: [0], doneToday: false, weekday: 4, goals: muscle,
                                    lowRecovery: false, liftedHeavyLowerToday: false) == nil)
        #expect(CardioPlanner.today(slots: fixed, doneSlots: [], doneToday: true, weekday: 4, goals: muscle,
                                    lowRecovery: false, liftedHeavyLowerToday: false) == nil)
        // Low recovery: the 15-minute version.
        let low = try #require(CardioPlanner.today(slots: fixed, doneSlots: [], doneToday: false, weekday: 4, goals: muscle,
                                                   lowRecovery: true, liftedHeavyLowerToday: false))
        #expect(low.minutes == 15)
        #expect(low.title == "Easy ride · 15 min")
        #expect(low.detail.hasPrefix("Recovery is low"))
        // A strain range 30 minutes would pass also shortens it.
        let tight = try #require(CardioPlanner.today(slots: fixed, doneSlots: [], doneToday: false, weekday: 4, goals: muscle,
                                                     lowRecovery: false, liftedHeavyLowerToday: false, strainRange: 0...10))
        #expect(tight.minutes == 15)
        // …and says why: the strain range, not recovery.
        #expect(tight.detail == "30 minutes would pass today's strain range: keep it to 15 easy minutes")

        let flexible = [CardioPlanner.Slot(index: 0, weekday: nil, kind: .row, minutes: 30),
                        CardioPlanner.Slot(index: 1, weekday: nil, kind: .row, minutes: 30)]
        let any = try #require(CardioPlanner.today(slots: flexible, doneSlots: [0], doneToday: false, weekday: 3, goals: muscle,
                                                   lowRecovery: false, liftedHeavyLowerToday: true))
        #expect(any.title == "Easy row · 30 min")
        #expect(any.detail.hasPrefix("Any day this week."))
        // Strength goal after a heavy lower session today: another day.
        #expect(CardioPlanner.today(slots: flexible, doneSlots: [], doneToday: false, weekday: 3, goals: strength,
                                    lowRecovery: false, liftedHeavyLowerToday: true) == nil)
        #expect(CardioPlanner.today(slots: flexible, doneSlots: [0, 1], doneToday: false, weekday: 3, goals: muscle,
                                    lowRecovery: false, liftedHeavyLowerToday: false) == nil)
    }

    @Test func oldPlansDecodeWithoutCardio() throws {
        let old = #"{"weekStart":0,"plannedDays":[],"changes":[]}"#
        let decoded = try JSONDecoder().decode(WeeklyPlan.self, from: Data(old.utf8))
        #expect(decoded.cardio == nil)
        let week = plan([(2, .upper)], cardio: 2)
        let round = try JSONDecoder().decode(WeeklyPlan.self, from: JSONEncoder().encode(week))
        #expect(round == week)
        #expect(round.cardio?.kind == .bike)
    }
}
