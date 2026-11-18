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
        // Each 4-minute work step: a 90 s ramp with no alert, then 150 s with it.
        #expect(workout.blocks[0].steps.map(\.kind) == [.work, .work, .recovery])
        #expect(workout.blocks[0].steps.map(\.seconds) == [90, 150, 180])
        #expect(workout.blocks[0].steps.map { $0.heartRate != nil } == [false, true, false])
        #expect(workout.blocks[1].iterations == 1)
        #expect(workout.blocks[1].steps.map(\.kind) == [.work, .work])
        #expect(workout.blocks[1].steps.map(\.seconds) == [90, 150])
    }

    @Test func unrolledStepsMatchTheSessionStepForStep() {
        for session in [IntervalSession.fourByFour(.rower), .threeByFour(.outdoorRun)] {
            let workout = StructuredWorkout.interval(session, scheme: scheme)
            // Each ramp joined back to its work step gives the session's steps.
            var merged: [StructuredWorkout.Step] = []
            for step in workout.unrolledSteps {
                if let last = merged.last, last.kind == .work, last.heartRate == nil, step.kind == .work, step.heartRate != nil {
                    merged[merged.count - 1].seconds += step.seconds
                } else {
                    merged.append(step)
                }
            }
            #expect(merged.map(\.seconds) == session.steps.map(\.seconds))
            #expect(merged.map(\.kind.rawValue) == session.steps.map(\.phase.rawValue))
            #expect(workout.totalSeconds == session.totalSeconds)
            #expect(workout.workSeconds == session.hardSeconds)
        }
    }

    @Test func onlyWorkStepsCarryTheZoneFourToFiveBandUpToMaximum() throws {
        let workout = StructuredWorkout.interval(.fourByFour(.treadmill), scheme: scheme)
        // Zone 4 starts at 80% of reserve: 55 + 0.8 × 130 = 159. Zone 5 has no top, so the alert stops at the maximum.
        for (index, step) in workout.unrolledSteps.enumerated() {
            let previous = index > 0 ? workout.unrolledSteps[index - 1] : nil
            if step.kind == .work, previous?.kind == .work {
                #expect(step.heartRate == StructuredWorkout.HeartRateRange(lower: 159, upper: 185))
            } else if step.kind == .work {
                // The ramp: heart rate is still climbing, so no alert.
                #expect(step.heartRate == nil && step.seconds == 90)
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
        #expect(workout.blocks.count == 1 && workout.blocks[0].iterations == 1)
        #expect(workout.blocks[0].steps.map(\.seconds) == [90, 30 * 60 - 90])
        #expect(workout.totalSeconds == 30 * 60)
        #expect(workout.blocks[0].steps.first?.heartRate == nil)
        let step = try #require(workout.blocks.first?.steps.last)
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

    @Test func aSecondAddReplacesTheWeekWhenAnyDayElseTheDay() {
        // Flexible week: added Tuesday, then again for Thursday: the Tuesday copy goes.
        let week = StructuredWorkout.replaceWindow(anyDay: true, day: at(3), weekStart: monday, calendar: calendar)
        #expect(week.start == at(0, 0) && week.end == at(7, 0))
        #expect(StructuredWorkout.isInReplaceWindow(at(1, 18), window: week))
        #expect(StructuredWorkout.isInReplaceWindow(at(6, 23), window: week))
        #expect(!StructuredWorkout.isInReplaceWindow(at(7, 9), window: week))
        #expect(!StructuredWorkout.isInReplaceWindow(at(-1, 18), window: week))
        // A fixed day: only that day.
        let day = StructuredWorkout.replaceWindow(anyDay: false, day: at(3, 0), weekStart: monday, calendar: calendar)
        #expect(day.start == at(3, 0) && day.end == at(4, 0))
        #expect(StructuredWorkout.isInReplaceWindow(at(3, 18), window: day))
        #expect(!StructuredWorkout.isInReplaceWindow(at(1, 18), window: day))
    }
}

@Suite("Ramp before a work step's heart-rate alert")
struct StructuredWorkoutRampTests {
    let range = StructuredWorkout.HeartRateRange(lower: 150, upper: 170)

    @Test func rampIsNinetySecondsOrHalfTheStep() {
        #expect(StructuredWorkout.rampSeconds(forWorkSeconds: 240) == 90)
        #expect(StructuredWorkout.rampSeconds(forWorkSeconds: 180) == 90)
        #expect(StructuredWorkout.rampSeconds(forWorkSeconds: 120) == 60)
        #expect(StructuredWorkout.rampSeconds(forWorkSeconds: 30) == 15)
    }

    @Test func splitKeepsTheLengthAndMovesTheAlertAfterTheRamp() {
        for seconds in [1, 2, 30, 61, 120, 179, 240, 1800] {
            let step = StructuredWorkout.Step(kind: .work, seconds: seconds, heartRate: range, name: "Hard")
            let split = StructuredWorkout.withRamp(step)
            #expect(split.reduce(0) { $0 + $1.seconds } == seconds)
            #expect(split.last?.heartRate == range)
            #expect(split.allSatisfy { $0.seconds > 0 && $0.kind == .work })
            if split.count == 2 { #expect(split[0].heartRate == nil) }
        }
        // A one-second step can't be split.
        #expect(StructuredWorkout.withRamp(.init(kind: .work, seconds: 1, heartRate: range, name: "Hard")).count == 1)
    }

    @Test func stepsWithoutAnAlertAreLeftAlone() {
        let recovery = StructuredWorkout.Step(kind: .recovery, seconds: 180, name: "Easy")
        #expect(StructuredWorkout.withRamp(recovery) == [recovery])
        let noAlert = StructuredWorkout.Step(kind: .work, seconds: 240, name: "Hard")
        #expect(StructuredWorkout.withRamp(noAlert) == [noAlert])
    }
}
