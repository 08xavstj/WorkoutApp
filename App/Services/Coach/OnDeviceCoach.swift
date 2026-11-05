import Foundation
import FoundationModels
import os
import AppCore

/// Coach powered by Apple's on-device model (Apple Intelligence). Free, private,
/// works offline; the app has no cloud AI.
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

    private static let log = Logger(subsystem: "com.lontraindustries.workoutapp", category: "coach")

    /// Whole request (instructions, data, recap and question) in characters: a
    /// safety net under the model's 4,096 tokens, since numbers tokenise at
    /// closer to 2-3 characters each. 6,000 chars leaves room for the answer.
    static let promptLimit = 6000
    /// Longest answer, in tokens; the instructions ask for under 100 words.
    static let maximumResponseTokens = 300

    static var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "The coach needs Apple Intelligence, which this iPhone doesn't support."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in the Settings app to use the on-device coach."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading. Try again in a few minutes."
        case .unavailable:
            return "The on-device model isn't available right now."
        }
    }

    private static var didPrewarm = false

    /// Loads the model's assets before the first question (`LanguageModelSession.prewarm`),
    /// so the first answer comes faster and an asset problem shows up early
    /// in the log. Once per launch; a no-op when the model isn't available.
    static func prewarm() {
        guard !didPrewarm, availabilityMessage == nil else { return }
        didPrewarm = true
        LanguageModelSession(instructions: CoachPrompt.onDeviceInstructions).prewarm()
        log.info("Prewarmed the on-device coach session.")
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
        } catch where Self.isContextOverflow(error) {
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
        // The default model (general use case, default guardrails). If health
        // questions keep being refused, `SystemLanguageModel(useCase: .general,
        // guardrails: .default)` is the same model; there is no looser setting
        // for health content, only `.permissiveContentTransformations` for
        // rewriting text the user supplied.
        let session = LanguageModelSession(instructions: CoachPrompt.onDeviceInstructions)
        let prompt = Self.prompt(message, topic: topic, snapshot: snapshot, hasPlan: hasPlan,
                                 recap: scale < 1 ? nil : lastExchange, scale: scale)
        Self.log.debug("Coach prompt: \(prompt.count) characters, topic \(String(describing: topic), privacy: .public)")
        // Low temperature: answers should stick to the data, not improvise.
        // A token cap so a long answer can't run the session out of context.
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: Self.maximumResponseTokens)
        let response = try await session.respond(to: prompt, options: options)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The data block, the recap and the question. Budgets are characters
    /// (about 3-4 per token) and keep the whole request well under the
    /// model's 4,096 tokens, with room for the answer; `promptLimit` caps the
    /// data as a whole so the question is never the part that gets cut.
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
        let question = "QUESTION: \(message.prefix(600))\n(\(focus))"
        let room = max(800, promptLimit - CoachPrompt.onDeviceInstructions.count - question.count - 2)
        let data = CoachSnapshot.capped(sections.joined(separator: "\n\n"), room)
        return data + "\n\n" + question
    }

    /// The prompt didn't fit the model's context, on either SDK's error type.
    static func isContextOverflow(_ error: Error) -> Bool {
        #if TENSILE_IOS27_SDK
        if #available(iOS 27.0, *), let modern = error as? LanguageModelError,
           case .contextSizeExceeded = modern { return true }
        #endif
        if let old = error as? LanguageModelSession.GenerationError, case .exceededContextWindowSize = old { return true }
        return false
    }

    /// Plain words for the model's errors, instead of an error code. The
    /// underlying description rides along in brackets for the less common
    /// cases, so the user can report what actually happened; every failure
    /// is logged in full.
    ///
    /// Apple's docs: an app built with Xcode 26 receives `GenerationError`; one
    /// built with Xcode 27 or later receives `LanguageModelError`,
    /// `SystemLanguageModel.Error` or `LanguageModelSession.Error` instead
    /// (iOS 27 SDK types), which the cast below misses, so they fall through to
    /// the generic message with the real reason in brackets. Once the project
    /// builds with Xcode 27, match those types here as well.
    static func friendly(_ error: Error) -> Error {
        if error is CoachError { return error }
        let detail = error.localizedDescription
        log.error("Coach generation failed: \(String(describing: error), privacy: .public)")
        let generic = "The coach couldn't answer that. Try again, or word it differently. (\(detail))"
        // Built with Xcode 27, the framework throws `LanguageModelError` instead
        // of the deprecated `GenerationError` (Apple's migration note), so an
        // app that only checked the old type showed the generic text for
        // everything. The type exists only in the iOS 27 SDK, so it's behind
        // TENSILE_IOS27_SDK (on in project.yml; CI's Xcode 26 passes
        // OTHER_SWIFT_FLAGS without it).
        #if TENSILE_IOS27_SDK
        if #available(iOS 27.0, *), let modern = error as? LanguageModelError {
            return friendlyModern(modern, detail: detail, generic: generic)
        }
        #endif
        guard let generation = error as? LanguageModelSession.GenerationError else {
            return CoachError.unavailable(generic)
        }
        switch generation {
        case .guardrailViolation:
            return CoachError.unavailable("Apple's on-device model declined that question; its safety filter is strict about health topics. Try wording it differently.")
        case .refusal:
            // The model itself (not the guardrail) chose not to answer; common with health advice.
            return CoachError.unavailable("The on-device model declined to answer that one; it is cautious with health topics. Try asking in a different way, or about one thing at a time. (\(detail))")
        case .exceededContextWindowSize:
            return CoachError.unavailable("That was more than the on-device coach can handle at once. Try a shorter question, or tap New conversation.")
        case .assetsUnavailable:
            return CoachError.unavailable("Apple Intelligence is still getting ready. Try again in a few minutes.")
        case .rateLimited, .concurrentRequests:
            return CoachError.unavailable("The on-device coach is busy. Try again in a moment.")
        case .unsupportedLanguageOrLocale:
            return CoachError.unavailable("The on-device model doesn't support your iPhone's language yet. (\(detail))")
        case .decodingFailure:
            return CoachError.unavailable("The model's answer was cut off before it finished. Try again. (\(detail))")
        case .unsupportedGuide:
            return CoachError.unavailable("The coach asked the model for a format it can't produce. Try again. (\(detail))")
        @unknown default:
            return CoachError.unavailable(generic)
        }
    }
}

