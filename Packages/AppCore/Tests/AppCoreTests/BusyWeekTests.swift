import Foundation
import Testing
@testable import AppCore

// The planned busy week (`BusyWeek`): the plan, the block pause, the volume
// targets, the consistency score, and multi-week simulations of the trainer
// with busy weeks in them (normal, busy, normal; three busy weeks in a row;
// a busy week in the deload week; a busy week with a session missed).

private let calendar = SimFixtures.calendar
private let monday = SimFixtures.monday

private func day(_ offset: Int, hour: Int = 18) -> Date {
    calendar.date(byAdding: .day, value: offset, to: monday)!.addingTimeInterval(Double(hour) * 3600)
}

private func week(_ index: Int) -> Date { calendar.date(byAdding: .day, value: 7 * index, to: monday)! }

/// Mon upper, Tue lower, Thu upper, Fri lower at 6 pm, 60 minutes.
private func standingPlan(weekStart: Date, flexible: Bool = false) -> WeeklyPlan {
    let days = [(2, WorkoutFocus.upper), (3, .lower), (5, .upper), (6, .lower)].map {
        PlannedDay(weekday: $0.0, time: 18 * 60, focus: $0.1, minutes: 60, ifThen: "If I'm late, the 15-minute version")
    }
    return WeeklyPlan(weekStart: weekStart, plannedDays: days, mode: flexible ? .flexible : .fixedDays,
                      sessionsPerWeek: flexible ? 4 : nil, cardio: EasyCardio(sessionsPerWeek: 1, kind: .bike))
}

@Suite("Busy week: the plan")
struct BusyWeekPlanTests {
    @Test func twoSessionsTakeTheFirstAndLastDaysAsShortFullBody() {
        let plan = BusyWeek.plan(from: standingPlan(weekStart: monday), sessions: 2)
        #expect(plan.isBusy)
        #expect(plan.sortedDays.map(\.weekday) == [2, 6])
        #expect(plan.plannedDays.allSatisfy { $0.focus == .fullBody && $0.minutes == BusyWeek.sessionMinutes })
        #expect(plan.plannedDays.allSatisfy { $0.time == 18 * 60 })
        #expect(plan.cardio == nil)
        #expect(plan.sessionTarget == 2)
    }

    @Test func oneSessionTakesAMiddleDay() {
        let plan = BusyWeek.plan(from: standingPlan(weekStart: monday), sessions: 1)
        #expect(plan.plannedDays.count == 1)
        #expect(plan.plannedDays[0].weekday == 5)
    }

    @Test func sessionCountIsKeptToOneOrTwo() {
        #expect(BusyWeek.plan(from: standingPlan(weekStart: monday), sessions: 7).plannedDays.count == 2)
        #expect(BusyWeek.plan(from: standingPlan(weekStart: monday), sessions: 0).plannedDays.count == 1)
    }

    @Test func restoredGivesTheStandingWeekBack() {
        let standing = standingPlan(weekStart: monday)
        let busy = BusyWeek.plan(from: standing, sessions: 2)
        let back = BusyWeek.restored(busy)
        #expect(back.sortedDays == standing.sortedDays)
        #expect(back.cardio == standing.cardio)
        #expect(!back.isBusy)
        // Changing the count works from the standing week, not the busy days.
        let one = BusyWeek.plan(from: busy, sessions: 1)
        #expect(one.busy?.standingDays == standing.sortedDays)
    }

    @Test func flexibleWeekAsksForThatManyOnAnyDays() {
        let plan = BusyWeek.plan(from: standingPlan(weekStart: monday, flexible: true), sessions: 2)
        #expect(plan.isFlexible)
        #expect(plan.sessionTarget == 2)
        #expect(BusyWeek.restored(plan).sessionTarget == 4)
    }

