import Foundation
import Testing
@testable import AppCore

// Planned sessions in Apple Calendar (`PlanCalendar`) and chosen variety at
// block boundaries (`BlockVariety`).

private let calendar = SimFixtures.calendar
private let monday = SimFixtures.monday

private func at(_ offset: Int, hour: Int) -> Date {
    calendar.date(byAdding: .day, value: offset, to: monday)!.addingTimeInterval(Double(hour) * 3600)
}

private let plan = WeeklyPlan(weekStart: monday, plannedDays: [
    PlannedDay(weekday: 2, time: 18 * 60, focus: .upper, minutes: 60),
    PlannedDay(weekday: 4, time: 18 * 60, focus: .lower, minutes: 60),
    PlannedDay(weekday: 6, time: 7 * 60, focus: .fullBody, minutes: 45),
])

@Suite("Plan calendar")
struct PlanCalendarTests {
    @Test func lastWeeksPlannedSessionsThatPassedAreClearedOnceTheWeekTurns() throws {
        // Week 1 planned Mon, Wed and Fri; Wed was missed. On Tuesday of week 2 the window is
        // week 2 and 3, so last week's entries are outside it: the lookback finds them.
        let now = at(8, hour: 9)
        let window = PlanCalendar.window(now: now, calendar: calendar)
        #expect(window.start == at(7, hour: 0))
        let lookback = PlanCalendar.lookback(before: window.start, calendar: calendar)
        #expect(lookback.start == monday)
        #expect(lookback.end == window.start)
        let entries = PlanCalendar.entries(plan: plan, week: nil, now: at(0, hour: 9), calendar: calendar)
        let missed = try #require(entries.first { $0.start == at(2, hour: 18) })
        #expect(PlanCalendar.isPassedSession(key: missed.key, start: missed.start, now: now, calendar: calendar))
        // A finished session's entry stays, and so does anything later today or untagged.
        #expect(!PlanCalendar.isPassedSession(key: "done|2026-01-07", start: at(2, hour: 18), now: now, calendar: calendar))
        #expect(!PlanCalendar.isPassedSession(key: "lift|2026-01-13", start: at(8, hour: 18), now: now, calendar: calendar))
        #expect(!PlanCalendar.isPassedSession(key: nil, start: at(2, hour: 18), now: now, calendar: calendar))
    }

    @Test func entriesForTheDaysStillToCome() {
        let entries = PlanCalendar.entries(plan: plan, week: nil, now: at(1, hour: 9), calendar: calendar)
        #expect(entries.map(\.title) == [WorkoutFocus.lower.title, WorkoutFocus.fullBody.title])
        #expect(entries.first?.start == at(2, hour: 18))
        #expect(entries.first?.end == at(2, hour: 19))
        #expect(entries.allSatisfy { $0.key.hasPrefix("lift|") })
    }

    @Test func aFinishedSessionIsMarkedDoneAtTheTimeItHappened() {
        let finished = [PlanCalendar.Finished(start: at(0, hour: 17), minutes: 55, name: "Upper")]
        let entries = PlanCalendar.entries(plan: plan, week: nil, finished: finished, now: at(0, hour: 20), calendar: calendar)
        let done = entries.first { $0.key.hasPrefix("done|") }
        #expect(done?.title == "Upper · done")
        #expect(done?.start == at(0, hour: 17))
        #expect(!entries.contains { $0.key.hasPrefix("lift|") && calendar.isDate($0.start, inSameDayAs: at(0, hour: 0)) })
    }

