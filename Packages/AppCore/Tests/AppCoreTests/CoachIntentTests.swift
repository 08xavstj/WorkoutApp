import Testing
@testable import AppCore

struct CoachIntentTests {
    @Test(arguments: [
        "What should I eat after my workout?",
        "what to eat after my workout",
        "What should I eat after?",
        "Am I eating enough for my training?",
        "How much protein after the gym?",
    ])
    func foodQuestionsGetNoWorkout(_ question: String) {
        #expect(!CoachIntent.wantsWorkoutPlan(question))
        #expect(CoachIntent.topic(question) == .nutrition)
    }

    @Test(arguments: [
        "How should I train today?",
        "Plan my next workout",
        "Make it leg day",
        "Make it 30 min",
        "make it 45min",
        "Give me a workout, then what should I eat?",
    ])
    func workoutRequestsGetAPlan(_ question: String) {
        #expect(CoachIntent.wantsWorkoutPlan(question))
        #expect(CoachIntent.topic(question) == .training)
    }

    @Test func recoveryQuestionsAreRecovery() {
        #expect(CoachIntent.topic("Why is my recovery where it is?") == .recovery)
        #expect(CoachIntent.topic("I slept badly, what now?") == .recovery)
        #expect(!CoachIntent.wantsWorkoutPlan("Why is my recovery where it is?"))
    }

    @Test func wholeWordsOnly() {
        // "vitamin", "feedback" and "crunches" contain no trigger words.
        #expect(CoachIntent.topic("Any feedback on vitamin D?") == .general)
        #expect(!CoachIntent.wantsCardio("Are crunches useful?"))
        #expect(CoachIntent.wantsCardio("Swap for a ride"))
    }
}

/// Every question the app itself suggests (empty-screen chips, follow-ups,
/// Today's "Ask why") must be answered from the data, never by the model.
struct CoachRoutingTests {
    @Test func everySuggestedQuestionRoutesToAnAnswer() {
        for text in CoachIntent.allSuggestedQuestions {
            let question = CoachIntent.question(text)
            #expect(question != nil, "\(text) would reach the model")
            guard let question else { continue }
            // With nothing synced, with everything, and in rest mode: always an answer.
            #expect(CoachAnswers.answer(for: question, facts: CoachFacts()) != nil, "\(text)")
            #expect(CoachAnswers.answer(for: question, facts: CoachAnswersTests().facts) != nil, "\(text)")
            var resting = CoachFacts()
            resting.restMode = true
            #expect(CoachAnswers.answer(for: question, facts: resting) != nil, "\(text)")
        }
    }

    @Test func theSuggestedListsMatchTheChips() {
        #expect(CoachIntent.suggestedQuestions.count == 4)
        #expect(CoachIntent.followUpQuestions.count == 4)
        #expect(CoachIntent.askWhyQuestion == "How should I train today, and why?")
        #expect(CoachIntent.question(CoachIntent.askWhyQuestion) == .trainToday)
    }

    /// When the model can't answer, the stand-in must be about the same thing:
    /// an open general question gets no canned answer (it used to get "how
    /// should I train today" for anything, e.g. a resting heart rate question).
    @Test func fallbacksOnlyAnswerTheSameQuestion() {
        let facts = CoachAnswersTests().facts
        #expect(CoachAnswers.fallback(for: "Any feedback on vitamin D?", facts: facts) == nil)
        #expect(CoachAnswers.fallback(for: "Is creatine worth taking?", facts: facts) == nil)
        #expect(CoachAnswers.fallback(for: "Why are my legs sore?", facts: facts) == nil)
        #expect(CoachAnswers.fallback(for: "Is my HRV normal?", facts: facts)?.question == .hrv)
        #expect(CoachAnswers.fallback(for: "Is my resting heart rate too high?", facts: facts)?.question == .restingHeartRate)
        #expect(CoachAnswers.fallback(for: "How can I sleep better?", facts: facts)?.question == .sleep)
        #expect(CoachAnswers.fallback(for: "What should I have for dinner?", facts: facts)?.question == .eatingEnough)
        #expect(CoachAnswers.fallback(for: "How is strain calculated?", facts: facts)?.question == .strain)
    }
}

