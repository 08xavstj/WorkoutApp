import Foundation
import Testing
@testable import AppCore

/// A lift trained for weeks with sets logged the way the app records them:
/// the plan's rep goal on set 1, a 0-4+ "reps left" tap after every set, the
/// next set's goal from `RepGoal` (or one weight change from
/// `Autoregulation`), reps falling across sets, and the session read back
/// with `ExerciseHistory.sessionResult`. `LiftSimulation` logs the same reps
/// on every set, which is why it never caught a plan that stood still.
struct RealisticLogging {
    struct Lift: Sendable, CustomStringConvertible {
        var id: String
        var slot: MovementSlot
        /// True 1RM at the start, in the gym's unit.
        var oneRepMax: Double
        var description: String { id }
    }

    struct Session {
        var week: Int
        var deload: Bool
        var rpeTarget: Double
        var range: ClosedRange<Int>
        var plannedLoad: Double
        var plannedReps: Int
        /// Sets as logged: weight, reps and the RPE the reps-left tap stores.
        var sets: [ExerciseHistory.WorkingSet]
        /// True 1RM that day.
        var capability: Double
        var note: String?

        var firstSet: ExerciseHistory.WorkingSet { sets[0] }
        var topWeight: Double { sets.map(\.weight).max() ?? plannedLoad }
        var line: String {
            let done = sets.map { "\($0.weight.formatted())×\($0.reps)@\(($0.rpe ?? 0).formatted())" }.joined(separator: " ")
            return "w\(week)\(deload ? "D" : "") target RPE \(rpeTarget) \(range) plan \(plannedLoad.formatted())×\(plannedReps) | \(done) | 1RM \(String(format: "%.1f", capability)) | \(note ?? "-")"
        }
    }

    var gym: GymProfile = .commercialKilograms
    var style: TrainingStyle = .muscle
    var lift: Lift
    /// Reps lost per set already done.
    var fatigue = 0.5
    /// Strength gained per building session.
    var gain = 0.006
    var weeks = 12
    var sessionsPerWeek = 2

    func run() -> [Session] {
        let planner = WorkoutPlanner(gym: gym, style: style)
        let schedule = TrainingBlock.schedule(style: style)
        guard let choice = (ExerciseCatalog.options[lift.slot] ?? []).first(where: { $0.id == lift.id }) else { return [] }
        var history: [String: ExerciseHistory] = [:]
        var capability = lift.oneRepMax
        var sessions: [Session] = []
        for week in 0..<weeks {
            let block = schedule[week % schedule.count]
            for _ in 0..<sessionsPerWeek {
                var planned = planner.prescribe(choice, slot: lift.slot, minutes: 60, sessionRPE: block.targetRPE,
                                                history: history, position: 1)
                guard let kind = planned.loadKind else { return sessions }
                if planned.load == nil {
                    // "First time: pick a weight": one for the top of the range with a couple left.
                    planned.load = gym.load(atMost: capability / (1 + Double(planned.reps.upperBound + 2) / 30), on: kind)
                }
                guard var weight = planned.load else { return sessions }
                let targetRIR = 10 - planned.rpe
                var goal = planned.repsToday
                var loadChanged = false
                var sets: [ExerciseHistory.WorkingSet] = []
                for index in 0..<planned.sets {
                    let fresh = 30 * (capability / weight - 1)
                    let able = max(0, Int((fresh - fatigue * Double(index)).rounded(.down)))
                    let reps = min(goal, able)
                    let left = min(4, able - reps)
                    let rpe = ReserveText.rpe(repsLeft: left)
                    sets.append(.init(weight: weight, reps: reps, rpe: rpe))
                    guard index < planned.sets - 1, reps > 0 else { continue }
                    // `LiveSetCoach.autoregulate`: one weight change a session, else the rep goal.
                    if !loadChanged,
                       let change = Autoregulation.nextSet(after: .init(weight: weight, reps: reps, rpe: rpe), setNumber: index + 1,
                                                           targetRIR: targetRIR, alreadyAdjusted: false, kind: kind, gym: gym),
                       change.change != .hold {
                        loadChanged = true
                        switch change.change {
                        case .loadUp, .loadDown: weight = change.load
                        case .addReps, .trimReps: goal = change.reps
                        case .hold: break
                        }
                    } else {
                        goal = RepGoal.next(repsDone: reps, repsLeft: left, targetRIR: targetRIR, range: planned.reps)
                    }
                }
                sessions.append(Session(week: week + 1, deload: block.isDeload, rpeTarget: planned.rpe, range: planned.reps,
                                        plannedLoad: planned.load ?? weight, plannedReps: planned.repsToday, sets: sets,
                                        capability: capability, note: planned.progressionNote))
                if let done = ExerciseHistory.sessionResult(sets) {
                    let past = history[lift.id]
                    history[lift.id] = ExerciseHistory(
                        bestEstimatedOneRepMax: max(past?.bestEstimatedOneRepMax ?? 0, done.estimatedOneRepMax),
                        lastWeight: done.weight, lastReps: done.reps, lastRPE: done.rpe, lastDate: SimFixtures.monday,
                        recentWeights: ExerciseHistory.appending(done.weight, to: past?.recentWeights ?? []), lastSets: done.sets)
                }
                if !block.isDeload { capability *= 1 + gain }
            }
        }
        return sessions
    }

