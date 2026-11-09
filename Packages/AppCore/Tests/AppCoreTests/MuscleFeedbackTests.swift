import Foundation
import Testing
@testable import AppCore

/// Per-muscle answers after a session (`MuscleFeedback`) and how the weekly
/// step uses them (`VolumeProgression.target`): hold when still sore or
/// painful, one set fewer when repeated, one set when you say it recovered
/// while the model alone would hold it.
struct MuscleFeedbackTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Monday 2 March 2026, 00:00 UTC.
    var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))! }
    /// Noon on day `offset` after `monday`.
    func day(_ offset: Int) -> Date { monday.addingTimeInterval(Double(offset) * 86_400 + 12 * 3_600) }

    func set(_ start: Date, _ muscle: Muscle = .chest) -> VolumeProgression.LoggedSet {
        VolumeProgression.LoggedSet(exerciseID: "x", name: "X", sessionStart: start, order: 0, primary: [muscle],
                                    weightKg: 50, reps: 8, rpe: 8, isCompound: true)
    }

    let block = TrainingBlock.WeekState(week: 3, length: 5, setMultiplier: 1, targetRIR: 2, isDeload: false)
    let fresh = MuscleRecovery.State(muscle: .chest, recovery: 95, weeklySets: 12, lastTrained: nil)
    let tired = MuscleRecovery.State(muscle: .chest, recovery: 70, weeklySets: 12, lastTrained: nil)
    let good = VolumeProgression.Performance(sets: 12)

    func target(_ feedback: MuscleFeedback.Signal?, state: MuscleRecovery.State? = nil,
                lastWeek: VolumeProgression.Performance? = nil) -> VolumeProgression.Target {
        VolumeProgression.target(for: .chest, previous: 12, week: block, style: .muscle, lastWeek: lastWeek ?? good,
                                 state: state ?? fresh, sessions: 2, timeCap: 20, feedback: feedback)
    }

    // MARK: Main muscles

    @Test func mainMusclesAreTheMostTrainedTwoToFour() {
        let sets: [Muscle: Double] = [.chest: 6, .shoulders: 3, .triceps: 4, .lats: 1.5, .quadriceps: 2, .hamstrings: 2.5]
        #expect(MuscleFeedback.mainMuscles(sets) == [.chest, .triceps, .shoulders, .hamstrings])
        #expect(MuscleFeedback.mainMuscles([.biceps: 1]).isEmpty)
    }

    // MARK: Signals

    @Test func signalsUseTheNewestAnswersInTheWeek() {
        let entries = [
            MuscleFeedback.Entry(sessionStart: day(1), muscle: .chest, pump: .great, soreness: .stillSore),
            MuscleFeedback.Entry(sessionStart: day(3), muscle: .chest, pump: .low, soreness: .stillSore, jointPain: true),
            // Last week and next week don't count.
            MuscleFeedback.Entry(sessionStart: day(-3), muscle: .chest, jointPain: true),
            MuscleFeedback.Entry(sessionStart: day(8), muscle: .chest, jointPain: true),
            MuscleFeedback.Entry(sessionStart: day(3), muscle: .triceps)
        ]
        let sets = [set(day(-1)), set(day(1)), set(day(3))]
        let signals = MuscleFeedback.signals(entries, sets: sets, weekStart: monday, calendar: calendar)
        let chest = signals[.chest]
        #expect(chest?.pump == .low)
        #expect(chest?.soreReports == 2)
        #expect(chest?.soreRepeatedly == true)
        #expect(chest?.jointPainReports == 1)
        // "Still sore" on Thursday is left over from Tuesday's session.
        #expect(chest?.soreFrom == day(1))
        #expect(signals[.triceps] == nil)
    }

    @Test func entryCodableRoundTrip() throws {
        let entry = MuscleFeedback.Entry(sessionStart: day(1), muscle: .middleBack, pump: .ok, soreness: .mild, jointPain: false)
        let data = try JSONEncoder().encode([entry])
        #expect(try JSONDecoder().decode([MuscleFeedback.Entry].self, from: data) == [entry])
    }

    // MARK: The weekly step

    @Test func noAnswersKeepsTheUsualRule() {
        #expect(target(nil).change == .added)
        #expect(target(nil).sets == 14)
        #expect(target(nil, state: tired).change == .heldNotRecovered)
    }

    @Test func greatPumpAndRecoveredIsTheNormalStep() {
        let signal = MuscleFeedback.Signal(pump: .great, soreness: .notSore)
        #expect(target(signal).change == .added)
        #expect(target(signal).sets == 14)
        // The model still holds a tired muscle: a great pump doesn't override it.
        #expect(target(signal, state: tired).change == .heldNotRecovered)
    }

    @Test func recoveredWithLowOrOkPumpAllowsOneSetWhenTheModelHolds() {
        for pump in [MuscleFeedback.Pump.low, .ok] {
            let result = target(MuscleFeedback.Signal(pump: pump, soreness: .mild), state: tired)
            #expect(result.sets == 13)
            #expect(result.change == .addedFeedback)
            #expect(result.change.isFromFeedback)
        }
        // Performance still comes first: reps dropped holds.
        let dropped = VolumeProgression.Performance(sets: 12, repsDropped: ["Bench Press"])
        #expect(target(MuscleFeedback.Signal(pump: .low, soreness: .notSore), state: tired, lastWeek: dropped).change
                == .heldRepsDropped(exercise: "Bench Press"))
    }

    @Test func stillSoreOrJointPainHolds() {
        let sore = target(MuscleFeedback.Signal(soreness: .stillSore, soreReports: 1, soreFrom: day(1)))
        #expect(sore.sets == 12)
        #expect(sore.change == .heldSore(from: day(1)))
        #expect(sore.change.isHeld)
        let pain = target(MuscleFeedback.Signal(pump: .great, soreness: .notSore, jointPainReports: 1))
        #expect(pain.sets == 12)
        #expect(pain.change == .heldJointPain)
        #expect(pain.note == "Chest held at 12 sets: you reported joint pain last week.")
        let unknown = target(MuscleFeedback.Signal(soreness: .stillSore, soreReports: 1))
        #expect(unknown.note == "Chest held at 12 sets: you said it was still sore last week.")
    }

    @Test func repeatedAnswersTakeOneSetOff() {
        let sore = target(MuscleFeedback.Signal(soreness: .stillSore, soreReports: 2))
        #expect(sore.sets == 11)
        #expect(sore.change == .reducedSore)
        let pain = target(MuscleFeedback.Signal(jointPainReports: 2))
        #expect(pain.sets == 11)
        #expect(pain.change == .reducedJointPain)
        // Sore twice but fine at the newest session: no cut, the usual step.
        #expect(target(MuscleFeedback.Signal(soreness: .notSore, soreReports: 2)).change == .added)
        // Never under the minimum.
        let low = VolumeProgression.target(for: .chest, previous: 4, week: block, style: .muscle,
                                           lastWeek: VolumeProgression.Performance(sets: 4), state: fresh, sessions: 2,
                                           timeCap: 20, feedback: MuscleFeedback.Signal(jointPainReports: 3))
        #expect(low.sets == VolumeProgression.minimumSets)
    }

    @Test func answersDontTouchStartDeloadOrSteadyWeeks() {
        let signal = MuscleFeedback.Signal(soreness: .stillSore, soreReports: 3, jointPainReports: 3)
        let start = TrainingBlock.WeekState(week: 1, length: 5, setMultiplier: 1, targetRIR: 3, isDeload: false)
        #expect(VolumeProgression.target(for: .chest, previous: nil, week: start, style: .muscle, lastWeek: nil, state: nil,
                                         sessions: 2, timeCap: 20, feedback: signal).change == .start)
        let deload = TrainingBlock.WeekState(week: 5, length: 5, setMultiplier: 0.5, targetRIR: 3, isDeload: true)
        #expect(VolumeProgression.target(for: .chest, previous: 16, week: deload, style: .muscle, lastWeek: good, state: nil,
                                         sessions: 2, timeCap: 20, feedback: signal).change == .deload)
    }

    @Test func weekPassesAnswersPerMuscle() {
        let days = [PlannedDay(weekday: 2, time: 1080, focus: .push, minutes: 60),
                    PlannedDay(weekday: 5, time: 1080, focus: .push, minutes: 60)]
        let previous = VolumeProgression.WeekTargets(weekStart: monday.addingTimeInterval(-7 * 86_400), targetRIR: 2, targets: [
            VolumeProgression.Target(muscle: .chest, sets: 12, previous: nil, change: .start)
        ])
        let week = VolumeProgression.week(weekStart: monday, block: block, style: .muscle, days: days, previous: previous,
                                          lastWeek: [.chest: good], states: [.chest: fresh],
                                          feedback: [.chest: MuscleFeedback.Signal(soreness: .stillSore, soreReports: 1)])
        #expect(week.target(for: .chest)?.change == .heldSore(from: nil))
        #expect(week.notable.contains { $0.muscle == .chest })
    }
}