    @Test func savedPlansRoundTripAndOldPlansDecodeAsNormal() throws {
        let busy = BusyWeek.plan(from: standingPlan(weekStart: monday), sessions: 2)
        let data = try JSONEncoder().encode(busy)
        #expect(try JSONDecoder().decode(WeeklyPlan.self, from: data) == busy)
        let old = try JSONEncoder().encode(standingPlan(weekStart: monday))
        #expect(try JSONDecoder().decode(WeeklyPlan.self, from: old).busy == nil)
    }

    @Test func busyWeekLeavesNothingOver() {
        let busy = BusyWeek.plan(from: standingPlan(weekStart: monday), sessions: 2)
        #expect(AdaptiveWeek.leftOver(plan: busy, done: [], calendar: calendar).isEmpty)
    }

    @Test func wordsSayWhatItDoes() {
        #expect(BusyWeek.headline == "Holds what you have; does not build.")
        #expect(BusyWeek.summary(sessions: 2).contains("does not build"))
        #expect(BusyWeek.evidence(age: 65).contains("60-75"))
        #expect(!BusyWeek.evidence(age: 35).contains("60-75"))
    }

    @Test func reviewAsksAfterThreeInARow() {
        let plans = (0..<4).map { BusyWeek.plan(from: standingPlan(weekStart: week($0)), sessions: 1) }
        #expect(BusyWeek.reviewQuestion(plans: Array(plans.prefix(2)), thisWeek: week(2), calendar: calendar) == nil)
        let three = BusyWeek.reviewQuestion(plans: Array(plans.prefix(3)), thisWeek: week(3), calendar: calendar)
        #expect(three?.hasPrefix("Three busy weeks") == true)
        #expect(three?.contains("Build again") == true)
        // A normal week in between starts the count again.
        var mixed = plans
        mixed[1] = standingPlan(weekStart: week(1))
        #expect(BusyWeek.reviewQuestion(plans: mixed, thisWeek: week(4), calendar: calendar) == nil)
    }

    @Test func weeklySetsAreAboutAThirdAndAtLeastTwo() {
        #expect(BusyWeek.weeklySets(usual: 15) == 5)
        #expect(BusyWeek.weeklySets(usual: 12) == 4)
        #expect(BusyWeek.weeklySets(usual: 3) == 2)
        #expect(BusyWeek.weeklySets(usual: 0) == 2)
    }

    @Test func lastSeenCountsABusyWeekThroughItsEnd() {
        let busy = BusyWeek.plan(from: standingPlan(weekStart: week(0)), sessions: 1)
        // Trained on Thursday of the busy week; the Monday a week later is only a day after its end.
        let seen = BusyWeek.lastSeen(lastTrained: day(3), plans: [busy], now: day(14), calendar: calendar)
        #expect(seen == calendar.startOfDay(for: day(6)))
        // Inside the busy week it is today.
        #expect(BusyWeek.lastSeen(lastTrained: day(0), plans: [busy], now: day(5), calendar: calendar) == calendar.startOfDay(for: day(5)))
        #expect(BusyWeek.lastSeen(lastTrained: day(0), plans: [], now: day(5), calendar: calendar) == calendar.startOfDay(for: day(0)))
    }
}

@Suite("Busy week: block, volume and consistency")
struct BusyWeekBlockTests {
    @Test func busyWeekPausesTheBlockAndTheNextWeekResumes() {
        var block = TrainingBlock(start: week(0), style: .muscle)
        block = block.advanced(to: day(7), calendar: calendar)          // week 2
        #expect(block.week.week == 2)
        block = block.advanced(to: day(14), busy: true, calendar: calendar)
        #expect(block.week.isBusy)
        #expect(block.week.week == 3)
        #expect(block.week.label == "Busy week")
        #expect(block.week.targetRIR <= BusyWeek.maximumRIR)
        block = block.advanced(to: day(21), calendar: calendar)
        #expect(!block.week.isBusy)
        #expect(block.week.week == 3)
        #expect(block.start == week(0))
        #expect(block.heldWeeks == 1)
    }

