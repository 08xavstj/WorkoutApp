import Foundation
import Testing
@testable import AppCore

/// Last week's left-over session goes first in the new week.
struct AdaptiveWeekCarryOverTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    /// Monday 2 November 2026 (last week) and Monday 9 November (this week).
    var lastMonday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))! }
    var thisMonday: Date { calendar.date(byAdding: .day, value: 7, to: lastMonday)! }

    func at(_ week: Date, _ offset: Int, hour: Int = 18) -> Date {
        calendar.date(byAdding: .hour, value: offset * 24 + hour, to: week)!
    }

    /// Mon Upper, Tue Lower, Thu Upper, Fri Lower.
    func upperLower(_ weekStart: Date, mode: WeeklyPlan.Mode = .fixedDays, quota: Int? = nil) -> WeeklyPlan {
        let days: [(Int, WorkoutFocus)] = [(2, .upper), (3, .lower), (5, .upper), (6, .lower)]
        return WeeklyPlan(weekStart: weekStart, plannedDays: days.map { PlannedDay(weekday: $0.0, time: 18 * 60, focus: $0.1, minutes: 60) },
                          mode: mode, sessionsPerWeek: quota)
    }

    /// Last week: Upper, Lower, Upper done; Friday's Lower missed.
    var lastWeekDone: [AdaptiveWeek.DoneSession] {
        [.init(date: at(lastMonday, 0), focus: .upper), .init(date: at(lastMonday, 1), focus: .lower),
         .init(date: at(lastMonday, 3), focus: .upper)]
    }

    @Test func leftOverIsTheSessionNotDone() {
        let left = AdaptiveWeek.leftOver(plan: upperLower(lastMonday), done: lastWeekDone, calendar: calendar)
        #expect(left.map(\.focus) == [.lower])
        #expect(left.first?.weekday == 6)
    }

    @Test func fullWeekLeavesNothing() {
        let done = lastWeekDone + [.init(date: at(lastMonday, 4), focus: .lower)]
        #expect(AdaptiveWeek.leftOver(plan: upperLower(lastMonday), done: done, calendar: calendar).isEmpty)
    }

    @Test func thisWeeksSessionsDontCountForLastWeek() {
        let done = lastWeekDone + [.init(date: at(thisMonday, 0), focus: .lower)]
        #expect(AdaptiveWeek.leftOver(plan: upperLower(lastMonday), done: done, calendar: calendar).map(\.focus) == [.lower])
    }

    @Test func flexibleQuotaOnlyOwesWhatItAskedFor() {
        // Three a week asked, three done: nothing owed, even with a fourth session listed.
        let plan = upperLower(lastMonday, mode: .flexible, quota: 3)
        #expect(AdaptiveWeek.leftOver(plan: plan, done: lastWeekDone, calendar: calendar).isEmpty)
    }

    @Test func newWeekStartsWithTheLeftOver() throws {
        let result = try #require(AdaptiveWeek.make(plan: upperLower(thisMonday), done: lastWeekDone, now: at(thisMonday, 0, hour: 8),
                                                    carriedOver: .lower, calendar: calendar))
        #expect(result.today?.focus == .lower)
        // The rotation carries on, so the week still alternates.
        #expect(result.slots.map(\.focus) == [.lower, .upper, .lower, .upper])
        #expect(result.slots.map(\.session.weekday) == [2, 3, 5, 6])
        #expect(result.today?.note == "Lower first: it didn't fit last week.")
        #expect(result.stillToDo.isEmpty)
    }

    /// "Same days as last week" after a missed Lower: this week is saved
    /// already rotated (Lower, Upper, Lower, Upper), with the rotation recorded.
    @Test func aStoredRotationSaysWhyAndLeavesTheStandingOrder() throws {
        let made = AdaptiveWeek.rotatedWeek(upperLower(lastMonday).plannedDays, startingWith: .lower)
        #expect(made.days.map(\.focus) == [.lower, .upper, .lower, .upper])
        #expect(made.days.map(\.weekday) == [2, 3, 5, 6])
        #expect(made.rotation == WeeklyPlan.Rotation(by: 1, focuses: [.lower, .upper, .lower, .upper]))
        let plan = WeeklyPlan(weekStart: thisMonday, plannedDays: made.days, rotation: made.rotation)
        // The reason shows this week, though nothing is moved again.
        let result = try #require(AdaptiveWeek.make(plan: plan, done: lastWeekDone, now: at(thisMonday, 0, hour: 8),
                                                    carriedOver: .lower, calendar: calendar))
        #expect(result.slots.map(\.focus) == [.lower, .upper, .lower, .upper])
        #expect(result.today?.note == "Lower first: it didn't fit last week.")
        // Next week starts again from the standing order: the split hasn't drifted.
        #expect(plan.standingDays.map(\.focus) == [.upper, .lower, .upper, .lower])
        #expect(plan.standingDays.map(\.weekday) == [2, 3, 5, 6])
        let next = AdaptiveWeek.rotatedWeek(plan.standingDays, startingWith: nil)
        #expect(next.days.map(\.focus) == [.upper, .lower, .upper, .lower])
        #expect(next.rotation == nil)
    }

    @Test func aWeekInItsStandingOrderHasNoRotationOrNote() throws {
        // Nothing left over, or the left-over already leads: nothing moves and nothing is recorded.
        #expect(AdaptiveWeek.rotatedWeek(upperLower(lastMonday).plannedDays, startingWith: nil).rotation == nil)
        #expect(AdaptiveWeek.rotatedWeek(upperLower(lastMonday).plannedDays, startingWith: .upper).rotation == nil)
        let plan = upperLower(thisMonday)
        #expect(plan.activeRotation == nil)
        #expect(plan.standingDays == plan.sortedDays)
        let result = try #require(AdaptiveWeek.make(plan: plan, done: [], now: at(thisMonday, 0, hour: 8), calendar: calendar))
        #expect(result.today?.note == nil)
    }

    @Test func threeDayRotationUnwinds() {
        let days: [(Int, WorkoutFocus)] = [(2, .push), (4, .pull), (6, .legs)]
        let standing = days.map { PlannedDay(weekday: $0.0, time: 18 * 60, focus: $0.1, minutes: 60) }
        let made = AdaptiveWeek.rotatedWeek(standing, startingWith: .legs)
        #expect(made.days.map(\.focus) == [.legs, .push, .pull])
        #expect(made.rotation?.by == 2)
        let plan = WeeklyPlan(weekStart: thisMonday, plannedDays: made.days, rotation: made.rotation)
        #expect(plan.standingDays.map(\.focus) == [.push, .pull, .legs])
    }

    @Test func planningTheWeekAgainByHandEndsTheRotation() {
        let made = AdaptiveWeek.rotatedWeek(upperLower(lastMonday).plannedDays, startingWith: .lower)
        var plan = WeeklyPlan(weekStart: thisMonday, plannedDays: made.days, rotation: made.rotation)
        // Only a time changed: still the rotated week.
        plan.plannedDays[0].time = 7 * 60
        #expect(plan.activeRotation != nil)
        // What a day trains changed: the days as they are now are the standing order.
        plan.plannedDays[0].focus = .fullBody
        #expect(plan.activeRotation == nil)
        #expect(plan.standingDays == plan.sortedDays)
    }

    @Test func rotationSurvivesSavingAndOlderPlansDecode() throws {
        let made = AdaptiveWeek.rotatedWeek(upperLower(lastMonday).plannedDays, startingWith: .lower)
        let plan = WeeklyPlan(weekStart: thisMonday, plannedDays: made.days, rotation: made.rotation)
        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(WeeklyPlan.self, from: data) == plan)
        // A plan saved before rotations were recorded has none.
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["rotation"] = nil
        let older = try JSONDecoder().decode(WeeklyPlan.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older.rotation == nil)
        #expect(older.plannedDays == plan.plannedDays)
    }

    @Test func afterTheLeftOverIsDoneTheWeekCarriesOn() throws {
        let done: [AdaptiveWeek.DoneSession] = [.init(date: at(thisMonday, 0), focus: .lower)]
        let result = try #require(AdaptiveWeek.make(plan: upperLower(thisMonday), done: done, now: at(thisMonday, 1, hour: 8),
                                                    carriedOver: .lower, calendar: calendar))
        #expect(result.today?.focus == .upper)
        #expect(result.slots.map(\.focus) == [.upper, .lower, .upper])
        #expect(result.slots.allSatisfy { $0.note == nil })
    }

    @Test func doingAnotherSessionFirstStillLeavesTheLeftOverNext() throws {
        // Upper on Monday anyway: Lower is next on Tuesday.
        let done: [AdaptiveWeek.DoneSession] = [.init(date: at(thisMonday, 0), focus: .upper)]
        let result = try #require(AdaptiveWeek.make(plan: upperLower(thisMonday), done: done, now: at(thisMonday, 1, hour: 8),
                                                    carriedOver: .lower, calendar: calendar))
        #expect(result.today?.focus == .lower)
    }

    @Test func noLeftOverKeepsThePlan() throws {
        let result = try #require(AdaptiveWeek.make(plan: upperLower(thisMonday), done: [], now: at(thisMonday, 0, hour: 8),
                                                    carriedOver: nil, calendar: calendar))
        #expect(result.slots.map(\.focus) == [.upper, .lower, .upper, .lower])
        #expect(result.today?.note == nil)
    }

    @Test func leftOverAlreadyFirstChangesNothing() throws {
        let result = try #require(AdaptiveWeek.make(plan: upperLower(thisMonday), done: [], now: at(thisMonday, 0, hour: 8),
                                                    carriedOver: .upper, calendar: calendar))
        #expect(result.slots.map(\.focus) == [.upper, .lower, .upper, .lower])
        #expect(result.today?.note == nil)
    }

    @Test func legsLeftOverMatchesALowerDay() throws {
        let result = try #require(AdaptiveWeek.make(plan: upperLower(thisMonday), done: [], now: at(thisMonday, 0, hour: 8),
                                                    carriedOver: .legs, calendar: calendar))
        #expect(result.today?.focus == .lower)
    }

    // MARK: Copying last week's days

    @Test func rotatedTemplatePutsTheLeftOverOnTheFirstDay() {
        var template = upperLower(lastMonday).sortedDays
        template[0].minutes = 45
        let days = AdaptiveWeek.rotated(template, startingWith: .lower)
        #expect(days.map(\.focus) == [.lower, .upper, .lower, .upper])
        // Days keep their weekday, time and length.
        #expect(days.map(\.weekday) == [2, 3, 5, 6])
        #expect(days.map(\.minutes) == [45, 60, 60, 60])
    }

    @Test func rotatedTemplateWithoutLeftOverIsUnchanged() {
        let template = upperLower(lastMonday).sortedDays
        #expect(AdaptiveWeek.rotated(template, startingWith: nil) == template)
        #expect(AdaptiveWeek.rotated(template, startingWith: .push) == template)
    }

    @Test func threeDaySplitRotates() {
        let days: [PlannedDay] = [(2, WorkoutFocus.upper), (4, .lower), (6, .fullBody)]
            .map { PlannedDay(weekday: $0.0, time: 18 * 60, focus: $0.1, minutes: 60) }
        #expect(AdaptiveWeek.rotated(days, startingWith: .fullBody).map(\.focus) == [.fullBody, .upper, .lower])
    }
}
