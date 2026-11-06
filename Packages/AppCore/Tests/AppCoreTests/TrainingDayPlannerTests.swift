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
        // Missed two days ago, but trained yesterday (made up already). Strain 40:
        // a day without `trained` now needs `trainingDayStrain` (35, was 25).
        #expect(guidance(today: nil, [day(2, .pull, strain: 5), day(1, nil, strain: 40)]).kind == .rest)
    }

    func past(_ daysAgo: Int, _ focus: WorkoutFocus?, strain: Double, planKnown: Bool = true, trained: Bool? = nil) -> TrainingDayPlanner.PastDay {
        TrainingDayPlanner.PastDay(date: today.addingTimeInterval(Double(-daysAgo) * 86_400), plannedFocus: focus,
                                   strain: strain, planKnown: planKnown, trained: trained)
    }

    @Test func daysWithoutAFixedPlanAreNeitherRestNorMissed() {
        // Monday after a week with no plan (or a flexible one): a hard Sunday wasn't a rest day.
        let sunday = past(1, nil, strain: 70, planKnown: false, trained: true)
        #expect(sunday.wasRestDay == nil)
        #expect(guidance(today: .push, [sunday]).kind == .training)
        #expect(guidance(today: nil, [sunday]).kind == .rest)
        // A focus on an unknown-plan day can't be missed either.
        #expect(guidance(today: nil, [past(1, .pull, strain: 5, planKnown: false, trained: false)]).kind == .rest)
    }

    @Test func doneOrMissedComesFromLoggedSessionsNotStrain() {
        // A 20-minute lift logged on the planned day (strain about 23%): done, not missed.
        #expect(guidance(today: nil, [past(1, .push, strain: 23, trained: true)]).kind == .rest)
        // A long walk on the planned day (strain 30%, no session): still missed.
        let walk = guidance(today: nil, [past(1, .push, strain: 30, trained: false)])
        #expect(walk.kind == .makeUp)
        #expect(walk.focus == .push)
        // A logged session the day after a miss makes it up, however light.
        #expect(guidance(today: nil, [past(2, .pull, strain: 5, trained: false), past(1, nil, strain: 20, trained: true)]).kind == .rest)
    }

    @Test func watchOnlyDaysNeedAWorkoutAndEnoughStrain() {
        #expect(TrainingDayPlanner.isWatchTrainingDay(hadWorkout: true, strain: 40))
        #expect(!TrainingDayPlanner.isWatchTrainingDay(hadWorkout: true, strain: 28))
        #expect(!TrainingDayPlanner.isWatchTrainingDay(hadWorkout: false, strain: 60))
        // The training-day line sits above the rest-day range, not on its edge.
        #expect(TrainingDayPlanner.trainingDayStrain > TrainingDayPlanner.restDayRange.upperBound)
    }

    // MARK: Flexible weeks (a quota, any days)

    func flexible(target: Int = 4, done: Int, daysLeft: Int, trainedToday: Bool = false,
                  past: [TrainingDayPlanner.PastDay] = [], low: Bool = false) -> TrainingDayPlanner.Guidance {
        TrainingDayPlanner.flexibleGuidance(
            week: WeeklyPlan.Progress(target: target, done: done, daysLeft: daysLeft, trainedToday: trainedToday),
            nextFocus: .pull, past: past, lowRecovery: low, usualTrainingStrain: 65, calendar: calendar
        )
    }

    @Test func flexibleWeekTrainsWhenSessionsRemainAndRecoveryIsFine() {
        // Wednesday: 1 of 4 done, 5 days left, yesterday light.
        let result = flexible(done: 1, daysLeft: 5, past: [day(1, nil, strain: 12)])
        #expect(result.kind == .training)
        #expect(result.focus == .pull)
        #expect(result.strainRange == StrainCalculator.targetStrain(forRecovery: 50, usualTrainingStrain: 65))
        #expect(result.reason.contains("3 sessions to go"))
    }

    @Test func flexibleWeekRestsOnceTheQuotaIsMet() {
        let result = flexible(done: 4, daysLeft: 3)
        #expect(result.kind == .rest)
        #expect(result.isRestDay)
        #expect(result.title == "Week done")
        #expect(result.strainRange == TrainingDayPlanner.restDayRange)
        // Trained today and that made the quota: a training day, with the week closed.
        let last = flexible(done: 4, daysLeft: 3, trainedToday: true)
        #expect(last.kind == .training)
        #expect(last.reason.contains("rest days from here"))
    }

    @Test func flexibleWeekAsksForTrainingWhenEveryDayIsNeeded() {
        // Saturday: 2 of 4 done, 2 days left.
        let result = flexible(done: 2, daysLeft: 2, past: [day(1, nil, strain: 62)])
        #expect(result.kind == .training)
        #expect(result.reason.contains("train today to make the week"))
        // Never a "missed" label, whatever the state.
        for guidance in [result, flexible(done: 0, daysLeft: 1), flexible(done: 1, daysLeft: 4, low: true)] {
            #expect(!guidance.title.lowercased().contains("miss"))
            #expect(!guidance.reason.lowercased().contains("missed"))
        }
    }

    @Test func flexibleWeekGoesEasyOnLowRecovery() {
        // Room in the week: rest, even though sessions are "due".
        let rest = flexible(done: 1, daysLeft: 5, low: true)
        #expect(rest.kind == .rest)
        #expect(rest.strainRange == TrainingDayPlanner.restDayRange)
        // No room left: an easy session rather than a skip.
        let easy = flexible(done: 2, daysLeft: 2, low: true)
        #expect(easy.kind == .easyTraining)
        #expect(easy.focus == .pull)
        #expect(easy.strainRange.upperBound < StrainCalculator.targetStrain(forRecovery: 50, usualTrainingStrain: 65).lowerBound)
    }

    @Test func flexibleWeekSpacesSessionsAfterAHardDay() {
        // Hard day yesterday and slack in the week: a rest day is suggested, training allowed.
        let spaced = flexible(done: 1, daysLeft: 5, past: [day(1, nil, strain: 62)])
        #expect(spaced.kind == .rest)
        #expect(spaced.reason.contains("training today is fine too"))
        // Trained today: a training day whatever else.
        #expect(flexible(done: 2, daysLeft: 4, trainedToday: true).kind == .training)
    }
}
