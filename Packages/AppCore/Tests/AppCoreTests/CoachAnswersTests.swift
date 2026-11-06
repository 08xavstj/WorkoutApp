import Foundation
import Testing
@testable import AppCore

struct CoachQuestionRoutingTests {
    // The four suggested prompts and four follow-ups, verbatim from the Coach tab.
    @Test(arguments: [
        ("How should I train today?", CoachIntent.Question.trainToday),
        ("Why is my recovery where it is?", .whyRecovery),
        ("Plan my next workout", .planWorkout),
        ("Am I eating enough for my training?", .eatingEnough),
        ("Make it 30 min", .planWorkout),
        ("Swap for a ride", .cardioSwap),
        ("What should I eat after?", .eatAfter),
        ("Make it leg day", .planWorkout),
        // Other phrasings.
        ("Should I rest today?", .shouldRest),
        ("should i take a day off", .shouldRest),
        ("Is today a rest day?", .shouldRest),
        ("what should I do today", .trainToday),
        ("Should I lift today?", .trainToday),
        ("How hard should I go today?", .trainToday),
        ("Build me a workout", .planWorkout),
        ("plan a 45 minute full body workout", .planWorkout),
        ("Give me a workout, then what should I eat?", .planWorkout),
        ("Why is my recovery so low?", .whyRecovery),
        ("What's my recovery score?", .whyRecovery),
        ("how recovered am I", .whyRecovery),
        ("How did I sleep?", .sleep),
        ("how was my sleep last night", .sleep),
        ("Did I get enough sleep?", .sleep),
        ("I slept badly, what now?", .sleep),
        ("What's my strain?", .strain),
        ("how much strain do I have today", .strain),
        ("Am I eating enough?", .eatingEnough),
        ("How much protein have I had today?", .eatingEnough),
        ("how many calories are left", .eatingEnough),
        ("What should I eat after my workout?", .eatAfter),
        ("How much protein after the gym?", .eatAfter),
        ("Post workout meal?", .eatAfter),
        ("Can I run instead of lifting?", .cardioSwap),
    ])
    func routesKnownQuestions(_ text: String, _ expected: CoachIntent.Question) {
        #expect(CoachIntent.question(text) == expected)
    }

    // Advice and explanations go to the model; so do questions about food choices.
    @Test(arguments: [
        "How can I sleep better?",
        "What is strain and how is it calculated?",
        "What should I have for dinner?",
        "Is creatine worth taking?",
        "Any feedback on vitamin D?",
        "How does recovery get calculated?",
        "Why does my knee hurt when I squat?",
    ])
    func openQuestionsAreNotRouted(_ text: String) {
        #expect(CoachIntent.question(text) == nil)
    }

    @Test func wholeWordsOnly() {
        // "restaurant" is not "rest"; "strained" is not "strain".
        #expect(CoachIntent.question("Which restaurant has good food?") == nil)
        #expect(CoachIntent.question("I strained my back, what now?") == nil)
    }
}

struct CoachAnswersTests {
    /// A normal training day: moderate recovery, a planned session, food half logged.
    var facts: CoachFacts {
        var f = CoachFacts()
        f.goals = Goals(weight: .maintain, focuses: [.muscle])
        f.strain = 18
        f.targetStrain = 50...70
        f.yesterdayStrain = 62
        f.cardioLoad = 30
        f.liftingLoad = 10
        f.recovery = 55
        f.recoveryContributors = [
            RecoveryContributor(id: "hrv", name: "HRV", detail: "48 ms, 5% under your baseline", effect: .lowers, weight: 3),
            RecoveryContributor(id: "sleep", name: "Sleep", detail: "7.6 h, close to your need", effect: .raises, weight: 2),
        ]
        f.hrv = 48
        f.restingHeartRate = 52
        f.sleepScore = 78
        f.sleepHours = 7.6
        f.sleepNeedHours = 8
        f.deepHours = 1.4
        f.remHours = 1.7
        f.sleepInterruptions = 2
        f.caloriesEaten = 1400
        f.calorieTarget = 2600
        f.proteinGrams = 70
        f.proteinTargetGrams = 150
        f.bodyMassKg = 85
        f.plannedSession = CoachFacts.PlannedSession(title: "Push Day", minutes: 45, exerciseCount: 5, rationale: "Chest and shoulders are fresh.", targetRPE: 8)
        f.gymConfigured = true
        f.workoutsLast14Days = 6
        f.daysSinceLastWorkout = 2
        return f
    }

    @Test func everyQuestionHasAnAnswerWithFullFacts() {
        for question in CoachIntent.Question.allCases {
            let answer = CoachAnswers.answer(for: question, facts: facts)
            #expect(answer != nil, "\(question)")
            #expect(answer?.question == question)
            #expect((answer?.text.count ?? 0) > 40, "\(question)")
        }
    }

