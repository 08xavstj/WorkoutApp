import Foundation

/// What a workout reminder may never say (`WorkoutBanter`). The same checks
/// run on every library line in the tests and on every line the on-device
/// model writes before it is used; a model line that trips any of them is
/// dropped and the library line stays.
///
/// The rules and what they rest on (docs/research/funny-nudges-2026-11.md):
/// - No body, body-weight, food or appearance talk: appearance and
///   body-image motives go with worse exercise adherence and well-being than
///   autonomous ones (Teixeira et al., IJBNPA 2012, via behaviour-change.md),
///   and weight stigma goes with avoiding exercise (Vartanian & Novak,
///   Obesity 2011; not re-verified). A joke on those topics has a cost and no upside.
/// - No guilt, shame, insults or controlling words ("should", "must"): see
///   `WorkoutBanter`. The word lists are the app's; no study tested them.
/// - Nothing about training through illness or pain in a joke, and in a
///   caution state no push to train at all (the app's own safety rules:
///   `PainGuard`, `IllnessWatch`, low recovery, rest mode).
/// - No number the facts don't hold: an invented "three weeks" or "100 kg"
///   would be the app making up data about the owner.
/// - No other product's name or mascot.
///
/// What it can't do: the word lists and the number check catch the usual ways
/// a line goes wrong, not every one. A model line can still invent a claim in
/// words the lists don't hold ("the barbell saw you leave early"). So only
/// training-log facts go into the prompt, model lines are at most half of what
/// is sent (`WorkoutBanter.generatedEvery`), and they can be switched off.
public enum WorkoutBanterGuard {
    public enum Problem: String, Sendable, CaseIterable {
        case tooLong, tooShort, unfilledSlot, bodyTalk, guiltOrShame, illnessOrInjury, pushesToTrain
        case otherProduct, strayNumber, emoji
    }

    // MARK: Word lists (app choices)

    static let bodyWords: Set<String> = [
        "fat", "fatter", "thin", "thinner", "skinny", "slim", "slimmer", "chubby", "flabby", "flab", "belly", "gut", "waist",
        "waistline", "abs", "sixpack", "beach", "bikini", "mirror", "sexy", "hot", "ugly", "diet", "diets", "dieting",
        "calorie", "calories", "eat", "eating", "ate", "food", "snack", "snacks", "dessert", "pizza", "burger", "cake",
        "donut", "doughnut", "hungry", "hunger", "meal", "meals", "protein", "body", "bodies", "physique", "figure",
        "toned", "shredded", "ripped", "jacked", "swole", "buff", "lean", "bulk", "bulking", "scale", "scales", "weigh",
        "weighs", "weighed", "bmi", "looks", "appearance", "attractive", "pretty", "handsome", "gains", "booty", "butt",
        "thighs", "pounds", "kilos", "overweight", "obese",
        // Jokes about thin limbs are body talk too ("noodle legs", "chicken legs"). Not "arms" or
        // "legs" on their own: lines name muscles and "Leg day" on purpose.
        "noodle", "noodles", "chicken", "scrawny", "puny", "twig", "twigs",
    ]

    static let bodyPhrases = [
        "your weight", "lose weight", "losing weight", "lost weight", "weight loss", "body weight", "bodyweight",
        "gain weight", "gained weight", "burn off", "work off", "earn your", "summer body", "in shape", "out of shape",
        "look good", "looking good", "look better",
    ]

    static let guiltWords: Set<String> = [
        "should", "shouldn", "must", "mustn", "ought", "missed", "skipped", "fail", "failed", "failing", "failure", "lazy",
        "laziness", "guilt", "guilty", "shame", "ashamed", "shameful", "excuse", "excuses", "disappoint", "disappointed",
        "disappointing", "pathetic", "weak", "weakling", "quitter", "quitting", "loser", "slacker", "slacking", "slack",
        "behind", "sad", "lonely", "cry", "crying", "cries", "heartbroken", "abandoned", "betrayed", "forgot", "forgotten",
        "ignored", "ignoring", "worthless", "useless", "coward", "wimp", "soft", "embarrassing", "embarrassed", "pitiful",
        "streak", "streaks", "slob", "sloth", "couch",
        // Skipping and quitting talk ("Never skip leg day", "Don't miss it", "Last time you quit early").
        "skip", "skips", "skipping", "miss", "quit", "quits",
    ]

    static let guiltPhrases = [
        "have to", "need to", "no excuses", "no excuse", "let me down", "let you down", "let yourself", "miss you",
        "misses you", "missing you", "where were you", "where have you been", "you owe", "don't break", "dont break",
        "you promised", "you said you", "you always", "you never", "what happened to", "give up", "gave up",
    ]

