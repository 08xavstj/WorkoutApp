import Foundation
import AppCore

/// Chat state for the Coach tab. Questions the app can answer from its own
/// numbers (`CoachIntent.question` → `CoachAnswers`) are answered instantly
/// without the model; open questions go to Apple's on-device model
/// (`OnDeviceCoach`), and when it declines or fails, the nearest data-backed
/// answer stands in. Nothing leaves the iPhone.
@Observable
final class CoachModel {
    struct ChatMessage: Identifiable, Equatable {
        enum Role { case user, coach, error }
        /// Where a coach reply came from: the app's own numbers, or the model.
        enum Source { case data, model }
        let id = UUID()
        let role: Role
        let text: String
        var source: Source = .model
        /// One suggested next step under the reply.
        var action: String?
        /// A workout the trainer built for this reply, shown as a card with Start.
        var plan: PlannedWorkout?
        /// The facts the reply was built from, so "Say more" can reuse them.
        var facts: CoachFacts?
        /// "Say more" was used (or isn't offered) for this reply.
        var expanded = false

        /// A data-backed reply the model can be asked to explain.
        var canSayMore: Bool { role == .coach && source == .data && facts != nil && !expanded }
    }

    private(set) var messages: [ChatMessage] = []
    private(set) var isThinking = false
    /// Set by other tabs (e.g. "Ask coach" on Today) to pre-fill a question.
    var pendingQuestion: String?
    /// What the model did last, for the Coach status sheet.
    private(set) var diagnostics = OnDeviceCoach.Diagnostics()

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

    /// Answers `text`: from the app's numbers when `CoachIntent` recognises
    /// the question, otherwise from the on-device model, with a data-backed
    /// fallback when the model declines or fails.
    func send(_ text: String, facts: CoachFacts, plan: PlannedWorkout? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))

        // 1. Deterministic: instant, never errors.
        if let question = CoachIntent.question(trimmed), let answer = CoachAnswers.answer(for: question, facts: facts) {
            onDevice.remember(question: trimmed, answer: answer.text)
            diagnostics = onDevice.diagnostics
            messages.append(ChatMessage(role: .coach, text: answer.text, source: .data, action: answer.action, plan: plan, facts: facts))
            return
        }

        // 2. Open question: the model, with a small prompt.
        isThinking = true
        defer { isThinking = false }
        let topic = CoachIntent.topic(trimmed)
        do {
            let reply = try await onDevice.openAnswer(to: trimmed, topic: topic, facts: facts)
            diagnostics = onDevice.diagnostics
            messages.append(ChatMessage(role: .coach, text: reply.answer, source: .model, action: reply.action, plan: plan, facts: facts))
        } catch {
            diagnostics = onDevice.diagnostics
            // 3. The nearest answer from the data, when there is one.
            if let fallback = CoachAnswers.fallback(for: topic, facts: facts) {
                let lead = Self.fallbackLead(for: error)
                messages.append(ChatMessage(role: .coach, text: lead + " " + fallback.text, source: .data,
                                            action: fallback.action, plan: plan, facts: facts, expanded: true))
            } else {
                messages.append(ChatMessage(role: .error, text: error.localizedDescription))
            }
        }
    }

    /// Asks the model to say more about a data-backed reply, as a new reply under it.
    func sayMore(about message: ChatMessage) async {
        guard !isThinking, let index = messages.firstIndex(where: { $0.id == message.id }),
              message.canSayMore, let facts = message.facts else { return }
        let question = messages[..<index].last { $0.role == .user }?.text ?? "Say more about this."
        messages[index].expanded = true
        isThinking = true
        defer { isThinking = false }
        do {
            let text = try await onDevice.expand(question: question, answer: message.text,
                                                 topic: CoachIntent.topic(question), facts: facts)
            diagnostics = onDevice.diagnostics
            messages.append(ChatMessage(role: .coach, text: text, source: .model, facts: nil, expanded: true))
        } catch {
            diagnostics = onDevice.diagnostics
            messages.append(ChatMessage(role: .error, text: error.localizedDescription))
        }
    }

    /// One short sentence before a fallback answer, saying why the model didn't answer.
    static func fallbackLead(for error: Error) -> String {
        if OnDeviceCoach.isRefusal(error) {
            return "Apple's on-device model declined that one, but here's what your data says:"
        }
        return "The on-device model couldn't take that one, but here's what your data says:"
    }
}
