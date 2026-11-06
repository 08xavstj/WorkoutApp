import Foundation
import SwiftData
import AppCore

/// Demo mode's app data (`DemoMode`: `-demoData YES`, Simulator only): an
/// in-memory workout log built from `DemoHealth`'s schedule, and this app's
/// own small stores (settings, gym, weekly plans, check-ins, pain log,
/// medications and supplements, measurements, labs) reset and filled with a
/// fixed made-up profile. Apple Health data comes from `DemoHealth`.
///
/// `prepare()` runs first thing at launch, before the stores load (it's the
/// first stored property of `WorkoutAppApp`), so they read the demo files.
/// It wipes this app's UserDefaults and JSON stores on the Simulator it runs
/// on; the real workout database is never opened for writing in demo mode
/// (the app uses `container` instead).
enum DemoData {
    /// Resets and fills the stores in demo mode; false (and does nothing) otherwise.
    static func prepare() -> Bool {
        guard let demo = DemoHealth.active else { return false }
        resetStores()
        seedSettings(demo)
        seedGym()
        seedPlans(demo)
        seedCheckIns(demo)
        seedMedications(demo)
        seedMeasurements(demo)
        seedLabs(demo)
        return true
    }

    /// The demo workout log, in memory only (gone when the app quits).
    static let container: ModelContainer = {
        let schema = Schema([WorkoutSession.self, ExerciseLog.self, SetLog.self, HRVReading.self,
                             WorkoutTemplate.self, TemplateExercise.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            if let demo = DemoHealth.active {
                seedWorkouts(demo, into: container.mainContext)
            }
            return container
        } catch {
            fatalError("Couldn't open the demo database: \(error)")
        }
    }()

    // MARK: Reset

    /// This app's UserDefaults (not the launch arguments) and JSON stores.
    private static func resetStores() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        let folder = URL.applicationSupportDirectory
        for name in ["weeklyplans.json", "checkins.json", "measurements.json", "sleep-scores.json", "lab-results.json"] {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }

    // MARK: Profile and goals

    private static func seedSettings(_ demo: DemoHealth) {
        let settings = UserSettings()
        settings.hasOnboarded = true
        settings.name = "Alex"
        settings.age = demo.age
        settings.sex = .male
        settings.heightCm = demo.heightCm
        settings.weightKg = 81.6
        settings.profileFromHealth = false
        settings.weightUnit = .kilograms
        settings.placeName = "Lisbon"
        settings.latitude = 38.72
        settings.longitude = -9.14
        settings.sleepNeedHours = 7.5
        settings.liftingExperience = .twoYearsPlus
        // Reminders off, so no notification permission alert interrupts the tour.
        settings.checkInRemindersOn = false
        settings.workoutRemindersOn = false
        settings.weeklyReviewOn = false
        settings.goals = goals(demo)
        settings.goalsSet = true
    }

    /// Lose weight slowly while building muscle and strength, with two lift goals.
    static func goals(_ demo: DemoHealth) -> Goals {
        let bench = LiftGoal(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", name: "Bench Press", targetKg: 100,
                             targetDate: demo.day(-120))
        let squat = LiftGoal(exerciseID: "Barbell_Squat", name: "Back Squat", bodyweightMultiple: 2)
        return Goals(weight: .lose, weeklyRatePercent: 0.5, focuses: [.muscle, .strength], targetWeightKg: 78,
                     liftGoals: [bench, squat])
    }

    private static func seedGym() {
        var profile = GymProfile.commercialKilograms
        profile.name = "Riverside Gym"
        GymStore().save(profile)
    }

    // MARK: Weekly plan and training block

    /// Upper/lower on the weekdays of the demo schedule (today is an upper
    /// day), this week and the five before, and a block that started three
    /// weeks ago.
    private static func seedPlans(_ demo: DemoHealth) {
        let calendar = demo.calendar
        let slots: [(daysAgo: Int, focus: WorkoutFocus)] = [(0, .upper), (2, .lower), (3, .upper), (5, .lower)]
        let days = slots.map { slot in
            PlannedDay(weekday: calendar.component(.weekday, from: demo.day(slot.daysAgo)), time: 18 * 60,
                       focus: slot.focus, minutes: 60, ifThen: "If work runs late, the 15-minute version")
        }
        let store = WeeklyPlanStore()
        store.trainingStyle = GoalPlanner.trainingStyle(goals(demo))
        let thisWeek = WeeklyPlan.weekStart(containing: demo.now, calendar: calendar)
        for weeksAgo in (0...5).reversed() {
            let weekStart = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: thisWeek) ?? thisWeek
            store.save(WeeklyPlan(weekStart: weekStart, plannedDays: days))
        }
        store.restartBlock(now: demo.day(21))
        store.refreshBlock(now: demo.now)
    }

