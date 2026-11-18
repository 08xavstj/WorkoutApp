import Foundation
import Testing
@testable import AppCore

// The cardio sessions as Apple's Workout app takes them (`StructuredWorkout`,
// docs/research/next-features-2026-11.md W1).

private let calendar = SimFixtures.calendar
/// Monday 5 January 2026.
private let monday = SimFixtures.monday
private let scheme = HeartRateZoneScheme.reserve(resting: 55, maximum: 185)

private func at(_ dayOffset: Int, _ hour: Int = 9) -> Date {
    calendar.date(byAdding: DateComponents(day: dayOffset, hour: hour), to: monday)!
}

@Suite("Structured workout for Apple's Workout app")
struct StructuredWorkoutTests {
    @Test func fourByFourIsWarmUpThreeRoundsTheLastHardAndCoolDown() throws {
        let workout = StructuredWorkout.interval(.fourByFour(.bike), scheme: scheme)
        #expect(workout.name == "4 × 4 min · Bike")
        #expect(workout.activity == .cycling)
        #expect(workout.location == .indoor)
        let warmUp = try #require(workout.warmUp)
        #expect(warmUp.kind == .warmUp && warmUp.seconds == 600 && warmUp.heartRate == nil)
        let coolDown = try #require(workout.coolDown)
        #expect(coolDown.kind == .coolDown && coolDown.seconds == 300 && coolDown.heartRate == nil)
        #expect(workout.blocks.count == 2)
        #expect(workout.blocks[0].iterations == 3)
        #expect(workout.blocks[0].steps.map(\.kind) == [.work, .recovery])
        #expect(workout.blocks[0].steps.map(\.seconds) == [240, 180])
        #expect(workout.blocks[1].iterations == 1)
        #expect(workout.blocks[1].steps.map(\.kind) == [.work])
    }

    @Test func unrolledStepsMatchTheSessionStepForStep() {
        for session in [IntervalSession.fourByFour(.rower), .threeByFour(.outdoorRun)] {
            let workout = StructuredWorkout.interval(session, scheme: scheme)
            #expect(workout.unrolledSteps.map(\.seconds) == session.steps.map(\.seconds))
            #expect(workout.unrolledSteps.map(\.kind.rawValue) == session.steps.map(\.phase.rawValue))
            #expect(workout.totalSeconds == session.totalSeconds)
            #expect(workout.workSeconds == session.hardSeconds)
        }
    }

    @Test func onlyWorkStepsCarryTheZoneFourToFiveBandUpToMaximum() throws {
        let workout = StructuredWorkout.interval(.fourByFour(.treadmill), scheme: scheme)
        // Zone 4 starts at 80% of reserve: 55 + 0.8 × 130 = 159. Zone 5 has no top, so the alert stops at the maximum.
        for step in workout.unrolledSteps {
            if step.kind == .work {
                #expect(step.heartRate == StructuredWorkout.HeartRateRange(lower: 159, upper: 185))
            } else {
                #expect(step.heartRate == nil)
            }
        }
        // The same numbers the app and the Watch show for the step.
        let band = try #require(IntervalSession.workBand.heartRateBand(in: scheme))
        #expect(band.text == "159+")
    }

    @Test func appleHealthZonesWithoutAMaximumUseThePlausibleTop() throws {
        let easy = HeartRateBand(lower: 110, upper: 130)
        let apple = try #require(HeartRateZoneScheme.appleHealth(floor: nil, boundaries: [137, 149, 160, 172], easyBand: easy))
        let range = StructuredWorkout.heartRateRange(IntervalSession.workBand, scheme: apple)
        #expect(range == StructuredWorkout.HeartRateRange(lower: 160, upper: StructuredWorkout.openBandTop))
        #expect(StructuredWorkout.openBandTop == 230)
    }

    @Test func noSchemeMeansNoAlerts() {
        let workout = StructuredWorkout.interval(.threeByFour(.bike), scheme: nil)
        #expect(workout.unrolledSteps.allSatisfy { $0.heartRate == nil })
        #expect(StructuredWorkout.heartRateRange(.none, scheme: scheme) == nil)
    }

    @Test func threeByFourHasTwoRepeatedRounds() {
        let workout = StructuredWorkout.interval(.threeByFour(.outdoorRide), scheme: scheme)
        #expect(workout.blocks.map(\.iterations) == [2, 1])
        #expect(workout.activity == .cycling)
        #expect(workout.location == .outdoor)
        #expect(workout.workSeconds == 12 * 60)
    }

