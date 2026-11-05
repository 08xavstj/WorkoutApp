import Foundation
import AppCore

/// Chat state for the Coach tab. Every message goes to Apple's on-device
/// model (`OnDeviceCoach`); nothing leaves the iPhone.
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

    init() {}

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
    static func words(_ text: String) -> [String] { CoachIntent.words(text) }

    /// Whether `text` contains `phrase` as whole words ("leg day" in "make it leg day").
    static func containsPhrase(_ phrase: String, in words: [String]) -> Bool {
        CoachIntent.containsPhrase(phrase, in: words)
    }

    /// Whether the reply should carry a workout card (`CoachIntent`): a food
    /// question that mentions a workout ("what should I eat after my workout?")
    /// doesn't.
    static func isTrainingQuestion(_ text: String) -> Bool { CoachIntent.wantsWorkoutPlan(text) }

    /// Whether a message asks for cardio instead of lifting (whole words: not "crunches").
    static func wantsCardio(_ text: String) -> Bool { CoachIntent.wantsCardio(text) }

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

    func send(_ text: String, snapshot: CoachSnapshot, plan: PlannedWorkout? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        isThinking = true
        defer { isThinking = false }

        do {
            let reply = try await onDevice.reply(to: trimmed, snapshot: snapshot, hasPlan: plan != nil)
            messages.append(ChatMessage(role: .coach, text: reply, plan: plan))
        } catch {
            messages.append(ChatMessage(role: .error, text: error.localizedDescription))
        }
    }
}
