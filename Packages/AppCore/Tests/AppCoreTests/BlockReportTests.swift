import Foundation
import Testing
@testable import AppCore

struct BlockReportTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Monday 5 January 2026, 00:00 UTC.
    private let start = Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!

    private func day(_ offset: Int, hour: Double = 18) -> Date {
        start.addingTimeInterval(Double(offset) * 86_400 + hour * 3_600)
    }

    private func set(_ weight: Double, _ reps: Int, rpe: Double? = nil, warmup: Bool = false, stage: Bool = false,
                     at date: Date) -> WorkoutSummary.LoggedSet {
        WorkoutSummary.LoggedSet(weightKg: weight, reps: reps, rpe: rpe, isWarmup: warmup, isStage: stage, completedAt: date)
    }

    private func session(_ date: Date, _ exercises: [(String, String, [WorkoutSummary.LoggedSet])]) -> WorkoutSummary.LoggedSession {
        WorkoutSummary.LoggedSession(
            name: "Workout", start: date, end: date.addingTimeInterval(3_600),
            exercises: exercises.map { WorkoutSummary.LoggedExercise(exerciseID: $0.0, name: $0.1, sets: $0.2) }
        )
    }

    private let benchID = "Barbell_Bench_Press_-_Medium_Grip"
    private let squatID = "Barbell_Squat"

    /// Five weeks, one session a week: bench 60 × 8 (weeks 1-2), 65 × 8
    /// (weeks 3-4), then a deload; squat 100 × 5 throughout.
    private func blockSessions(offsetDays: Int = 0, benchLate: Double = 65) -> [WorkoutSummary.LoggedSession] {
        (0..<5).map { week in
            let date = day(offsetDays + week * 7)
            let bench: Double = week == 4 ? 50 : (week < 2 ? 60 : benchLate)
            var benchSets = [set(bench, 8, at: date), set(bench, 8, at: date), set(bench, 8, at: date)]
            if week == 0 {
                // A heavy single as a warm-up and a drop stage: neither counts.
                benchSets.insert(set(100, 1, warmup: true, at: date), at: 0)
                benchSets.append(set(90, 3, stage: true, at: date))
            }
            return session(date, [
                (benchID, "Bench Press", benchSets),
                (squatID, "Back Squat", [set(100, 5, at: date), set(100, 5, at: date)]),
            ])
        }
    }

    private func weeks(done: [Int]) -> [WeekRecord] {
        done.enumerated().map { index, count in
            WeekRecord(weekStart: start.addingTimeInterval(Double(index) * 7 * 86_400), planned: 3, done: count)
        }
    }

    private func input(sessions: [WorkoutSummary.LoggedSession], done: [Int] = [3, 3, 3, 3, 2],
                       style: TrainingStyle = .balanced, muscles: [String: BlockReport.ExerciseMuscles] = [:],
                       previous: DateInterval? = nil, hrv: [DayValue] = []) -> BlockReport.Input {
        BlockReport.Input(
            number: 2, start: start, end: start.addingTimeInterval(35 * 86_400), length: 5, hadDeload: true,
            style: style, weeks: weeks(done: done), sessions: sessions, previous: previous, muscles: muscles,
            hrv: hrv
        )
    }

    @Test func countsSessionsWeeksKeptAndVolume() {
        let report = BlockReport.make(input(sessions: blockSessions()), calendar: Self.calendar)
        #expect(report.weeksRun == 5)
        #expect(report.sessionsDone == 14)
        #expect(report.sessionsPlanned == 15)
        // 2 of 3 is a kept week (`Consistency.sessionsNeeded`).
        #expect(report.weeksKept == 5)
        #expect(report.weeksPlanned == 5)
        // Bench: 2 × 1440 + 2 × 1560 + 1200, plus the 270 kg drop stage; squat 5 × 1000.
        let expected = 12_470.0
        #expect(abs(report.volumeKg - expected) < 0.001)
    }

    @Test func liftChangeComparesFirstAndLastWorkingWeeks() {
        let report = BlockReport.make(input(sessions: blockSessions()), calendar: Self.calendar)
        let bench = report.lifts.first { $0.exerciseID == benchID }
        // 60 × 8 → e1RM 76; 65 × 8 → 82.33. The warm-up single, the drop stage
        // and the deload's 50 kg don't count.
        #expect(bench.map { abs($0.start - 76) < 0.001 } == true)
        #expect(bench.map { abs($0.end - 65 * (1 + 8.0 / 30)) < 0.001 } == true)
        #expect(bench?.isStalled == false)
        #expect(bench?.points.count == 5)
        let squat = report.lifts.first { $0.exerciseID == squatID }
        #expect(squat?.change == 0)
        #expect(squat?.isStalled == true)
        // Top lifts first: bench, then squat.
        #expect(report.lifts.map(\.exerciseID) == [benchID, squatID])
    }

    @Test func stalledLiftSwapsOrChangesRepsByGoal() {
        let balanced = BlockReport.make(input(sessions: blockSessions(), muscles: [:]), calendar: Self.calendar)
        let swap = balanced.next.first { if case .swapExercise = $0.kind { true } else { false } }
        #expect(swap?.kind == .swapExercise(fromID: squatID, toID: "Leg_Press", toName: "Leg Press"))
        #expect(swap?.isAppChoice == true)

        let strength = BlockReport.make(input(sessions: blockSessions(), style: .strength), calendar: Self.calendar)
        #expect(strength.next.contains { $0.kind == .repRange(exerciseID: squatID, reps: 3...6) })

        // Gym alternatives without another option: a rep-range change instead.
        var noAlternative = input(sessions: blockSessions())
        noAlternative.alternatives = [squatID: [ExerciseCatalog.options[.squat]![0]]]
        let reps = BlockReport.make(noAlternative, calendar: Self.calendar)
        #expect(reps.next.contains { $0.kind == .repRange(exerciseID: squatID, reps: 8...12) })
    }

    @Test func musclesUnderTargetGetTwoMoreSets() {
        let muscles = [
            benchID: BlockReport.ExerciseMuscles(primary: ["chest"], secondary: ["triceps"]),
            squatID: BlockReport.ExerciseMuscles(primary: ["quadriceps"]),
        ]
        let report = BlockReport.make(input(sessions: blockSessions(), muscles: muscles), calendar: Self.calendar)
        let chest = report.muscles.first { $0.muscle == .chest }
        // 3 sets a week over the 4 working weeks; the drop stage adds a set's
        // credit in week 1 (one stage: 2 sets), the deload is left out: 13 / 4.
        #expect(chest.map { abs($0.averageSets - 13.0 / 4) < 0.001 } == true)
        #expect(chest?.target == 10...20)
        #expect(chest?.status == .under)
        #expect(report.next.contains { $0.kind == .addSets(.chest, sets: 2) })
        // Muscles under target: no general volume step on top.
        #expect(!report.next.contains { $0.kind == .volumeUp(sets: 1) })
    }

    @Test func blockTargetsSetTheBand() {
        var custom = input(sessions: blockSessions(), muscles: [benchID: .init(primary: ["chest"])])
        // Weekly targets average 13: the band is 11-13 (`VolumeProgression.Target.band`).
        custom.weeklyTargets = [[.chest: 12], [.chest: 14], [.chest: 12], [.chest: 14]]
        let report = BlockReport.make(custom, calendar: Self.calendar)
        #expect(report.muscles.first { $0.muscle == .chest }?.target == 11...13)
        // A muscle without targets keeps 10-20.
        #expect(report.muscles.first { $0.muscle == .lats }?.target == 10...20)
        #expect(BlockReport.target(for: .chest, weeklyTargets: [[.chest: 4]]) == 4...4)
    }

    @Test func adherenceDecidesTheVolumeStep() {
        let kept = BlockReport.make(input(sessions: blockSessions()), calendar: Self.calendar)
        #expect(kept.next.contains { $0.kind == .volumeUp(sets: 1) })

        let missed = BlockReport.make(input(sessions: blockSessions(), done: [3, 1, 0, 1, 0]), calendar: Self.calendar)
        #expect(missed.adherence < BlockReport.highAdherence)
        #expect(missed.next.contains { $0.kind == .holdVolume })
        #expect(!missed.next.contains { $0.kind == .volumeUp(sets: 1) })

        // Stamina goals keep steady weeks: no set changes.
        let endurance = BlockReport.make(input(sessions: blockSessions(), style: .endurance), calendar: Self.calendar)
        #expect(!endurance.next.contains { $0.kind == .volumeUp(sets: 1) })
    }

    @Test func fallingHRVHoldsVolume() {
        let hrv = (0..<35).map { DayValue(date: day($0, hour: 6), value: $0 < 7 ? 60 : ($0 >= 28 ? 50 : 55)) }
        let report = BlockReport.make(input(sessions: blockSessions(), hrv: hrv), calendar: Self.calendar)
        #expect(report.hrv?.start == 60)
        #expect(report.hrv?.end == 50)
        #expect(report.next.contains { $0.kind == .holdVolume })
        // Too little data: no trend.
        let sparse = BlockReport.make(input(sessions: blockSessions(), hrv: Array(hrv.prefix(3))), calendar: Self.calendar)
        #expect(sparse.hrv == nil)
    }

    @Test func volumeChangeIsPerWeekAgainstThePreviousBlock() {
        // The previous block: same five weeks, five weeks earlier, at half the work (one squat set fewer, no bench).
        let previous = (0..<5).map { week -> WorkoutSummary.LoggedSession in
            let date = day(-35 + week * 7)
            return session(date, [(squatID, "Back Squat", [set(100, 5, at: date)])])
        }
        let interval = DateInterval(start: start.addingTimeInterval(-35 * 86_400), duration: 35 * 86_400)
        let report = BlockReport.make(input(sessions: previous + blockSessions(), previous: interval), calendar: Self.calendar)
        let before = 5 * 500.0
        let after = report.volumeKg
        #expect(report.volumeChange.map { abs($0 - (after - before) / before) < 0.0001 } == true)
    }

    @Test func recordsInTheBlock() {
        let report = BlockReport.make(input(sessions: blockSessions()), calendar: Self.calendar)
        let bench = report.records.filter { $0.exerciseID == benchID }
        // Week 3's 65 × 8: e1RM, heaviest and volume records; nothing on week 1.
        #expect(bench.contains { $0.record == .estimatedOneRepMax(65 * (1 + 8.0 / 30)) })
        #expect(bench.contains { $0.record == .heaviest(weight: 65, reps: 8) })
        #expect(bench.allSatisfy { $0.date > day(0) })
    }

    @Test func shortBlocksShowNoLiftChange() {
        var short = input(sessions: Array(blockSessions().prefix(2)))
        short.end = start.addingTimeInterval(14 * 86_400)
        short.hadDeload = false
        let report = BlockReport.make(short, calendar: Self.calendar)
        #expect(report.weeksRun == 2)
        #expect(report.lifts.isEmpty)
    }

    @Test func shareTextNamesTheBlock() {
        let report = BlockReport.make(input(sessions: blockSessions()), calendar: Self.calendar)
        let text = BlockReport.shareText(report) { "\(Int($0.rounded())) kg" }
        #expect(text.hasPrefix("Block 2 · 5 of 5 weeks kept"))
        #expect(text.contains("Bench Press: 76 kg → 82 kg (+8.3%)"))
    }
}