    /// Never in a joke; a caution line may name the state it is about.
    static let illnessWords: Set<String> = [
        "sick", "ill", "illness", "injury", "injured", "injuries", "hurt", "hurts", "hurting", "pain", "pains", "painful",
        "ache", "aches", "sore", "soreness", "fever", "flu", "doctor", "hospital", "vomit", "puke",
    ]

    static let illnessPhrases = [
        "push through", "power through", "tough it out", "suck it up", "man up", "no pain no gain", "no pain, no gain",
        "train through", "lift through", "through the pain", "until you drop", "till you drop", "no days off", "no rest days",
    ]

    /// A caution line must not urge training…
    static let pushPhrases = [
        "let's go", "lets go", "get after", "crush", "smash", "send it", "full send", "time to train", "time to lift",
        "go lift", "get to the gym", "don't skip", "you can still", "no days off", "get moving", "get it done", "do it anyway",
    ]
    /// …and must say that resting or going easy is fine.
    static let restWords: Set<String> = ["rest", "resting", "easy", "wait", "lighter", "fine", "off", "keep"]

    /// Other products' names and a well-known mascot, which a model's line must
    /// never borrow. Spelled backwards so that none of those names appears
    /// anywhere in the app, even in a list of words to refuse.
    static let otherProducts = Set(["ognilloud", "oud", "lwo", "poohw", "leveb"].map { String($0.reversed()) })

    static let numberWords: [String: String] = [
        "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
        "ten": "10", "eleven": "11", "twelve": "12",
    ]
    /// Number words with no single value to check against the facts: never used.
    /// ("one" and "zero" are left alone: "one more rep", "pick one" are not counts.)
    static let looseNumberWords: Set<String> = [
        "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty",
        "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "hundreds", "thousand", "thousands", "million",
        "millions", "billion", "billions", "dozen", "dozens", "twice", "thrice", "triple", "double",
    ]

    // MARK: Checks

    /// Everything wrong with a finished reminder line for these facts; empty when it may be sent.
    public static func problems(in text: String, facts: WorkoutBanter.Facts) -> [Problem] {
        var found: [Problem] = []
        if text.count > WorkoutBanter.maxBodyCharacters { found.append(.tooLong) }
        if text.count < WorkoutBanter.minBodyCharacters { found.append(.tooShort) }
        if text.contains("{") || text.contains("}") { found.append(.unfilledSlot) }
        if text.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { found.append(.emoji) }
        // The owner's own names ("Full body", a lift) are facts, not the app's wording.
        let wording = scrubbed(text, facts: facts).lowercased().replacingOccurrences(of: "’", with: "'")
        found += wordingProblems(wording, caution: facts.caution != nil)
        if !strayNumbers(in: text, facts: facts).isEmpty { found.append(.strayNumber) }
        return found
    }

    /// Problems in a library line's own words, before any fact is filled in:
    /// the word rules, an unknown slot, or a number written into the template.
    public static func templateProblems(_ line: WorkoutBanter.Line) -> [Problem] {
        var found: [Problem] = []
        if WorkoutBanter.slotNames(in: line.template).contains(where: { WorkoutBanter.Slot(rawValue: $0) == nil }) {
            found.append(.unfilledSlot)
        }
        let wording = line.template.replacing(/\{[A-Za-z]+\}/, with: "·").lowercased()
        let isCaution = WorkoutBanter.Caution.allCases.contains { $0.situation == line.situation }
        found += wordingProblems(wording, caution: isCaution)
        let words = CoachIntent.words(wording)
        if wording.contains(where: \.isNumber) || words.contains(where: { numberWords[$0] != nil || looseNumberWords.contains($0) }) {
            found.append(.strayNumber)
        }
        return found
    }

    static func wordingProblems(_ wording: String, caution: Bool) -> [Problem] {
        var found: [Problem] = []
        let ordered = CoachIntent.words(wording)
        let words = Set(ordered)
        // Whole words only: "learn your job" is not "earn your".
        func has(_ phrases: [String]) -> Bool {
            phrases.contains { CoachIntent.containsPhrase(CoachIntent.words($0).joined(separator: " "), in: ordered) }
        }
        if !words.isDisjoint(with: bodyWords) || has(bodyPhrases) { found.append(.bodyTalk) }
        if !words.isDisjoint(with: guiltWords) || has(guiltPhrases) { found.append(.guiltOrShame) }
        if has(illnessPhrases) || (!caution && !words.isDisjoint(with: illnessWords)) { found.append(.illnessOrInjury) }
        if caution, has(pushPhrases) || words.isDisjoint(with: restWords) { found.append(.pushesToTrain) }
        if !words.isDisjoint(with: otherProducts) { found.append(.otherProduct) }
        return found
    }

