import Foundation
import Testing
@testable import AppCore

struct WarmUpRoutineTests {
    let gym = GymProfile.commercialPounds

    /// Off and ramp-only add no movement steps: the ramp sets are `WarmUp`.
    @Test func offAndRampOnlyHaveNoSteps() {
        for tier in [WarmUpRoutine.Tier.off, .rampOnly] {
            let routine = WarmUpRoutine.make(tier: tier, firstSlots: [.squat, .horizontalPress], gym: gym)
            #expect(routine.isEmpty)
            #expect(routine.tier == tier)
            #expect(routine.minutes == 0)
            #expect(!tier.hasSteps)
        }
        #expect(WarmUpRoutine.Tier.short.hasSteps && WarmUpRoutine.Tier.full.hasSteps)
    }

    /// Short: 90 s raise + 2–3 drills, under 5 min; full: 180 s raise + more,
    /// under 10 min, so the first working set stays inside the temperature
    /// decay window (McGowan 2015).
    @Test func tiersFitTheirTimeBudgets() {
        for focus in WorkoutFocus.allCases {
            let short = WarmUpRoutine.make(tier: .short, firstSlots: focus.slots, gym: gym)
            #expect(short.steps.first?.dose == .seconds(WarmUpRoutine.shortRaiseSeconds), "\(focus)")
            #expect((3...4).contains(short.steps.count), "\(focus): \(short.steps.map(\.id))")
            #expect(short.totalSeconds <= 5 * 60, "\(focus) short \(short.totalSeconds)s")

            let full = WarmUpRoutine.make(tier: .full, firstSlots: focus.slots, gym: gym)
            #expect(full.steps.first?.dose == .seconds(WarmUpRoutine.fullRaiseSeconds), "\(focus)")
            #expect(full.steps.count > short.steps.count, "\(focus)")
            #expect(full.totalSeconds <= 10 * 60, "\(focus) full \(full.totalSeconds)s")
            #expect(full.steps.last?.phase == .potentiate, "\(focus)")
            #expect(full.steps.filter { $0.phase == .potentiate }.count == 1)
        }
    }

    /// The raise is the only timed step; every drill is counted in reps, so
    /// the UI never counts down over a rep-based movement.
    @Test func onlyTheRaiseIsTimed() {
        for tier in [WarmUpRoutine.Tier.short, .full] {
            for focus in WorkoutFocus.allCases {
                let routine = WarmUpRoutine.make(tier: tier, firstSlots: focus.slots, gym: gym)
                let timed = routine.steps.filter(\.isTimed)
                #expect(timed.count == 1, "\(tier) \(focus)")
                #expect(timed.first?.phase == .raise)
                #expect(routine.steps.dropFirst().allSatisfy { !$0.isTimed })
            }
        }
    }

    @Test func drillsMatchTheFirstLifts() {
        let legs = WarmUpRoutine.make(tier: .short, firstSlots: WorkoutFocus.legs.slots, gym: gym)
        #expect(legs.steps.map(\.id) == ["raise", "ankleRocks", "hipHinge", "bodyweightSquat"])

        let push = WarmUpRoutine.make(tier: .short, firstSlots: WorkoutFocus.push.slots, gym: gym)
        #expect(push.steps.map(\.id) == ["raise", "bandPullApart", "shoulderCircles", "scapPushUp"])

        let pull = WarmUpRoutine.make(tier: .short, firstSlots: [.verticalPull, .horizontalRow], gym: gym)
        #expect(pull.steps.map(\.id) == ["raise", "scapPullUp", "thoracicRotation"])
        #expect(!pull.steps.contains { $0.id == "ankleRocks" })

        // Isolation slots map to the nearest pattern; core maps to none.
        #expect(WarmUpRoutine.Pattern(slot: .triceps) == .horizontalPress)
        #expect(WarmUpRoutine.Pattern(slot: .legCurl) == .hinge)
        #expect(WarmUpRoutine.Pattern(slot: .core) == nil)
        // Compound lifts decide, whatever their position.
        #expect(WarmUpRoutine.firstPatterns(in: [.biceps, .squat, .horizontalPress]) == [.squat, .horizontalPress])
    }

    @Test func noLiftsFallsBackToAGeneralPair() {
        let routine = WarmUpRoutine.make(tier: .short, firstSlots: [], gym: gym)
        #expect(routine.steps.count >= 3)
        #expect(routine.steps.contains { $0.id == "ankleRocks" })
        #expect(routine.steps.contains { $0.id == "bandPullApart" })
        let coreOnly = WarmUpRoutine.make(tier: .short, firstSlots: [.core], gym: gym)
        #expect(coreOnly.steps.map(\.id) == routine.steps.map(\.id))
    }