    // MARK: Check-ins and pain

    /// Morning and evening check-ins for four weeks; this morning a sore
    /// knee (4/10, worse after training), also in the trainer's pain log.
    private static func seedCheckIns(_ demo: DemoHealth) {
        let store = CheckInStore()
        for daysAgo in (0...27).reversed() {
            let day = demo.day(daysAgo)
            var morning = MorningCheckIn(day: day)
            morning.rested = 3 + (DemoHealth.noise(daysAgo, 80) > 0 ? 1 : 0)
            morning.soreness = 2 + Int((DemoHealth.noise(daysAgo, 81) + 1) * 1.5)
            morning.soreAreas = daysAgo % 2 == 0 ? [.legs] : [.chest, .arms]
            morning.mood = 3 + (DemoHealth.noise(daysAgo, 82) > -0.2 ? 1 : 0)
            morning.nightWakings = daysAgo % 3 == 0 ? 1 : 0
            if daysAgo <= 2, daysAgo != 1 {
                let level = daysAgo == 0 ? 4 : 3
                morning.pains = [PainReport(area: .knee, level: level, worseAfterTraining: true,
                                            loggedAt: day.addingTimeInterval(7.5 * 3600))]
            }
            store.save(morning)
            // Evenings up to yesterday.
            guard daysAgo > 0 else { continue }
            var evening = EveningCheckIn(day: day)
            evening.caffeineMg = 175
            evening.drinks = demo.dayValue(.alcoholicDrinks, daysAgo).map { Int($0) } ?? 0
            evening.stress = 2 + (DemoHealth.noise(daysAgo, 83) > 0.4 ? 1 : 0)
            // A seeded mix of evenings (mostly good, a few stressed or tired
            // ones after drinks or a long day), with words, like a real log.
            let roll = DemoHealth.noise(daysAgo, 84)
            let mood = roll > 0.35 ? 5 : (roll > -0.45 ? 4 : (roll > -0.8 ? 3 : 2))
            evening.mood = mood
            let feelings: [MoodFeeling] = switch mood {
            case 5: [.happy, .content]
            case 4: roll > 0 ? [.calm] : [.content, .grateful]
            case 3: [.drained]
            default: [.stressed, .anxious]
            }
            evening.feelings = feelings.map(\.rawValue)
            evening.associations = (mood >= 4 ? [MoodAssociation.fitness, .friends] : [.work]).map(\.rawValue)
            store.save(evening)
        }
        PainLogStore.shared.log([PainReport(area: .knee, level: 4, worseAfterTraining: true,
                                            loggedAt: demo.now.addingTimeInterval(-3600))])
    }

    // MARK: Medications and supplements