    @Test func busyWeekInTheDeloadWeekIsTheBlocksEasyWeek() {
        var block = TrainingBlock(start: week(0), style: .strength)   // 5 weeks, deload in week 5
        for index in 1..<4 { block = block.advanced(to: day(7 * index), calendar: calendar) }
        #expect(block.week.week == 4)
        block = block.advanced(to: day(28), busy: true, calendar: calendar)
        #expect(block.week.isBusy && !block.week.isDeload)
        #expect(block.week.week == 5)
        // The usual weights: the building week's effort, not the deload's.
        #expect(block.week.targetRIR <= BusyWeek.maximumRIR)
        block = block.advanced(to: day(35), calendar: calendar)
        #expect(block.start == week(5))
        #expect(block.week.week == 1)
    }

    @Test func busyWeekNeverRestartsTheBlockAsTimeAway() {
        var block = TrainingBlock(start: week(0), style: .muscle)
        block = block.advanced(to: day(7), calendar: calendar)
        for index in 2...5 { block = block.advanced(to: day(7 * index), busy: true, calendar: calendar) }
        #expect(block.start == week(0))
        block = block.advanced(to: day(42), calendar: calendar)
        #expect(block.start == week(0))
        #expect(block.week.week == 3)
    }

    @Test func settingBusyMidWeekAndBack() {
        var block = TrainingBlock(start: week(0), style: .muscle)
        block = block.advanced(to: day(7), calendar: calendar)
        let busy = block.settingBusy(true)
        #expect(busy.week.isBusy && busy.week.week == 2)
        #expect(busy.settingBusy(false).week == block.week)
    }

    @Test func hrvHoldDoesNotStackOnABusyWeek() {
        var block = TrainingBlock(start: week(0), style: .muscle)
        block = block.advanced(to: day(7), hrvBelowNormal: true, busy: true, calendar: calendar)
        #expect(block.week.isBusy && !block.week.isHeld)
    }

    @Test func volumeTargetsDropToAThirdAndComeBack() {
        let days = standingPlan(weekStart: week(0)).plannedDays
        let w2 = TrainingBlock.weekState(2, style: .muscle, length: 6)
        let normal = VolumeProgression.week(weekStart: week(1), block: w2, style: .muscle, days: days,
                                            previous: nil, lastWeek: [:], states: [:], gym: .commercialKilograms)
        #expect(!normal.targets.isEmpty)
        var block = TrainingBlock(start: week(0), style: .muscle)
        block = block.advanced(to: day(7), calendar: calendar).settingBusy(true)
        let busy = VolumeProgression.week(weekStart: week(2), block: block.week, style: .muscle, days: days,
                                          previous: normal, lastWeek: [:], states: [:], gym: .commercialKilograms)
        for target in busy.targets {
            let usual = normal.target(for: target.muscle)!.sets
            #expect(target.change == .busyWeek)
            #expect(target.previous == usual)
            #expect(target.sets == BusyWeek.weeklySets(usual: usual))
        }
        #expect(busy.notable.isEmpty)
        // The week after: back where it was, not stepped up or cut for the sets the busy week skipped.
        let w3 = TrainingBlock.weekState(3, style: .muscle, length: 6)
        let after = VolumeProgression.week(weekStart: week(3), block: w3, style: .muscle, days: days,
                                           previous: busy, lastWeek: [:], states: [:], gym: .commercialKilograms)
        for target in after.targets {
            guard let before = normal.target(for: target.muscle) else { continue }
            #expect(target.sets == before.sets, "\(target.muscle): \(target.sets) after, \(before.sets) before")
            #expect(target.change == .afterBusyWeek || target.change == .cappedTime || target.change == .cappedCeiling)
        }
    }

