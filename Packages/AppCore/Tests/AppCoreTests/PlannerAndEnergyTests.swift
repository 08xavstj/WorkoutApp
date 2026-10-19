import Foundation
import Testing
@testable import AppCore

struct EquipmentTests {
    let gym = GymProfile.commercialPounds

    @Test func barbellLoadsUseRealPlates() {
        let loads = gym.achievableLoads(for: .barbell)
        #expect(loads.first == 45)
        #expect(loads.contains(50))      // 2.5 per side
        #expect(loads.contains(135))     // 45 per side
        #expect(!loads.contains(47.5))   // no 1.25 plates
    }

    @Test func roundsDownToLoadableWeight() {
        #expect(gym.load(atMost: 188, on: .barbell) == 185)
        #expect(gym.load(atMost: 33, on: .dumbbell) == 30)
        #expect(gym.load(atMost: 2, on: .dumbbell) == 5) // lighter than the smallest: use the smallest
    }

    @Test func smallestJumpDependsOnEquipment() {
        #expect(gym.smallestJump(from: 185, on: .barbell) == 5)
        #expect(gym.smallestJump(from: 30, on: .dumbbell) == 5)
        #expect(gym.smallestJump(from: 50, on: .cable) == 10)
        let home = GymProfile.homeDumbbells
        #expect(home.smallestJump(from: 30, on: .dumbbell) == 2.5)
    }

    @Test func plateBreakdownRespectsInventory() {
        #expect(gym.plateBreakdown(total: 225, on: .barbell) == [45, 45])
        #expect(gym.plateBreakdown(total: 185, on: .barbell) == [45, 25])
        #expect(gym.plateBreakdown(total: 45, on: .barbell) == [])
        #expect(gym.plateBreakdown(total: 275, on: .barbell) == [45, 45, 25])
        // Only one pair of 45s here, so 105 per side needs the 35 and a 25.
        var small = gym
        small.plates = [PlateCount(weight: 45, pairs: 1), PlateCount(weight: 35, pairs: 1), PlateCount(weight: 25, pairs: 2)]
        #expect(small.plateBreakdown(total: 255, on: .barbell) == [45, 35, 25])
        #expect(small.plateBreakdown(total: 345, on: .barbell) == nil)
        #expect(gym.plateBreakdown(total: 47, on: .barbell) == nil)
    }

    @Test func kilogramGymUsesSmallPlates() {
        let kg = GymProfile.commercialKilograms
        #expect(kg.smallestJump(from: 60, on: .barbell) == 2.5) // 1.25 per side
    }
}

struct StrainPlannerTests {
    let planner = StrainPlanner()

    @Test func statusAgainstTarget() {
        #expect(planner.status(current: 11.4, target: 14...18) == .below(remaining: 2.6))
        #expect(planner.status(current: 15, target: 14...18) == .inRange)
        #expect(planner.status(current: 19, target: 14...18) == .above)
    }

    @Test func gainsShrinkAsStrainRises() {
        let load = planner.liftingLoad(minutes: 45, rpe: 8)
        #expect(planner.strainGain(current: 24, addedLoad: load) > planner.strainGain(current: 71, addedLoad: load))
    }

    @Test func rankingPrefersOptionsThatLandInRange() {
        let options = [
            StrainPlanner.Option(id: "short", kind: .strength, title: "Short", detail: "", minutes: 20, load: planner.liftingLoad(minutes: 20, rpe: 6)),
            StrainPlanner.Option(id: "push45", kind: .strength, title: "Push", detail: "", minutes: 45, load: planner.liftingLoad(minutes: 45, rpe: 8)),
            StrainPlanner.Option(id: "huge", kind: .strength, title: "Huge", detail: "", minutes: 180, load: planner.liftingLoad(minutes: 180, rpe: 10))
        ]
        // Strain is a percentage; these match 11.4 and 14-18 on the old 0-21 scale.
        let scale = 100.0 / 21
        let target = (14 * scale)...(18 * scale)
        let ranked = planner.rank(options, current: 11.4 * scale, target: target)
        #expect(ranked.first?.id == "push45")
        #expect(ranked.last?.id == "huge")
        #expect(target.contains(ranked[0].landsAt))
    }
}

