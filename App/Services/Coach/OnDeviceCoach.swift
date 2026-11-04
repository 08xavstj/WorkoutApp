import Foundation
import FoundationModels
import AppCore

/// Coach powered by Apple's on-device model (Apple Intelligence). Free, private,
/// works offline.
///
/// The model is small (about 4,000 tokens of context, and unreliable at
/// deciding when to call tools), so each question gets a fresh session with
/// the data that question needs written into the prompt (`CoachIntent`
/// picks it), plus a short recap of the last exchange for follow-ups. Earlier
/// versions let the model fetch data through tools and kept the whole chat,
/// which left answers ungrounded and ran out of context after a few messages.
final class OnDeviceCoach {
    /// The last question and answer, for follow-ups ("and for dinner?").
    private var lastExchange: (question: String, answer: String)?

    static var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This iPhone doesn't support Apple Intelligence. Switch the coach to Claude in Settings."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in the Settings app to use the on-device coach."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading. Try again in a few minutes."
        case .unavailable:
            return "The on-device model isn't available right now."
        }
    }

    func reset() {
        lastExchange = nil
    }

    /// - Parameter hasPlan: the app is showing a planned workout card with this reply.
    func reply(to message: String, snapshot: CoachSnapshot, hasPlan: Bool) async throws -> String {
        if let unavailable = Self.availabilityMessage {
            throw CoachError.unavailable(unavailable)
        }
        let topic = CoachIntent.topic(message)
        do {
            let answer = try await generate(message, topic: topic, snapshot: snapshot, hasPlan: hasPlan, scale: 1)
            lastExchange = (message, answer)
            return answer
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Still too long: retry once with half the data and no recap.
            lastExchange = nil
            do {
                let answer = try await generate(message, topic: topic, snapshot: snapshot, hasPlan: hasPlan, scale: 0.5)
                lastExchange = (message, answer)
                return answer
            } catch {
                throw Self.friendly(error)
            }
        } catch {
            throw Self.friendly(error)
        }
    }

    private func generate(_ message: String, topic: CoachIntent.Topic, snapshot: CoachSnapshot,
                        hasPlan: Bool, scale: Double) async throws -> String {
        let session = LanguageModelSession(instructions: CoachPrompt.onDeviceInstructions)
        let prompt = Self.prompt(message, topic: topic, snapshot: snapshot, hasPlan: hasPlan,
                                 recap: scale < 1 ? nil : lastExchange, scale: scale)
        // Low temperature: answers should stick to the data, not improvise.
        let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.3))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The data block, the recap and the question. Budgets are characters
    /// (about 3-4 per token) and keep the whole request well under the
    /// model's 4,096 tokens, with room for the answer.
    static func prompt(_ message: String, topic: CoachIntent.Topic, snapshot: CoachSnapshot, hasPlan: Bool,
                       recap: (question: String, answer: String)?, scale: Double) -> String {
        func budget(_ characters: Int) -> Int { Int(Double(characters) * scale) }
        var sections: [String] = []
        switch topic {
        case .nutrition:
            sections.append("YOUR DATA TODAY:\n" + snapshot.onDeviceSummary(budget: budget(2600), goalsFirst: true))
        case .training:
            sections.append("YOUR DATA TODAY:\n" + snapshot.onDeviceSummary(budget: budget(1500)))
            sections.append("GYM AND PLANNED WORKOUT:\n" + CoachSnapshot.capped(snapshot.trainerSummary, budget(1300)))
            sections.append("RECENT WORKOUTS:\n" + CoachSnapshot.capped(snapshot.workoutsSummary, budget(800)))
        case .recovery:
            sections.append("YOUR DATA TODAY:\n" + snapshot.onDeviceSummary(budget: budget(2400)))
            sections.append("RECENT WORKOUTS:\n" + CoachSnapshot.capped(snapshot.workoutsSummary, budget(600)))
        case .general:
            sections.append("YOUR DATA TODAY:\n" + snapshot.onDeviceSummary(budget: budget(2200)))
            sections.append("RECENT WORKOUTS:\n" + CoachSnapshot.capped(snapshot.workoutsSummary, budget(600)))
        }
        if let recap {
            sections.append("EARLIER IN THIS CHAT:\nUser: \(recap.question.prefix(200))\nCoach: \(recap.answer.prefix(400))")
        }
        let focus: String = switch topic {
        case .nutrition: "This is a food question: answer about food only, no exercises."
        case .training: hasPlan
            ? "The app is showing the planned workout as a card under your answer: say why it suits today, don't list the exercises."
            : "Answer about training."
        case .recovery: "This is about recovery or sleep: explain it from the numbers above."
        case .general: "Answer the question directly."
        }
        sections.append("QUESTION: \(message)\n(\(focus))")
        return sections.joined(separator: "\n\n")
    }

    /// Plain words for the model's errors, instead of an error code.
    static func friendly(_ error: Error) -> Error {
        guard let generation = error as? LanguageModelSession.GenerationError else {
            if error is CoachError { return error }
            return CoachError.unavailable("The on-device coach couldn't answer that. Try again, or switch the coach to Claude in Settings › Coach.")
        }
        switch generation {
        case .guardrailViolation:
            return CoachError.unavailable("Apple's on-device model declined that question; its safety filter is strict about health topics. Try wording it differently, or switch the coach to Claude in Settings › Coach.")
        case .exceededContextWindowSize:
            return CoachError.unavailable("That was more than the on-device coach can handle at once. Try a shorter question, or tap New conversation.")
        case .assetsUnavailable:
            return CoachError.unavailable("Apple Intelligence is still getting ready. Try again in a few minutes.")
        case .rateLimited, .concurrentRequests:
            return CoachError.unavailable("The on-device coach is busy. Try again in a moment.")
        default:
            return CoachError.unavailable("The on-device coach couldn't answer that. Try again, or switch the coach to Claude in Settings › Coach.")
        }
    }
}
