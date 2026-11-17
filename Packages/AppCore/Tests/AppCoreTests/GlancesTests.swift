import Foundation
import Testing
@testable import AppCore

/// The Plan widget and the Watch's plan complication (`PlanGlance`), and when
/// scores go "--" (`GlanceFreshness`). Times are UTC; 2027-01-11 is a Monday.
struct PlanGlanceTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    func date(day: Int = 11, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour, minute: minute))!
    }

    func slot(day: Int, hour: Int = 18, title: String = "Push Day", short: String = "Push") -> PlanGlance.Slot {
        PlanGlance.Slot(start: date(day: day, hour: hour), title: title, shortTitle: short, symbol: "dumbbell.fill", minutes: 60)
    }

    /// A plan written on `day` at `hour` in the week of 11-17 January (it ends Monday 18th 00:00).
    func plan(day: Int = 11, hour: Int = 8, slots: [PlanGlance.Slot], hasPlan: Bool = true,
              nextWeek: PlanGlance.NextWeek = .unplanned, doneAt: Date? = nil, restToday: Bool = false,
              bed: (start: Date, end: Date)? = nil, week: (done: Int, planned: Int)? = nil,
              restUntil: Date? = nil) -> PlanGlance.Plan {
        PlanGlance.Plan(updated: date(day: day, hour: hour), hasPlan: hasPlan, slots: slots, weekEnd: date(day: 18, hour: 0),
                        nextWeek: nextWeek, doneAt: doneAt, restToday: restToday, bedByStart: bed?.start, bedByEnd: bed?.end,
                        weekDone: week?.done, weekPlanned: week?.planned, restUntil: restUntil)
    }

    func state(_ plan: PlanGlance.Plan?, _ now: Date, alsoDoneAt: Date? = nil) -> PlanGlance.State {
        PlanGlance.state(of: plan, at: now, alsoDoneAt: alsoDoneAt, calendar: calendar)
    }

    // MARK: "--"

    @Test func nothingFromThePhoneIsBlank() {
        #expect(state(nil, date(hour: 9)) == .stale)
    }

    @Test func aPlanFromTwoDaysAgoIsBlank() {
        let written = plan(slots: [slot(day: 13)])
        #expect(state(written, date(day: 12, hour: 23, minute: 59)) != .stale)
        #expect(state(written, date(day: 13, hour: 0)) == .stale)
    }

    @Test func aClockThatWentBackIsBlank() {
        #expect(state(plan(day: 12, slots: [slot(day: 13)]), date(day: 11, hour: 20)) == .stale)
    }

    @Test func yesterdaysOpenSessionBlanksTheCarriedDay() {
        // Monday's session wasn't done: the queue may have moved it to Tuesday.
        let missed = plan(slots: [slot(day: 11), slot(day: 13)])
        #expect(state(missed, date(day: 12, hour: 9)) == .stale)
        // Done on Monday: Tuesday reads from the same plan.
        let done = plan(slots: [slot(day: 11), slot(day: 13)], doneAt: date(hour: 19))
        #expect(state(done, date(day: 12, hour: 9)) == .rest(next: slot(day: 13)))
    }

    @Test func aWatchWorkoutTodayKeepsYesterdaysDoneSession() {
        // The phone knew Monday's lift; Tuesday's ended on the Watch since.
        let written = plan(slots: [slot(day: 11), slot(day: 12, hour: 7), slot(day: 14)], doneAt: date(hour: 19))
        let shown = state(written, date(day: 12, hour: 8), alsoDoneAt: date(day: 12, hour: 7, minute: 55))
        #expect(shown == .next(slot(day: 14)))
    }

    // MARK: Sessions

    @Test func sessionShowsItsTimeThenJustToday() {
        let written = plan(slots: [slot(day: 11), slot(day: 13)])
        #expect(state(written, date(hour: 12)) == .session(slot(day: 11), timed: true))
        #expect(state(written, date(hour: 19, minute: 59)) == .session(slot(day: 11), timed: true))
        #expect(state(written, date(hour: 20)) == .session(slot(day: 11), timed: false))
    }

    @Test func bedByReplacesALateSessionInTheEvening() {
        let bed = (start: date(hour: 22, minute: 30), end: date(hour: 23))
        let written = plan(slots: [slot(day: 11), slot(day: 13)], bed: bed)
        // Before the lead the session holds; once its time has passed and bed is near, bed wins.
        #expect(state(written, date(hour: 19)) == .session(slot(day: 11), timed: true))
        #expect(state(written, date(hour: 20, minute: 30)) == .bedBy(start: bed.start, end: bed.end, next: slot(day: 13)))
    }

    @Test func aSessionStillOnTimeKeepsTheWidgetNearBedtime() {
        let bed = (start: date(hour: 22, minute: 30), end: date(hour: 23))
        let written = plan(slots: [slot(day: 11, hour: 21)], bed: bed)
        #expect(state(written, date(hour: 21, minute: 30)) == .session(slot(day: 11, hour: 21), timed: true))
    }

    @Test func afterTrainingTheBedByWindowShows() {
        let bed = (start: date(hour: 22, minute: 30), end: date(hour: 23))
        let written = plan(hour: 19, slots: [slot(day: 11), slot(day: 13)], doneAt: date(hour: 19), bed: bed)
        #expect(state(written, date(hour: 19, minute: 30)) == .bedBy(start: bed.start, end: bed.end, next: slot(day: 13)))
        // Up to an hour after the window, then the next day reads as a rest day.
        #expect(state(written, date(hour: 23, minute: 59)) == .bedBy(start: bed.start, end: bed.end, next: slot(day: 13)))
        #expect(state(written, date(day: 12, hour: 0, minute: 1)) == .rest(next: slot(day: 13)))
    }

    @Test func afterTrainingWithoutABedTimeTheNextSessionShows() {
        let written = plan(slots: [slot(day: 11), slot(day: 13)], doneAt: date(hour: 19))
        #expect(state(written, date(hour: 19, minute: 30)) == .next(slot(day: 13)))
        let last = plan(slots: [slot(day: 11)], doneAt: date(hour: 19))
        #expect(state(last, date(hour: 19, minute: 30)) == .done)
    }

    @Test func aWatchWorkoutCountsBeforeThePhoneHearsOfIt() {
        let written = plan(slots: [slot(day: 11), slot(day: 13)])
        #expect(state(written, date(hour: 19, minute: 10), alsoDoneAt: date(hour: 19)) == .next(slot(day: 13)))
    }

    @Test func afterMidnightTheWindowLeadsToTheMorningSession() {
        // Written late Monday; Tuesday's 07:00 session comes after the sleep the window is for.
        let bed = (start: date(hour: 23, minute: 30), end: date(day: 12, hour: 0))
        let written = plan(hour: 22, slots: [slot(day: 12, hour: 7)], bed: bed)
        #expect(state(written, date(day: 12, hour: 0, minute: 30)) == .bedBy(start: bed.start, end: bed.end, next: slot(day: 12, hour: 7)))
        #expect(state(written, date(day: 12, hour: 1, minute: 1)) == .session(slot(day: 12, hour: 7), timed: true))
    }

    // MARK: Rest days

    @Test func restDayGivesWayToTheBedByWindowTwoHoursBefore() {
        let bed = (start: date(hour: 22, minute: 30), end: date(hour: 23))
        let written = plan(slots: [slot(day: 13)], bed: bed)
        #expect(state(written, date(hour: 20, minute: 29)) == .rest(next: slot(day: 13)))
        #expect(state(written, date(hour: 20, minute: 30)) == .bedBy(start: bed.start, end: bed.end, next: slot(day: 13)))
    }

    @Test func theDaysGuidanceCanMakeAPlannedDayARestDay() {
        let written = plan(slots: [slot(day: 11), slot(day: 13)], restToday: true)
        #expect(state(written, date(hour: 12)) == .rest(next: slot(day: 13)))
        // The next day the session may have moved: only the app knows.
        #expect(state(written, date(day: 12, hour: 9)) == .stale)
    }

    @Test func restModeCoversItsSessionsOnCarriedDaysToo() {
        let written = plan(slots: [slot(day: 11), slot(day: 12), slot(day: 14)], restToday: true,
                           restUntil: date(day: 13, hour: 8))
        #expect(state(written, date(hour: 12)) == .rest(next: slot(day: 14)))
        #expect(state(written, date(day: 12, hour: 12)) == .rest(next: slot(day: 14)))
    }

    // MARK: Weeks

    @Test func noPlanThisWeekSaysSo() {
        #expect(state(plan(slots: [], hasPlan: false), date(hour: 9)) == .noPlan)
    }

    @Test func theNewWeekFollowsWhatThePhoneKnewOfIt() {
        let sunday = 17
        let monday = slot(day: 18, hour: 7)
        #expect(state(plan(day: sunday, slots: [monday], nextWeek: .unplanned), date(day: 18, hour: 6)) == .noPlan)
        #expect(state(plan(day: sunday, slots: [], nextWeek: .open), date(day: 18, hour: 6)) == .stale)
        #expect(state(plan(day: sunday, slots: [monday], nextWeek: .planned), date(day: 18, hour: 6)) == .session(monday, timed: true))
    }

    @Test func weekCountShowsOnlyWhileItIsTrue() {
        let written = plan(hour: 19, slots: [slot(day: 11), slot(day: 13)], doneAt: date(hour: 19), week: (done: 2, planned: 4))
        #expect(PlanGlance.week(of: written, at: date(hour: 20), calendar: calendar) == PlanGlance.Week(done: 2, planned: 4))
        // A Watch workout the count doesn't include yet.
        #expect(PlanGlance.week(of: written, at: date(day: 12, hour: 9), alsoDoneAt: date(day: 12, hour: 8), calendar: calendar) == nil)
        // Stale plan, a new week, no plan.
        #expect(PlanGlance.week(of: written, at: date(day: 13, hour: 9), calendar: calendar) == nil)
        let sunday = plan(day: 17, slots: [], week: (done: 4, planned: 4))
        #expect(PlanGlance.week(of: sunday, at: date(day: 18, hour: 1), calendar: calendar) == nil)
        #expect(PlanGlance.week(of: plan(slots: [], hasPlan: false, week: (done: 0, planned: 3)), at: date(hour: 9), calendar: calendar) == nil)
        // More days trained than planned reads as all done, never "5 of 4".
        let extra = plan(slots: [slot(day: 13)], week: (done: 5, planned: 4))
        #expect(PlanGlance.week(of: extra, at: date(hour: 9), calendar: calendar) == PlanGlance.Week(done: 4, planned: 4))
    }

    // MARK: Timeline and Smart Stack

    @Test func changeDatesCoverEveryMomentTheGlanceMoves() {
        let bed = (start: date(hour: 22, minute: 30), end: date(hour: 23))
        let written = plan(slots: [slot(day: 11), slot(day: 13), slot(day: 20)], bed: bed, restUntil: date(day: 12, hour: 10))
        let dates = PlanGlance.changeDates(of: written, after: date(hour: 9), calendar: calendar)
        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
        #expect(dates.contains(date(hour: 20)))                 // Monday's session window ends
        #expect(dates.contains(date(hour: 20, minute: 30)))     // bed-by lead
        #expect(dates.contains(date(hour: 23, minute: 59) + 60)) // bed-by grace ends at midnight
        #expect(dates.contains(date(day: 12, hour: 0)))         // midnight
        #expect(dates.contains(date(day: 12, hour: 10)))        // rest mode ends
        #expect(dates.allSatisfy { $0 > date(hour: 9) && $0 <= date(day: 13, hour: 9) })
        #expect(!dates.contains(date(day: 20, hour: 20)))       // past the horizon
    }

    @Test func smartStackWindowsBeforeSessionsAndBedtime() {
        let bed = (start: date(hour: 22, minute: 30), end: date(hour: 23))
        let written = plan(slots: [slot(day: 11), slot(day: 12, hour: 7), slot(day: 14)], bed: bed)
        let windows = PlanGlance.relevantWindows(of: written, after: date(hour: 9), calendar: calendar)
        #expect(windows == [
            PlanGlance.Window(interval: DateInterval(start: date(hour: 17), end: date(hour: 18)), reason: .session),
            PlanGlance.Window(interval: DateInterval(start: date(hour: 21, minute: 30), end: date(hour: 23)), reason: .bedtime),
            PlanGlance.Window(interval: DateInterval(start: date(day: 12, hour: 6), end: date(day: 12, hour: 7)), reason: .session),
        ])
        // Thursday's is beyond what the plan can be trusted for (written Monday).
        #expect(!windows.contains { $0.interval.end == date(day: 14, hour: 18) })
    }

    @Test func smartStackSkipsDoneRestedAndBlankPlans() {
        let done = plan(hour: 19, slots: [slot(day: 11), slot(day: 12)], doneAt: date(hour: 19))
        #expect(PlanGlance.relevantWindows(of: done, after: date(hour: 19, minute: 30), calendar: calendar)
            .map(\.interval.end) == [date(day: 12, hour: 18)])
        let rested = plan(slots: [slot(day: 11), slot(day: 12)], restUntil: date(day: 13, hour: 0))
        #expect(PlanGlance.relevantWindows(of: rested, after: date(hour: 9), calendar: calendar).isEmpty)
        let missed = plan(slots: [slot(day: 11), slot(day: 12)])
        #expect(PlanGlance.relevantWindows(of: missed, after: date(day: 12, hour: 9), calendar: calendar).isEmpty)
        #expect(PlanGlance.relevantWindows(of: nil, after: date(hour: 9), calendar: calendar).isEmpty)
    }

    @Test func smartStackDoesNotPromiseNextWeekWithoutItsPlan() {
        let sunday = plan(day: 17, slots: [slot(day: 17), slot(day: 18, hour: 7)], nextWeek: .open)
        #expect(PlanGlance.relevantWindows(of: sunday, after: date(day: 17, hour: 9), calendar: calendar)
            .map(\.interval.end) == [date(day: 17, hour: 18)])
    }

    // MARK: Words

    @Test func wordsForEachState() {
        let now = date(hour: 9)
        let stale = PlanGlance.lines(for: .stale, at: now, calendar: calendar)
        #expect(stale.title == "--" && stale.short == "--")
        #expect(stale.detail == "Open Tensile to update")
        #expect(PlanGlance.lines(for: .stale, at: now, onWatch: true, calendar: calendar).detail == "Open Tensile on iPhone")
        let rest = PlanGlance.lines(for: .rest(next: slot(day: 12)), at: now, calendar: calendar)
        #expect(rest.title == "Rest day" && rest.detail == "Tomorrow: Push")
        let bed = PlanGlance.lines(for: .bedBy(start: date(hour: 22), end: date(hour: 22, minute: 30), next: nil), at: now, calendar: calendar)
        #expect(bed.eyebrow == "In bed by" && bed.symbol == "bed.double.fill")
        let session = PlanGlance.lines(for: .session(slot(day: 11), timed: false), at: now, calendar: calendar)
        #expect(session.title == "Push Day" && session.short == "Today" && session.detail == "60 min")
        #expect(session.spoken == "Today's session: Push Day, 60 minutes.")
        #expect(PlanGlance.lines(for: .done, at: now, calendar: calendar).title == "Done for today")
        #expect(PlanGlance.lines(for: .noPlan, at: now, calendar: calendar).title == "No plan yet")
    }

    // MARK: Stored data

    @Test func aPlanStoredWithoutRestModeStillDecodes() throws {
        let written = plan(slots: [slot(day: 11)], restUntil: date(day: 12, hour: 0))
        let data = try JSONEncoder().encode(written)
        #expect(try JSONDecoder().decode(PlanGlance.Plan.self, from: data) == written)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "restUntil")
        let older = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(PlanGlance.Plan.self, from: older).restUntil == nil)
    }

    // MARK: Three weeks, hour by hour

    /// Mon/Wed/Fri/Sat at 18:00 for three weeks. The phone writes the plan at
    /// 07:00 and after each session, except on the days it isn't opened; one
    /// Wednesday session is missed. Whatever the hour, the glance never shows a
    /// session that was done, never offers a day the phone hasn't confirmed
    /// after a missed session, and is never older than a day.
    @Test func threeWeeksHourByHour() {
        let weekStarts = [11, 18, 25]
        let sessionDays = weekStarts.flatMap { [$0, $0 + 2, $0 + 4, $0 + 5] }
        let missedDay = 20
        let unopenedDays: Set<Int> = [12, 19, 21, 27]
        var written: PlanGlance.Plan?
        var lastDone: Date?
        var shownSession = 0
        var shownBlank = 0
        for day in 11...31 {
            for hour in 0..<24 {
                let now = date(day: day, hour: hour)
                // Sessions end at 19:00, logged on the Watch when the phone isn't opened.
                if hour == 19, sessionDays.contains(day), day != missedDay { lastDone = date(day: day, hour: 19) }
                // The phone writes at 07:00 and at 19:00 after a session (not on unopened days).
                if (hour == 7 || hour == 19) && !unopenedDays.contains(day) {
                    let weekStart = weekStarts.last { $0 <= day }!
                    let upcoming = sessionDays.filter { $0 >= day && $0 < day + 8 }.map { slot(day: $0) }
                    let done = lastDone.map { calendar.isDate($0, inSameDayAs: now) } ?? false
                    written = PlanGlance.Plan(
                        updated: now, hasPlan: true, slots: upcoming, weekEnd: date(day: weekStart + 7, hour: 0),
                        nextWeek: weekStart + 7 <= 25 ? .planned : .unplanned, doneAt: lastDone,
                        bedByStart: date(day: day, hour: 22, minute: 30), bedByEnd: date(day: day, hour: 23),
                        weekDone: done ? 1 : 0, weekPlanned: 4)
                }
                // As the Watch sees it: its own workout end counts at once.
                let shown = state(written, now, alsoDoneAt: lastDone)
                switch shown {
                case .session(let slot, _):
                    shownSession += 1
                    #expect(calendar.isDate(slot.start, inSameDayAs: now))
                    #expect(!(lastDone.map { calendar.isDate($0, inSameDayAs: now) } ?? false) || hour < 19,
                            "a done session still showing on day \(day) at \(hour):00")
                case .stale:
                    shownBlank += 1
                default:
                    break
                }
                if let written, shown != .stale {
                    let age = calendar.dateComponents([.day], from: calendar.startOfDay(for: written.updated),
                                                      to: calendar.startOfDay(for: now)).day!
                    #expect(age <= PlanGlance.carryDays)
                }
                // The day after the missed Wednesday wasn't opened: blank, not a guess.
                if day == 21 { #expect(shown == .stale) }
            }
        }
        #expect(shownSession > 0)
        #expect(shownBlank > 0)
    }
}

