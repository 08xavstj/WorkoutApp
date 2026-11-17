import Foundation
import Testing
@testable import AppCore

// One hard cardio session a week (`HardCardio`) and its step-by-step
// description (`IntervalSession`).

private let calendar = SimFixtures.calendar
private let monday = SimFixtures.monday

private func plan(_ days: [(Int, WorkoutFocus)], cardio: EasyCardio? = EasyCardio(sessionsPerWeek: 1, kind: .bike),
                  flexible: Bool = false) -> WeeklyPlan {
    WeeklyPlan(weekStart: monday, plannedDays: days.map { PlannedDay(weekday: $0.0, time: 18 * 60, focus: $0.1, minutes: 60) },
               mode: flexible ? .flexible : .fixedDays, sessionsPerWeek: flexible ? days.count : nil, cardio: cardio)
}

private let upperLower = plan([(2, .upper), (3, .lower), (5, .upper), (6, .lower)])

@Suite("Interval session")
struct IntervalSessionTests {
    @Test func fourByFourIsFortyMinutesWithSixteenHard() {
        let session = IntervalSession.fourByFour(.bike)
        #expect(session.totalMinutes == 40)
        #expect(session.hardMinutes == 16)
        #expect(session.steps.first?.phase == .warmUp)
        #expect(session.steps.last?.phase == .coolDown)
        #expect(session.steps.filter { $0.phase == .work }.count == 4)
        #expect(session.steps.filter { $0.phase == .recovery }.count == 3)
        #expect(session.steps.map(\.index) == Array(0..<session.steps.count))
        #expect(session.title == "4 × 4 min · Bike")
    }

    @Test func threeByFourIsShorterAndUnderTheLongIntervalLine() {
        let session = IntervalSession.threeByFour(.rower)
        #expect(session.totalMinutes == 30)
        #expect(session.hardMinutes == 12)
        #expect(HardCardio.promise(session).contains("Wen 2019"))
        #expect(!HardCardio.promise(.fourByFour(.rower)).contains("Wen 2019"))
    }

    @Test func targetsUseTheEasyBandAndZonesFourToFive() {
        let session = IntervalSession.fourByFour(.treadmill)
        for step in session.steps {
            switch step.phase {
            case .warmUp, .recovery: #expect(step.target.band == .easy)
            case .work: #expect(step.target.band == .zones(low: 4, high: 5))
            case .coolDown: #expect(step.target.band == IntervalSession.Band.none)
            }
        }
        #expect(IntervalSession.Band.easy.watchStorage == CardioTarget.easy.storage)
        #expect(IntervalSession.Band.zones(low: 4, high: 5).watchStorage == CardioTarget.zone(4).storage)
    }

    @Test func bandsComeFromTheSameSchemeAsTheWatch() {
        let scheme = HeartRateZoneScheme.reserve(resting: 55, maximum: 185)
        #expect(IntervalSession.Band.easy.heartRateBand(in: scheme) == scheme.easyBand)
        let hard = IntervalSession.Band.zones(low: 4, high: 5).heartRateBand(in: scheme)
        #expect(hard?.lower == scheme.band(forZone: 4)?.lower)
        #expect(hard?.upper == HeartRateBand.noUpperLimit)
        #expect(IntervalSession.Band.none.heartRateBand(in: scheme) == nil)
        // Helgerud's 90-95% of maximum sits inside the hard band on both scales, and 70% inside easy.
        for scale in [scheme, HeartRateZoneScheme.percentOfMax(maximum: 185, resting: 55)] {
            let work = IntervalSession.Band.zones(low: 4, high: 5).heartRateBand(in: scale)!
            #expect(work.contains(0.90 * 185) && work.contains(0.95 * 185))
            #expect(scale.easyBand.contains(0.70 * 185))
        }
        #expect(IntervalSession.Band.easy.text(in: nil) == "Easy")
        #expect(IntervalSession.Band.easy.text(in: scheme).hasSuffix("bpm"))
    }

    @Test func stepAtElapsedTime() {
        let session = IntervalSession.fourByFour(.bike)
        #expect(session.step(at: 0)?.step.phase == .warmUp)
        #expect(session.step(at: 600)?.step.phase == .work)
        #expect(session.step(at: 600)?.remaining == 240)
        #expect(session.step(at: 840)?.step.phase == .recovery)
        #expect(session.step(at: 2400) == nil)
    }

