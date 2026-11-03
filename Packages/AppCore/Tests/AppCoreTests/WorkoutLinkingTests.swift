import Foundation
import Testing
@testable import AppCore

struct WorkoutLinkingTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func interval(_ fromMinutes: Double, _ toMinutes: Double) -> DateInterval {
        DateInterval(start: start.addingTimeInterval(fromMinutes * 60), end: start.addingTimeInterval(toMinutes * 60))
    }

    func candidate(_ fromMinutes: Double, _ toMinutes: Double, source: String = "Apple Watch", strength: Bool = true) -> WorkoutLinking.Candidate {
        WorkoutLinking.Candidate(
            id: UUID(), start: start.addingTimeInterval(fromMinutes * 60), end: start.addingTimeInterval(toMinutes * 60),
            source: source, isStrength: strength
        )
    }

    @Test func overlapIsMeasuredAgainstTheShorterWorkout() {
        #expect(WorkoutLinking.overlapFraction(interval(0, 60), interval(30, 90)) == 0.5)
        #expect(WorkoutLinking.overlapFraction(interval(0, 60), interval(10, 30)) == 1)
        #expect(WorkoutLinking.overlapFraction(interval(0, 60), interval(60, 90)) == 0)
        #expect(WorkoutLinking.overlapFraction(interval(0, 0), interval(0, 30)) == 0)
    }

    @Test func halfOverlapMatches() {
        let watch = candidate(30, 90)
        #expect(WorkoutLinking.match(session: interval(0, 60), candidates: [watch])?.id == watch.id)
    }

    @Test func lessThanHalfDoesNot() {
        let walk = candidate(45, 90, strength: false)
        #expect(WorkoutLinking.match(session: interval(0, 60), candidates: [walk]) == nil)
    }

    @Test func picksTheLargestOverlap() {
        let early = candidate(0, 40, source: "Garmin Connect")
        let whole = candidate(5, 65, source: "Apple Watch")
        #expect(WorkoutLinking.match(session: interval(0, 60), candidates: [early, whole])?.source == "Apple Watch")
    }

    @Test func tieGoesToTheStrengthWorkout() {
        let walk = candidate(0, 60, source: "Apple Watch", strength: false)
        let lift = candidate(0, 60, source: "Garmin Connect", strength: true)
        #expect(WorkoutLinking.match(session: interval(0, 60), candidates: [walk, lift])?.source == "Garmin Connect")
    }

    @Test func summaryCarriesTheLink() {
        let id = UUID()
        let summary = StrengthSessionSummary(start: start, end: start.addingTimeInterval(3600), linkedWorkoutUUID: id, linkedWorkoutSource: "Apple Watch")
        #expect(summary.linkedWorkoutUUID == id)
        #expect(StrengthSessionSummary(start: start, end: start).linkedWorkoutUUID == nil)
    }
}