struct GlanceFreshnessTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(day: Int = 11, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour, minute: minute))!
    }

    @Test func strainBlanksAfterThreeHoursAndAtMidnight() {
        let updated = date(hour: 9)
        #expect(GlanceFreshness.strainIsCurrent(updated: updated, at: date(hour: 11, minute: 59), calendar: calendar))
        #expect(!GlanceFreshness.strainIsCurrent(updated: updated, at: date(hour: 12), calendar: calendar))
        let late = date(hour: 23)
        #expect(!GlanceFreshness.strainIsCurrent(updated: late, at: date(day: 12, hour: 0, minute: 30), calendar: calendar))
    }

    @Test func scoresBelongToTheirDay() {
        #expect(GlanceFreshness.isToday(date(hour: 6), at: date(hour: 23), calendar: calendar))
        #expect(!GlanceFreshness.isToday(date(hour: 23), at: date(day: 12, hour: 0), calendar: calendar))
    }

    @Test func changeDatesAreWhenStrainBlanksAndMidnight() {
        #expect(GlanceFreshness.changeDates(updated: date(hour: 9), after: date(hour: 10), calendar: calendar)
            == [date(hour: 12), date(day: 12, hour: 0)])
        // Already blank: only midnight.
        #expect(GlanceFreshness.changeDates(updated: date(hour: 6), after: date(hour: 10), calendar: calendar)
            == [date(day: 12, hour: 0)])
        #expect(GlanceFreshness.changeDates(updated: nil, after: date(hour: 10), calendar: calendar) == [date(day: 12, hour: 0)])
    }
}
