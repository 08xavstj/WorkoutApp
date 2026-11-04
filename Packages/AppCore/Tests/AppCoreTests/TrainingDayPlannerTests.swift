import Foundation
import Testing
@testable import AppCore

struct TrainingDayPlannerTests {
    let calendar = Calendar(identifier: .gregorian)
    let today = Date(timeIntervalSince1970: 1_800_000_000)

    func day(_ daysAgo: Int, _ focus: WorkoutFocus?, strain: Double) -> TrainingDayPlanner.PastDay {
        TrainingDayPlanner.PastDay(date: today.addingTimeInterval(Double(-daysAgo) * 86_400), plannedFocus: focus, strain: strain)
    }

    func guidance(today planned: WorkoutFocus?, _ past: [TrainingDayPlanner.PastDay], low: Bool = false) -> TrainingDayPlanner.Guidance {
        TrainingDayPlanner.guidance(plannedToday: planned, past: past, lowRecovery: low, usualTrainingStrain: 65, calendar: calendar)
    }

    @Test func restDayAimsLow() {
        let result = guidance(today: nil, [day(2, .push, strain: 60), day(1, .pull, strain: 58)])
        #expect(result.kind == .rest)
        #expect(result.strainRange == TrainingDayPlanner.restDayRange)
        #expect(result.strainRange.upperBound <= 25)
    }

    @Test func plannedDayTrainsAsPlanned() {
        let result = guidance(today: .legs, [day(1, nil, strain: 10)])
        #expect(result.kind == .training)
        #expect(result.focus == .legs)
        #expect(result.strainRange == StrainCalculator.targetStrain(forRecovery: 50, usualTrainingStrain: 65))
    }

    @Test func lowRecoveryMakesAPlannedDayEasy() {
        let result = guidance(today: .legs, [day(1, nil, strain: 10)], low: true)
        #expect(result.kind == .easyTraining)
        #expect(result.strainRange.upperBound < StrainCalculator.targetStrain(forRecovery: 50, usualTrainingStrain: 65).lowerBound)
    }

    @Test func hardRestDayMeansRestTomorrow() {
        let result = guidance(today: nil, [day(1, nil, strain: 62)])
        #expect(result.kind == .recovery)
        #expect(result.strainRange == TrainingDayPlanner.restDayRange)
    }

    @Test func hardRestDayBeforeAPlannedDayMakesItEasy() {
        let easy = guidance(today: .push, [day(1, nil, strain: 62)])
        #expect(easy.kind == .easyTraining)
        #expect(easy.focus == .push)
        // With low recovery too, it's a full rest day.
        #expect(guidance(today: .push, [day(1, nil, strain: 62)], low: true).kind == .recovery)
    }

    @Test func lightRestDayChangesNothing() {
        #expect(guidance(today: .push, [day(1, nil, strain: 18)]).kind == .training)
    }

    @Test func missedSessionMovesToTheNextFreeDay() {
        let result = guidance(today: nil, [day(1, .pull, strain: 8)])
        #expect(result.kind == .makeUp)
        #expect(result.focus == .pull)
        #expect(result.strainRange == StrainCalculator.targetStrain(forRecovery: 50, usualTrainingStrain: 65))
    }

    @Test func missedSessionWaitsWhenRecoveryIsLow() {
        #expect(guidance(today: nil, [day(1, .pull, strain: 8)], low: true).kind == .rest)
    }

    @Test func missedSessionNeverDoublesUpWithAPlannedOne() {
        let result = guidance(today: .legs, [day(1, .pull, strain: 8)])
        #expect(result.kind == .training)
        #expect(result.focus == .legs)
    }

    @Test func oldOrMadeUpMissesAreLeftAlone() {
        // Missed three days ago: too old to move.
        #expect(guidance(today: nil, [day(3, .pull, strain: 5), day(2, nil, strain: 10), day(1, nil, strain: 12)]).kind == .rest)
        // Missed two days ago, but trained yesterday (made up already).
        #expect(guidance(today: nil, [day(2, .pull, strain: 5), day(1, nil, strain: 30)]).kind == .rest)
    }
}
