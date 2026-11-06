import Foundation

/// What a coach question is about, from its words, so the app can give the
/// coach the right data and only attach a workout card when one was asked for.
/// "What should I eat after my workout?" is a food question, not a request for
/// a workout, even though it says "workout".
public enum CoachIntent {
    public enum Topic: String, Sendable, Equatable {
        case nutrition, training, recovery, general
    }

    /// The lowercased words in a message ("leg-day!" → ["leg", "day"]).
    public static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Whether `words` contains `phrase` as whole words ("leg day" in "make it leg day").
    public static func containsPhrase(_ phrase: String, in words: [String]) -> Bool {
        let target = phrase.split(separator: " ").map(String.init)
        guard !target.isEmpty, words.count >= target.count else { return false }
        return (0...(words.count - target.count)).contains { Array(words[$0..<($0 + target.count)]) == target }
    }

    static let nutritionWords: Set<String> = [
        "eat", "eating", "ate", "food", "foods", "meal", "meals", "snack", "snacks", "protein", "carb", "carbs",
        "carbohydrate", "carbohydrates", "fat", "fats", "calorie", "calories", "kcal", "diet", "nutrition",
        "drink", "drinks", "drinking", "water", "hydration", "hydrate", "supplement", "supplements", "creatine",
        "fuel", "breakfast", "lunch", "dinner", "shake", "macros", "fibre", "fiber", "hungry", "fasting",
    ]

    static let trainingWords: Set<String> = [
        "train", "training", "workout", "workouts", "session", "lift", "lifting", "gym", "push", "pull", "leg",
        "legs", "upper", "exercise", "exercises", "chest", "arms", "shoulders",
    ]

    static let recoveryWords: Set<String> = [
        "recovery", "recover", "recovered", "recovering", "sleep", "slept", "sleeping", "hrv", "tired", "fatigue",
        "fatigued", "sore", "soreness", "rest", "resting", "stress", "stressed", "strain",
    ]

    /// Asking for a workout in so many words: these win even over food words.
    static let workoutRequests = [
        "plan my workout", "plan a workout", "plan my next workout", "next workout", "build a workout",
        "build me a workout", "give me a workout", "make me a workout", "make it leg day", "full body",
        "lower body", "leg day", "work out today",
    ]

    /// Whether the reply should carry a planned workout: the message asks
    /// for training, and isn't a food question that merely mentions it.
    public static func wantsWorkoutPlan(_ text: String) -> Bool {
        let tokens = words(text)
        if workoutRequests.contains(where: { containsPhrase($0, in: tokens) }) { return true }
        let set = Set(tokens)
        if !set.isDisjoint(with: nutritionWords) { return false }
        if !set.isDisjoint(with: trainingWords) || containsPhrase("work out", in: tokens) { return true }
        // "Make it 30 min" after a workout reply.
        return mentionsMinutes(tokens)
    }

    /// "30 min", "45 minutes" or "30min": a two- or three-digit number of minutes.
    static func mentionsMinutes(_ tokens: [String]) -> Bool {
        let units: Set<String> = ["min", "mins", "minute", "minutes"]
        for (index, token) in tokens.enumerated() {
            let digits = token.prefix { $0.isNumber }
            guard (2...3).contains(digits.count) else { continue }
            let rest = String(token.dropFirst(digits.count))
            if units.contains(rest) { return true }
            if rest.isEmpty, index + 1 < tokens.count, units.contains(tokens[index + 1]) { return true }
        }
        return false
    }

    /// The main subject, for choosing which data the coach gets.
    public static func topic(_ text: String) -> Topic {
        let set = Set(words(text))
        if wantsWorkoutPlan(text) { return .training }
        if !set.isDisjoint(with: nutritionWords) { return .nutrition }
        if !set.isDisjoint(with: recoveryWords) { return .recovery }
        return .general
    }

    /// Whether a message asks for cardio instead of lifting (whole words: not "crunches").
    public static func wantsCardio(_ text: String) -> Bool {
        !Set(words(text)).isDisjoint(with: cardioWords)
    }

    static let cardioWords: Set<String> = ["run", "running", "ride", "riding", "cycle", "cycling", "bike", "cardio", "swim", "row", "rowing"]