    @Test func consistencyCountsABusyWeekAsKeptFromItsFirstSession() {
        let records = [
            WeekRecord(weekStart: week(0), planned: 4, done: 4),
            WeekRecord(weekStart: week(1), planned: 2, done: 1, busy: true),
            WeekRecord(weekStart: week(2), planned: 4, done: 3),
        ]
        let result = Consistency.score(records: records, now: day(22), calendar: calendar)
        #expect(result.keptWeeks == 3)
        #expect(result.plannedWeeks == 3)
        #expect(result.note == nil)
    }

    @Test func aBusyWeekWithNoSessionIsLeftOutNotHeldAgainst() {
        let records = [
            WeekRecord(weekStart: week(0), planned: 4, done: 4),
            WeekRecord(weekStart: week(1), planned: 1, done: 0, busy: true),
        ]
        let result = Consistency.score(records: records, now: day(15), calendar: calendar)
        #expect(result.keptWeeks == 1)
        #expect(result.plannedWeeks == 1)
        #expect(result.note == nil)
        #expect(Consistency.weeksTrainingAtLeast(2, records: records + [WeekRecord(weekStart: week(2), planned: 4, done: 4)],
                                                 now: day(22), calendar: calendar) == 2)
    }

    @Test func deloadAdvisorIgnoresBusyWeekSessions() {
        // Three lifts flat for four weeks: a stall. Inside the busy week the points are left out.
        var lifts: [DeloadAdvisor.LiftPoint] = []
        for offset in stride(from: 0, to: 28, by: 2) {
            for name in ["Squat", "Bench", "Row"] {
                lifts.append(.init(exercise: name, date: day(offset), estimatedOneRepMax: 100))
            }
        }
        let now = day(28)
        #expect(DeloadAdvisor.evaluate(lifts, hrvBelowNormal: false, now: now) != nil)
        let busyWeeks = [week(2), week(3)]
        #expect(DeloadAdvisor.evaluate(lifts, hrvBelowNormal: false, now: now, busyWeeks: busyWeeks) == nil)
    }
}

@Suite("First session back")
struct FirstSessionBackTests {
    let plan = standingPlan(weekStart: week(0))

    @Test func theFirstSessionEverIsAStartNotAReturn() {
        #expect(!FirstSessionBack.applies(sessionDay: day(0), earlierTrainingDays: [], plans: [plan], calendar: calendar))
    }

    @Test func afterAMissedPlannedSession() {
        // Mon done, Tue missed, Thu trained.
        #expect(FirstSessionBack.applies(sessionDay: day(3), earlierTrainingDays: [day(0)], plans: [plan], calendar: calendar))
        // Mon and Tue done: Thursday is on plan.
        #expect(!FirstSessionBack.applies(sessionDay: day(3), earlierTrainingDays: [day(0), day(1)], plans: [plan], calendar: calendar))
    }

    @Test func afterSevenDaysOff() {
        #expect(FirstSessionBack.applies(sessionDay: day(10), earlierTrainingDays: [day(3)], plans: [], calendar: calendar))
        #expect(!FirstSessionBack.applies(sessionDay: day(9), earlierTrainingDays: [day(3)], plans: [], calendar: calendar))
    }

    @Test func aPlannedBusyWeekIsNotTimeAway() {
        var busy = BusyWeek.plan(from: standingPlan(weekStart: week(1)), sessions: 1)
        busy.weekStart = week(1)
        // Last week's Friday, then the busy week's one session (Thursday), then next Monday.
        let earlier = [day(4), day(10)]
        #expect(!FirstSessionBack.applies(sessionDay: day(14), earlierTrainingDays: earlier,
                                          plans: [plan, busy, standingPlan(weekStart: week(2))], calendar: calendar))
    }

    @Test func theLineNeverSaysWhatWasMissed() {
        var facts = CoachCheckIns.PostWorkoutFacts(name: "Upper", minutes: 50, workingSets: 16)
        facts.firstSessionBack = true
        let text = CoachCheckIns.postWorkout(facts)?.body ?? ""
        #expect(text.hasPrefix(FirstSessionBack.lead))
        for word in ["missed", "skipped", "days off", "since"] { #expect(!text.lowercased().contains(word)) }
    }
}

