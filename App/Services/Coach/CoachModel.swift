import Foundation
import AppCore

/// Chat state for the Coach tab. Routes each message to the on-device model
/// or to Claude, depending on Settings.
@Observable
final class CoachModel {
    struct ChatMessage: Identifiable, Equatable {
        enum Role { case user, coach, error }
        let id = UUID()
        let role: Role
        let text: String
        /// A workout the trainer built for this reply, shown as a card with Start.
        var plan: PlannedWorkout?
    }

    private(set) var messages: [ChatMessage] = []
    private(set) var isThinking = false
    /// Set by other tabs (e.g. "Ask coach" on Today) to pre-fill a question.
    var pendingQuestion: String?

    @ObservationIgnored private let onDevice = OnDeviceCoach()
    @ObservationIgnored private let cloud: CloudCoach

    init(cloud: CloudCoach) {
        self.cloud = cloud
    }

    static let suggestions = [
        "How should I train today?",
        "Why is my recovery where it is?",
        "Plan my next workout",
        "Am I eating enough for my training?"
    ]

    static let followUps = [
        "Make it 30 min",
        "Swap for a ride",
        "What should I eat after?",
        "Make it leg day"
    ]

    func newConversation() {
        messages = []
        onDevice.reset()
    }

    /// The lowercased words in a message ("leg-day!" → ["leg", "day"]).
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Whether `text` contains `phrase` as whole words ("leg day" in "make it leg day").
    static func containsPhrase(_ phrase: String, in words: [String]) -> Bool {
        let target = phrase.split(separator: " ").map(String.init)
        guard !target.isEmpty, words.count >= target.count else { return false }
        return (0...(words.count - target.count)).contains { Array(words[$0..<($0 + target.count)]) == target }
    }

    /// Whether a message is about training, so the reply should carry a workout.
    /// Whole words only, so "vitamin", "feedback" or "meal plan" don't count.
    static func isTrainingQuestion(_ text: String) -> Bool {
        let tokens = words(text)
        let single: Set<String> = ["train", "training", "workout", "workouts", "session", "lift", "lifting", "gym",
                                   "push", "pull", "leg", "legs", "upper", "exercise", "exercises", "chest", "arms", "shoulders"]
        if tokens.contains(where: { single.contains($0) }) { return true }
        let phrases = ["work out", "full body", "lower body", "leg day", "plan my workout", "plan a workout", "next workout"]
        if phrases.contains(where: { containsPhrase($0, in: tokens) }) { return true }
        // "Make it 30 min" after a workout reply.
        return text.lowercased().firstMatch(of: /\b\d{2,3}\s*(min|mins|minute|minutes)\b/) != nil
    }

    /// Whether a message asks for cardio instead of lifting (whole words: not "crunches").
    static func wantsCardio(_ text: String) -> Bool {
        let tokens = Set(words(text))
        return !tokens.isDisjoint(with: ["run", "running", "ride", "riding", "cycle", "cycling", "bike", "cardio", "swim", "row", "rowing"])
    }

    /// Focus and length mentioned in a message ("make it 30 min", "leg day").
    static func requestedFocusAndMinutes(_ text: String) -> (WorkoutFocus?, Int?) {
        let tokens = words(text)
        let set = Set(tokens)
        var focus: WorkoutFocus?
        if containsPhrase("full body", in: tokens) { focus = .fullBody }
        else if set.contains("upper") { focus = .upper }
        else if containsPhrase("lower body", in: tokens) || (set.contains("lower") && !containsPhrase("lower my", in: tokens)) { focus = .lower }
        else if set.contains("push") || set.contains("chest") { focus = .push }
        else if set.contains("pull") || containsPhrase("back day", in: tokens) || containsPhrase("my back", in: tokens) { focus = .pull }
        else if set.contains("leg") || set.contains("legs") { focus = .legs }
        var minutes: Int?
        if let match = text.lowercased().firstMatch(of: /(\d{2,3})\s*(min|minute)/), let value = Int(match.1) {
            minutes = [30, 45, 60, 75].min { abs($0 - value) < abs($1 - value) }
        }
        return (focus, minutes)
    }

    func send(_ text: String, snapshot: CoachSnapshot, settings: UserSettings, plan: PlannedWorkout? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        isThinking = true
        defer { isThinking = false }

        do {
            let reply: String
            switch settings.coachMode {
            case .onDevice:
                reply = try await onDevice.reply(to: trimmed, snapshot: snapshot)
            case .cloud:
                // Send the visible conversation (minus errors) so Claude keeps context.
                let history = messages.compactMap { message -> CloudCoach.Message? in
                    switch message.role {
                    case .user: CloudCoach.Message(role: "user", content: message.text)
                    case .coach: CloudCoach.Message(role: "assistant", content: message.text)
                    case .error: nil
                    }
                }
                reply = try await cloud.reply(history: history, snapshot: snapshot, settings: settings)
            }
            messages.append(ChatMessage(role: .coach, text: reply, plan: plan))
        } catch {
            messages.append(ChatMessage(role: .error, text: error.localizedDescription))
        }
    }
}
