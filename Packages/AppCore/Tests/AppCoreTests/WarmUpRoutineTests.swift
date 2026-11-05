import Foundation
import Testing
@testable import AppCore

struct WarmUpRoutineTests {
    let gym = GymProfile.commercialPounds

    @Test func everyFocusFitsItsMinutes() {
        for focus in WorkoutFocus.allCases {
            for minutes in WarmUpRoutine.minutesRange {
                let routine = WarmUpRoutine.make(focus: focus, exerciseIDs: [], minutes: minutes, gym: gym)
                #expect(routine.totalSeconds <= minutes * 60, "\(focus) \(minutes) min")
                // At least the raise and two movements.
                #expect(routine.movements.count >= 3, "\(focus) \(minutes) min")
                #expect(routine.movements.first == WarmUpRoutine.raise)
                #expect(routine.minutes <= minutes)
            }
        }
    }

    @Test func minutesAreClampedToTheRange() {
        let short = WarmUpRoutine.make(groups: [.legs], minutes: 1, gym: gym)
        #expect(short.totalSeconds <= 5 * 60)
        #expect(short.totalSeconds > WarmUpRoutine.raiseSeconds)
        let long = WarmUpRoutine.make(groups: [.legs, .push, .pull, .core], minutes: 30, gym: gym)
        #expect(long.totalSeconds <= 8 * 60)
    }

    /// Long static holds before lifting cut strength (Simic 2013; Kay &
    /// Blazevich 2012), so nothing in the catalog or a routine is a hold.
    @Test func noStaticHoldsByDefault() {
        #expect(WarmUpRoutine.catalog.allSatisfy { !$0.isStatic })
        for focus in WorkoutFocus.allCases {
            let routine = WarmUpRoutine.make(focus: focus, exerciseIDs: [], gym: gym)
            #expect(routine.movements.allSatisfy { !$0.isStatic })
        }
    }

    @Test func movementsMatchTheSessionsMuscles() {
        let push = WarmUpRoutine.make(focus: .push, exerciseIDs: [], gym: gym)
        let pushMovements = push.movements.dropFirst()
        #expect(pushMovements.allSatisfy { $0.preps.contains(.push) })
        #expect(!pushMovements.contains { $0.id == "legSwings" })
        #expect(pushMovements.contains { $0.id == "armCircles" })

        let legs = WarmUpRoutine.make(focus: .legs, exerciseIDs: [], gym: gym)
        let legMovements = legs.movements.dropFirst()
        #expect(legMovements.allSatisfy { $0.preps.contains(.legs) })
        #expect(legMovements.contains { $0.id == "legSwings" })
        #expect(!legMovements.contains { $0.id == "armCircles" })
    }

    @Test func exercisesAddTheirMuscles() {
        // A push plan that also has rows gets pull prep.
        let routine = WarmUpRoutine.make(focus: .push, exerciseIDs: ["Bent_Over_Barbell_Row"], gym: gym)
        #expect(routine.groups == [.push, .pull])
        #expect(routine.movements.contains { $0.preps.contains(.pull) })
        let noFocus = WarmUpRoutine.make(focus: nil, exerciseIDs: [], gym: gym)
        #expect(noFocus.groups == [.legs, .pull, .push, .core])
    }

    @Test func largeMusclesComeFirst() {
        let routine = WarmUpRoutine.make(focus: .fullBody, exerciseIDs: [], minutes: 8, gym: gym)
        let movements = Array(routine.movements.dropFirst())
        guard let lastLeg = movements.lastIndex(where: { $0.preps == [.legs] }),
              let firstPush = movements.firstIndex(where: { $0.preps == [.push] }) else {
            Issue.record("expected leg-only and push-only movements in a full-body routine")
            return
        }
        #expect(lastLeg < firstPush)
    }

    @Test func equipmentIsRespected() {
        var noBands = gym
        noBands.equipment.remove(.bands)
        noBands.equipment.remove(.pullUpBar)
        let routine = WarmUpRoutine.make(focus: .upper, exerciseIDs: [], minutes: 8, gym: noBands)
        #expect(!routine.movements.contains { $0.requires == .bands })
        #expect(!routine.movements.contains { $0.requires == .pullUpBar })
        #expect(routine.movements.count >= 3)

        let withBands = WarmUpRoutine.make(focus: .pull, exerciseIDs: [], minutes: 8, gym: gym)
        #expect(withBands.movements.contains { $0.id == "bandRows" })
    }

    @Test func eachMovementIsPickedOnce() {
        let routine = WarmUpRoutine.make(focus: .fullBody, exerciseIDs: [], minutes: 8, gym: gym)
        let ids = routine.movements.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func titleRoundsUp() {
        let routine = WarmUpRoutine.Routine(movements: [WarmUpRoutine.raise], groups: [.legs])
        #expect(routine.title == "Warm-up · 2 min")
        let plus = WarmUpRoutine.Routine(movements: [WarmUpRoutine.raise, WarmUpRoutine.catalog[0]], groups: [.legs])
        #expect(plus.minutes == 3)
    }

    @Test func routineRoundTripsThroughJSON() throws {
        let routine = WarmUpRoutine.make(focus: .legs, exerciseIDs: [], gym: gym)
        let data = try JSONEncoder().encode(routine)
        let back = try JSONDecoder().decode(WarmUpRoutine.Routine.self, from: data)
        #expect(back == routine)
    }
}