// MARK: - Multi-week simulation

/// The app's weekly loop with a simulated lifter: plan the week (normal or
/// busy), advance the block, set the volume targets, plan each session with
/// the trainer (busy sessions cut down by `BusyWeek.session`), do it at the
/// planned load and reps, log it, and keep the week's record.
private struct BusySimulation {
    enum Week: Equatable { case normal, busy(sessions: Int, missed: Int = 0) }

    var weeks: [Week]
    var style: TrainingStyle = .muscle
    var gym: GymProfile = .commercialKilograms
    /// Start the run this many weeks into the block (to put a busy week on the deload).
    var leadIn = 0

    struct WeekResult {
        var plan: WeeklyPlan
        var block: TrainingBlock
        var targets: VolumeProgression.WeekTargets
        var sessions: [PlannedWorkout]
        var record: WeekRecord
    }

    struct Output {
        var weeks: [WeekResult] = []
        var problems: [String] = []
        /// Planned load per compound lift, per week index.
        var loads: [String: [Int: Double]] = [:]
        var trainingDays: [Date] = []
        var plans: [WeeklyPlan] { weeks.map(\.plan) }
    }

    func run() -> Output {
        var output = Output()
        let planner = WorkoutPlanner(gym: gym, style: style)
        var history: [String: ExerciseHistory] = [:]
        var logged: [VolumeProgression.LoggedSet] = []
        var previousTargets: VolumeProgression.WeekTargets?
        var block: TrainingBlock?
        let all: [Week] = Array(repeating: .normal, count: leadIn) + weeks

        for (index, kind) in all.enumerated() {
            let weekStart = week(index)
            var plan = standingPlan(weekStart: weekStart)
            var missed = 0
            if case .busy(let sessions, let skip) = kind {
                plan = BusyWeek.plan(from: plan, sessions: sessions)
                missed = skip
            }
            let now = weekStart.addingTimeInterval(3600)
            let current = block.map { $0.advanced(to: now, busy: plan.isBusy, calendar: calendar) }
                ?? TrainingBlock(start: weekStart, style: style)
            block = current
            let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart)!
            let lastWeek = VolumeProgression.summarize(logged, weekStart: lastWeekStart, targetRPE: previousTargets?.targetRPE ?? 7,
                                                       style: style, calendar: calendar)
            let targets = VolumeProgression.week(weekStart: weekStart, block: current.week, style: style,
                                                 days: BusyWeek.restored(plan).plannedDays, previous: previousTargets,
                                                 lastWeek: lastWeek, states: [:], gym: gym)
            previousTargets = targets

            var workouts: [PlannedWorkout] = []
            var doneDays: [Date] = []
            let days = plan.sortedDays
            for (position, planned) in days.enumerated() {
                if position >= days.count - missed { continue }
                let start = calendar.date(byAdding: .day, value: WeeklyPlan.order(planned.weekday), to: weekStart)!
                    .addingTimeInterval(Double(planned.time) * 60)
                var workout: PlannedWorkout
                if plan.isBusy {
                    let full = planner.plan(focus: planned.focus, minutes: BusyWeek.planningMinutes, recovery: 80, history: history,
                                            block: current.week, bodyMassKg: 80, trainingStatus: .intermediate)
                    workout = BusyWeek.session(from: full, minutes: planned.minutes, planner: planner)
                } else {
                    let done = VolumeProgression.summarize(logged, weekStart: weekStart, targetRPE: targets.targetRPE, style: style,
                                                           calendar: calendar).mapValues(\.sets)
                    let goals = VolumeProgression.sessionGoals(targets: targets, doneThisWeek: done, focus: planned.focus,
                                                               minutes: planned.minutes, laterSessions: Array(days.dropFirst(position + 1)),
                                                               gym: gym)
                    workout = planner.plan(focus: planned.focus, minutes: planned.minutes, recovery: 80, history: history,
                                           block: current.week, bodyMassKg: 80, trainingStatus: .intermediate, muscleSetGoals: goals)
                }
                workouts.append(workout)
                doneDays.append(start)
                // The lifter does the planned reps at the planned load, at the planned effort.
                for (order, exercise) in workout.exercises.enumerated() {
                    guard let slot = ExerciseCatalog.slot(for: exercise.exerciseID) else { continue }
                    let muscles = MuscleCoverage.muscles(for: slot)
                    let load = exercise.load ?? (exercise.loadKind.flatMap { gym.load(atMost: 40, on: $0) } ?? 0)
                    if slot.isCompound, exercise.load != nil {
                        output.loads[exercise.exerciseID, default: [:]][index] = max(output.loads[exercise.exerciseID]?[index] ?? 0, load)
                    }
                    for set in 0..<exercise.sets {
                        logged.append(VolumeProgression.LoggedSet(
                            exerciseID: exercise.exerciseID, name: exercise.name, sessionStart: start, order: order * 10 + set,
                            primary: [muscles.primary], secondary: muscles.secondary, weightKg: gym.unit.toKilograms(load),
                            reps: exercise.repsToday, rpe: exercise.rpe, isCompound: slot.isCompound,
                            supersetGroup: exercise.supersetGroup))
                    }
                    let past = history[exercise.exerciseID]
                    let e1RM = OneRepMax.estimate(weight: load, reps: exercise.repsToday, rpe: exercise.rpe)
                    history[exercise.exerciseID] = ExerciseHistory(
                        bestEstimatedOneRepMax: max(past?.bestEstimatedOneRepMax ?? 0, e1RM), lastWeight: load,
                        lastReps: exercise.repsToday, lastRPE: exercise.rpe, lastDate: start,
                        recentWeights: ExerciseHistory.appending(load, to: past?.recentWeights ?? []), lastSets: exercise.sets)
                }
            }
            output.trainingDays += doneDays
            let record = WeekRecord.make(plan: plan, trainingDays: doneDays, calendar: calendar)
            output.weeks.append(WeekResult(plan: plan, block: current, targets: targets, sessions: workouts, record: record))
        }
        output.weeks.removeFirst(leadIn)
        for key in output.loads.keys {
            output.loads[key] = Dictionary(uniqueKeysWithValues: output.loads[key]!.compactMap { $0.key >= leadIn ? ($0.key - leadIn, $0.value) : nil })
        }
        return output
    }

    /// Invariants every run must keep; returns what broke.
    static func check(_ output: Output, gym: GymProfile = .commercialKilograms) -> [String] {
        var problems: [String] = []
        let compoundIDs = Set(output.loads.keys)
        for (index, result) in output.weeks.enumerated() {
            let label = "week \(index + 1)\(result.plan.isBusy ? " (busy)" : "")"
            if result.plan.isBusy {
                if !result.block.week.isBusy { problems.append("\(label): block not marked busy") }
                if !result.record.isBusy { problems.append("\(label): record not marked busy") }
                for workout in result.sessions {
                    if workout.exercises.isEmpty { problems.append("\(label): empty busy session") }
                    for exercise in workout.exercises {
                        if !(BusyWeek.minimumSetsPerLift...BusyWeek.setsPerLift).contains(exercise.sets) {
                            problems.append("\(label): \(exercise.name) has \(exercise.sets) sets")
                        }
                        if ExerciseCatalog.slot(for: exercise.exerciseID)?.isCompound != true {
                            problems.append("\(label): \(exercise.name) is not a main lift")
                        }
                        // Only loads the gym can make (CLAUDE.md: the trainer plans only what the gym supports).
                        if let load = exercise.load, let kind = exercise.loadKind,
                           !gym.achievableLoads(for: kind).contains(where: { abs($0 - load) < 0.001 }) {
                            problems.append("\(label): \(exercise.name) at \(load), which the gym can't load")
                        }
                    }
                    if let estimate = workout.estimatedMinutes, estimate > BusyWeek.sessionMinutes + 8 {
                        problems.append("\(label): busy session estimated at \(estimate) min")
                    }
                }
                // About a third of the usual weekly sets, never more than half.
                if let usual = output.weeks.prefix(index).last(where: { !$0.plan.isBusy }) {
                    let busySets = result.sessions.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
                    let normalSets = usual.sessions.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
                    if Double(busySets) > Double(normalSets) * 0.5 {
                        problems.append("\(label): \(busySets) sets against \(normalSets) in a normal week")
                    }
                }
                // The usual weights: every main lift at least what it was last time it was done.
                for id in compoundIDs {
                    guard let now = output.loads[id]?[index],
                          let before = (0..<index).reversed().compactMap({ output.loads[id]?[$0] }).first else { continue }
                    if now < before * 0.95 - 0.001 { problems.append("\(label): \(id) at \(now), down from \(before)") }
                }
            } else if index > 0, output.weeks[index - 1].plan.isBusy {
                // The week after a busy week picks up where the lifter was: no regression, no restart.
                for id in compoundIDs {
                    guard let now = output.loads[id]?[index],
                          let before = (0..<index).reversed().compactMap({ output.loads[id]?[$0] }).first else { continue }
                    // After a busy week that stood in for the deload, a new block starts at week 1's
                    // effort (three reps in reserve), a little lighter, exactly as after a deload.
                    let newBlock = result.block.start != output.weeks[index - 1].block.start
                    let floor = newBlock ? before * 0.9 : before
                    if now < floor - 0.001 { problems.append("\(label): \(id) at \(now) after the busy week, down from \(before)") }
                }
                for target in result.targets.targets where target.change == .start {
                    if output.weeks[index - 1].block.start == result.block.start {
                        problems.append("\(label): \(target.muscle.name) started over at week-1 sets")
                    }
                }
            }
            if result.record.done > 0, !Consistency.weekKept(planned: result.record.planned, done: result.record.done), result.plan.isBusy {
                problems.append("\(label): a busy week with \(result.record.done) sessions isn't kept")
            }
        }
        // The deload advisor and the restart card stay quiet.
        var points: [DeloadAdvisor.LiftPoint] = []
        for result in output.weeks {
            for (offset, workout) in result.sessions.enumerated() {
                let date = result.plan.weekStart.addingTimeInterval(Double(offset * 2 + 1) * 86_400)
                for exercise in workout.exercises where exercise.load != nil {
                    points.append(.init(exercise: exercise.name, date: date,
                                        estimatedOneRepMax: OneRepMax.estimate(weight: exercise.load!, reps: exercise.repsToday, rpe: exercise.rpe)))
                }
            }
        }
        let end = output.weeks.last.map { $0.plan.weekStart.addingTimeInterval(7 * 86_400) } ?? monday
        let busyWeeks = output.weeks.filter(\.plan.isBusy).map(\.plan.weekStart)
        if let advice = DeloadAdvisor.evaluate(points, hrvBelowNormal: false, now: end, busyWeeks: busyWeeks), advice.strong {
            problems.append("deload advised after busy weeks: \(advice.stalledLifts)")
        }
        for result in output.weeks {
            let monday = result.plan.weekStart.addingTimeInterval(12 * 3600)
            let last = output.trainingDays.filter { $0 < monday }.max()
            let seen = BusyWeek.lastSeen(lastTrained: last, plans: output.plans, now: monday, calendar: calendar)
            if let days = RestartPlan.daysOff(lastTrained: seen, now: monday, calendar: calendar),
               RestartPlan.make(daysOff: days, lastPlan: result.plan) != nil {
                problems.append("week starting \(result.plan.weekStart): restart card after \(days) days")
            }
        }
        return problems
    }
}