    @Test func aMovedSessionFollowsTheQueue() throws {
        // Monday's upper wasn't done: the queue moves it to Wednesday, and lower to Friday.
        let week = try #require(AdaptiveWeek.make(plan: plan, done: [], now: at(1, hour: 9), calendar: calendar))
        let entries = PlanCalendar.entries(plan: plan, week: week, now: at(1, hour: 9), calendar: calendar)
        #expect(entries.count == week.slots.filter { $0.date >= calendar.startOfDay(for: at(1, hour: 9)) }.count)
        for entry in entries {
            #expect(week.slots.contains { calendar.isDate($0.date, inSameDayAs: entry.start) })
        }
        // Nothing is left on the day that passed without a session.
        #expect(!entries.contains { calendar.isDate($0.start, inSameDayAs: at(0, hour: 0)) })
    }

    @Test func restModeLeavesTheRestingDaysEmpty() {
        let entries = PlanCalendar.entries(plan: plan, week: nil, restUntil: at(3, hour: 0), now: at(0, hour: 6), calendar: calendar)
        #expect(entries.map { calendar.component(.weekday, from: $0.start) } == [6])
    }

    @Test func aBusyWeekShowsItsShortSessions() {
        let busy = BusyWeek.plan(from: plan, sessions: 1)
        let entries = PlanCalendar.entries(plan: busy, week: nil, now: at(0, hour: 6), calendar: calendar)
        #expect(entries.count == 1)
        #expect(entries[0].notes?.contains(BusyWeek.headline) == true)
        #expect(entries[0].end.timeIntervalSince(entries[0].start) == Double(BusyWeek.sessionMinutes) * 60)
    }

    @Test func nextWeekOnceSavedAndFlexibleWeeksNever() {
        var next = plan
        next.weekStart = calendar.date(byAdding: .day, value: 7, to: monday)!
        // Saturday: this week's sessions are behind it; next week's three are all there.
        let entries = PlanCalendar.entries(plan: plan, week: nil, nextPlan: next, now: at(5, hour: 9), calendar: calendar)
        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.start >= next.weekStart })
        // Thursday: Friday's session and next week's.
        #expect(PlanCalendar.entries(plan: plan, week: nil, nextPlan: next, now: at(3, hour: 9), calendar: calendar).count == 4)
        var flexible = plan
        flexible.mode = .flexible
        #expect(PlanCalendar.entries(plan: flexible, week: nil, now: at(0, hour: 6), calendar: calendar).isEmpty)
    }

    @Test func changesCreateUpdateAndRemoveOnlyWhatDiffers() {
        let desired = PlanCalendar.entries(plan: plan, week: nil, now: at(0, hour: 6), calendar: calendar)
        let first = PlanCalendar.changes(desired: desired, existing: [])
        #expect(first.create.count == 3 && first.update.isEmpty && first.remove.isEmpty)
        // The calendar now holds them.
        var existing = desired.enumerated().map { index, entry in
            PlanCalendar.Existing(id: "e\(index)", key: entry.key, title: entry.title, start: entry.start, end: entry.end, notes: entry.notes)
        }
        #expect(PlanCalendar.changes(desired: desired, existing: existing).isEmpty)
        // A session moved by an hour, an untagged duplicate, and a stale event.
        existing[0].start = existing[0].start.addingTimeInterval(3600)
        existing.append(PlanCalendar.Existing(id: "dup", key: desired[1].key, title: "x", start: at(9, hour: 1), end: at(9, hour: 2)))
        existing.append(PlanCalendar.Existing(id: "stale", key: "lift|2026-01-01", title: "Old", start: at(0, hour: 1), end: at(0, hour: 2)))
        let changes = PlanCalendar.changes(desired: desired, existing: existing)
        #expect(changes.create.isEmpty)
        #expect(changes.update.map(\.id) == ["e0"])
        #expect(Set(changes.remove) == ["dup", "stale"])
    }

    @Test func keysTravelInTheEventsURL() {
        let url = PlanCalendar.url(for: "lift|2026-01-05")
        #expect(PlanCalendar.key(from: url) == "lift|2026-01-05")
        #expect(PlanCalendar.key(from: URL(string: "https://example.com")) == nil)
    }
}