struct WorkoutPlannerTests {
    @Test func picksExercisesTheGymCanDo() {
        let planner = WorkoutPlanner(gym: .homeDumbbells)
        let plan = planner.plan(focus: .push, minutes: 45, recovery: 80, history: [:])
        #expect(plan.exercises.count == 5)
        #expect(plan.exercises.allSatisfy { $0.loadKind == nil || $0.loadKind == .dumbbell })
        #expect(plan.exercises.first?.exerciseID == "Dumbbell_Bench_Press")
    }

    @Test func shorterSessionsHaveFewerExercises() {
        let planner = WorkoutPlanner(gym: .commercialPounds)
        #expect(planner.plan(focus: .legs, minutes: 30, recovery: nil, history: [:]).exercises.count == 4)
        #expect(planner.plan(focus: .legs, minutes: 60, recovery: nil, history: [:]).exercises.count == 6)
    }

    @Test func suggestedLoadIsLoadableAndProgresses() {
        let planner = WorkoutPlanner(gym: .commercialPounds)
        // 185 x 8 at RPE 7 last time: e1RM ≈ 234.
        let history = ExerciseHistory(bestEstimatedOneRepMax: 234, lastWeight: 185, lastReps: 8, lastRPE: 7, lastDate: .now)
        let load = planner.suggestedLoad(history: history, reps: 6...8, rpe: 8, kind: .barbell)
        #expect(load == 190) // beat the range at an easier effort → next 5 lb jump
        let plan = planner.plan(focus: .push, minutes: 45, recovery: 80, history: ["Barbell_Bench_Press_-_Medium_Grip": history])
        #expect(plan.exercises.first?.load == 190)
        #expect(plan.exercises.first?.note == "45 + 25 + 2.5 lb per side")
    }

    @Test func focusRotatesAwayFromWhatWasJustTrained() {
        #expect(WorkoutPlanner.suggestedFocus(recentExerciseIDs: []) == .push)
        #expect(WorkoutPlanner.suggestedFocus(recentExerciseIDs: ["Barbell_Bench_Press_-_Medium_Grip"]) == .pull)
        #expect(WorkoutPlanner.suggestedFocus(recentExerciseIDs: ["Pullups", "Barbell_Bench_Press_-_Medium_Grip"]) == .legs)
    }

    @Test func recoverySetsEffort() {
        #expect(WorkoutPlanner.targetRPE(recovery: 20) < WorkoutPlanner.targetRPE(recovery: 90))
    }
}

struct TrainingLoadTests {
    @Test func calibratesWithLittleHistory() {
        let result = TrainingLoadCalculator().evaluate(dailyLoads: [50, 60])
        #expect(result.status == .calibrating)
    }

    @Test func steadyTrainingIsSteady() {
        let result = TrainingLoadCalculator().evaluate(dailyLoads: Array(repeating: 80, count: 28))
        #expect(result.status == .steady)
        #expect(result.usual.contains(result.value))
    }

    @Test func suddenJumpIsASpike() {
        let loads = Array(repeating: 40.0, count: 21) + Array(repeating: 150.0, count: 7)
        #expect(TrainingLoadCalculator().evaluate(dailyLoads: loads).status == .spike)
    }

    @Test func easyWeekIsLighter() {
        let loads = Array(repeating: 80.0, count: 21) + Array(repeating: 20.0, count: 7)
        #expect(TrainingLoadCalculator().evaluate(dailyLoads: loads).status == .lighter)
    }

    @Test func trendDirection() {
        #expect(Biomarkers.trend([170, 169, 168, 167, 166]) == .decreasing)
        #expect(Biomarkers.trend([50, 52, 55, 57, 60]) == .increasing)
        #expect(Biomarkers.trend([60, 60.1, 59.9, 60]) == .stable)
    }
}