    private static func seedMedications(_ demo: DemoHealth) {
        let started = demo.day(60)
        let medications = [
            Medication(name: "Creatine", dose: "5 g", times: [8 * 60], startDate: started),
            Medication(name: "Vitamin D", dose: "2000 IU", times: [8 * 60], startDate: started),
            Medication(name: "Magnesium", dose: "300 mg", times: [21 * 60 + 30], startDate: started),
            Medication(name: "Cetirizine", dose: "10 mg", startDate: demo.day(20), notes: "As needed for hay fever"),
        ]
        MedicationStore.save(medications)
        // Every daily supplement taken on time for the last two weeks (one
        // missed magnesium), so the vitamins page counts them.
        for daysAgo in 0..<14 {
            for dose in MedicationStore.doses(on: demo.day(daysAgo)) where dose.time < demo.now {
                if dose.name == "Magnesium" && daysAgo == 5 { continue }
                MedicationStore.markTaken(dose.id, at: dose.time.addingTimeInterval(4 * 60))
            }
        }
    }

    // MARK: Measurements and labs

    private static func seedMeasurements(_ demo: DemoHealth) {
        let store = BodyMeasurementsStore()
        store.addWaist(centimeters: 89, date: demo.day(62))
        store.addWaist(centimeters: 87.5, date: demo.day(33))
        store.addWaist(centimeters: 86, date: demo.day(4))
        // The dominant hand only, as grip norms use (Dodds et al. 2014).
        store.addGrip(kilograms: 47, hand: .right, date: demo.day(40))
    }

    private static func seedLabs(_ demo: DemoHealth) {
        let date = demo.day(45)
        LabsModel().add([
            LabResult(name: "LDL cholesterol", markerID: "ldl", value: 112, unit: "mg/dL", referenceHigh: 100, date: date, panel: "Lipids"),
            LabResult(name: "HDL cholesterol", markerID: "hdl", value: 52, unit: "mg/dL", referenceLow: 40, date: date, panel: "Lipids"),
            LabResult(name: "HbA1c", markerID: "hba1c", value: 5.3, unit: "%", referenceHigh: 5.7, date: date, panel: "Blood sugar"),
            LabResult(name: "Ferritin", markerID: "ferritin", value: 110, unit: "ng/mL", referenceLow: 30, referenceHigh: 400,
                      date: date, panel: "Iron"),
            LabResult(name: "Vitamin D (25-OH)", markerID: "vitaminD", value: 24, unit: "ng/mL", referenceLow: 30,
                      referenceHigh: 100, date: date, panel: "Vitamins"),
        ])
    }

    // MARK: Workouts

    /// One lift in the demo sessions: sets × reps, a starting weight that
    /// rises a little each session, rounded down to what the gym can load, so
    /// bench goes up 2.5 kg every 2-3 weeks with flat weeks between.
    private struct Lift {
        let id: String
        let name: String
        let sets: Int
        let reps: Int
        let startKg: Double
        let stepKg: Double
        let roundKg: Double
        var warmUp = false

        func weight(session: Int) -> Double {
            ((startKg + stepKg * Double(session)) / roundKg).rounded(.down) * roundKg
        }
    }

    private static let upperLifts = [
        Lift(id: "Barbell_Bench_Press_-_Medium_Grip", name: "Bench Press", sets: 4, reps: 6, startKg: 77.5, stepKg: 0.5, roundKg: 2.5, warmUp: true),
        Lift(id: "Bent_Over_Barbell_Row", name: "Barbell Row", sets: 3, reps: 8, startKg: 60, stepKg: 0.5, roundKg: 2.5),
        Lift(id: "Dumbbell_Shoulder_Press", name: "Dumbbell Shoulder Press", sets: 3, reps: 10, startKg: 20, stepKg: 0.2, roundKg: 2),
        Lift(id: "Wide-Grip_Lat_Pulldown", name: "Lat Pulldown", sets: 3, reps: 10, startKg: 55, stepKg: 0.5, roundKg: 5),
        Lift(id: "Side_Lateral_Raise", name: "Lateral Raise", sets: 3, reps: 15, startKg: 8, stepKg: 0.2, roundKg: 2),
        Lift(id: "Triceps_Pushdown_-_Rope_Attachment", name: "Rope Pushdown", sets: 3, reps: 12, startKg: 25, stepKg: 0.4, roundKg: 5),
    ]