    @Test func encodesForTheWatchAndRefusesNewerFormats() throws {
        let session = IntervalSession.threeByFour(.outdoorRun)
        let data = try #require(session.encoded())
        #expect(IntervalSession.decoded(from: data) == session)
        var newer = session
        newer.version = IntervalSession.currentVersion + 1
        #expect(IntervalSession.decoded(from: try #require(newer.encoded())) == nil)
        #expect(IntervalSession.decoded(from: Data("nope".utf8)) == nil)
        // The Watch's activity names.
        #expect(Set(IntervalSession.Modality.allCases.map(\.watchActivity)).isSubset(of: Set(CardioActivity.allCases.map(\.rawValue))))
    }
}

@Suite("Hard cardio: when and where")
struct HardCardioTests {
    @Test func neverOnOrTheDayBeforeHeavyLegs() {
        let weekday = HardCardio.weekday(for: upperLower)
        #expect(weekday != nil)
        for check in [weekday!] {
            #expect(upperLower.day(for: check).map { CardioPlanner.isHeavyLower($0.focus) } != true)
            let next = WeeklyPlan.weekdayOrder[(WeeklyPlan.order(check) + 1) % 7]
            #expect(upperLower.day(for: next).map { CardioPlanner.isHeavyLower($0.focus) } != true)
        }
        // A rest day first.
        #expect(upperLower.day(for: weekday!) == nil)
    }

    @Test func noDayWhenEveryDayIsLegsOrBeforeLegs() {
        let full = plan([(2, .fullBody), (3, .fullBody), (4, .fullBody), (5, .fullBody), (6, .fullBody), (7, .fullBody)])
        #expect(HardCardio.weekday(for: full) == nil)
        #expect(HardCardio.blocker(plan: full, goals: nil) == .noDay)
    }

    @Test func blockedInABusyWeekARestWeekADeloadAndAHardCut() {
        var busy = BusyWeek.plan(from: upperLower, sessions: 2)
        busy.cardio = EasyCardio(sessionsPerWeek: 1, hard: HardCardio.Choice(modality: .bike))
        #expect(HardCardio.blocker(plan: busy, goals: nil) == .busyWeek)
        #expect(HardCardio.slot(for: busy, goals: nil) == nil)
        #expect(HardCardio.blocker(plan: upperLower, goals: nil, restMode: true) == .restMode)
        #expect(HardCardio.blocker(plan: upperLower, goals: nil, isDeloadWeek: true) == .deloadWeek)
        let cut = Goals(weight: .lose, weeklyRatePercent: 1.0, focuses: [.muscle])
        #expect(HardCardio.blocker(plan: upperLower, goals: cut) == .hardCut)
        let gentle = Goals(weight: .lose, weeklyRatePercent: 0.5, focuses: [.muscle])
        #expect(HardCardio.blocker(plan: upperLower, goals: gentle) == nil)
    }