    @Test func easySessionIsOneStepAtTheEasyBand() throws {
        let workout = StructuredWorkout.easy(.inclineWalk, minutes: 30, indoor: true, scheme: scheme)
        #expect(workout.name == "Incline walk · 30 min")
        #expect(workout.activity == .walking)
        #expect(workout.location == .indoor)
        #expect(workout.warmUp == nil && workout.coolDown == nil)
        let step = try #require(workout.blocks.first?.steps.first)
        #expect(workout.blocks.count == 1 && workout.blocks[0].iterations == 1)
        #expect(step.seconds == 30 * 60)
        // 40-60% of reserve: 55 + 52 = 107, 55 + 78 = 133.
        #expect(step.heartRate == StructuredWorkout.HeartRateRange(lower: 107, upper: 133))
        #expect(StructuredWorkout.easy(.bike, minutes: 30, indoor: false, scheme: scheme).location == .outdoor)
        #expect(StructuredWorkout.easy(.row, minutes: 30, indoor: false, scheme: scheme).location == .indoor)
    }

    @Test func workoutBuddyOnlyWhereAppleListsIt() {
        #expect(StructuredWorkout.interval(.fourByFour(.outdoorRun), scheme: scheme).workoutBuddySpeaks)
        #expect(StructuredWorkout.interval(.fourByFour(.treadmill), scheme: scheme).workoutBuddySpeaks)
        #expect(StructuredWorkout.interval(.fourByFour(.outdoorRide), scheme: scheme).workoutBuddySpeaks)
        #expect(!StructuredWorkout.interval(.fourByFour(.bike), scheme: scheme).workoutBuddySpeaks)
        #expect(!StructuredWorkout.interval(.fourByFour(.rower), scheme: scheme).workoutBuddySpeaks)
        #expect(StructuredWorkout.easy(.inclineWalk, minutes: 30, indoor: true, scheme: scheme).workoutBuddySpeaks)
    }

    /// A session Apple's Workout app records must tick the plan: the done check
    /// matches Health workout names, and these are the names the types get.
    @Test func recordedTypesCountAsTheSessionDone() {
        for modality in IntervalSession.Modality.allCases {
            #expect(modality.workoutNames.contains(modality.structuredActivity.healthName))
        }
        for kind in EasyCardio.Kind.allCases {
            #expect(kind.workoutNames.contains(kind.structuredActivity.healthName))
        }
    }

    @Test func aFortyMinuteRideOnItsDayTicksTheHardSession() {
        // An upper/lower week: the hard session gets a fixed day (`HardCardio.weekday`).
        let plan = WeeklyPlan(weekStart: monday,
                              plannedDays: [(2, WorkoutFocus.upper), (3, .lower), (5, .upper), (6, .lower)]
                                .map { PlannedDay(weekday: $0.0, time: 18 * 60, focus: $0.1, minutes: 60) },
                              mode: .fixedDays, sessionsPerWeek: nil,
                              cardio: EasyCardio(sessionsPerWeek: 1, kind: .bike, hard: HardCardio.Choice(modality: .bike)))
        guard let slot = HardCardio.slot(for: plan, goals: nil), let weekday = slot.weekday else {
            Issue.record("expected a fixed hard day")
            return
        }
        let workout = StructuredWorkout.interval(slot.session, scheme: scheme)
        let day = StructuredWorkout.day(weekday: weekday, weekStart: monday, now: monday, calendar: calendar)!
        let recorded = CardioPlanner.Workout(name: workout.activity.healthName, start: day.addingTimeInterval(18 * 3600),
                                             minutes: workout.totalSeconds / 60)
        #expect(HardCardio.weekDone(plan: plan, goals: nil, workouts: [recorded], calendar: calendar).hard)
    }

    @Test func dayIsThePlannedWeekdayUntilItPasses() {
        // Thursday (weekday 5) is offset 3 from Monday.
        #expect(StructuredWorkout.day(weekday: 5, weekStart: monday, now: at(0), calendar: calendar) == at(3, 0))
        #expect(StructuredWorkout.day(weekday: 5, weekStart: monday, now: at(3, 20), calendar: calendar) == at(3, 0))
        #expect(StructuredWorkout.day(weekday: 5, weekStart: monday, now: at(4), calendar: calendar) == nil)
        // Any day: today, while the week lasts.
        #expect(StructuredWorkout.day(weekday: nil, weekStart: monday, now: at(2, 15), calendar: calendar) == at(2, 0))
        #expect(StructuredWorkout.day(weekday: nil, weekStart: monday, now: at(7), calendar: calendar) == nil)
    }

    @Test func startTimeFollowsThePlan() {
        let plan = WeeklyPlan(weekStart: monday,
                              plannedDays: [PlannedDay(weekday: 3, time: 7 * 60, focus: .upper, minutes: 60),
                                            PlannedDay(weekday: 5, time: 17 * 60 + 30, focus: .lower, minutes: 60)],
                              mode: .fixedDays, sessionsPerWeek: nil, cardio: nil)
        #expect(StructuredWorkout.startMinutes(plan: plan, weekday: 5) == 17 * 60 + 30)
        #expect(StructuredWorkout.startMinutes(plan: plan, weekday: 2) == 7 * 60)
        let empty = WeeklyPlan(weekStart: monday, plannedDays: [], mode: .flexible, sessionsPerWeek: 3, cardio: nil)
        #expect(StructuredWorkout.startMinutes(plan: empty, weekday: nil) == StructuredWorkout.fallbackStartMinutes)
    }
}
