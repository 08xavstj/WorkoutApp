import Foundation

/// Chat state for the Coach tab. Routes each message to the on-device model
/// or to Claude, depending on Settings.
@Observable
final class CoachModel {
    struct ChatMessage: Identifiable, Equatable {
        enum Role { case user, coach, error }
        let id = UUID()
        let role: Role
        let text: String
    }

    private(set) var messages: [ChatMessage] = []
    private(set) var isThinking = false
    /// Set by other tabs (e.g. "Ask coach" on Today) to pre-fill a question.
    var pendingQuestion: String?

    @ObservationIgnored private let onDevice = OnDeviceCoach()
    @ObservationIgnored private let cloud = CloudCoach()

    static let suggestions = [
        "How hard should I train today?",
        "Why is my recovery where it is?",
        "Plan my next workout",
        "How can I sleep better tonight?"
    ]

    func newConversation() {
        messages = []
        onDevice.reset()
    }

    func send(_ text: String, snapshot: CoachSnapshot, settings: UserSettings) async {
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
            messages.append(ChatMessage(role: .coach, text: reply))
        } catch {
            messages.append(ChatMessage(role: .error, text: error.localizedDescription))
        }
    }
}