#if TENSILE_IOS27_SDK
extension OnDeviceCoach {
    @available(iOS 27.0, *)
    static func friendlyModern(_ error: LanguageModelError, detail: String, generic: String) -> Error {
        switch error {
        case .guardrailViolation:
            return CoachError.unavailable("Apple's on-device model declined that question; its safety filter is strict about health topics. Try wording it differently.")
        case .refusal:
            return CoachError.unavailable("The on-device model declined to answer that one; it is cautious with health topics. Try asking in a different way, or about one thing at a time. (\(detail))")
        case .contextSizeExceeded:
            return CoachError.unavailable("That was more than the on-device coach can handle at once. Try a shorter question, or tap New conversation.")
        case .rateLimited:
            return CoachError.unavailable("The on-device coach is busy. Try again in a moment.")
        case .timeout:
            return CoachError.unavailable("The on-device model took too long. Try again.")
        case .unsupportedLanguageOrLocale:
            return CoachError.unavailable("The on-device model doesn't support your iPhone's language yet. (\(detail))")
        case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide:
            return CoachError.unavailable("The coach asked the model for something it can't do. Try again. (\(detail))")
        @unknown default:
            return CoachError.unavailable(generic)
        }
    }
}
#endif

/// Errors the coach shows in the chat, in plain words.
enum CoachError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        }
    }
}

enum CoachPrompt {
    // Autonomy-supportive coaching (self-determination theory: Teixeira et al.
    // 2012; Ntoumanis et al. 2021; docs/research/behaviour-change.md rec. 5).
    /// Instructions for Apple's on-device model. Each prompt brings its own
    /// data block (`OnDeviceCoach.prompt`), so the model is told to answer
    /// from that data and to stay on the question's topic.
    /// Food guidance: about 20-40 g of protein (roughly 0.25-0.4 g/kg) in a
    /// meal after training, with total daily protein mattering most (ISSN
    /// position stands: Jäger et al., JISSN 2017; Kerksick et al., JISSN 2017
    /// on nutrient timing; Morton et al., Br J Sports Med 2018 meta-analysis).
    /// Quoted from memory; the wording stays cautious ("about", "helps").
    static let onDeviceInstructions = """
    You are a friendly, direct coach in a fitness app. Each message gives the user's data, then their QUESTION.
    Answer that QUESTION, using the data given. If the data doesn't cover it, say so in one sentence and give general advice.
    Never change the subject. A food question gets a food answer, never exercises.
    Food: after training, a meal or snack with about 20-40 g of protein within a couple of hours helps muscles recover, \
    with some carbs to refuel; the day's total protein matters more than exact timing. Use their protein target and what they've logged.
    Recovery is 0-100% (under 34 an easy day, 34-66 normal, 67+ recovered). Strain is 0-100%.
    If a planned workout is shown as a card, say in one or two sentences why it suits today; don't list exercises. Only mention equipment they have.
    Keep answers under 100 words. Say "you could", never "you should", "you're behind" or "you missed". Low recovery is an easy day, not a failure.
    You are not a doctor; for pain, illness or injury suggest seeing one.
    """
}
