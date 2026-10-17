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
    @ObservationIgnored private let cloud = CloudCoach()

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

    /// Whether a message is about training, so the reply should carry a workout.
    static func isTrainingQuestion(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = ["train", "workout", "work out", "session", "lift", "gym", "push", "pull", "leg", "upper", "lower", "full body", "exercise", "plan", "min"]
        return words.contains { lower.contains($0) }
    }

    /// Focus and length mentioned in a message ("make it 30 min", "leg day").
    static func requestedFocusAndMinutes(_ text: String) -> (WorkoutFocus?, Int?) {
        let lower = text.lowercased()
        var focus: WorkoutFocus?
        if lower.contains("full body") { focus = .fullBody }
        else if lower.contains("upper") { focus = .upper }
        else if lower.contains("lower") { focus = .lower }
        else if lower.contains("push") || lower.contains("chest") { focus = .push }
        else if lower.contains("pull") || lower.contains("back") { focus = .pull }
        else if lower.contains("leg") { focus = .legs }
        var minutes: Int?
        if let match = lower.firstMatch(of: /(\d{2,3})\s*(min|minute)/), let value = Int(match.1) {
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