    @Test func fullTierPicksExplosiveRepsForTheFirstLift() {
        let lower = WarmUpRoutine.make(tier: .full, firstSlots: [.squat, .horizontalPress], gym: gym)
        #expect(lower.steps.last?.name == "Jump squats")
        let upper = WarmUpRoutine.make(tier: .full, firstSlots: [.horizontalPress, .squat], gym: gym)
        #expect(upper.steps.last?.name == "Plyo push-ups")
        #expect(upper.steps.last?.dose == .reps(3, perSide: false))
    }

    /// Steps that need bands, a bar or a cable are swapped for the next
    /// alternative when the gym lacks them; nothing requires missing kit.
    @Test func equipmentIsRespected() {
        var bare = gym
        bare.equipment = [.bodyweight]
        for tier in [WarmUpRoutine.Tier.short, .full] {
            for focus in WorkoutFocus.allCases {
                let routine = WarmUpRoutine.make(tier: tier, firstSlots: focus.slots, gym: bare)
                #expect(routine.steps.allSatisfy { $0.requires == nil || $0.requires == .bodyweight }, "\(tier) \(focus)")
                #expect(routine.steps.count >= 3)
            }
        }
        let push = WarmUpRoutine.make(tier: .short, firstSlots: WorkoutFocus.push.slots, gym: bare)
        #expect(push.steps.contains { $0.id == "armCrossovers" })
        #expect(!push.steps.contains { $0.id == "bandPullApart" })
        let pull = WarmUpRoutine.make(tier: .short, firstSlots: [.verticalPull], gym: bare)
        #expect(pull.steps.contains { $0.id == "armCrossovers" })

        var bandsOnly = bare
        bandsOnly.equipment.insert(.bands)
        let pullWithBands = WarmUpRoutine.make(tier: .short, firstSlots: [.verticalPull], gym: bandsOnly)
        #expect(pullWithBands.steps.contains { $0.id == "bandRow" })
    }

    @Test func eachStepIsPickedOnceAndHasWhy() {
        for tier in [WarmUpRoutine.Tier.short, .full] {
            for focus in WorkoutFocus.allCases {
                let routine = WarmUpRoutine.make(tier: tier, firstSlots: focus.slots, gym: gym)
                let ids = routine.steps.map(\.id)
                #expect(Set(ids).count == ids.count, "\(tier) \(focus)")
                #expect(routine.steps.allSatisfy { !$0.why.isEmpty && !$0.cue.isEmpty })
            }
        }
    }

    @Test func doseTextAndEstimates() {
        #expect(WarmUpRoutine.Dose.reps(10, perSide: true).text == "10 each side")
        #expect(WarmUpRoutine.Dose.reps(15, perSide: false).text == "15")
        #expect(WarmUpRoutine.Dose.seconds(90).text == "90 s")
        #expect(WarmUpRoutine.Dose.seconds(90).seconds == 90)
        #expect(WarmUpRoutine.Dose.reps(8, perSide: true).seconds == nil)
        #expect(WarmUpRoutine.Dose.reps(8, perSide: true).estimatedSeconds == 48)
        let routine = WarmUpRoutine.Routine(tier: .short, steps: [WarmUpRoutine.raise(seconds: 90)], slots: [])
        #expect(routine.title == "Warm-up · 2 min")
        #expect(routine.drillNames.isEmpty)
    }

    @Test func tierLabels() {
        #expect(WarmUpRoutine.Tier.rampOnly.menuLabel == "Ramp sets only")
        #expect(WarmUpRoutine.Tier.short.menuLabel == "Short · 5 min")
        #expect(WarmUpRoutine.Tier.full.menuLabel == "Full · 8–10 min")
        #expect(WarmUpRoutine.Tier(rawValue: "rampOnly") == .rampOnly)
    }

    /// The planner counts the movement steps by `plannedMinutes`; the made
    /// routines must not run longer than that promise by more than a minute.
    @Test func plannedMinutesMatchTheRoutines() {
        #expect(WarmUpRoutine.Tier.off.plannedMinutes == 0)
        #expect(WarmUpRoutine.Tier.rampOnly.plannedMinutes == 0)
        for tier in [WarmUpRoutine.Tier.short, .full] {
            for focus in WorkoutFocus.allCases {
                let routine = WarmUpRoutine.make(tier: tier, firstSlots: focus.slots, gym: gym)
                #expect(routine.minutes <= tier.plannedMinutes + 1, "\(tier) \(focus): \(routine.minutes) min")
            }
        }
    }

    @Test func routineRoundTripsThroughJSON() throws {
        let routine = WarmUpRoutine.make(tier: .full, firstSlots: WorkoutFocus.fullBody.slots, gym: gym)
        let data = try JSONEncoder().encode(routine)
        let back = try JSONDecoder().decode(WarmUpRoutine.Routine.self, from: data)
        #expect(back == routine)
        let tierData = try JSONEncoder().encode(WarmUpRoutine.Tier.short)
        #expect(String(decoding: tierData, as: UTF8.self) == "\"short\"")
    }
}
