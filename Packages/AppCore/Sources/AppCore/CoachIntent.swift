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
        "fuel", "breakfast", "lunch", "dinner", "shake", "macros", "fibre", "fiber", "hungry", "fasting", "fasted",
    ]

    /// Words that make a message about training, not a request for a plan
    /// on their own: "Why are my legs sore?" mentions legs and wants no workout.
    static let trainingWords: Set<String> = [
        "train", "training", "workout", "workouts", "session", "lift", "lifting", "gym", "exercise", "exercises", "routine",
    ]

    /// Body parts and split days a workout can be built around (`requestedFocusAndMinutes` in the app).
    static let focusWords: Set<String> = [
        "push", "pull", "leg", "legs", "upper", "lower", "chest", "back", "arms", "arm", "shoulders", "shoulder", "glutes",
    ]

    static let recoveryWords: Set<String> = [
        "recovery", "recover", "recovered", "recovering", "sleep", "slept", "sleeping", "hrv", "tired", "fatigue",
        "fatigued", "sore", "soreness", "rest", "resting", "stress", "stressed", "strain",
    ]

    /// Pain, injury and illness: such a message never gets a workout card or a
    /// canned answer; it goes to the model, whose reply says what the data can't.
    static let painOrIllnessWords: Set<String> = [
        "sore", "soreness", "hurt", "hurts", "hurting", "pain", "painful", "ache", "aches", "aching", "achy", "injury",
        "injured", "injure", "strained", "sprain", "sprained", "tweaked", "cramp", "cramps", "cold", "sick", "ill",
        "illness", "flu", "fever", "covid", "unwell", "nausea", "nauseous", "dizzy", "headache", "migraine", "tendonitis",
    ]

    /// "How did…", "was my…": a question about something that already happened.
    static let pastQuestionPhrases = [
        "did i", "did my", "have i", "how did", "how was", "how were", "what did", "when did", "when was", "was my",
        "were my", "i did", "i went",
    ]
    /// Past-tense words that only count when nothing in the message points at today or later.
    static let pastWords: Set<String> = [
        "yesterday", "yesterdays", "went", "last", "ago", "ran", "rode", "swam", "walked", "trained", "lifted", "worked", "did",
    ]
    static let presentWords: Set<String> = ["today", "tomorrow", "tonight", "now", "next"]

    /// Asking for a workout in so many words: these win even over food words
    /// and over past-tense words ("I did legs yesterday, plan my workout").
    static let workoutRequests = [
        "plan my workout", "plan a workout", "plan me a workout", "plan my next workout", "plan my session", "plan a session",
        "next workout", "next session", "build a workout", "build me a workout", "build my workout", "give me a workout",
        "give me a session", "make me a workout", "make it leg day", "make it a leg day", "make it push day",
        "make it pull day", "make it upper", "make it lower", "make it full body", "work out today", "start a workout", "start my workout", "workout plan", "workout for today", "workout today",
        "i want to train", "i want to lift", "i want to work out", "i want a workout",
    ]

    /// A split named on its own ("Leg day", "45 min full body"): a request
    /// unless the message is a question about it ("Why is leg day so hard?").
    static let splitNames = [
        "full body", "lower body", "upper body", "leg day", "push day", "pull day", "upper day", "lower day", "arm day",
        "back day", "chest day", "shoulder day",
    ]

    /// Openers that ask for something to do ("what should I do at the gym").
    static let requestPhrases = [
        "what should i do", "what should i train", "what should i lift", "what can i do", "what workout", "which workout",
        "what to do", "what to train", "give me", "make me", "make it", "make a", "build me", "build a", "build my",
        "plan", "create", "generate", "design", "suggest", "recommend", "write me", "want to train", "want to do",
        "want to lift", "want to work out", "i only have", "i ve got", "what s a good", "whats a good", "what is a good",
        "show me", "quick", "short",
    ]

    /// Openers of a question that wants information, not a session ("How many
    /// sets for chest?", "Do you recommend squats?"): no plan card unless the
    /// message also asks for one in so many words.
    static let informationOpeners = [
        "how many", "how much", "how often", "how long", "how do", "how does", "how is", "is it", "is", "are", "does",
        "do", "why", "when", "what does", "what do",
    ]

    /// Whether `tokens` begin with `phrase` as whole words.
    static func starts(with phrase: String, _ tokens: [String]) -> Bool {
        let target = phrase.split(separator: " ").map(String.init)
        return tokens.count >= target.count && Array(tokens.prefix(target.count)) == target
    }

    /// Whether the message is about pain, an injury or illness.
    public static func isAboutPainOrIllness(_ text: String) -> Bool {
        !Set(words(text)).isDisjoint(with: painOrIllnessWords)
    }

    /// Whether the message asks about something that already happened
    /// ("How did my workout go yesterday?"), not about today or the next session.
    public static func isAboutThePast(_ text: String) -> Bool {
        let tokens = words(text)
        if pastQuestionPhrases.contains(where: { containsPhrase($0, in: tokens) }) { return true }
        let set = Set(tokens)
        return !set.isDisjoint(with: pastWords) && set.isDisjoint(with: presentWords)
    }

    /// Whether the user asks for a workout even on a rest day or in rest mode
    /// ("give me a workout anyway", "I want to train").
    public static func insistsOnWorkout(_ text: String) -> Bool {
        let tokens = words(text)
        if !Set(tokens).isDisjoint(with: ["anyway", "anyways", "regardless"]) { return true }
        return [
            "i want to train", "i want to lift", "i want to work out", "i want a workout", "i still want", "still want to",
            "give me a workout", "give me a session", "i d like to train", "i would like to train", "i d like a workout",
            "let me train", "i m training anyway", "i feel fine",
        ].contains { containsPhrase($0, in: tokens) }
    }

    /// Whether the reply should carry a planned workout: the message asks for
    /// one (a request verb with a training word, a focus with a length, or
    /// "how should I train today"), and isn't a food question that merely
    /// mentions it, a question about a past workout, or about pain or illness.
    public static func wantsWorkoutPlan(_ text: String) -> Bool {
        let tokens = words(text)
        let set = Set(tokens)
        func has(_ phrases: [String]) -> Bool { phrases.contains { containsPhrase($0, in: tokens) } }
        if !set.isDisjoint(with: painOrIllnessWords) { return false }
        if has(workoutRequests) { return true }
        if isAboutThePast(text) { return false }
        if !set.isDisjoint(with: nutritionWords) { return false }
        if asksAboutTrainingToday(tokens) { return true }
        // "Why is leg day so hard?" or "How many sets for chest?" is a question, not a request.
        if set.contains("why") || informationOpeners.contains(where: { starts(with: $0, tokens) }) { return false }
        if has(splitNames) { return true }
        let training = !set.isDisjoint(with: trainingWords) || containsPhrase("work out", in: tokens)
        let focus = !set.isDisjoint(with: focusWords)
        let minutes = mentionsMinutes(tokens)
        if has(requestPhrases), training || focus || minutes { return true }
        // "45 min upper", "push, 30 minutes".
        if focus && minutes { return true }
        // "Make it 30 min" or "30 min please" after a workout reply.
        return minutes && tokens.count <= 5
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
        if !set.isDisjoint(with: trainingWords) || !set.isDisjoint(with: focusWords) { return .training }
        return .general
    }

    /// Whether a message asks for cardio instead of lifting (whole words: not "crunches").
    public static func wantsCardio(_ text: String) -> Bool {
        !Set(words(text)).isDisjoint(with: cardioWords)
    }

    static let cardioWords: Set<String> = ["run", "running", "ride", "riding", "cycle", "cycling", "bike", "cardio", "swim", "row", "rowing"]

    // MARK: - Questions the app suggests

    /// The prompts offered on the empty Coach screen. Every one of these must
    /// route through `question(_:)` to a `CoachAnswers` answer: a suggestion
    /// the app itself makes must never reach the on-device model, which
    /// declines questions it reads as health advice (`CoachRoutingTests`).
    public static let suggestedQuestions = [
        "How should I train today?",
        "Why is my recovery where it is?",
        "Plan my next workout",
        "Am I eating enough for my training?",
    ]

    /// The follow-up chips shown under a reply; same rule as `suggestedQuestions`.
    public static let followUpQuestions = [
        "Make it 30 min",
        "Swap for a ride",
        "What should I eat after?",
        "Make it leg day",
    ]

    /// What Today's "Ask why" sends to Coach (`ScoresCard`); same rule.
    public static let askWhyQuestion = "How should I train today, and why?"

    /// Every question the app puts in the user's mouth.
    public static var allSuggestedQuestions: [String] {
        suggestedQuestions + followUpQuestions + [askWhyQuestion]
    }

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
        /// "Should I rest today?" (a rest *day*, not rest between sets)
        case shouldRest
        /// "How long should I rest between sets?"
        case restBetweenSets
        /// "How many calories did I burn today?" (energy out, not food in)
        case energyBurned
        /// "How did my workout go yesterday?"
        case lastWorkout
        /// "What's my resting heart rate?"
        case restingHeartRate
        /// "What's my HRV?"
        case hrv
        /// "How many steps today?"
        case steps
        /// "What's my VO2 max?"
        case vo2Max
        /// "What do I weigh?"
        case bodyWeight
    }

    static let restQuestions = [
        "should i rest", "rest today", "take a rest", "day off", "today off", "skip today", "should i skip",
        "rest day", "need a rest", "need rest", "take it easy today", "is today a rest",
    ]

    static let trainTodayQuestions = [
        "how should i train", "train today", "training today", "workout today", "work out today",
        "what should i do today", "gym today", "lift today", "what kind of day", "hard today", "what today",
        "plan for today", "how hard today", "how hard should i", "how hard can i",
    ]
    /// "Should I train?" is about today only when it says so or stops there:
    /// "Should I train to failure?" is a technique question for the model.
    static let shouldITrainQuestions = ["should i train", "should i lift", "should i work out", "should i go to the gym", "should i workout"]

    /// Whether the message asks how (or whether) to train today.
    static func asksAboutTrainingToday(_ tokens: [String]) -> Bool {
        if trainTodayQuestions.contains(where: { containsPhrase($0, in: tokens) }) { return true }
        guard let phrase = shouldITrainQuestions.first(where: { containsPhrase($0, in: tokens) }) else { return false }
        // Today, tonight…, or nothing after it ("Should I train?").
        return !Set(tokens).isDisjoint(with: presentWords) || tokens.count == phrase.split(separator: " ").count
    }

    static let sleepReadingWords: Set<String> = ["how", "did", "was", "my", "score", "night", "enough", "last", "hours", "much", "long"]
    /// Sleep *advice* ("how can I sleep better") goes to the model.
    static let sleepAdviceWords: Set<String> = ["better", "improve", "improving", "tips", "tip", "advice", "help", "fall", "trouble", "insomnia", "earlier", "cant", "can't", "routine"]
    /// "What is strain?" or "how is strain calculated" is an explanation, not a reading.
    static let explanationWords: Set<String> = ["calculated", "computed", "mean", "means", "meaning", "definition", "work", "works", "explain", "explained"]
    static let enoughWords: Set<String> = ["enough", "left", "remaining", "track", "today", "far", "many", "much", "hit", "target", "under", "over", "short", "low", "deficit", "surplus"]

    static let restBetweenSetsPhrases = [
        "between sets", "between my sets", "between each set", "between exercises", "rest timer", "rest period",
        "rest periods", "rest interval", "rest intervals", "rest time", "rest times", "per set", "after each set",
    ]
    static let burnWords: Set<String> = ["burn", "burned", "burnt", "burning", "expenditure", "expended"]
    static let lastWorkoutPhrases = [
        "last workout", "last session", "last gym session", "last lift", "last training", "yesterday s workout",
        "yesterdays workout", "workout yesterday", "session yesterday", "how did my workout", "how did my session",
        "how was my workout", "how was my session", "how did i do", "how did my training", "how was my training",
        "when did i last", "last time i trained", "last time i lifted", "last time i worked out", "when was my last",
        "my previous workout", "previous session",
    ]
    /// A reading ("what's my HRV") is answered from the data; a question that
    /// wants advice or a judgement about it ("why is my HRV low", "how can I
    /// lower my resting heart rate") goes to the model.
    static let readingAdviceWords: Set<String> = [
        "why", "improve", "improving", "lower", "lowering", "raise", "raising", "increase", "increasing", "boost", "better",
        "tips", "tip", "advice", "help", "affect", "affects", "normal", "good", "bad", "healthy", "mean", "means", "should",
        "fix", "drop", "dropped", "high", "low", "higher", "calculated", "measure", "measured", "accurate", "explain",
    ]

    /// The data reading a message mentions, if any (resting heart rate, HRV,
    /// steps, VO2 max, body weight), whatever it asks about it.
    static func readingMentioned(_ tokens: [String]) -> Question? {
        let set = Set(tokens)
        func has(_ phrases: [String]) -> Bool { phrases.contains { containsPhrase($0, in: tokens) } }
        if has(["resting heart rate", "resting hr", "resting pulse", "morning pulse", "resting bpm"]) || set.contains("rhr") { return .restingHeartRate }
        if set.contains("hrv") || has(["heart rate variability"]) { return .hrv }
        if !set.isDisjoint(with: ["vo2", "vo2max", "vo₂", "vo₂max"]) || has(["cardio fitness", "vo 2"]) { return .vo2Max }
        if has(["how many steps", "my steps", "steps today", "step count", "steps so far", "step goal", "steps did", "steps have", "steps yesterday"]) { return .steps }
        if has(["do i weigh", "i weigh", "my weight", "my body weight", "my bodyweight", "current weight", "weigh in", "weigh ins"]) { return .bodyWeight }
        return nil
    }

    /// The question the app can answer itself, or nil for an open question.
    public static func question(_ text: String) -> Question? {
        let tokens = words(text)
        let set = Set(tokens)
        func has(_ phrases: [String]) -> Bool { phrases.contains { containsPhrase($0, in: tokens) } }
        let food = !set.isDisjoint(with: nutritionWords)
        let past = isAboutThePast(text)

        // Pain, injury and illness: never a canned answer about something else.
        if !set.isDisjoint(with: painOrIllnessWords) { return nil }
        // Rest between sets is the rest timer, not a rest day.
        if !food, has(restBetweenSetsPhrases)
            || (set.contains("rest") && has(["how long", "how much"]) && !set.isDisjoint(with: ["sets", "set", "reps", "lifts", "exercise", "exercises"])) {
            return .restBetweenSets
        }
        // Energy out ("calories did I burn"), not food in; "burn fat" is advice.
        let burnAdvice: Set<String> = ["fat", "eat", "eating", "ate", "food", "meal", "lose", "more", "should", "best", "help", "most"]
        if (!set.isDisjoint(with: burnWords) && set.isDisjoint(with: burnAdvice))
            || has(["active calories", "active energy", "energy out", "calories out"]) {
            return .energyBurned
        }
        if !food, has(lastWorkoutPhrases) { return .lastWorkout }
        if !food, !past, has(restQuestions) { return .shouldRest }
        if !food, !past, asksAboutTrainingToday(tokens) { return .trainToday }
        if !food, !past, wantsCardio(text), set.contains("swap") || set.contains("instead") || set.contains("rather")
            || has(["make it a", "make it cardio", "change it to"]) { return .cardioSwap }
        if wantsWorkoutPlan(text) { return .planWorkout }
        if food {
            if set.contains("after") || set.contains("post") || has(["for recovery"]) { return .eatAfter }
            // Before training is a different question from the day's totals: the model takes it.
            if set.contains("before") || set.contains("pre") { return nil }
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
        if let reading = readingMentioned(tokens), set.isDisjoint(with: readingAdviceWords) { return reading }
        return nil
    }

    /// The data answer closest to an open question, for when the on-device
    /// model can't take it (turned off, still downloading, or it declined):
    /// only an answer about the same thing ("Is my HRV normal?" gets the HRV
    /// reading), never a different one. nil means show the model's error.
    public static func relatedQuestion(_ text: String) -> Question? {
        if let routed = question(text) { return routed }
        let tokens = words(text)
        let set = Set(tokens)
        if !set.isDisjoint(with: painOrIllnessWords) { return nil }
        if let reading = readingMentioned(tokens) { return reading }
        if set.contains("strain") { return .strain }
        if !set.isDisjoint(with: ["recovery", "recovered"]) { return .whyRecovery }
        if !set.isDisjoint(with: ["sleep", "slept", "sleeping"]) { return .sleep }
        // A meal question gets the day's food against the targets; supplements,
        // water or creatine don't (that would answer a different question).
        if !set.isDisjoint(with: ["eat", "eating", "ate", "meal", "meals", "breakfast", "lunch", "dinner", "snack", "snacks", "protein", "calories", "calorie", "kcal", "macros"]) {
            return .eatingEnough
        }
        return nil
    }
}