    // MARK: - Questions the app answers itself

    /// A question the app can answer from its own numbers, without the
    /// language model (`CoachAnswers`). Routing is by whole words and short
    /// phrases, so "what should I eat after my workout" is `eatAfter`, not a
    /// workout request, and "how can I sleep better" (advice, not a reading)
    /// stays an open question for the model.
    public enum Question: String, Sendable, Equatable, CaseIterable {
        /// "How should I train today?"
        case trainToday
        /// "Why is my recovery where it is?"
        case whyRecovery
        /// "Plan my next workout", "Make it leg day", "Make it 30 min"
        case planWorkout
        /// "Swap for a ride": cardio instead of the gym.
        case cardioSwap
        /// "Am I eating enough?"
        case eatingEnough
        /// "What should I eat after?"
        case eatAfter
        /// "How did I sleep?"
        case sleep
        /// "What's my strain?"
        case strain
        /// "Should I rest today?"
        case shouldRest
    }

    static let restQuestions = [
        "should i rest", "rest today", "take a rest", "day off", "today off", "skip today", "should i skip",
        "rest day", "need a rest", "need rest", "take it easy today", "is today a rest",
    ]

    static let trainTodayQuestions = [
        "how should i train", "train today", "training today", "workout today", "work out today",
        "what should i do today", "should i train", "should i lift", "should i work out", "should i go to the gym",
        "gym today", "lift today", "what kind of day", "hard today", "what today", "plan for today",
        "how hard today", "how hard should i", "how hard can i",
    ]

    static let sleepReadingWords: Set<String> = ["how", "did", "was", "my", "score", "night", "enough", "last", "hours", "much", "long"]
    /// Sleep *advice* ("how can I sleep better") goes to the model.
    static let sleepAdviceWords: Set<String> = ["better", "improve", "improving", "tips", "tip", "advice", "help", "fall", "trouble", "insomnia", "earlier", "cant", "can't", "routine"]
    /// "What is strain?" or "how is strain calculated" is an explanation, not a reading.
    static let explanationWords: Set<String> = ["calculated", "computed", "mean", "means", "meaning", "definition", "work", "works", "explain", "explained"]
    static let enoughWords: Set<String> = ["enough", "left", "remaining", "track", "today", "far", "many", "much", "hit", "target", "under", "over", "short", "low", "deficit", "surplus"]

    /// The question the app can answer itself, or nil for an open question.
    public static func question(_ text: String) -> Question? {
        let tokens = words(text)
        let set = Set(tokens)
        func has(_ phrases: [String]) -> Bool { phrases.contains { containsPhrase($0, in: tokens) } }
        let food = !set.isDisjoint(with: nutritionWords)

        if !food, has(restQuestions) { return .shouldRest }
        if !food, has(trainTodayQuestions) { return .trainToday }
        if !food, wantsCardio(text), set.contains("swap") || set.contains("instead") || set.contains("rather")
            || has(["make it a", "make it cardio", "change it to"]) { return .cardioSwap }
        if wantsWorkoutPlan(text) { return .planWorkout }
        if food {
            if set.contains("after") || set.contains("post") || has(["for recovery"]) { return .eatAfter }
            if has(["am i eating", "have i eaten", "did i eat", "eating enough", "eaten enough", "eat enough", "protein left", "calories left"])
                || (!set.isDisjoint(with: enoughWords) && (set.contains("protein") || set.contains("calories") || set.contains("calorie")
                    || set.contains("eating") || set.contains("eaten") || set.contains("eat") || set.contains("kcal"))) {
                return .eatingEnough
            }
            return nil
        }
        if !set.isDisjoint(with: ["recovery", "recovered"]), set.isDisjoint(with: explanationWords) { return .whyRecovery }
        if !set.isDisjoint(with: ["sleep", "slept", "sleeping"]) {
            if !set.isDisjoint(with: sleepAdviceWords) || !set.isDisjoint(with: explanationWords) { return nil }
            if !set.isDisjoint(with: sleepReadingWords) || set.contains("slept") { return .sleep }
            return nil
        }
        if set.contains("strain"), set.isDisjoint(with: explanationWords) { return .strain }
        return nil
    }
}
