import Foundation
import Testing
@testable import AppCore

/// The insomnia path (`SleepWindow`): who it's offered to, the first window,
/// the weekly rule over whole courses, every boundary, and the wording.
struct SleepWindowTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Day 0 is Monday 4 January 2027, 00:00 UTC.
    func day(_ offset: Int, hour: Int = 0, minute: Int = 0) -> Date {
        let start = calendar.date(from: DateComponents(year: 2027, month: 1, day: 4))!
        let date = calendar.date(byAdding: .day, value: offset, to: start)!
        return date.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    /// A night that ended on `morning`, in bed for `inBedMinutes` up to
    /// `wakeMinutes`, asleep for `efficiency` of it.
    func night(_ morning: Int, inBedMinutes: Int = 480, wakeMinutes: Int = 390, efficiency: Double) -> SleepWindow.Night {
        let wake = day(morning).addingTimeInterval(TimeInterval(wakeMinutes * 60))
        let bedtime = wake.addingTimeInterval(-TimeInterval(inBedMinutes * 60))
        return SleepWindow.Night(date: day(morning), asleepHours: Double(inBedMinutes) * efficiency / 60, bedtime: bedtime, wake: wake)
    }

    /// Fourteen nights before day 0 with `asleepMinutes` of sleep in 8 h in bed.
    func baseline(asleepMinutes: Int, nights: Int = 14) -> [SleepWindow.Night] {
        ((1 - nights)...0).map { night($0, inBedMinutes: 480, efficiency: Double(asleepMinutes) / 480) }
    }

    /// Runs a course day by day, as the app does: each morning the night just
    /// slept is added (kept to the window, asleep for `efficiency(week, day)`
    /// of it; nil = no data that night) and `advance` is called twice a day.
    func simulate(_ start: SleepWindow.Course, regular: Int, days: Int = 60,
                  resting: (Int) -> Bool = { _ in false },
                  efficiency: (_ week: Int, _ day: Int) -> Double?) -> (course: SleepWindow.Course, outcome: SleepWindow.Outcome?, endedOn: Int?, windows: [Int]) {
        var course = start
        var nights: [SleepWindow.Night] = []
        var windows: [Int] = [course.windowMinutes]
        for offset in 1...days {
            if let value = efficiency((offset - 1) / 7 + 1, (offset - 1) % 7) {
                nights.append(night(offset, inBedMinutes: course.windowMinutes, wakeMinutes: course.wakeMinutes, efficiency: value))
            }
            for hour in [8, 13] {
                let before = course.reviews.count
                let result = SleepWindow.advance(course, nights: nights, regularMinutes: regular, resting: resting(offset),
                                                 now: day(offset, hour: hour), calendar: calendar)
                course = result.course
                if course.reviews.count > before { windows.append(course.windowMinutes) }
                if let outcome = result.outcome { return (course, outcome, offset, windows) }
            }
        }
        return (course, nil, nil, windows)
    }

    func course(windowMinutes: Int, wakeMinutes: Int = 390) -> SleepWindow.Course {
        SleepWindow.Course(startDay: day(0), wakeMinutes: wakeMinutes, windowMinutes: windowMinutes, averageSleepMinutes: windowMinutes - 30)
    }

    // MARK: The two questions

    @Test func onlyLastingTroubleThatAffectsTheDayOpensThePath() {
        for frequency in SleepWindow.Frequency.allCases {
            for affects in [true, false] {
                let answers = SleepWindow.Answers(frequency: frequency, affectsDay: affects, day: day(0))
                #expect(answers.applies == (frequency == .lasting && affects))
                // A "no" always gets one plain line; a "yes" gets none (the screening follows).
                #expect((answers.note == nil) == answers.applies)
            }
        }
        #expect(SleepWindow.Frequency.lasting.label == "3 or more nights a week, for 3 months or longer")
        #expect(SleepWindow.Frequency.fewer.label == "Fewer than 3 nights a week")
    }

    // MARK: When the app asks by itself

    @Test func twelvePoorMorningsInFourWeeksRaiseTheQuestion() {
        func mornings(_ poor: Int) -> [SleepWindow.MorningReport] {
            (0..<28).map { SleepWindow.MorningReport(day: day(-$0), rested: $0 < poor ? 2 : 4, nightWakings: 0) }
        }
        #expect(SleepWindow.askReason(mornings: mornings(12), nights: [], now: day(0, hour: 9), calendar: calendar) == .mornings(12))
        #expect(SleepWindow.askReason(mornings: mornings(11), nights: [], now: day(0, hour: 9), calendar: calendar) == nil)
        // Two or more wakings counts as a poor morning too; "OK" with one waking doesn't.
        #expect(SleepWindow.MorningReport(day: day(0), rested: 4, nightWakings: 2).isPoor)
        #expect(!SleepWindow.MorningReport(day: day(0), rested: 3, nightWakings: 1).isPoor)
        #expect(!SleepWindow.MorningReport(day: day(0)).isPoor)
        // Poor mornings older than four weeks don't count.
        let old = (30..<50).map { SleepWindow.MorningReport(day: day(-$0), rested: 1) }
        #expect(SleepWindow.askReason(mornings: old, nights: [], now: day(0, hour: 9), calendar: calendar) == nil)
    }

    @Test func fourWeeksOfLowTrackerEfficiencyRaiseTheQuestionOnly() {
        func nights(_ count: Int, efficiency: Double) -> [SleepWindow.Night] {
            (0..<count).map { night(-$0, efficiency: efficiency) }
        }
        #expect(SleepWindow.askReason(mornings: [], nights: nights(20, efficiency: 0.84), now: day(0, hour: 9), calendar: calendar) == .efficiency(84))
        // 85% is good sleep (Ohayon 2017): no question.
        #expect(SleepWindow.askReason(mornings: [], nights: nights(28, efficiency: 0.85), now: day(0, hour: 9), calendar: calendar) == nil)
        // Under 20 nights of data: no question.
        #expect(SleepWindow.askReason(mornings: [], nights: nights(19, efficiency: 0.7), now: day(0, hour: 9), calendar: calendar) == nil)
        // His own mornings come first when both apply.
        let mornings = (0..<28).map { SleepWindow.MorningReport(day: day(-$0), rested: 1) }
        #expect(SleepWindow.askReason(mornings: mornings, nights: nights(28, efficiency: 0.7), now: day(0, hour: 9), calendar: calendar) == .mornings(28))
        #expect(SleepWindow.AskReason.efficiency(84).text.contains("estimate"))
    }

    @Test func theAppDoesNotAskAgainForNinetyDays() {
        var state = SleepWindow.State()
        #expect(state.mayAsk(now: day(0)))
        state.answers = SleepWindow.Answers(frequency: .fewer, affectsDay: false, day: day(0))
        #expect(!state.mayAsk(now: day(89)))
        #expect(state.mayAsk(now: day(90)))
        // Never while a course runs or an ending is unread, and 90 days from a refusal or an ending.
        state.course = course(windowMinutes: 390)
        #expect(!state.mayAsk(now: day(200)))
        state.course = nil
        state.outcome = SleepWindow.Outcome(ending: .stopped, day: day(100), weeks: 2, wakeMinutes: 390)
        #expect(!state.mayAsk(now: day(300)))
        state.outcome = nil
        state.endedDay = day(100)
        #expect(!state.mayAsk(now: day(189)))
        #expect(state.mayAsk(now: day(190)))
        state.refusedDay = day(150)
        #expect(!state.mayAsk(now: day(200)))
        // "Not now" counts the same.
        var later = SleepWindow.State(notNowDay: day(10))
        #expect(!later.mayAsk(now: day(99)))
        #expect(later.mayAsk(now: day(100)))
        later.notNowDay = nil
        #expect(later.mayAsk(now: day(11)))
    }

    // MARK: Who it isn't offered to

    @Test func everyDeclaredExclusionRefusesWithAReasonAndAClinician() {
        for exclusion in SleepWindow.Exclusion.allCases {
            let decision = SleepWindow.decide(SleepWindow.Screening(declared: [exclusion], stopBangScore: 1))
            guard case .refuse(let refusals) = decision else {
                Issue.record("\(exclusion) was not refused")
                continue
            }
            #expect(refusals.map(\.exclusion) == [exclusion])
            #expect(refusals[0].reason.contains(exclusion.reason))
            #expect(!exclusion.question.isEmpty)
        }
        #expect(SleepWindow.refusalAdvice.contains("GP or a sleep clinic"))
        // The ones the task names, and the others the sources give.
        let all = Set(SleepWindow.Exclusion.allCases)
        #expect(all.isSuperset(of: [.shiftWork, .apnoea, .bipolarOrPsychosis, .seizures, .pregnancy]))
        #expect(all.isSuperset(of: [.safetyCriticalWork, .verySleepy, .otherSleepDisorder, .selfHarm, .otherCondition, .alreadyHelped]))
        #expect(SleepWindow.Exclusion.selfHarm.reason.contains("today"))
    }

    @Test func pregnancyIsNotAskedOfAMan() {
        #expect(!SleepWindow.Exclusion.asked(sex: .male).contains(.pregnancy))
        #expect(SleepWindow.Exclusion.asked(sex: .female).contains(.pregnancy))
        #expect(SleepWindow.Exclusion.asked(sex: .male).count == SleepWindow.Exclusion.allCases.count - 1)
    }

    @Test func apnoeaIsScreenedBeforeAnyOffer() {
        // Never answered: the screen comes first.
        #expect(SleepWindow.decide(SleepWindow.Screening()) == .screenApnoeaFirst)
        // Low risk (0-2): offered. From 3 (a positive screen, Chung 2016): refused.
        for score in 0...2 { #expect(SleepWindow.decide(SleepWindow.Screening(stopBangScore: score)) == .offer) }
        for score in 3...8 {
            guard case .refuse(let refusals) = SleepWindow.decide(SleepWindow.Screening(stopBangScore: score)) else {
                Issue.record("STOP-Bang \(score) was offered")
                continue
            }
            #expect(refusals.map(\.exclusion) == [.apnoea])
            #expect(refusals[0].reason.contains("\(score) of 8"))
            #expect(refusals[0].reason.contains("only a sleep study can tell"))
        }
    }

    @Test func aWatchApnoeaFlagRefusesEvenWithALowScreen() throws {
        let flagged = SleepWindow.decide(SleepWindow.Screening(stopBangScore: 0, apnoeaFlaggedNights: 1))
        guard case .refuse(let refusals) = flagged else { Issue.record("offered despite a flag"); return }
        #expect(refusals[0].exclusion == .apnoea)
        #expect(refusals[0].reason.contains("flagged possible sleep apnoea on 1 night in the last 30"))
        // Refused before the screen is even asked for.
        guard case .refuse = SleepWindow.decide(SleepWindow.Screening(apnoeaFlaggedNights: 3)) else { Issue.record("offered"); return }
        // Breathing disturbances running above his usual: also a no for now.
        guard case .refuse(let rising) = SleepWindow.decide(SleepWindow.Screening(stopBangScore: 0, breathingDisturbancesUp: true)) else {
            Issue.record("offered despite rising breathing disturbances"); return
        }
        #expect(rising[0].reason.contains("breathing disturbances"))
    }

    @Test func aNightShiftPatternIsRefused() {
        // Two weeks of nights: asleep 08:30-15:30, with two days off slept at night.
        var nights: [SleepWindow.Night] = []
        for offset in -13...0 {
            let dayOff = offset == -6 || offset == -5
            nights.append(dayOff
                ? night(offset, inBedMinutes: 450, wakeMinutes: 7 * 60, efficiency: 0.9)
                : night(offset, inBedMinutes: 420, wakeMinutes: 15 * 60 + 30, efficiency: 0.85))
        }
        #expect(SleepWindow.daytimeSleeps(nights, calendar: calendar) == 12)
        let screening = SleepWindow.Screening(stopBangScore: 0, daytimeSleeps: SleepWindow.daytimeSleeps(nights, calendar: calendar))
        guard case .refuse(let refusals) = SleepWindow.decide(screening) else { Issue.record("a shift pattern was offered the window"); return }
        #expect(refusals.map(\.exclusion) == [.shiftWork])
        #expect(refusals[0].reason.contains("12 of the last 14 days"))
        // The same pattern stops a course that is already running.
        #expect(SleepWindow.stopReasons(apnoeaFlaggedNights: 0, nights: nights, calendar: calendar).map(\.exclusion) == [.shiftWork])
    }

    @Test func daytimeSleepBoundaries() {
        // Two daytime sleeps in 14 (a party, a red-eye) aren't a pattern; three are.
        func nights(daytime: Int) -> [SleepWindow.Night] {
            (-13...0).map { offset in
                offset > -daytime
                    ? night(offset, inBedMinutes: 420, wakeMinutes: 15 * 60, efficiency: 0.9)
                    : night(offset, inBedMinutes: 450, wakeMinutes: 7 * 60, efficiency: 0.9)
            }
        }
        #expect(SleepWindow.daytimeSleeps(nights(daytime: 2), calendar: calendar) == 2)
        #expect(SleepWindow.decide(SleepWindow.Screening(stopBangScore: 0, daytimeSleeps: 2)) == .offer)
        guard case .refuse = SleepWindow.decide(SleepWindow.Screening(stopBangScore: 0, daytimeSleeps: 3)) else { Issue.record("offered"); return }
        #expect(SleepWindow.stopReasons(apnoeaFlaggedNights: 0, nights: nights(daytime: 2), calendar: calendar).isEmpty)
        // A late sleeper (03:00-11:00, middle 07:00) is still a night sleeper; 04:00-12:00 (middle 08:00) isn't.
        #expect(SleepWindow.daytimeSleeps([night(0, inBedMinutes: 480, wakeMinutes: 11 * 60, efficiency: 0.9)], calendar: calendar) == 0)
        #expect(SleepWindow.daytimeSleeps([night(0, inBedMinutes: 480, wakeMinutes: 12 * 60, efficiency: 0.9)], calendar: calendar) == 1)
        // Only the last 14 nights count.
        let old = (-30...(-15)).map { night($0, inBedMinutes: 420, wakeMinutes: 15 * 60, efficiency: 0.9) }
        #expect(SleepWindow.daytimeSleeps(old + nights(daytime: 0), calendar: calendar) == 0)
    }

    @Test func aWatchFlagStopsARunningCourse() {
        let nights = (1...7).map { night($0, inBedMinutes: 390, efficiency: 0.9) }
        #expect(SleepWindow.stopReasons(apnoeaFlaggedNights: 0, nights: nights, calendar: calendar).isEmpty)
        let reasons = SleepWindow.stopReasons(apnoeaFlaggedNights: 2, nights: nights, calendar: calendar)
        #expect(reasons.map(\.exclusion) == [.apnoea])
        let outcome = SleepWindow.Outcome(ending: .excluded, day: day(8), weeks: 1, wakeMinutes: 390, refusals: reasons)
        let text = SleepWindow.outcomeText(outcome)
        #expect(text.contains("turned off"))
        #expect(text.contains("2 nights in the last 30"))
        #expect(text.contains("GP or a sleep clinic"))
    }

    // MARK: The first window

    @Test func theFirstWindowIsRecentSleepPlusThirtyMinutes() throws {
        // 5 h 45 min asleep a night → 6 h 15 min in bed; need 7.5 h → regular 8 h 20 min.
        let proposal = try #require(SleepWindow.propose(nights: baseline(asleepMinutes: 345), sleepNeedHours: 7.5, usualWakeMinutes: 6 * 60 + 32))
        #expect(proposal.averageSleepMinutes == 345)
        #expect(proposal.nightsUsed == 14)
        #expect(proposal.windowMinutes == 375)
        #expect(proposal.regularMinutes == 500)
        #expect(proposal.isShorter)
        // The wake time is offered to the nearest 5 minutes.
        #expect(proposal.wakeMinutes == 6 * 60 + 30)
        let started = SleepWindow.start(proposal, wakeMinutes: proposal.wakeMinutes, now: day(0, hour: 21), calendar: calendar)
        #expect(started.startDay == day(0))
        #expect(started.bedMinutes == 15) // 00:15 → 06:30 is 6 h 15 min
        #expect(started.week == 1)
        #expect(SleepWindow.basisText(proposal).contains("5 h 45 min asleep a night over your last 14 nights, plus 30 minutes"))
        #expect(SleepWindow.basisText(proposal).contains("estimate"))
    }

    @Test func theWindowIsNeverUnderSixHours() throws {
        // 4 h 10 min asleep: 4 h 40 min would be the window; the floor holds it at 6 h.
        let short = try #require(SleepWindow.propose(nights: baseline(asleepMinutes: 250), sleepNeedHours: 7.5, usualWakeMinutes: 390))
        #expect(short.windowMinutes == 360)
        #expect(SleepWindow.basisText(short).contains("held at the 6 h minimum"))
        // Exactly 5 h 30 asleep → exactly 6 h; one minute more rounds up to 6 h 05.
        #expect(try #require(SleepWindow.propose(nights: baseline(asleepMinutes: 330), sleepNeedHours: 7.5, usualWakeMinutes: 390)).windowMinutes == 360)
        #expect(try #require(SleepWindow.propose(nights: baseline(asleepMinutes: 331), sleepNeedHours: 7.5, usualWakeMinutes: 390)).windowMinutes == 365)
        #expect(!SleepWindow.basisText(try #require(SleepWindow.propose(nights: baseline(asleepMinutes: 330), sleepNeedHours: 7.5, usualWakeMinutes: 390))).contains("minimum"))
    }

    @Test func aWindowNoShorterThanTheRegularOneIsNotOffered() throws {
        // 7 h 40 asleep on a 7.5 h need: plus 30 is 8 h 10, within a step of the regular 8 h 20.
        let long = try #require(SleepWindow.propose(nights: baseline(asleepMinutes: 460), sleepNeedHours: 7.5, usualWakeMinutes: 390))
        #expect(long.windowMinutes == 490)
        #expect(!long.isShorter)
        #expect(SleepWindow.nothingToShortenText(long).contains("nothing to take away"))
        // Never longer than the regular window.
        let longer = try #require(SleepWindow.propose(nights: baseline(asleepMinutes: 520), sleepNeedHours: 7.5, usualWakeMinutes: 390))
        #expect(longer.windowMinutes == 500)
        // One step under the regular window is the boundary: 7 h 35 + 30 = 8 h 05 = 500 − 15.
        let edge = try #require(SleepWindow.propose(nights: baseline(asleepMinutes: 455), sleepNeedHours: 7.5, usualWakeMinutes: 390))
        #expect(edge.windowMinutes == 485)
        #expect(edge.isShorter)
    }

    @Test func theFirstWindowNeedsAWeekOfNightsAndAWakeTime() {
        #expect(SleepWindow.propose(nights: baseline(asleepMinutes: 345, nights: 6), sleepNeedHours: 7.5, usualWakeMinutes: 390) == nil)
        #expect(SleepWindow.propose(nights: baseline(asleepMinutes: 345, nights: 7), sleepNeedHours: 7.5, usualWakeMinutes: 390)?.nightsUsed == 7)
        #expect(SleepWindow.propose(nights: baseline(asleepMinutes: 345), sleepNeedHours: 7.5, usualWakeMinutes: nil) == nil)
        // Only the last 14 nights are averaged.
        let mixed = baseline(asleepMinutes: 480, nights: 30).dropLast(14) + baseline(asleepMinutes: 345)
        #expect(SleepWindow.propose(nights: Array(mixed), sleepNeedHours: 7.5, usualWakeMinutes: 390)?.averageSleepMinutes == 345)
    }

    @Test func regularTimeInBedIsNeedOverPointNine() {
        #expect(SleepWindow.regularMinutes(sleepNeedHours: 7.5) == 500)
        #expect(SleepWindow.regularMinutes(sleepNeedHours: 8) == 535)
        #expect(SleepWindow.regularMinutes(sleepNeedHours: 3) == 400) // need is held to 6-11 h, as in BedtimeWindow
    }

    @Test func bedtimeIsTheWakeTimeMinusTheWindow() {
        #expect(course(windowMinutes: 405, wakeMinutes: 390).bedMinutes == 23 * 60 + 45)
        #expect(course(windowMinutes: 360, wakeMinutes: 5 * 60).bedMinutes == 23 * 60)
        #expect(course(windowMinutes: 390, wakeMinutes: 390).bedMinutes == 0)
        #expect(course(windowMinutes: 360, wakeMinutes: 7 * 60).bedMinutes == 60)
    }

    // MARK: One week's rule, at every boundary

    @Test func weeklyRuleBoundaries() {
        func review(_ percent: Double, window: Int = 390, nights count: Int = 7, sleepy: Bool = false, resting: Bool = false) -> SleepWindow.Review {
            let nights = (1...count).map { night($0, inBedMinutes: window, efficiency: percent / 100) }
            return SleepWindow.review(week: 1, windowMinutes: window, nights: nights, regularMinutes: 500, sleepy: sleepy, resting: resting)
        }
        // 85% or more: 15 minutes longer (HABIT).
        #expect(review(85).change == .widened)
        #expect(review(85).windowMinutes == 405)
        #expect(review(100).windowMinutes == 405)
        // 80-84%: no change.
        #expect(review(84).change == .held)
        #expect(review(84).windowMinutes == 390)
        #expect(review(80).change == .held)
        // 79% or less: 15 minutes shorter.
        #expect(review(79).change == .narrowed)
        #expect(review(79).windowMinutes == 375)
        // Judged on the whole percent shown, so the number and the change always agree.
        #expect(review(84.6).efficiencyPercent == 85)
        #expect(review(84.6).change == .widened)
        #expect(review(84.4).change == .held)
        #expect(review(79.6).change == .held)
        #expect(review(79.4).change == .narrowed)
        // Never under six hours.
        #expect(review(60, window: 370).windowMinutes == 360)
        #expect(review(60, window: 370).change == .narrowed)
        #expect(review(60, window: 360).windowMinutes == 360)
        #expect(review(60, window: 360).change == .heldAtFloor)
        // Never past the regular window.
        #expect(review(95, window: 495).windowMinutes == 500)
        #expect(review(95, window: 500).change == .held)
        // Never narrowed in a week he said he was too sleepy; widening still happens.
        #expect(review(70, sleepy: true).change == .heldSleepy)
        #expect(review(70, sleepy: true).windowMinutes == 390)
        #expect(review(90, sleepy: true).change == .widened)
        // Four nights are too few to judge; five are enough.
        #expect(review(60, nights: 4).change == .heldFewNights)
        #expect(review(60, nights: 4).windowMinutes == 390)
        #expect(review(60, nights: 4).efficiencyPercent == nil)
        #expect(review(60, nights: 5).change == .narrowed)
        #expect(review(95, nights: 4).change == .heldFewNights)
        // Rest mode: nothing moves, whatever the nights say.
        #expect(review(60, resting: true).change == .heldResting)
        #expect(review(95, resting: true).windowMinutes == 390)
    }

    @Test func efficiencyIsTimeAsleepOverTheNightsSpan() {
        #expect(night(1, inBedMinutes: 400, efficiency: 0.9).efficiency.map { abs($0 - 0.9) < 0.0001 } == true)
        // More "asleep" than the span (overlapping samples) is capped at 100%.
        let odd = SleepWindow.Night(date: day(1), asleepHours: 9, bedtime: day(0, hour: 23), wake: day(1, hour: 7))
        #expect(odd.efficiency == 1)
        // No span or no sleep: no reading.
        #expect(SleepWindow.Night(date: day(1), asleepHours: 6, bedtime: day(1, hour: 7), wake: day(1, hour: 7)).efficiency == nil)
        #expect(SleepWindow.efficiencyPercent([]) == nil)
        #expect(SleepWindow.efficiencyPercent([night(1, efficiency: 0.8), night(2, efficiency: 0.9)]) == 85)
    }

    @Test func reviewsComeDueAtNoonOnTheSeventhDayAndRunOnce() {
        var running = course(windowMinutes: 390)
        let nights = (1...7).map { night($0, inBedMinutes: 390, efficiency: 0.9) }
        // 11:59 on day 7: not yet.
        var result = SleepWindow.advance(running, nights: nights, regularMinutes: 500, now: day(7, hour: 11, minute: 59), calendar: calendar)
        #expect(result.course.reviews.isEmpty)
        #expect(result.outcome == nil)
        // Noon: reviewed once, and not again later that day or week.
        result = SleepWindow.advance(running, nights: nights, regularMinutes: 500, now: day(7, hour: 12), calendar: calendar)
        #expect(result.course.reviews.count == 1)
        #expect(result.course.windowMinutes == 405)
        running = result.course
        for offset in 7...13 {
            running = SleepWindow.advance(running, nights: nights, regularMinutes: 500, now: day(offset, hour: 23), calendar: calendar).course
        }
        #expect(running.reviews.count == 1)
        #expect(running.windowMinutes == 405)
        #expect(running.week == 2)
        #expect(running.nextReviewDay(calendar: calendar) == day(14, hour: 12))
    }

    @Test func aWeeksReviewOnlyUsesThatWeeksNights() {
        // Week 1 bad (70%), week 2 good (92%): opened only on day 15, both reviews run in order.
        let nights = (1...7).map { night($0, inBedMinutes: 390, efficiency: 0.70) }
            + (8...14).map { night($0, inBedMinutes: 375, efficiency: 0.92) }
        let result = SleepWindow.advance(course(windowMinutes: 390), nights: nights, regularMinutes: 500, now: day(15, hour: 9), calendar: calendar)
        #expect(result.course.reviews.map(\.change) == [.narrowed, .widened])
        #expect(result.course.reviews.map(\.efficiencyPercent) == [70, 92])
        #expect(result.course.reviews.map(\.windowMinutes) == [375, 390])
        // The night that ended on the start day belongs to no week.
        let before = SleepWindow.nights(ofWeek: 1, course: course(windowMinutes: 390), from: [night(0, efficiency: 0.5)] + nights, calendar: calendar)
        #expect(before.count == 7)
    }

    // MARK: Whole courses

    @Test func anImprovingSleeperWidensEachWeekBackToTheRegularWindow() throws {
        // 6 h 45 asleep → 7 h 15 window; regular 8 h 20. Asleep for 90% of it every week.
        let proposal = try #require(SleepWindow.propose(nights: baseline(asleepMinutes: 405), sleepNeedHours: 7.5, usualWakeMinutes: 390))
        #expect(proposal.windowMinutes == 435)
        let start = SleepWindow.start(proposal, wakeMinutes: 390, now: day(0, hour: 20), calendar: calendar)
        let run = simulate(start, regular: proposal.regularMinutes) { _, _ in 0.90 }
        #expect(run.windows == [435, 450, 465, 480, 495, 500])
        #expect(run.outcome?.ending == .reachedRegular)
        #expect(run.endedOn == 35) // the fifth review
        #expect(run.course.reviews.allSatisfy { $0.change == .widened })
        #expect(!run.course.isStalled)
        #expect(SleepWindow.outcomeText(try #require(run.outcome)).contains("back to your regular time in bed"))
    }

    @Test func anImprovingShortSleeperRunsTheFullEightWeeksAndIsAskedAgain() throws {
        // 5 h 45 asleep → 6 h 15 window; eight widenings reach 8 h 15, still under the regular 8 h 20.
        let proposal = try #require(SleepWindow.propose(nights: baseline(asleepMinutes: 345), sleepNeedHours: 7.5, usualWakeMinutes: 390))
        let start = SleepWindow.start(proposal, wakeMinutes: 390, now: day(0, hour: 20), calendar: calendar)
        let run = simulate(start, regular: proposal.regularMinutes) { week, _ in week <= 2 ? 0.86 : 0.93 }
        #expect(run.windows == [375, 390, 405, 420, 435, 450, 465, 480, 495])
        let outcome = try #require(run.outcome)
        #expect(outcome.ending == .timeLimit)
        #expect(run.endedOn == 56)
        #expect(outcome.weeks == 8)
        #expect(outcome.needsAnswer)
        #expect(SleepWindow.outcomeText(outcome).contains("8 weeks are up"))
        var answered = outcome
        answered.stillStruggling = false
        #expect(!answered.needsAnswer)
        #expect(SleepWindow.outcomeText(answered).contains("regular bed-by window is back"))
        answered.stillStruggling = true
        #expect(SleepWindow.outcomeText(answered).contains("see a GP or a sleep clinic"))
    }

    @Test func aNonResponderIsNarrowedOnlyToTheFloorAndToldToSeeSomeone() throws {
        // 5 h 50 asleep → 6 h 20 window. Asleep for about 74% of it, week after week.
        let proposal = try #require(SleepWindow.propose(nights: baseline(asleepMinutes: 350), sleepNeedHours: 7.5, usualWakeMinutes: 390))
        #expect(proposal.windowMinutes == 380)
        let start = SleepWindow.start(proposal, wakeMinutes: 390, now: day(0, hour: 20), calendar: calendar)
        var stalledAt: Int?
        var course = start
        var nights: [SleepWindow.Night] = []
        for offset in 1...60 {
            nights.append(night(offset, inBedMinutes: course.windowMinutes, efficiency: 0.74))
            let result = SleepWindow.advance(course, nights: nights, regularMinutes: 500, now: day(offset, hour: 13), calendar: calendar)
            course = result.course
            #expect(course.windowMinutes >= SleepWindow.floorMinutes)
            if course.isStalled, stalledAt == nil { stalledAt = offset }
            if result.outcome != nil { break }
        }
        #expect(course.reviews.map(\.windowMinutes) == [365, 360, 360, 360, 360, 360, 360, 360])
        #expect(course.reviews.map(\.change) == [.narrowed, .narrowed, .heldAtFloor, .heldAtFloor, .heldAtFloor, .heldAtFloor, .heldAtFloor, .heldAtFloor])
        // The suggestion to see someone comes at the fourth review, well before the time limit.
        #expect(stalledAt == 28)
        #expect(SleepWindow.stalledText.contains("see a GP or a sleep clinic"))
        let run = simulate(start, regular: 500) { _, _ in 0.74 }
        #expect(run.outcome?.ending == .timeLimit)
        #expect(run.endedOn == 56)
    }

    @Test func efficiencyBouncingAroundTheThresholdsMovesTheWindowOnlyWhenItCrossesThem() {
        // 84, 85, 79, 80, 86, 84, 78, 85: held, wider, narrower, held, wider, held, narrower, wider.
        let weekly = [0.84, 0.85, 0.79, 0.80, 0.86, 0.84, 0.78, 0.85]
        let run = simulate(course(windowMinutes: 390), regular: 500) { week, _ in weekly[min(week, 8) - 1] }
        #expect(run.course.reviews.map(\.change) == [.held, .widened, .narrowed, .held, .widened, .held, .narrowed, .widened])
        #expect(run.windows == [390, 390, 405, 390, 390, 405, 405, 390, 405])
        #expect(run.outcome?.ending == .timeLimit)
        // A widening within any four weeks: never told to see someone early.
        #expect(!run.course.isStalled)
    }

    @Test func nightToNightNoiseIsJudgedOnTheWeeksAverage() {
        // 95, 70, 92, 75, 90, 78, 95 → average 85: wider, though three nights were under 80%.
        let nightly = [0.95, 0.70, 0.92, 0.75, 0.90, 0.78, 0.95]
        let run = simulate(course(windowMinutes: 390), regular: 500, days: 7) { _, day in nightly[day] }
        #expect(run.course.reviews.first?.efficiencyPercent == 85)
        #expect(run.course.reviews.first?.change == .widened)
    }

    @Test func missingNightsHoldTheWindowAndAreNotCountedAgainstHim() {
        // Week 1: watch worn 4 nights (poor ones). Week 2: not worn. Week 3: 5 nights at 75%. Week 4 on: 90%.
        let run = simulate(course(windowMinutes: 390), regular: 500, days: 35) { week, day in
            switch week {
            case 1: return day < 4 ? 0.60 : nil
            case 2: return nil
            case 3: return day < 5 ? 0.75 : nil
            default: return 0.90
            }
        }
        #expect(run.course.reviews.map(\.change) == [.heldFewNights, .heldFewNights, .narrowed, .widened, .widened])
        #expect(run.course.reviews.map(\.nights) == [4, 0, 5, 7, 7])
        #expect(run.windows == [390, 390, 390, 375, 390, 405])
        #expect(run.course.reviews[0].text.contains("only 4 nights recorded"))
        #expect(run.course.reviews[1].text.contains("only 0 nights recorded"))
    }

    @Test func weeksWithoutDataNeverCountTowardsSeeingSomeone() {
        // Eight weeks with no tracker at all: held throughout, ends at the time limit, never "stalled".
        let run = simulate(course(windowMinutes: 390), regular: 500) { _, _ in nil }
        #expect(run.course.reviews.count == 8)
        #expect(run.course.reviews.allSatisfy { $0.change == .heldFewNights })
        #expect(run.course.windowMinutes == 390)
        #expect(!run.course.isStalled)
        #expect(run.outcome?.ending == .timeLimit)
        // Held weeks with data do count: 82% for four weeks is four reviews without a wider window.
        let flat = simulate(course(windowMinutes: 390), regular: 500, days: 28) { _, _ in 0.82 }
        #expect(flat.course.isStalled)
        // Three such weeks don't.
        #expect(!simulate(course(windowMinutes: 390), regular: 500, days: 21) { _, _ in 0.82 }.course.isStalled)
    }

    @Test func aPhoneLeftClosedForWeeksCatchesUpInOrderAndStillEndsOnTime() {
        var nights: [SleepWindow.Night] = []
        for offset in 1...70 { nights.append(night(offset, inBedMinutes: 390, efficiency: 0.82)) }
        // Opened for the first time on day 70: all eight reviews run, then the time limit.
        let result = SleepWindow.advance(course(windowMinutes: 390), nights: nights, regularMinutes: 500, now: day(70, hour: 9), calendar: calendar)
        #expect(result.course.reviews.map(\.week) == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(result.outcome?.ending == .timeLimit)
        #expect(result.outcome?.day == day(70))
    }

    @Test func tooSleepyWidensAtOnceAndBlocksNarrowingThatWeek() {
        var running = course(windowMinutes: 375)
        running = SleepWindow.tooSleepy(running, regularMinutes: 500, now: day(3, hour: 15), calendar: calendar)
        #expect(running.windowMinutes == 390)
        #expect(running.sleepyDays == [day(3)])
        // A poor week (70%) would narrow; it doesn't in a week he was too sleepy.
        let week1 = (1...7).map { night($0, inBedMinutes: 390, efficiency: 0.70) }
        var result = SleepWindow.advance(running, nights: week1, regularMinutes: 500, now: day(7, hour: 13), calendar: calendar)
        #expect(result.course.reviews.map(\.change) == [.heldSleepy])
        #expect(result.course.windowMinutes == 390)
        // The week after, with no tap, the rule applies again.
        let week2 = week1 + (8...14).map { night($0, inBedMinutes: 390, efficiency: 0.70) }
        result = SleepWindow.advance(result.course, nights: week2, regularMinutes: 500, now: day(14, hour: 13), calendar: calendar)
        #expect(result.course.reviews.map(\.change) == [.heldSleepy, .narrowed])
        // Tapped until the window is the regular one: the course is over at the next refresh.
        var wide = course(windowMinutes: 490)
        wide = SleepWindow.tooSleepy(wide, regularMinutes: 500, now: day(1), calendar: calendar)
        #expect(wide.windowMinutes == 500)
        #expect(SleepWindow.tooSleepy(wide, regularMinutes: 500, now: day(1), calendar: calendar).windowMinutes == 500)
        #expect(SleepWindow.advance(wide, nights: [], regularMinutes: 500, now: day(1, hour: 10), calendar: calendar).outcome?.ending == .reachedRegular)
    }

    @Test func restModeHoldsTheWindow() {
        // Ill in week 2 (rest mode on at its review): a 70% week doesn't narrow the window.
        let run = simulate(course(windowMinutes: 390), regular: 500, days: 21, resting: { $0 == 14 }) { week, _ in week == 2 ? 0.70 : 0.90 }
        #expect(run.course.reviews.map(\.change) == [.widened, .heldResting, .widened])
        #expect(run.windows == [390, 405, 405, 420])
        #expect(!run.course.isStalled)
    }

    @Test func aLowerSleepNeedEndsTheCourseSooner() {
        // He lowers his sleep need to 6.5 h (regular 7 h 15): a 7 h 15 window is already regular.
        let result = SleepWindow.advance(course(windowMinutes: 435), nights: [], regularMinutes: SleepWindow.regularMinutes(sleepNeedHours: 6.5),
                                         now: day(2), calendar: calendar)
        #expect(result.outcome?.ending == .reachedRegular)
    }

    // MARK: The bed-by window in sleep-window mode

    @Test func theBedByWindowBecomesTheSleepWindow() {
        // 6 h 45 min window, up at 06:30 → bed from 23:45.
        let window = BedtimeWindow.sleepWindow(minutes: 405, wakeMinutes: 390, sleepNeedHours: 7.5, now: day(0, hour: 20), calendar: calendar)
        #expect(window.isSleepWindow)
        #expect(window.wake == day(1, hour: 6, minute: 30))
        #expect(window.start == day(0, hour: 23, minute: 45))
        #expect(window.end == day(1, hour: 0, minute: 15))
        #expect(window.repaymentMinutes == 0)
        #expect(!window.wakeForSession)
        #expect(window.regularityNote == nil)
        #expect(abs(window.timeInBedHours - 6.75) < 0.0001)
        #expect(window.reason.contains("6 h 45 min sleep window"))
        #expect(window.reason.hasSuffix("every day"))
        #expect(window.line.contains("bed from"))
        #expect(window.line.hasSuffix("when sleepy"))
        #expect(!window.line.contains("in bed by"))
        #expect(!window.reason.contains("debt"))
        #expect(window.headline.hasPrefix("Bed from"))
        // After the night has started (within 4 h of the wake time) it is tomorrow night's, as in the regular mode.
        let late = BedtimeWindow.sleepWindow(minutes: 405, wakeMinutes: 390, sleepNeedHours: 7.5, now: day(1, hour: 3), calendar: calendar)
        #expect(late.wake == day(2, hour: 6, minute: 30))
    }

    @Test func theRegularBedByWindowIsUnchanged() throws {
        let debt = SleepDebt.compute(nightlyHours: Array(repeating: 6, count: 14), needHours: 8)
        let window = try #require(BedtimeWindow.compute(sleepNeedHours: 8, sleepDebt: debt, usualWakeMinutes: 7 * 60, regularity: nil,
                                                        now: day(0, hour: 20), calendar: calendar))
        #expect(!window.isSleepWindow)
        #expect(window.line.contains("in bed by"))
        #expect(window.reason.contains("8 h need"))
        #expect(window.headline == "In bed by \(window.windowText)")
        // A planned early session moves the regular wake time; the sleep window's wake time is fixed.
        let session = day(1, hour: 6)
        let regular = try #require(BedtimeWindow.compute(sleepNeedHours: 8, sleepDebt: nil, usualWakeMinutes: 7 * 60, regularity: nil,
                                                         plannedSessionStart: session, now: day(0, hour: 20), calendar: calendar))
        #expect(regular.wakeForSession)
        #expect(regular.wake == day(1, hour: 5))
    }

    // MARK: Catch-up sleep wording

    @Test func weekendShiftNoteInEachState() {
        let within = SleepRegularity.MidpointShift(minutes: 40, weekdayNights: 5, weekendNights: 2)
        let later = SleepRegularity.MidpointShift(minutes: 95, weekdayNights: 5, weekendNights: 2)
        let earlier = SleepRegularity.MidpointShift(minutes: -95, weekdayNights: 5, weekendNights: 2)
        let levels: [SleepDebt.Level?] = [nil, SleepDebt.Level.none, .low, .moderate, .high]

        // Within an hour: the same praise whatever the debt or the mode.
        for level in levels {
            #expect(within.note(sleepDebt: level) == within.note)
            #expect(within.note(sleepDebt: level, sleepWindowOn: true) == within.note)
        }
        // A lie-in with no, unknown or low debt: unchanged.
        for level in [nil, SleepDebt.Level.none, .low] as [SleepDebt.Level?] {
            #expect(later.note(sleepDebt: level) == later.note)
        }
        // A lie-in with moderate or high debt: probably worth it, earlier night next time.
        for level in [SleepDebt.Level.moderate, .high] {
            let note = later.note(sleepDebt: level)
            #expect(note != later.note)
            #expect(note.contains("lie-in was probably worth it"))
            #expect(note.contains("Sletten 2023"))
            #expect(note.contains("earlier night"))
            #expect(!note.contains("time-zone"))
            // A weekend that runs earlier isn't a lie-in: unchanged.
            #expect(earlier.note(sleepDebt: level) == earlier.note)
        }
        // Sleep window on: the fixed wake time wins, whatever the debt and whichever way the shift goes.
        for level in levels {
            for shift in [later, earlier] {
                let note = shift.note(sleepDebt: level, sleepWindowOn: true)
                #expect(note.contains("fixed wake time wins"))
                #expect(!note.contains("worth it"))
            }
        }
    }

    @Test func theLieInNoteAndTheDebtPlanGiveTheSameNextStep() throws {
        // Two weeks of 6 h nights on an 8 h need: high debt. Both lines point to an earlier night, neither to sleeping in again.
        let debt = try #require(SleepDebt.compute(nightlyHours: Array(repeating: 6, count: 14), needHours: 8))
        #expect(debt.level == .high)
        let note = SleepRegularity.MidpointShift(minutes: 120, weekdayNights: 5, weekendNights: 2).note(sleepDebt: debt.level)
        let plan = try #require(debt.plan)
        #expect(plan.contains("go to bed earlier rather than sleeping in"))
        #expect(note.contains("earlier night"))
        #expect(note.contains("without moving your body clock"))
    }

    // MARK: The coach's messages

    @Test func theEveningNoteSpeaksOfTheSleepWindowNotBedBy() throws {
        let window = BedtimeWindow.sleepWindow(minutes: 405, wakeMinutes: 390, sleepNeedHours: 7.5, now: day(0, hour: 20), calendar: calendar)
        var f = CoachCheckIns.EveningFacts()
        f.sleepWindow = true
        f.bedByText = SleepWindow.clock(23 * 60 + 45)
        f.bedByReason = window.reason
        f.checkInDone = true
        let message = try #require(CoachCheckIns.evening(f))
        #expect(message.title == "Bed from \(SleepWindow.clock(23 * 60 + 45)), when sleepy")
        #expect(message.title.count <= CoachCheckIns.maxTitleCharacters)
        #expect(message.body.hasPrefix("Tonight: 6 h 45 min sleep window"))
        #expect(!message.title.contains("In bed by"))
        #expect(!message.body.contains("Worked back"))
        #expect(message.body.count <= CoachCheckIns.maxBodyCharacters)
        // Without the flag the note is as before.
        f.sleepWindow = false
        f.bedByText = "21:50–22:20"
        f.bedByReason = "8 h need, up at 6:30"
        #expect(try #require(CoachCheckIns.evening(f)).title == "In bed by 21:50–22:20")
    }

    @Test func thePostWorkoutLineDoesNotAskForAFullNightUnderASleepWindow() throws {
        var f = CoachCheckIns.PostWorkoutFacts(name: "Pull", minutes: 45, workingSets: 14)
        f.proteinSoFarGrams = 150
        f.proteinTargetGrams = 140
        f.sleepWindowText = "23:45 to 6:30"
        let message = try #require(CoachCheckIns.postWorkout(f))
        #expect(message.body.contains("Tonight's sleep window is 23:45 to 6:30"))
        #expect(!message.body.contains("full night"))
        #expect(!message.body.contains("in bed by"))
    }

    @Test func theMorningMessageDropsDebtAndShortNightTipsUnderASleepWindow() throws {
        var f = CoachCheckIns.MorningFacts()
        f.recovery = 60
        f.sleepHours = 6
        f.sleepNeedHours = 7.5
        f.sleepDebtHours = 6
        f.bedByText = "21:50–22:20"
        f.caffeineCutoffText = "1:30 PM"
        // Without the window: the debt tip.
        #expect(try #require(CoachCheckIns.morning(f)).body.contains("Sleep debt is 6 h"))
        f.sleepWindow = true
        let body = try #require(CoachCheckIns.morning(f)).body
        #expect(!body.lowercased().contains("sleep debt"))
        #expect(!body.contains("short night"))
        #expect(!body.contains("in bed by"))
        // Debt alone, no recovery or session: nothing to say but the check-in.
        var debtOnly = CoachCheckIns.MorningFacts()
        debtOnly.sleepDebtHours = 6
        debtOnly.sleepWindow = true
        #expect(CoachCheckIns.morning(debtOnly) == nil)
    }

    @Test func theCoachKeepsToTheWindow() throws {
        let running = course(windowMinutes: 405)
        var f = CoachFacts()
        f.sleepHours = 6
        f.sleepNeedHours = 7.5
        f.sleepDebtHours = 5
        let before = try #require(CoachAnswers.sleep(f))
        #expect(before.text.contains("earlier night"))
        #expect(before.action?.contains("earlier") == true)
        f.sleepWindowFact = SleepWindow.coachFact(running)
        let answer = try #require(CoachAnswers.sleep(f))
        #expect(!answer.text.contains("earlier"))
        #expect(answer.text.contains("sleep debt is paused"))
        #expect(answer.action?.contains("Keep to the window") == true)
        // The on-device model's facts carry the window, not the debt.
        let lines = CoachAnswers.factLines(for: "should I sleep more", topic: .recovery, facts: f)
        #expect(lines.contains { $0.hasPrefix("Sleep window on (week 1 of 8,") })
        #expect(!lines.contains { $0.hasPrefix("Sleep debt") })
        #expect(SleepWindow.coachFact(running).contains("don't suggest earlier nights"))
    }

    @Test func theInsightsFeedDoesNotSayYoureSleepingLessUnderASleepWindow() {
        func inputs(windowOn: Bool) -> DailyInsights.Inputs {
            var i = DailyInsights.Inputs(day: day(35, hour: 9), calendar: calendar)
            // Four weeks at about 7.5 h, then a week at about 6.3 h (the window's first week).
            i.sleepHours = (0...35).map { DayValue(date: day($0, hour: 7), value: ($0 >= 29 ? 6.3 : 7.5) + Double($0 % 3) * 0.1) }
            i.sleepWindowOn = windowOn
            return i
        }
        #expect(DailyInsights.evaluate(inputs(windowOn: false)).feed.today.contains { $0.id == "sleepWeek" })
        #expect(!DailyInsights.evaluate(inputs(windowOn: true)).feed.today.contains { $0.id == "sleepWeek" })
    }

    @Test func theCutAdviceDoesNotSendHimToTheDebtPlanUnderASleepWindow() throws {
        var goals = Goals()
        goals.weight = .lose
        let debt = try #require(SleepDebt.compute(nightlyHours: Array(repeating: 6, count: 14), needHours: 8))
        let regular = try #require(CutAndSleep.advice(goals: goals, sleepDebt: debt))
        #expect(regular.message.contains("sleep plan"))
        let window = try #require(CutAndSleep.advice(goals: goals, sleepDebt: debt, sleepWindowOn: true))
        #expect(!window.message.contains("sleep plan"))
        #expect(window.message.contains("sleep window"))
        #expect(window.suggestedRatePercent == regular.suggestedRatePercent)
    }

    @Test func theUpNextLineSaysTheWeekOrWhatNext() {
        var running = course(windowMinutes: 390)
        #expect(SleepWindow.rowDetail(running) == "Sleep window · week 1 of 8 · only when sleepy")
        running.reviews = (1...4).map { SleepWindow.Review(week: $0, nights: 7, efficiencyPercent: 82, change: .held, windowMinutes: 390) }
        #expect(running.isStalled)
        #expect(SleepWindow.rowDetail(running).contains("tap for what next"))
        running.continuedPastStall = true
        #expect(SleepWindow.rowDetail(running) == "Sleep window · week 5 of 8 · only when sleepy")
    }

    // MARK: Words

    /// Every sentence the path can show.
    var allCopy: [String] {
        let running = course(windowMinutes: 405)
        let proposal = SleepWindow.Proposal(windowMinutes: 405, averageSleepMinutes: 375, nightsUsed: 14, regularMinutes: 500, wakeMinutes: 390)
        var copy = [
            SleepWindow.questionTitle, SleepWindow.questionIntro, SleepWindow.frequencyQuestion, SleepWindow.daytimeQuestion,
            SleepWindow.screeningTitle, SleepWindow.screeningIntro, SleepWindow.screenFirstText, SleepWindow.refusalTitle,
            SleepWindow.refusalAdvice, SleepWindow.sleepinessWarning, SleepWindow.estimateNote, SleepWindow.notCareNote,
            SleepWindow.debtPausedNote, SleepWindow.restingNote, SleepWindow.stalledText, SleepWindow.howItChanges,
            SleepWindow.needsNightsText, SleepWindow.nothingToShortenText(proposal), SleepWindow.basisText(proposal),
            SleepWindow.heading(running), SleepWindow.windowText(windowMinutes: 405, wakeMinutes: 390),
            SleepWindow.AskReason.mornings(14).text, SleepWindow.AskReason.efficiency(80).text,
            SleepWindow.rowDetail(running), SleepWindow.coachFact(running),
        ]
        copy += SleepWindow.rules(running) + SleepWindow.evidence
        copy += SleepWindow.Frequency.allCases.map(\.label)
        copy += SleepWindow.Exclusion.allCases.flatMap { [$0.question, $0.reason] }
        for frequency in SleepWindow.Frequency.allCases {
            for affects in [true, false] {
                if let note = SleepWindow.Answers(frequency: frequency, affectsDay: affects, day: day(0)).note { copy.append(note) }
            }
        }
        for change in [SleepWindow.Change.widened, .held, .narrowed, .heldAtFloor, .heldSleepy, .heldFewNights, .heldResting] {
            copy.append(SleepWindow.Review(week: 2, nights: 6, efficiencyPercent: change == .heldFewNights ? nil : 82, change: change, windowMinutes: 405).text)
        }
        for ending in [SleepWindow.Ending.reachedRegular, .timeLimit, .stopped, .excluded] {
            for answer in [nil, true, false] as [Bool?] {
                copy.append(SleepWindow.outcomeText(SleepWindow.Outcome(
                    ending: ending, day: day(56), weeks: 8, wakeMinutes: 390,
                    refusals: [SleepWindow.Refusal(exclusion: .apnoea, reason: SleepWindow.Exclusion.apnoea.reason)], stillStruggling: answer)))
            }
        }
        let shift = SleepRegularity.MidpointShift(minutes: 95, weekdayNights: 5, weekendNights: 2)
        copy += [shift.note(sleepDebt: .high), shift.note(sleepDebt: nil, sleepWindowOn: true)]
        return copy
    }

    @Test func nothingIsCalledTreatmentOrDiagnosis() {
        for text in allCopy {
            let lower = text.lowercased()
            for word in ["treat", "therap", "diagnos", "cure", "prescri", "patient", "insomnia disorder"] {
                #expect(!lower.contains(word), "\"\(word)\" in: \(text)")
            }
            #expect(!text.isEmpty)
            #expect(!text.contains("—"))
        }
        #expect(SleepWindow.notCareNote.contains("not medical care"))
        #expect(SleepWindow.notCareNote.contains("Stop any time"))
    }

    @Test func thereAreNoRelaxationBreathingOrHygieneTips() {
        // Furukawa 2024: sleep-hygiene education adds nothing and relaxation may hinder.
        let advice = SleepWindow.rules(course(windowMinutes: 405)) + [SleepWindow.sleepinessWarning, SleepWindow.howItChanges,
                                                                    SleepWindow.estimateNote, SleepWindow.notCareNote]
        for text in advice {
            let lower = text.lowercased()
            for word in ["relax", "breath", "meditat", "caffeine", "coffee", "alcohol", "screen", "bedroom", "wind down", "nap", "temperature"] {
                #expect(!lower.contains(word), "\"\(word)\" in: \(text)")
            }
        }
        // The rules are the method and nothing else: wake time, bedtime, out of bed when awake.
        let rules = SleepWindow.rules(wakeMinutes: 390, bedMinutes: 23 * 60 + 45)
        #expect(rules.count == 3)
        #expect(rules[0].contains("every day, weekends too"))
        #expect(rules[0].contains(SleepWindow.clock(390)))
        #expect(rules[1].contains("only when you're sleepy"))
        #expect(rules[1].contains(SleepWindow.clock(23 * 60 + 45)))
        #expect(rules[2].contains("20 minutes"))
        #expect(rules[2].contains("Get up"))
    }

    @Test func theSafetyWordsAreThere() {
        // Sleepiness, slower reactions and driving (Kyle 2014).
        #expect(SleepWindow.sleepinessWarning.contains("sleepier"))
        #expect(SleepWindow.sleepinessWarning.contains("slower to react"))
        #expect(SleepWindow.sleepinessWarning.contains("Don't drive"))
        #expect(SleepWindow.sleepinessWarning.contains("Too sleepy"))
        // The efficiency number is called an estimate wherever it's shown.
        #expect(SleepWindow.estimateNote.contains("estimate"))
        #expect(SleepWindow.Review(week: 1, nights: 7, efficiencyPercent: 88, change: .widened, windowMinutes: 405).text
            == "Week 1: asleep for about 88% of your time in bed (an estimate), so the window is 15 minutes longer.")
        #expect(SleepWindow.Review(week: 3, nights: 7, efficiencyPercent: 82, change: .held, windowMinutes: 405).text
            == "Week 3: asleep for about 82% of your time in bed (an estimate), so the window stays.")
        #expect(SleepWindow.Review(week: 2, nights: 6, efficiencyPercent: 71, change: .narrowed, windowMinutes: 390).text
            == "Week 2: asleep for about 71% of your time in bed (an estimate), so the window is 15 minutes shorter.")
        #expect(SleepWindow.Review(week: 4, nights: 7, efficiencyPercent: 70, change: .heldAtFloor, windowMinutes: 360).text.contains("stays at 6 h; it never goes lower"))
        #expect(SleepWindow.Review(week: 4, nights: 7, efficiencyPercent: 70, change: .heldSleepy, windowMinutes: 390).text.contains("you were too sleepy, so the window stays"))
        #expect(SleepWindow.Review(week: 4, nights: 1, efficiencyPercent: nil, change: .heldFewNights, windowMinutes: 390).text.contains("only 1 night recorded"))
        // The rule in words matches the numbers.
        #expect(SleepWindow.howItChanges.contains("85% or more"))
        #expect(SleepWindow.howItChanges.contains("under 80%"))
        #expect(SleepWindow.howItChanges.contains("never under 6 h"))
        #expect(SleepWindow.howItChanges.contains("after 8 weeks"))
        #expect(SleepWindow.debtPausedNote.contains("Sleep debt is paused"))
        #expect(SleepWindow.heading(course(windowMinutes: 390)) == "Sleep window · week 1 of 8")
        #expect(SleepWindow.windowText(windowMinutes: 405, wakeMinutes: 390)
            == "6 h 45 min in bed: \(SleepWindow.clock(23 * 60 + 45)) to \(SleepWindow.clock(390))")
        #expect(SleepWindow.duration(360) == "6 h")
        #expect(SleepWindow.duration(405) == "6 h 45 min")
    }

    @Test func theNumbersAreTheCautiousOnes() {
        #expect(SleepWindow.floorMinutes == 360)
        #expect(SleepWindow.extraMinutes == 30)
        #expect(SleepWindow.stepMinutes == 15)
        #expect(SleepWindow.widenPercent == 85)
        #expect(SleepWindow.narrowBelowPercent == 80)
        #expect(SleepWindow.maximumWeeks == 8)
        #expect(SleepWindow.nightsPerWeek == 3)
    }

    @Test func stateSurvivesSaving() throws {
        var running = course(windowMinutes: 390)
        running.reviews = [SleepWindow.Review(week: 1, nights: 7, efficiencyPercent: 88, change: .widened, windowMinutes: 405)]
        running.sleepyDays = [day(3)]
        let state = SleepWindow.State(
            answers: SleepWindow.Answers(frequency: .lasting, affectsDay: true, day: day(0)),
            refusals: [SleepWindow.Refusal(exclusion: .seizures, reason: SleepWindow.Exclusion.seizures.reason)], refusedDay: day(-100),
            course: running,
            outcome: SleepWindow.Outcome(ending: .timeLimit, day: day(56), weeks: 8, wakeMinutes: 390, stillStruggling: true),
            endedDay: day(56))
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(SleepWindow.State.self, from: data) == state)
        // An empty file from before any of it decodes too.
        #expect(try JSONDecoder().decode(SleepWindow.State.self, from: Data("{}".utf8)) == SleepWindow.State())
    }
}