    static let lifts: [Lift] = [
        Lift(id: "Barbell_Bench_Press_-_Medium_Grip", slot: .horizontalPress, oneRepMax: 90),
        Lift(id: "Barbell_Squat", slot: .squat, oneRepMax: 130),
        Lift(id: "Wide-Grip_Lat_Pulldown", slot: .verticalPull, oneRepMax: 85),
        Lift(id: "Dumbbell_Bicep_Curl", slot: .biceps, oneRepMax: 22),
        Lift(id: "Dumbbell_Bench_Press", slot: .horizontalPress, oneRepMax: 45),
    ]
}

@Suite("Weights go up when sets are logged the way the app records them")
struct RealisticLoggingTests {
    static let cases: [(lift: RealisticLogging.Lift, style: TrainingStyle, fatigue: Double, gain: Double)] =
        RealisticLogging.lifts.flatMap { lift in
            [TrainingStyle.muscle, .strengthAndMuscle, .balanced].flatMap { style in
                [0.5, 1.0].flatMap { fatigue in
                    [0.004, 0.008].map { (lift, style, fatigue, $0) }
                }
            }
        }

    private func label(_ lift: RealisticLogging.Lift, _ style: TrainingStyle, _ fatigue: Double, _ gain: Double) -> String {
        "\(lift.id) \(style.rawValue) fatigue \(fatigue) gain \(gain)"
    }

    @Test("The weight keeps up with the lifter's strength over 12 weeks", arguments: cases)
    func theWeightKeepsUp(lift: RealisticLogging.Lift, style: TrainingStyle, fatigue: Double, gain: Double) throws {
        let sessions = RealisticLogging(style: style, lift: lift, fatigue: fatigue, gain: gain).run()
        let first = try #require(sessions.first)
        let last = try #require(sessions.last { !$0.deload })
        let strength = last.capability / first.capability - 1
        let load = last.topWeight / first.topWeight - 1
        let detail = Comment(rawValue: label(lift, style, fatigue, gain) + "\n" + sessions.map(\.line).joined(separator: "\n"))
        // At least half the strength gained shows up on the bar (a step may still be pending).
        #expect(load >= strength / 2 - 0.001, detail)
    }

    @Test("A plan the lifter finds easy doesn't repeat for weeks", arguments: cases)
    func easySessionsMoveThePlan(lift: RealisticLogging.Lift, style: TrainingStyle, fatigue: Double, gain: Double) {
        let sessions = RealisticLogging(style: style, lift: lift, fatigue: fatigue, gain: gain).run()
        // The fault this guards: 62.5 kg × 9 planned every session while the first set had 4+ left
        // and the later sets went to 11 reps.
        var run = 0
        var worst = 0
        for (previous, session) in zip(sessions, sessions.dropFirst()) where !session.deload && !previous.deload {
            let repeated = abs(session.plannedLoad - previous.plannedLoad) < 0.001 && session.plannedReps <= previous.plannedReps
            let easy = (previous.firstSet.rpe ?? 10) <= previous.rpeTarget - WorkoutPlanner.catchUpGap + 0.001
                && previous.firstSet.reps >= previous.range.lowerBound
            run = repeated && easy ? run + 1 : 0
            worst = max(worst, run)
        }
        let detail = Comment(rawValue: label(lift, style, fatigue, gain) + "\n" + sessions.map(\.line).joined(separator: "\n"))
        #expect(worst <= 1, detail)
    }

    @Test("A weight step doesn't leave the lifter failing under the rep range", arguments: cases)
    func stepsLandInTheRange(lift: RealisticLogging.Lift, style: TrainingStyle, fatigue: Double, gain: Double) {
        let sessions = RealisticLogging(style: style, lift: lift, fatigue: fatigue, gain: gain).run()
        // The fault this guards: 16 kg × 8 with 3 left → 18 kg, where 7 was the limit, for weeks.
        var run = 0
        var worst = 0
        for session in sessions.dropFirst() {
            let failedUnder = session.firstSet.reps < session.range.lowerBound && (session.firstSet.rpe ?? 0) >= 10 - 0.001
            run = failedUnder ? run + 1 : 0
            worst = max(worst, run)
        }
        let detail = Comment(rawValue: label(lift, style, fatigue, gain) + "\n" + sessions.map(\.line).joined(separator: "\n"))
        #expect(worst <= 1, detail)
    }
}

@Suite("What a session showed (ExerciseHistory.sessionResult)")
struct SessionResultTests {
    private func set(_ weight: Double, _ reps: Int, _ rpe: Double?) -> ExerciseHistory.WorkingSet {
        .init(weight: weight, reps: reps, rpe: rpe)
    }

