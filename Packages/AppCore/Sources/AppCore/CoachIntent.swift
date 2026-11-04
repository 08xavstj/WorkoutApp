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
        !Set(words(text)).isDisjoint(with: ["run", "running", "ride", "riding", "cycle", "cycling", "bike", "cardio", "swim", "row", "rowing"])
    }
}