@Suite("Block variety")
struct BlockVarietyTests {
    let planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)

    private func session(_ offset: Int, _ ids: [String]) -> WorkoutSummary.LoggedSession {
        WorkoutSummary.LoggedSession(name: "Upper", start: at(offset, hour: 18), end: at(offset, hour: 19),
                                     exercises: ids.map { WorkoutSummary.LoggedExercise(exerciseID: $0, name: $0, sets: []) })
    }

    private var ids: (press: String, raise: String, curl: String, pushdown: String) {
        let press = planner.alternatives(for: .horizontalPress)[0].id
        let raise = planner.alternatives(for: .lateralRaise)[0].id
        let curl = planner.alternatives(for: .biceps)[0].id
        let pushdown = planner.alternatives(for: .triceps)[0].id
        return (press, raise, curl, pushdown)
    }

    private func alternatives(_ list: [String]) -> [String: [CatalogExercise]] {
        var result: [String: [CatalogExercise]] = [:]
        for id in list { if let slot = ExerciseCatalog.slot(for: id) { result[id] = planner.alternatives(for: slot) } }
        return result
    }

    @Test func offersAccessoriesOnlyWithTheGymsAlternatives() {
        let ids = self.ids
        let list = [ids.press, ids.raise, ids.curl, ids.pushdown]
        let sessions = [session(0, list), session(7, list), session(14, list)]
        let options = BlockVariety.options(sessions: sessions, start: monday, end: at(35, hour: 0), alternatives: alternatives(list))
        #expect(!options.contains { $0.fromID == ids.press })
        #expect(options.allSatisfy { BlockVariety.isAccessory($0.fromID) })
        #expect(options.allSatisfy { option in
            alternatives(list)[option.fromID]?.contains { $0.id == option.toID } == true && option.toID != option.fromID })
        #expect(options.count <= BlockVariety.maximumOptions)
        // Never random: the same block gives the same offer.
        #expect(options == BlockVariety.options(sessions: sessions, start: monday, end: at(35, hour: 0), alternatives: alternatives(list)))
    }

    @Test func atMostTwoAreAddedAndTheReportsSwapsWin() {
        let ids = self.ids
        let list = [ids.raise, ids.curl, ids.pushdown]
        let sessions = [session(0, list), session(7, list)]
        let options = BlockVariety.options(sessions: sessions, start: monday, end: at(35, hour: 0), alternatives: alternatives(list))
        #expect(options.count == 3)
        let base = NextBlockAdjustments.make(report: emptyReport, chosen: [], sourceStart: monday, blockStart: at(35, hour: 0), finishedTargets: [])
        let added = base.addingVariety(options)
        #expect(added.swaps.count == BlockVariety.maximumChanges)
        var withReport = base
        withReport.swaps = [NextBlockAdjustments.Swap(fromID: options[0].fromID, fromName: "x", toID: "y", toName: "y")]
        let merged = withReport.addingVariety(options)
        #expect(merged.swaps.first { $0.fromID == options[0].fromID }?.toID == "y")
        // A main lift is never swapped for variety, even if asked.
        let press = BlockVariety.Option(fromID: ids.press, fromName: "Press", toID: "z", toName: "z", sessions: 3)
        #expect(base.addingVariety([press]).swaps.isEmpty)
    }

    @Test func excludesLiftsTheReportAlreadyChanges() {
        let ids = self.ids
        let list = [ids.raise, ids.curl]
        let sessions = [session(0, list), session(7, list)]
        let options = BlockVariety.options(sessions: sessions, start: monday, end: at(35, hour: 0), alternatives: alternatives(list),
                                           excluding: [ids.raise])
        #expect(options.map(\.fromID) == [ids.curl])
    }

    private var emptyReport: BlockReport.Report {
        BlockReport.make(BlockReport.Input(number: 1, start: monday, end: at(35, hour: 0), length: 5, hadDeload: true,
                                           style: .muscle, weeks: [], sessions: []))
    }
}
