import Foundation
import Testing
@testable import AppCore

struct AbsFinisherTests {
    let gym = GymProfile.commercialPounds
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func planner(_ gym: GymProfile = .commercialPounds, style: TrainingStyle = .balanced,
                 filter: ExerciseFilter? = nil) -> WorkoutPlanner {
        var planner = WorkoutPlanner(gym: gym, style: style)
        planner.exerciseFilter = filter
        return planner
    }

    func patterns(_ plan: AbsFinisher.Plan?) -> [CorePattern] {
        (plan?.exercises ?? []).compactMap { CoreMoves.move(id: $0.exerciseID)?.pattern }
    }

    /// A bare floor: no equipment at all.
    var floorOnly: GymProfile {
        var gym = GymProfile.homeDumbbells
        gym.equipment = []
        return gym
    }

    // MARK: Catalog

    @Test func everyCoreExerciseIsTagged() {
        let catalog = (ExerciseCatalog.options[.core] ?? []).map(\.id)
        #expect(Set(catalog) == Set(CoreMoves.all.map(\.id)))
        #expect(catalog.count == CoreMoves.all.count)
        // Every pattern has a move that needs no equipment, so any gym gets a finisher.
        for pattern in CorePattern.allCases {
            let bodyweight = CoreMoves.all.filter { $0.pattern == pattern }.contains { move in
                ExerciseCatalog.exercise(id: move.id)?.requires.allSatisfy { $0 == .bodyweight } == true
            }
            #expect(bodyweight, "\(pattern)")
        }
        // The planner's long-standing core picks keep their order.
        #expect(Array(catalog.prefix(3)) == ["Hanging_Leg_Raise", "Cable_Crunch", "Plank"])
    }

    @Test func holdsArePrescribedInSeconds() {
        let plank = ExerciseCatalog.exercise(id: "Plank")
        #expect(plank != nil)
        if let plank {
            let planned = planner().prescribe(plank, slot: .core, minutes: 45, sessionRPE: 8, history: [:])
            #expect(planned.reps == CoreMoves.holdSeconds)
            #expect(planned.name.contains("seconds"))
        }
        // The main planner on a bare floor picks the plank, in seconds.
        let plan = planner(floorOnly).plan(focus: .fullBody, minutes: 60, recovery: 80, history: [:])
        let core = plan.exercises.first { ExerciseCatalog.slot(for: $0.exerciseID) == .core }
        #expect(core?.exerciseID == "Plank")
        #expect(core?.reps == CoreMoves.holdSeconds)
    }

    // MARK: Length

    @Test func offMakesNothing() {
        #expect(AbsFinisher.make(length: .off, planner: planner()) == nil)
    }

    @Test func fiveMinutesIsOneDynamicAndOneBracingMovePaired() throws {
        let plan = try #require(AbsFinisher.make(length: .five, planner: planner()))
        #expect(plan.exercises.count == 2)
        let kinds = patterns(plan)
        #expect(kinds.filter(\.isDynamic).count == 1)
        #expect(kinds.filter { !$0.isDynamic }.count == 1)
        #expect(plan.exercises.allSatisfy { $0.supersetGroup == 1 })
        #expect(plan.exercises.allSatisfy { $0.sets == AbsFinisher.setsPerExercise })
        #expect(plan.exercises.allSatisfy { $0.restSeconds == AbsFinisher.restSeconds && $0.isFinisher == true })
        #expect(plan.estimatedMinutes <= 5)
        #expect(plan.totalSets == 4)
        #expect(plan.title == "Abs finisher · 5 min")
    }

    @Test func tenMinutesCoversEveryPattern() throws {
        let plan = try #require(AbsFinisher.make(length: .ten, planner: planner()))
        #expect((3...4).contains(plan.exercises.count))
        #expect(Set(patterns(plan)).count == plan.exercises.count)
        #expect(plan.estimatedMinutes <= 10)
        // Two pairs: A and B.
        #expect(Supersets.label(for: 0, in: plan.exercises) == "A1")
        #expect(Supersets.label(for: 1, in: plan.exercises) == "A2")
        #expect(Supersets.label(for: 2, in: plan.exercises) == "B1")
    }