    @Test func offeredOnlyWithAReason() {
        let none = HardCardio.offer(plan: upperLower, goals: nil, gym: .commercialKilograms, vo2: 52, age: 35, sex: .male,
                                    blockWeeks: 6, weeklyVigorousMinutes: 30, now: monday)
        #expect(none == nil)
        let few = HardCardio.offer(plan: upperLower, goals: nil, gym: .commercialKilograms, vo2: 52, age: 35, sex: .male,
                                   blockWeeks: 6, weeklyVigorousMinutes: 6, now: monday)
        #expect(few?.reasons == [.fewVigorousMinutes(6)])
        #expect(few?.replacesEasy == true)
        let low = HardCardio.offer(plan: upperLower, goals: nil, gym: .commercialKilograms, vo2: 33, age: 35, sex: .male,
                                   blockWeeks: 6, weeklyVigorousMinutes: nil, now: monday)
        #expect(low?.reasons.first.map { if case .belowGood = $0 { true } else { false } } == true)
        // Never during a hard cut, whatever the reason.
        let cut = Goals(weight: .lose, weeklyRatePercent: 1.0, focuses: [.muscle])
        #expect(HardCardio.offer(plan: upperLower, goals: cut, gym: nil, vo2: 33, age: 35, sex: .male,
                                 blockWeeks: 6, weeklyVigorousMinutes: 0, now: monday) == nil)
    }

    @Test func flatFitnessOverABlock() {
        let readings = (0..<10).map { DayValue(date: monday.addingTimeInterval(Double($0) * 7 * 86_400), value: 44 + 0.05 * Double($0)) }
        let now = readings.last!.date.addingTimeInterval(86_400)
        #expect(HardCardio.isFlat(readings, weeks: 6, now: now) == true)
        let rising = readings.enumerated().map { DayValue(date: $0.element.date, value: 40 + Double($0.offset)) }
        #expect(HardCardio.isFlat(rising, weeks: 6, now: now) == false)
        // A stale last reading says nothing.
        #expect(HardCardio.isFlat(readings, weeks: 6, now: now.addingTimeInterval(60 * 86_400)) == nil)
    }

    @Test func onlyWhatTheGymHas() {
        #expect(HardCardio.modalities(gym: .commercialKilograms).prefix(3) == [.bike, .rower, .treadmill])
        #expect(HardCardio.modalities(gym: .homeDumbbells) == [.outdoorRide, .outdoorRun])
        var gym = GymProfile.homeDumbbells
        gym.cardioMachines = [.rower]
        #expect(HardCardio.modalities(gym: gym).first == .rower)
        #expect(HardCardio.supported(HardCardio.Choice(modality: .bike), gym: gym).modality == .rower)
    }

    @Test func takesOneEasySessionsPlaceAndItsDay() {
        var week = upperLower
        week.cardio = EasyCardio(sessionsPerWeek: 2, kind: .bike, hard: HardCardio.Choice(modality: .bike))
        let hard = HardCardio.slot(for: week, goals: nil)
        let easy = CardioPlanner.slots(for: week, goals: nil)
        #expect(hard != nil)
        #expect(easy.count == 1)
        #expect(!easy.contains { $0.weekday == hard?.weekday })
        // 30 easy minutes plus the 40-minute session.
        #expect(CardioPlanner.plannedMinutes(week.cardio, goals: nil) == 70)
        // A week with no easy cardio can still take it.
        week.cardio = EasyCardio(sessionsPerWeek: 0, hard: HardCardio.Choice(modality: .rower, isShort: true))
        #expect(CardioPlanner.slots(for: week, goals: nil).isEmpty)
        #expect(HardCardio.slot(for: week, goals: nil) != nil)
        #expect(CardioPlanner.plannedMinutes(week.cardio, goals: nil) == 30)
    }

    @Test func waitsOnADayThatReadsAsEasy() {
        let slot = HardCardio.Slot(weekday: 4, choice: HardCardio.Choice(modality: .bike))
        #expect(HardCardio.dayNote(slot: slot, weekday: 4, lowRecovery: true) != nil)
        #expect(HardCardio.dayNote(slot: slot, weekday: 4, lowRecovery: false) == nil)
        #expect(HardCardio.dayNote(slot: slot, weekday: 5, lowRecovery: true) == nil)
    }

    @Test func promisesMinutesNotAVO2MaxNumber() {
        let text = HardCardio.promise(.fourByFour(.bike))
        #expect(text.contains("vigorous minutes"))
        #expect(text.contains("No promise about your VO2 max"))
    }

    @Test func doneFromAppleHealthWorkouts() {
        var week = upperLower
        week.cardio = EasyCardio(sessionsPerWeek: 1, kind: .bike, hard: HardCardio.Choice(modality: .bike))
        let weekday = HardCardio.slot(for: week, goals: nil)!.weekday!
        let day = calendar.date(byAdding: .day, value: WeeklyPlan.order(weekday), to: monday)!.addingTimeInterval(7 * 3600)
        let done = HardCardio.weekDone(plan: week, goals: nil, workouts: [CardioPlanner.Workout(name: "Ride", start: day, minutes: 41)],
                                       calendar: calendar)
        #expect(done.hard)
        let short = HardCardio.weekDone(plan: week, goals: nil, workouts: [CardioPlanner.Workout(name: "Ride", start: day, minutes: 10)],
                                        calendar: calendar)
        #expect(!short.hard)
    }

    @Test func oldPlansDecodeWithoutTheHardSession() throws {
        let json = #"{"sessionsPerWeek":1,"minutes":30,"kind":"bike"}"#
        let cardio = try JSONDecoder().decode(EasyCardio.self, from: Data(json.utf8))
        #expect(cardio.hard == nil)
        let gym = try JSONDecoder().decode(GymProfile.self, from: JSONEncoder().encode(GymProfile.homeDumbbells))
        #expect(gym.cardioMachines == [])
    }
}