    /// `text` with the owner's own names taken out (session, lift, muscle,
    /// painful area), so a session called "Full body" isn't read as body talk.
    static func scrubbed(_ text: String, facts: WorkoutBanter.Facts) -> String {
        var result = text
        let names = [facts.sessionName, facts.lift?.name, facts.neglected?.muscle, facts.standout?.recordLift, facts.painArea]
            .compactMap { WorkoutBanter.clean($0) }
            .sorted { $0.count > $1.count }
        for name in names where name.count >= 2 {
            result = result.replacingOccurrences(of: name, with: "·", options: .caseInsensitive)
        }
        return result
    }

    /// "82.5", "6,240", "30" → "82.5", "6240", "30".
    static func numberTokens(_ text: String) -> [String] {
        text.matches(of: /\d+(?:,\d{3})*(?:\.\d+)?/).map { match in
            let raw = String(match.output).replacingOccurrences(of: ",", with: "")
            return Double(raw).map { WorkoutBanter.decimal($0) } ?? raw
        }
    }

    /// Every number the facts hold, as it would be written: whatever any slot shows.
    public static func allowedNumbers(_ facts: WorkoutBanter.Facts) -> Set<String> {
        Set(WorkoutBanter.Slot.allCases.compactMap { WorkoutBanter.value(of: $0, in: facts) }.flatMap(numberTokens))
    }

    /// Numbers in `text`, as digits or words, that the facts don't hold.
    public static func strayNumbers(in text: String, facts: WorkoutBanter.Facts) -> [String] {
        let allowed = allowedNumbers(facts)
        var stray = numberTokens(text).filter { !allowed.contains($0) }
        for word in CoachIntent.words(scrubbed(text, facts: facts)) {
            if let digits = numberWords[word], !allowed.contains(digits) { stray.append(word) }
            if looseNumberWords.contains(word) { stray.append(word) }
        }
        return stray
    }

    // MARK: Lines from the on-device model

    /// At most this share of a model line's words may match a recent line (app choice).
    public static let maxSimilarity = 0.6
    public static let maxGeneratedSentences = 3

    /// The model's line, tidied, if it may be sent; nil keeps the library line.
    /// On top of `problems`: one to three sentences, plain text, not a
    /// near-copy of a recent line or of the examples it was shown, and not
    /// the same opening as the last reminder.
    public static func acceptGenerated(_ candidate: String, facts: WorkoutBanter.Facts, recent: [String]) -> String? {
        guard facts.caution == nil, !facts.lastCall else { return nil }
        var text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        // "- line", "1. line", quoted lines: the model's habits, not content.
        guard !text.contains("\n") else { return nil }
        text = text.replacing(/^[-•*]\s+/, with: "")
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'‘’ "))
        guard !text.isEmpty, !text.contains(where: { "*_#<>[]|\\".contains($0) }) else { return nil }
        let lowered = text.lowercased()
        guard !["here", "sure", "okay", "ok,", "certainly", "reminder:"].contains(where: { lowered.hasPrefix($0) }) else { return nil }
        guard problems(in: text, facts: facts).isEmpty, CoachCheckIns.sentenceCount(text) <= maxGeneratedSentences else { return nil }
        guard !recent.contains(where: { similarity(text, $0) >= maxSimilarity }) else { return nil }
        if let last = recent.last, WorkoutBanter.opening(of: last) == WorkoutBanter.opening(of: text) { return nil }
        return text
    }

    static let stopWords: Set<String> = [
        "the", "a", "an", "in", "of", "to", "and", "is", "it", "its", "s", "your", "you", "for", "on", "at", "has", "have",
        "been", "this", "that", "with", "minutes", "i", "m", "ll", "t",
    ]

    /// Shared share of the two lines' distinct words (Jaccard), small words left out.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let first = Set(CoachIntent.words(a)).subtracting(stopWords)
        let second = Set(CoachIntent.words(b)).subtracting(stopWords)
        let union = first.union(second)
        return union.isEmpty ? 1 : Double(first.intersection(second).count) / Double(union.count)
    }
}

/// The prompt for a fresh line from Apple's on-device model (FoundationModels;
/// nothing leaves the iPhone). Only training-log facts go in: the session,
/// the week's count, a lift, a muscle group. Recovery, illness and pain never
/// do, and in those states the model isn't asked at all.
public enum WorkoutBanterPrompt {
    /// Short on purpose: the on-device model does best with small, specific prompts (`CoachNudgeWriter`).
    public static let instructions = """
    You write one short, funny reminder line for a workout log app. Dry, playful and kind. \
    Joke about the barbell, the plates, the gym or the app itself, never about the person. \
    Use only the facts given and no other numbers. Nothing about food, looks, health or feeling bad. \
    Never say "should", "must", "missed" or "skip". One or two sentences, under 140 characters. Reply with the line only.
    """