    @Test func everyQuestionStillAnswersWithEmptyFacts() {
        // Nothing synced yet: the answer says what is missing instead of failing.
        for question in CoachIntent.Question.allCases {
            let answer = CoachAnswers.answer(for: question, facts: CoachFacts())
            #expect(answer != nil, "\(question)")
            #expect(answer?.text.isEmpty == false)
        }
    }

    @Test func trainTodayUsesTheStrainTargetAndPlan() {
        let answer = CoachAnswers.trainToday(facts)!
        #expect(answer.text.contains("55%"))
        #expect(answer.text.contains("50-70%"))
        #expect(answer.text.contains("Push Day"))
        #expect(answer.text.contains("32 points to go"))
        #expect(answer.action?.contains("Start") == true)
    }

    @Test func trainTodayFollowsTheWeeklyPlan() {
        var f = facts
        f.dayGuidance = TrainingDayPlanner.Guidance(kind: .rest, strainRange: 0...25, title: "Rest day", reason: "Rest day in your plan.")
        let answer = CoachAnswers.trainToday(f)!
        #expect(answer.text.hasPrefix("Rest day: Rest day in your plan."))
        #expect(answer.action?.contains("walk") == true)
    }

    @Test func lowRecoveryIsAnEasyDayNotADayOff() {
        var f = facts
        f.recovery = 25
        let train = CoachAnswers.trainToday(f)!
        #expect(train.text.contains("easy day"))
        #expect(train.action?.contains("easy") == true)
        let rest = CoachAnswers.shouldRest(f)!
        #expect(rest.text.hasPrefix("Not necessarily"))
    }

    @Test func restModeWinsEverywhere() {
        var f = facts
        f.restMode = true
        #expect(CoachAnswers.trainToday(f)!.text.contains("Rest mode is on"))
        #expect(CoachAnswers.shouldRest(f)!.text.hasPrefix("Yes"))
        #expect(CoachAnswers.planWorkout(f)!.text.contains("Rest mode is on"))
    }

    @Test func whyRecoveryListsContributors() {
        let answer = CoachAnswers.whyRecovery(facts)!
        #expect(answer.text.hasPrefix("Recovery is 55%: normal."))
        #expect(answer.text.contains("Pulling it down: hrv (48 ms, 5% under your baseline)."))
        #expect(answer.text.contains("Helping: sleep (7.6 h, close to your need)."))
    }

    @Test func whyRecoveryFallsBackToInputsAndFlagsCalibration() {
        var f = facts
        f.recoveryContributors = []
        f.recoveryCalibrated = false
        let answer = CoachAnswers.whyRecovery(f)!
        #expect(answer.text.contains("baseline is still building"))
        #expect(answer.text.contains("HRV 48 ms"))
        #expect(answer.text.contains("resting heart rate 52 bpm"))
    }

    @Test func planWorkoutExplainsTheCard() {
        let answer = CoachAnswers.planWorkout(facts)!
        #expect(answer.text.hasPrefix("Push Day, about 45 min with 5 exercises at around RPE 8."))
        #expect(answer.text.contains("Chest and shoulders are fresh."))
        #expect(answer.text.contains("rounded to the plates"))
    }

    @Test func planWorkoutWithoutAGymAsksForOne() {
        var f = facts
        f.plannedSession = nil
        f.gymConfigured = false
        #expect(CoachAnswers.planWorkout(f)!.text.contains("no gym is set up"))
    }

    @Test func cardioSwapIsEasyOnLowRecovery() {
        var f = facts
        f.recovery = 20
        #expect(CoachAnswers.cardioSwap(f)!.text.contains("zone 2"))
        #expect(CoachAnswers.cardioSwap(facts)!.text.contains("40-60 minutes"))
    }

    @Test func eatingEnoughComparesWithTargets() {
        let answer = CoachAnswers.eatingEnough(facts)!
        #expect(answer.text.contains("Protein so far: 70 g of your 150 g target, so about 80 g to go."))
        #expect(answer.text.contains("1400 kcal eaten, about 1200 kcal left of your 2600 kcal target."))
        #expect(answer.action == "Make your next meal protein-led: about 40 g.")
    }

    @Test func eatingEnoughIsTailoredToTheGoal() {
        var f = facts
        f.goals = Goals(weight: .lose, focuses: [.muscle])
        #expect(CoachAnswers.eatingEnough(f)!.text.contains("On a cut"))
        f.goals = Goals(weight: .gain, focuses: [.muscle])
        #expect(CoachAnswers.eatingEnough(f)!.text.contains("To gain"))
    }

    @Test func eatingEnoughWithoutFoodSaysSo() {
        var f = facts
        f.caloriesEaten = nil
        f.proteinGrams = nil
        #expect(CoachAnswers.eatingEnough(f)!.text.hasPrefix("No food is logged"))
    }