struct EnergyTests {
    @Test func watchRestingCaloriesReplaceTheFormula() {
        let body = EnergyCalculator.Body(weightKg: 80, heightCm: 180, age: 30, sex: .male)
        let profile = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 60)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let noon = start.addingTimeInterval(12 * 3600)
        let calculator = EnergyCalculator()
        let measured = calculator.estimate(body: body, profile: profile, heartRate: [], strengthSessions: [],
                                           stepsOutsideWorkouts: 0, intake: nil, dayStart: start, now: noon,
                                           measuredRestingPerDay: 1700)
        #expect(measured.restingFullDay == 1700)
        #expect(abs(measured.restingSoFar - 850) < 0.001)
        let implausible = calculator.estimate(body: body, profile: profile, heartRate: [], strengthSessions: [],
                                              stepsOutsideWorkouts: 0, intake: nil, dayStart: start, now: noon,
                                              measuredRestingPerDay: 200)
        #expect(implausible.restingFullDay == calculator.bmr(body).kcal)
    }

    let calc = EnergyCalculator()
    let body = EnergyCalculator.Body(weightKg: 74.3, heightCm: 180, age: 30, sex: .male)

    @Test func mifflinStJeor() {
        // 10*74.3 + 6.25*180 - 5*30 + 5 = 1723
        #expect(abs(calc.bmr(body).kcal - 1723) < 0.5)
    }

    @Test func katchMcArdleWhenBodyFatKnown() {
        var lean = body
        lean.bodyFatPercent = 13.3
        let result = calc.bmr(lean)
        #expect(result.method == "Katch-McArdle")
        #expect(abs(result.kcal - (370 + 21.6 * 74.3 * 0.867)) < 0.5)
    }

    @Test func keytelRisesWithHeartRate() {
        #expect(calc.keytelKcalPerMinute(bpm: 160, body: body) > calc.keytelKcalPerMinute(bpm: 120, body: body))
        // About 14 kcal/min at 150 bpm for this person.
        #expect((10...15).contains(calc.keytelKcalPerMinute(bpm: 150, body: body)))
    }

    @Test func fullDayEstimateIsPlausible() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 55)
        // 40 minutes running at 150 bpm.
        let run = (0...40).map { HeartRateSample(date: start.addingTimeInterval(36_000 + Double($0) * 60), bpm: 150) }
        let result = calc.estimate(
            body: body, profile: profile, heartRate: run, strengthSessions: [],
            stepsOutsideWorkouts: 8000, intake: 2400, dayStart: start, now: start.addingTimeInterval(86_399)
        )
        // The run's steps aren't counted twice (heart rate already covers them).
        #expect((2450...3300).contains(result.projectedTotal))
        #expect(result.everydayMovement < 8000 * calc.kcalPerStepPerKg * body.weightKg)
        #expect(result.digestion == 240)
        #expect(result.balance! < 0)
    }

    @Test func oneRaisedReadingBeforeASyncGapIsTwoMinutes() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 55)
        let samples = [HeartRateSample(date: start, bpm: 150), HeartRateSample(date: start.addingTimeInterval(540), bpm: 70)]
        let result = calc.estimate(body: body, profile: profile, heartRate: samples, strengthSessions: [],
                                   stepsOutsideWorkouts: 0, intake: nil, dayStart: start, now: start.addingTimeInterval(3600))
        let perMinute = calc.keytelKcalPerMinute(bpm: 150, body: body) - calc.bmr(body).kcal / 1440
        #expect(abs(result.exercise - 2 * perMinute) < 0.5)
    }

    @Test func sessionLeftRunningIsCapped() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let session = StrengthSessionSummary(start: start, end: start.addingTimeInterval(10 * 3600), sessionRPE: 8)
        let result = calc.estimate(
            body: body, profile: HeartRateProfile(age: 30, sex: .male, restingHeartRate: 55),
            heartRate: [], strengthSessions: [session], stepsOutsideWorkouts: 0, intake: nil,
            dayStart: start, now: start.addingTimeInterval(11 * 3600)
        )
        #expect(abs(result.exercise - 3 * 5 * 74.3) < 0.5)
    }

    @Test func liftingFloorAppliesWhenHeartRateIsLow() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let session = StrengthSessionSummary(start: start, end: start.addingTimeInterval(3600), sessionRPE: 8)
        let result = calc.estimate(
            body: body, profile: HeartRateProfile(age: 30, sex: .male, restingHeartRate: 55),
            heartRate: [], strengthSessions: [session], stepsOutsideWorkouts: 0, intake: nil,
            dayStart: start, now: start.addingTimeInterval(7200)
        )
        #expect(abs(result.exercise - 5 * 74.3) < 0.5) // (6 - 1) METs × kg × 1 h
    }
}