@Suite("Busy week: multi-week simulations")
struct BusyWeekSimulationTests {
    @Test(arguments: [TrainingStyle.muscle, .strength, .strengthAndMuscle])
    func normalBusyNormal(_ style: TrainingStyle) {
        let sim = BusySimulation(weeks: [.normal, .normal, .busy(sessions: 2), .normal, .normal], style: style)
        let output = sim.run()
        let problems = BusySimulation.check(output)
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
        // The block paused: the week after the busy week is the one that would have come.
        #expect(output.weeks[2].block.week.week == 3)
        #expect(output.weeks[3].block.week.week == 3 && !output.weeks[3].block.week.isBusy)
        #expect(output.weeks[3].targets.targets.allSatisfy { $0.change == .afterBusyWeek || $0.change == .cappedTime || $0.change == .cappedCeiling })
        let score = Consistency.score(records: output.weeks.map(\.record), now: week(4).addingTimeInterval(6 * 86_400), calendar: calendar)
        #expect(score.keptWeeks == score.plannedWeeks)
    }

    @Test func threeBusyWeeksInARow() {
        let sim = BusySimulation(weeks: [.normal, .busy(sessions: 2), .busy(sessions: 1), .busy(sessions: 2), .normal])
        let output = sim.run()
        let problems = BusySimulation.check(output)
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
        #expect(output.weeks[1...3].allSatisfy { $0.block.week.week == 2 })
        #expect(output.weeks[4].block.week.week == 2)
        #expect(output.weeks[4].block.start == output.weeks[0].block.start)
        // The review asks once three busy weeks have run.
        #expect(BusyWeek.reviewQuestion(plans: output.plans, thisWeek: week(3), calendar: calendar) == nil)
        #expect(BusyWeek.reviewQuestion(plans: output.plans, thisWeek: week(4), calendar: calendar) != nil)
    }