    @Test func eatAfterGivesTheProteinDose() {
        // 0.3 g/kg × 85 kg ≈ 26 g, inside the ISSN 20-40 g range (Jäger 2017; Kerksick 2017).
        let answer = CoachAnswers.eatAfter(facts)!
        #expect(answer.text.contains("about 26 g of protein"))
        #expect(answer.text.contains("70 g of 150 g"))
        #expect(answer.action == "Have a meal with about 26 g of protein in the next two hours.")
        var heavy = facts
        heavy.bodyMassKg = 150
        #expect(CoachAnswers.eatAfter(heavy)!.text.contains("about 40 g"))
        var light = facts
        light.bodyMassKg = 50
        #expect(CoachAnswers.eatAfter(light)!.text.contains("about 20 g"))
    }

    @Test func eatAfterTailorsCarbsToTheGoal() {
        var f = facts
        f.goals = Goals(weight: .maintain, focuses: [.endurance])
        #expect(CoachAnswers.eatAfter(f)!.text.contains("85 g of carbs"))
        f.goals = Goals(weight: .lose, focuses: [.health])
        #expect(CoachAnswers.eatAfter(f)!.text.contains("protein-led"))
    }

    @Test func sleepReportsHoursAgainstNeed() {
        let answer = CoachAnswers.sleep(facts)!
        #expect(answer.text.hasPrefix("You slept 7.6 h, about 0.4 h under your 8.0 h need (sleep score 78)."))
        #expect(answer.text.contains("Deep 1.4 h, REM 1.7 h, 2 interruptions."))
        #expect(answer.action == "Keep the same bed and wake time tonight.")
    }

    @Test func shortSleepGetsTheSevenHourFloor() {
        var f = facts
        f.sleepHours = 5.5
        f.sleepDebtHours = 6
        let answer = CoachAnswers.sleep(f)!
        #expect(answer.text.contains("7 h is the adult floor"))
        #expect(answer.text.contains("6.0 h behind"))
        #expect(answer.action == "Aim for bed about 30 minutes earlier tonight.")
    }

    @Test func strainSplitsCardioAndLifting() {
        let answer = CoachAnswers.strain(facts)!
        #expect(answer.text.hasPrefix("Strain is 18% so far today"))
        #expect(answer.text.contains("About 75% of it came from cardio and 25% from lifting."))
        #expect(answer.text.contains("Yesterday reached 62%."))
        #expect(answer.action == "A session that adds about 32 points lands you in range.")
    }

    @Test func strainAboveTargetSuggestsAnEasyRest() {
        var f = facts
        f.strain = 80
        #expect(CoachAnswers.strain(f)!.action == "You're past today's range; make the rest of the day easy.")
    }

    @Test func fallbackPicksTheNearestAnswer() {
        #expect(CoachAnswers.fallback(for: .nutrition, facts: facts)?.question == .eatingEnough)
        #expect(CoachAnswers.fallback(for: .training, facts: facts)?.question == .planWorkout)
        #expect(CoachAnswers.fallback(for: .recovery, facts: facts)?.question == .whyRecovery)
        #expect(CoachAnswers.fallback(for: .general, facts: facts)?.question == .trainToday)
        var noPlan = facts
        noPlan.plannedSession = nil
        #expect(CoachAnswers.fallback(for: .training, facts: noPlan)?.question == .trainToday)
    }

    @Test func factLinesStayShortAndOnTopic() {
        var f = facts
        f.extraLines = ["Water today 1.2 L.", "Usual bedtime 23:10; caffeine cut-off 14:10 for coffee.", "Body age 34-38 vs real age 36."]
        f.medicationLines = ["Metformin: can lower resting heart rate readings."]
        f.labLines = ["Ferritin 20 ng/mL (low)."]
        let lines = CoachAnswers.factLines(for: "When should I stop drinking coffee?", topic: .general, facts: f)
        #expect(lines.count <= 10)
        #expect(lines.joined(separator: "\n").count <= 900)
        #expect(lines.contains { $0.contains("caffeine cut-off") })
        #expect(!lines.contains { $0.contains("Metformin") })
        #expect(!lines.contains { $0.contains("Ferritin") })
        #expect(lines.contains { $0.hasPrefix("Goal:") })
        #expect(lines.contains { $0.hasPrefix("Recovery 55%") })
    }

    @Test func factLinesIncludeMedicationsOnlyWhenAsked() {
        var f = facts
        f.medicationLines = ["Metformin: can lower resting heart rate readings."]
        let lines = CoachAnswers.factLines(for: "Do my medications change my recovery?", topic: .recovery, facts: f)
        #expect(lines.contains { $0.contains("Metformin") })
        #expect(lines.contains { $0.hasPrefix("Sleep 7.6 h") })
    }

    @Test func nutritionFactLinesCarryTheFoodNumbers() {
        let lines = CoachAnswers.factLines(for: "What should I have for dinner?", topic: .nutrition, facts: facts)
        #expect(lines.contains("Protein today 70 g of 150 g target."))
        #expect(lines.contains("Calories eaten 1400 kcal, target 2600 kcal."))
    }
}
