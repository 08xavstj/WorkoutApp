import Foundation
import Testing
@testable import AppCore

struct MuscleRecoveryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func benchSets(_ count: Int, hoursAgo: Double, rpe: Double = 8) -> [MuscleRecovery.WorkSet] {
        (0..<count).map { _ in
            MuscleRecovery.WorkSet(date: now.addingTimeInterval(-hoursAgo * 3600), primary: ["chest"], secondary: ["triceps", "shoulders"], rpe: rpe)
        }
    }

    @Test func hardSessionLeavesMuscleFatigued() throws {
        let states = MuscleRecovery.evaluate(sets: benchSets(10, hoursAgo: 0), now: now)
        let chest = try #require(states[.chest])
        #expect(abs(chest.recovery - 20) < 0.001)
        #expect(chest.status == .fatigued)
        #expect(chest.weeklySets == 10)
        #expect(chest.volume == .productive)
        // Helper muscles count half.
        #expect(states[.triceps]?.weeklySets == 5)
        #expect(states[.quadriceps]?.status == .fresh)
        #expect(states[.quadriceps]?.volume == MuscleRecovery.Volume.none)
    }

    @Test func recoversAfterAboutThreeDays() throws {
        let states = MuscleRecovery.evaluate(sets: benchSets(10, hoursAgo: 72), now: now)
        let chest = try #require(states[.chest])
        #expect(chest.status == .fresh)
        #expect(chest.hoursUntilFresh == nil)
    }

    @Test func tooMuchVolumeIsOverworked() throws {
        let sets = benchSets(12, hoursAgo: 4) + benchSets(12, hoursAgo: 52)
        let chest = try #require(MuscleRecovery.evaluate(sets: sets, now: now)[.chest])
        #expect(chest.volume == .high)
        #expect(chest.isOverworked)
        #expect((chest.hoursUntilFresh ?? 0) > 24)
    }

    @Test func tiredLegsSuggestUpperBody() {
        let squats = (0..<10).map { _ in MuscleRecovery.WorkSet(date: now.addingTimeInterval(-3600), primary: ["quadriceps", "glutes", "hamstrings"], rpe: 9) }
        #expect(MuscleRecovery.suggestedFocus(MuscleRecovery.evaluate(sets: squats, now: now)) == .upper)
    }

    @Test func runsTireTheLegs() throws {
        let run = MuscleRecovery.Cardio(kind: .run, end: now.addingTimeInterval(-1800), minutes: 60)
        let quads = try #require(MuscleRecovery.evaluate(sets: [], cardio: [run], now: now)[.quadriceps])
        #expect(quads.recovery < 100)
        #expect(quads.recovery > 60)
    }
}
