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