    private static let lowerLifts = [
        Lift(id: "Barbell_Squat", name: "Back Squat", sets: 4, reps: 5, startKg: 100, stepKg: 0.6, roundKg: 2.5, warmUp: true),
        Lift(id: "Romanian_Deadlift", name: "Romanian Deadlift", sets: 3, reps: 8, startKg: 80, stepKg: 0.5, roundKg: 2.5),
        Lift(id: "Leg_Press", name: "Leg Press", sets: 3, reps: 10, startKg: 120, stepKg: 1, roundKg: 5),
        Lift(id: "Seated_Leg_Curl", name: "Seated Leg Curl", sets: 3, reps: 12, startKg: 40, stepKg: 0.5, roundKg: 5),
        Lift(id: "Standing_Calf_Raises", name: "Standing Calf Raise", sets: 3, reps: 12, startKg: 70, stepKg: 1, roundKg: 5),
        Lift(id: "Cable_Crunch", name: "Cable Crunch", sets: 3, reps: 15, startKg: 35, stepKg: 0.4, roundKg: 5),
    ]

    /// Every session in `DemoHealth.sessions`, with ramp warm-ups on the
    /// first lift, RPE 7 → 8.5 across the working sets, and steady
    /// progression, so the last bench and squat sessions are PRs. Plus one
    /// saved workout.
    private static func seedWorkouts(_ demo: DemoHealth, into context: ModelContext) {
        var count: [WorkoutFocus: Int] = [:]
        for planned in demo.sessions.sorted(by: { $0.start < $1.start }) {
            let index = count[planned.focus, default: 0]
            count[planned.focus] = index + 1
            // The same names as the saved workout ("Upper A") and the plan ("Upper").
            let session = WorkoutSession(name: planned.focus == .upper ? "Upper A" : "Lower A", startedAt: planned.start)
            session.endedAt = planned.end
            session.sessionRPE = planned.rpe
            session.savedToHealth = true
            context.insert(session)
            var clock = planned.start.addingTimeInterval(6 * 60)
            let lifts = planned.focus == .upper ? upperLifts : lowerLifts
            for (order, lift) in lifts.enumerated() {
                let log = ExerciseLog(exerciseID: lift.id, name: lift.name, order: order)
                log.session = session
                context.insert(log)
                let top = lift.weight(session: index)
                var setOrder = 0
                if lift.warmUp {
                    for (fraction, reps) in [(0.4, 8), (0.6, 5), (0.8, 3)] {
                        let kg = ((top * fraction) / 2.5).rounded() * 2.5
                        let set = SetLog(order: setOrder, weightKg: kg, reps: reps, isWarmup: true)
                        set.completedAt = clock
                        set.exercise = log
                        context.insert(set)
                        setOrder += 1
                        clock = clock.addingTimeInterval(90)
                    }
                }
                for number in 0..<lift.sets {
                    let last = number == lift.sets - 1
                    let rpe = min(9, 7 + 0.5 * Double(number))
                    let set = SetLog(order: setOrder, weightKg: top, reps: last && lift.reps >= 10 ? lift.reps - 1 : lift.reps, rpe: rpe)
                    set.completedAt = clock
                    set.exercise = log
                    context.insert(set)
                    setOrder += 1
                    clock = clock.addingTimeInterval(150)
                }
            }
        }
        seedTemplate(into: context, demo: demo)
        try? context.save()
    }

    private static func seedTemplate(into context: ModelContext, demo: DemoHealth) {
        let template = WorkoutTemplate(name: "Upper A", createdAt: demo.day(30))
        template.lastUsedAt = demo.day(3)
        context.insert(template)
        for (order, lift) in upperLifts.prefix(5).enumerated() {
            let item = TemplateExercise(exerciseID: lift.id, name: lift.name, order: order, sets: lift.sets,
                                        repsLow: lift.reps, repsHigh: lift.reps + 2, targetRPE: 8)
            item.template = template
            context.insert(item)
        }
    }
}