    @Test func everyFinisherFitsItsMinutes() {
        let gyms: [GymProfile] = [.commercialPounds, .commercialKilograms, .homeDumbbells, floorOnly]
        let styles: [TrainingStyle] = [.balanced, .strength, .muscle, .endurance]
        for gym in gyms {
            for style in styles {
                for length in [AbsFinisher.Length.five, .ten] {
                    let plan = AbsFinisher.make(length: length, planner: planner(gym, style: style))
                    #expect(plan != nil, "\(gym.name) \(style) \(length)")
                    guard let plan else { continue }
                    #expect(plan.estimatedMinutes <= length.minutes, "\(gym.name) \(style) \(length)")
                    #expect(AbsFinisher.estimatedSeconds(plan.exercises) <= length.minutes * 60 + 29)
                    #expect(plan.exercises.count >= 2)
                    #expect(Set(plan.exercises.map(\.exerciseID)).count == plan.exercises.count)
                }
            }
        }
    }

    // MARK: Gym, pain and the main plan

    @Test func onlyPlansWhatTheGymSupports() throws {
        let home = GymProfile.homeDumbbells
        let plan = try #require(AbsFinisher.make(length: .ten, planner: planner(home)))
        for exercise in plan.exercises {
            let needs = try #require(ExerciseCatalog.exercise(id: exercise.exerciseID)).requires
            #expect(needs.allSatisfy { home.has($0) }, "\(exercise.exerciseID)")
        }
        #expect(!plan.exercises.contains { $0.exerciseID == "Cable_Crunch" || $0.exerciseID == "Pallof_Press" })
    }

