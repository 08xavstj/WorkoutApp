import Foundation
import Testing
@testable import AppCore

struct WatchLogMergeTests {
    typealias Logged = WatchLogMerge.LoggedSet
    typealias Exercise = WatchLogMerge.LoggedExercise

    let bench = Exercise(catalogID: "bench-press", name: "Bench press", sets: [
        Logged(reps: 10, weightKg: 40, isWarmup: true),
        Logged(reps: 8, weightKg: 80, rpe: 8),
        Logged(reps: 8, weightKg: 80, rpe: 9),
        Logged(reps: 8, weightKg: 80, isCompleted: false),
    ])
    let row = Exercise(catalogID: "cable-row", name: "Cable row", sets: [Logged(reps: 10, weightKg: 50, isCompleted: false)])

    @Test func onlyCompletedSetsCountAndEmptyExercisesGo() {
        let done = WatchLogMerge.completed([bench, row])
        #expect(done.count == 1)
        #expect(done[0].sets.count == 3)
        #expect(done[0].sets.allSatisfy { $0.isCompleted })
        #expect(WatchLogMerge.workingSetCount([bench, row]) == 2)
    }

    @Test func anExerciseWithNoCatalogIDGetsAStableID() {
        let custom = Exercise(catalogID: nil, name: "Landmine Press", sets: [])
        #expect(custom.storedID == "watch-landmine-press")
        #expect(bench.storedID == "bench-press")
    }

    @Test func fillsOpenSetsThenAddsTheRest() {
        let existing = [WatchLogMerge.ExistingExercise(catalogID: "bench-press", name: "Bench press", openSets: 2)]
        let actions = WatchLogMerge.merge([bench], into: existing)
        #expect(actions.count == 1)
        guard case let .merge(index, fill, extra) = actions[0] else {
            Issue.record("Expected a merge")
            return
        }
        #expect(index == 0)
        #expect(fill.count == 2)
        #expect(extra.count == 1)
        #expect(extra[0].rpe == 9)
    }

    @Test func matchesByNameWhenTheIDsDiffer() {
        let existing = [WatchLogMerge.ExistingExercise(catalogID: "bench-press-barbell", name: "bench press", openSets: 0)]
        let actions = WatchLogMerge.merge([bench], into: existing)
        guard case let .merge(_, fill, extra) = actions.first else {
            Issue.record("Expected a merge")
            return
        }
        #expect(fill.isEmpty)
        #expect(extra.count == 3)
    }

    @Test func addsAnExerciseThePhoneSessionDoesntHave() {
        let squat = Exercise(catalogID: "back-squat", name: "Back squat", sets: [Logged(reps: 5, weightKg: 100)])
        let existing = [WatchLogMerge.ExistingExercise(catalogID: "bench-press", name: "Bench press", openSets: 3)]
        let actions = WatchLogMerge.merge([squat, row], into: existing)
        #expect(actions == [.add(squat)])
    }

    @Test func eachPhoneExerciseIsUsedOnce() {
        let again = Exercise(catalogID: "bench-press", name: "Bench press", sets: [Logged(reps: 6, weightKg: 85)])
        let existing = [WatchLogMerge.ExistingExercise(catalogID: "bench-press", name: "Bench press", openSets: 3)]
        let actions = WatchLogMerge.merge([bench, again], into: existing)
        #expect(actions.count == 2)
        #expect(actions[1] == .add(again))
    }

    @Test func overlapFindsTheSameWorkout() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let recording = DateInterval(start: start, duration: 3600)
        let sessions = [
            DateInterval(start: start.addingTimeInterval(-7200), duration: 1800),
            DateInterval(start: start.addingTimeInterval(300), duration: 3000),
        ]
        #expect(WatchLogMerge.overlappingSession(for: recording, sessions: sessions) == 1)
        #expect(WatchLogMerge.overlappingSession(for: recording, sessions: [sessions[0]]) == nil)
    }
}