    @Test("Reps and rating come from the same set, not the fewest reps with the hardest rating")
    func repsAndRatingStayTogether() throws {
        // Plan said 9; 4+ left, so the goal went to 11.
        let result = try #require(ExerciseHistory.sessionResult([set(62.5, 9, 6), set(62.5, 11, 8), set(62.5, 11, 9), set(62.5, 11, 9)]))
        #expect(result.weight == 62.5)
        #expect(result.reps == 11)
        #expect(result.rpe == 8)
        #expect(result.sets == 4)
    }

    @Test("The set that showed the most reps to failure stands for the session")
    func bestSetStands() throws {
        let result = try #require(ExerciseHistory.sessionResult([set(60, 10, 8), set(60, 9, 9), set(60, 8, 10)]))
        #expect(result.reps == 10)
        #expect(result.rpe == 8)
    }

    @Test("On a tie the set with more reps wins: its rating is the more accurate one")
    func tieGoesToMoreReps() throws {
        let result = try #require(ExerciseHistory.sessionResult([set(62.5, 9, 6), set(62.5, 12, 9)]))
        #expect(result.reps == 12)
        #expect(result.rpe == 9)
    }

    @Test("Without a rating on every set, every set has to reach the reps")
    func unratedSetsUseTheFewestReps() throws {
        let result = try #require(ExerciseHistory.sessionResult([set(60, 10, nil), set(60, 10, 9), set(60, 8, nil)]))
        #expect(result.reps == 8)
        #expect(result.rpe == 9)
        let none = try #require(ExerciseHistory.sessionResult([set(60, 10, nil), set(60, 9, nil)]))
        #expect(none.reps == 9)
        #expect(none.rpe == nil)
    }

    @Test("The top weight is the weight of the best set; lighter sets don't count toward its reps")
    func topWeightOnly() throws {
        let result = try #require(ExerciseHistory.sessionResult([set(100, 5, 8), set(100, 5, 9), set(80, 12, 9)]))
        #expect(result.weight == 100)
        #expect(result.reps == 5)
        #expect(result.rpe == 8)
        #expect(result.sets == 3)
    }

    @Test("Bodyweight sets: the best set by reps to failure")
    func bodyweight() throws {
        let result = try #require(ExerciseHistory.sessionResult([set(0, 8, 8), set(0, 8, 9), set(0, 6, 10)]))
        #expect(result.weight == 0)
        #expect(result.reps == 8)
        #expect(result.rpe == 8)
    }

    @Test("No completed reps: nothing to report")
    func empty() {
        #expect(ExerciseHistory.sessionResult([]) == nil)
        #expect(ExerciseHistory.sessionResult([set(60, 0, nil)]) == nil)
    }
}

@Suite("Progress after realistic sessions")
struct RealisticProgressionTests {
    private let planner = WorkoutPlanner(gym: .commercialKilograms, style: .muscle)

    private func history(_ weight: Double, _ reps: Int, _ rpe: Double) -> ExerciseHistory {
        ExerciseHistory(bestEstimatedOneRepMax: OneRepMax.estimate(weight: weight, reps: reps, rpe: rpe), lastWeight: weight,
                        lastReps: reps, lastRPE: rpe, lastDate: SimFixtures.monday, recentWeights: [weight, weight, weight], lastSets: 3)
    }

    @Test("Reps past the top of the range count toward the step: 12 with one left moves the weight up")
    func repsPastTheTopCount() throws {
        let next = try #require(planner.progression(history: history(62.5, 12, 9), reps: 6...10, rpe: 8.5, kind: .barbell))
        #expect(next.load == 65)
        #expect((6...10).contains(next.targetReps))
    }

    @Test("At the top of the range and over the effort target, the weight still waits")
    func atTheTopAndHarderWaits() throws {
        let next = try #require(planner.progression(history: history(62.5, 10, 9), reps: 6...10, rpe: 8.5, kind: .barbell))
        #expect(next.load == 62.5)
        #expect(next.targetReps == 10)
    }

    @Test("Equating only trades reps that are past the top")
    func equatingKeepsTheTop() {
        let equated = planner.effortEquated(history(62.5, 11, 10), reps: 6...10, rpe: 8.5, kind: .barbell)
        #expect(equated.lastReps == 11)
        #expect(equated.lastRPE == 10)
        let traded = planner.effortEquated(history(62.5, 12, 9), reps: 6...10, rpe: 8.5, kind: .barbell)
        #expect(traded.lastReps == 11)
        #expect(traded.lastRPE == 8)
    }

    @Test("An easy set with a counted reserve adds reps when the next dumbbell is too heavy for the range")
    func countedReserveDoesNotForceAStep() throws {
        // 16 kg × 8 with 3 left: about 11 to failure, so 18 kg would be about 7. Reps first.
        let next = try #require(planner.progression(history: history(16, 8, 7), reps: 8...12, rpe: 9.5, kind: .dumbbell, mode: .reps))
        #expect(next.load == 16)
        #expect(next.targetReps == 9)
    }

    @Test("\"4 or more left\" still moves the weight up a step")
    func fourOrMoreLeftSteps() throws {
        let next = try #require(planner.progression(history: history(62.5, 9, 6), reps: 6...10, rpe: 8.5, kind: .barbell))
        #expect(next.load > 62.5)
    }
}