    @Test func skipsWhatTheMainPlanAlreadyHas() throws {
        let main = planner().plan(focus: .pull, minutes: 60, recovery: 80, history: [:])
        let mainCore = main.exercises.filter { ExerciseCatalog.slot(for: $0.exerciseID) == .core }.map(\.exerciseID)
        #expect(!mainCore.isEmpty)
        let plan = try #require(AbsFinisher.make(length: .ten, planner: planner(),
                                                 excluding: Set(main.exercises.map(\.exerciseID))))
        #expect(plan.exercises.allSatisfy { !mainCore.contains($0.exerciseID) })
    }

    @Test func lowerBackPainLeavesOutFlexionAndRollouts() throws {
        let filter = ExerciseFilter(pains: [PainReport(area: .lowerBack, level: 7, loggedAt: now)])
        let plan = try #require(AbsFinisher.make(length: .ten, planner: planner(filter: filter)))
        for exercise in plan.exercises {
            #expect(!PainGuard.areas(forExerciseID: exercise.exerciseID, slot: .core).contains(.lowerBack), "\(exercise.exerciseID)")
        }
        #expect(plan.exercises.contains { $0.exerciseID == "Dead_Bug" })
    }

    @Test func moderateLowerBackPainPutsSpineFriendlyMovesFirst() throws {
        let filter = ExerciseFilter(pains: [PainReport(area: .lowerBack, level: 4, loggedAt: now)])
        let plan = try #require(AbsFinisher.make(length: .five, planner: planner(filter: filter)))
        // The bracing pick doesn't load the lower back.
        let brace = plan.exercises.first { CoreMoves.move(id: $0.exerciseID)?.pattern.isDynamic == false }
        #expect(brace.map { !PainGuard.areas(forExerciseID: $0.exerciseID, slot: .core).contains(.lowerBack) } == true)
        // The main planner's core slot gets the regression first.
        let main = planner(filter: filter).plan(focus: .pull, minutes: 60, recovery: 80, history: [:], exerciseFilter: filter)
        let core = main.exercises.first { ExerciseCatalog.slot(for: $0.exerciseID) == .core }
        #expect(core?.exerciseID == "Dead_Bug")
    }

    @Test func neverAgainIsRespected() throws {
        let filter = ExerciseFilter(neverAgain: ["Cable_Crunch", "Dead_Bug"])
        let plan = try #require(AbsFinisher.make(length: .ten, planner: planner(filter: filter)))
        #expect(!plan.exercises.contains { $0.exerciseID == "Cable_Crunch" || $0.exerciseID == "Dead_Bug" })
    }

    // MARK: Rotation and goals

    @Test func rotatesAwayFromRecentMoves() throws {
        let first = try #require(AbsFinisher.make(length: .five, planner: planner()))
        let ids = first.exercises.map(\.exerciseID)
        let next = try #require(AbsFinisher.make(length: .five, planner: planner(), recentExerciseIDs: ids))
        #expect(Set(next.exercises.map(\.exerciseID)).isDisjoint(with: ids))
        // The pattern last done gives way to its family's other pattern.
        #expect(Set(patterns(next)).isDisjoint(with: patterns(first)))
        // Still one dynamic and one bracing move.
        #expect(patterns(next).filter(\.isDynamic).count == 1)
    }

    @Test func goalSetsTheOrder() throws {
        let strength = try #require(AbsFinisher.make(length: .ten, planner: planner(style: .strength)))
        #expect(patterns(strength).first == .antiExtension)
        let muscle = try #require(AbsFinisher.make(length: .ten, planner: planner(style: .muscle)))
        #expect(patterns(muscle).first == .flexion)
        // Muscle: the loadable crunch first, so the sets can progress.
        #expect(muscle.exercises.first?.exerciseID == "Cable_Crunch")
        #expect(muscle.exercises.first?.loadKind == .cable)
    }

    @Test func holdsAndPerSideMovesSaySo() {
        var gym = floorOnly
        gym.equipment = []
        let plan = AbsFinisher.make(length: .ten, planner: planner(gym))
        for exercise in plan?.exercises ?? [] {
            guard let move = CoreMoves.move(id: exercise.exerciseID) else { continue }
            if move.isHold {
                #expect(exercise.reps == CoreMoves.holdSeconds)
                #expect(exercise.note?.contains("log the seconds as reps") == true)
            }
            if move.perSide || move.alternating { #expect(exercise.note?.contains("side") == true) }
        }
    }

    // MARK: With the main plan

    @Test func plannerCanLeaveCoreToTheFinisher() {
        let without = planner().plan(focus: .pull, minutes: 60, recovery: 80, history: [:], includeCore: false)
        #expect(!without.exercises.contains { ExerciseCatalog.slot(for: $0.exerciseID) == .core })
        let with = planner().plan(focus: .pull, minutes: 60, recovery: 80, history: [:])
        #expect(with.exercises.contains { ExerciseCatalog.slot(for: $0.exerciseID) == .core })
        #expect(!WorkoutPlanner.orderedSlots(focus: .fullBody, minutes: 45, priority: [.core], includeCore: false).contains(.core))
        // The filtered path forwards it too.
        let filtered = planner().plan(focus: .lower, minutes: 60, recovery: 80, history: [:],
                                      exerciseFilter: ExerciseFilter(neverAgain: ["Barbell_Squat"]), includeCore: false)
        #expect(!filtered.exercises.contains { ExerciseCatalog.slot(for: $0.exerciseID) == .core })
    }

    @Test func appendingKeepsTheSessionAndContinuesTheGroups() throws {
        var main = planner().plan(focus: .push, minutes: 20, recovery: 80, history: [:], includeCore: false)
        let groups = main.exercises.compactMap(\.supersetGroup)
        let next = AbsFinisher.nextGroup(after: main.exercises)
        #expect(next == (groups.max() ?? 0) + 1)
        let finisher = try #require(AbsFinisher.make(length: .five, planner: planner(), firstGroup: next))
        let estimate = main.estimatedMinutes
        main = AbsFinisher.appending(finisher, to: main)
        #expect(main.estimatedMinutes == estimate)
        #expect(Array(main.exercises.suffix(2)) == finisher.exercises)
        #expect(finisher.exercises.allSatisfy { $0.supersetGroup == next })
        #expect(AbsFinisher.appending(nil, to: main) == main)
    }

    @Test func evidenceNoteIsHonestAboutSpotReduction() {
        #expect(AbsFinisher.evidenceNote.contains("won't burn belly fat"))
        #expect(AbsFinisher.Length.allCases.map(\.label) == ["Off", "5 min", "10 min"])
    }
}