    /// The facts as the model sees them. Also what a model line is tied to:
    /// when these change, the line is dropped (`signature`).
    public static func factLines(_ facts: WorkoutBanter.Facts) -> [String] {
        func slot(_ slot: WorkoutBanter.Slot) -> String? { WorkoutBanter.value(of: slot, in: facts) }
        let fitting = WorkoutBanter.situations(for: facts)
        var lines: [String] = []
        if let session = slot(.session) {
            var parts = ["Session: \(session)"]
            if let lead = slot(.lead) { parts.append("starts in \(lead) minutes") }
            if let minutes = slot(.minutes) { parts.append("planned \(minutes) minutes") }
            if let short = slot(.short) { parts.append("short version \(short) minutes") }
            lines.append(parts.joined(separator: ", "))
        }
        if let weekday = slot(.weekday) { lines.append("Day: \(weekday)") }
        if fitting.contains(.deload) { lines.append("Deload week: loads are lighter on purpose") }
        if fitting.contains(.stuckLift), let lift = slot(.Lift), let weight = slot(.lastWeight), let weeks = slot(.stuckWeeks) {
            lines.append("\(lift) has stayed at \(weight) for \(weeks) weeks")
        } else if fitting.contains(.nearRecord), let lift = slot(.Lift), let last = slot(.last), let next = slot(.next) {
            lines.append("\(lift): \(last) last time, next step \(next)")
        }
        if fitting.contains(.comeback), let days = slot(.days) { lines.append("Days since the last session: \(days)") }
        if let done = slot(.done), let planned = slot(.planned),
           !fitting.isDisjoint(with: [.weekStart, .weekProgress, .lastOfWeek]) {
            lines.append("This week: \(done) of \(planned) sessions done")
        }
        if fitting.contains(.weeksInARow), let weeks = slot(.weeks) { lines.append("Weeks on plan in a row: \(weeks)") }
        if fitting.contains(.neglectedMuscle), let muscle = slot(.muscle), let days = slot(.muscleDays) {
            lines.append("No \(muscle) training for \(days) days")
        }
        if fitting.contains(.afterRecord), let lift = slot(.standoutLift) {
            lines.append("Last session: a new best on the \(lift)")
        } else if fitting.contains(.afterVolume), let volume = slot(.volume) {
            lines.append("Last session: \(volume) lifted in total")
        }
        return lines
    }

    public static func signature(_ facts: WorkoutBanter.Facts) -> String {
        factLines(facts).joined(separator: "|")
    }

    /// Up to `count` library lines for these facts, in different registers,
    /// about different things and not among the recently sent, as examples of the voice.
    public static func examples(facts: WorkoutBanter.Facts, history: WorkoutBanter.History, count: Int = 3,
                                library: [WorkoutBanter.Line] = WorkoutBanterLibrary.all) -> [String] {
        let recent = Set(history.entries.suffix(WorkoutBanter.recentWindow).map(\.lineID))
        let candidates = WorkoutBanter.eligible(facts: facts, tone: .playful, library: library)
            // Recovery is never part of the prompt, so no example mentions it either.
            .filter { !recent.contains($0.line.id) && $0.line.situation != .highRecovery }
            .sorted { $0.line.weight != $1.line.weight ? $0.line.weight > $1.line.weight : $0.line.id < $1.line.id }
        var registers: Set<WorkoutBanter.Register> = []
        var situations: Set<WorkoutBanter.Situation> = []
        var result: [String] = []
        for candidate in candidates where result.count < count {
            // Different registers about different things, so the model copies the voice and not one joke.
            guard !registers.contains(candidate.line.register), !situations.contains(candidate.line.situation) else { continue }
            registers.insert(candidate.line.register)
            situations.insert(candidate.line.situation)
            result.append(candidate.text)
        }
        return result
    }

    public static func prompt(facts: WorkoutBanter.Facts, examples: [String]) -> String {
        var parts = ["Facts:"] + factLines(facts).map { "- " + $0 }
        if !examples.isEmpty {
            parts.append("")
            parts.append("Lines in the right voice:")
            parts += examples.map { "- " + $0 }
        }
        parts.append("")
        parts.append("Write one new line in the same voice with a different joke. Mention the session and at most one other fact.")
        return parts.joined(separator: "\n")
    }
}