/// Realistic phrasings, with the data answer each should get (nil = the
/// model) and whether a workout card is attached. Written from the user's
/// reports: a food, soreness or rest-timer question must never get a plan.
struct CoachPhrasingTableTests {
    @Test(arguments: [
        // Workout requests: a plan.
        ("Plan my next workout", CoachIntent.Question?.some(.planWorkout), true),
        ("Give me a push workout", .planWorkout, true),
        ("Can you build me a 45 minute leg session?", .planWorkout, true),
        ("45 min upper body", .planWorkout, true),
        ("I only have 30 minutes, what should I do at the gym?", .planWorkout, true),
        ("What's a good pull workout for today?", .planWorkout, true),
        ("I did legs yesterday, plan my workout", .planWorkout, true),
        ("Make it 30 min", .planWorkout, true),
        ("Make it leg day", .planWorkout, true),
        ("How should I train today?", .trainToday, true),
        ("Should I lift today?", .trainToday, true),
        ("Give me a workout anyway", .planWorkout, true),
        ("I want to train", .planWorkout, true),
        // Questions that mention training but want no plan.
        ("How long should I rest between sets?", .restBetweenSets, false),
        ("How much rest between sets for strength?", .restBetweenSets, false),
        ("Why are my legs sore?", nil, false),
        ("My shoulders hurt when I push", nil, false),
        ("Is it OK to train with a cold?", nil, false),
        ("Should I train if I'm sick?", nil, false),
        ("I tweaked my back deadlifting", nil, false),
        ("How did my workout go yesterday?", .lastWorkout, false),
        ("When was my last workout?", .lastWorkout, false),
        ("Did I train today?", nil, false),
        ("How many sets should I do for chest?", nil, false),
        ("Why is leg day so hard?", nil, false),
        ("Does lifting make you bulky?", nil, false),
        ("What muscles does the bench press work?", nil, false),
        ("Is training fasted bad?", nil, false),
        ("Should I train to failure?", nil, false),
        ("Should I train fasted?", nil, false),
        ("What should I eat before I train today?", nil, false),
        // Food.
        ("What should I eat after my workout?", .eatAfter, false),
        ("What should I eat after?", .eatAfter, false),
        ("Am I eating enough protein today?", .eatingEnough, false),
        ("How many calories did I burn today?", .energyBurned, false),
        ("How many calories have I burned?", .energyBurned, false),
        ("What burns more calories, running or lifting?", nil, false),
        ("What should I eat to burn fat?", nil, false),
        // Rest days, sleep, scores and readings.
        ("Should I rest today?", .shouldRest, false),
        ("Should I take a day off?", .shouldRest, false),
        ("How did I sleep?", .sleep, false),
        ("Why is my recovery low?", .whyRecovery, false),
        ("What's my strain?", .strain, false),
        ("What's my resting heart rate?", .restingHeartRate, false),
        ("What is my HRV today?", .hrv, false),
        ("How many steps today?", .steps, false),
        ("What's my VO2 max?", .vo2Max, false),
        ("How much do I weigh?", .bodyWeight, false),
        ("How can I lower my resting heart rate?", nil, false),
        ("Swap for a ride", .cardioSwap, false),
    ])
    func routes(_ text: String, _ expected: CoachIntent.Question?, _ plan: Bool) {
        #expect(CoachIntent.question(text) == expected, "\(text)")
        // The app attaches a card for a training request that isn't cardio (CoachView.send).
        let attaches = CoachIntent.wantsWorkoutPlan(text) && !CoachIntent.wantsCardio(text)
        #expect(attaches == plan, "\(text)")
    }

    @Test(arguments: ["Give me a workout anyway", "I want to train", "I'd like to train regardless", "I still want to lift"])
    func insistingOverridesARestDay(_ text: String) {
        #expect(CoachIntent.insistsOnWorkout(text))
    }

    @Test(arguments: ["Plan my next workout", "How should I train today?", "Make it 30 min"])
    func ordinaryRequestsDoNotInsist(_ text: String) {
        #expect(!CoachIntent.insistsOnWorkout(text))
    }
}