    @Test func busyWeekInTheDeloadWeek() {
        // Strength: five-week block, deload in week 5. Four normal weeks, then the busy week on the deload.
        let sim = BusySimulation(weeks: [.busy(sessions: 2), .normal, .normal], style: .strength, leadIn: 4)
        let output = sim.run()
        let problems = BusySimulation.check(output)
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
        #expect(output.weeks[0].block.week.isBusy && output.weeks[0].block.week.week == 5)
        // It was the block's easy week: a new block starts, with no second deload.
        #expect(output.weeks[1].block.week.week == 1)
        #expect(output.weeks[1].block.start == week(5))
        #expect(!output.weeks[1].block.week.isDeload && !output.weeks[2].block.week.isDeload)
    }

    @Test func busyWeekWithASessionMissed() {
        let sim = BusySimulation(weeks: [.normal, .busy(sessions: 2, missed: 1), .normal])
        let output = sim.run()
        let problems = BusySimulation.check(output)
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
        #expect(output.weeks[1].record.done == 1)
        #expect(Consistency.weekKept(planned: output.weeks[1].record.planned, done: output.weeks[1].record.done))
        // Nothing carries over into the next week.
        #expect(AdaptiveWeek.leftOver(plan: output.weeks[1].plan, done: [], calendar: calendar).isEmpty)
        // The next session follows a planned session that didn't happen: the first session back.
        let nextMonday = week(2).addingTimeInterval(18 * 3600)
        #expect(FirstSessionBack.applies(sessionDay: nextMonday, earlierTrainingDays: output.trainingDays.filter { $0 < week(2) },
                                         plans: output.plans, calendar: calendar))
    }

    @Test(arguments: [GymProfile.homeDumbbells, SimFixtures.barbellRack, SimFixtures.hotel])
    func otherGymsKeepToWhatTheyCanLoad(_ gym: GymProfile) {
        let sim = BusySimulation(weeks: [.normal, .busy(sessions: 2), .normal], gym: gym)
        let output = sim.run()
        let problems = BusySimulation.check(output, gym: gym).filter { !$0.contains("not a main lift") || gym.equipment.contains(.barbell) }
        #expect(problems.isEmpty, "\(gym.name): \(problems.joined(separator: "\n"))")
    }
}
