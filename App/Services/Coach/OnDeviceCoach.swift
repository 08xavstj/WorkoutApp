import Foundation
import FoundationModels
import os
import AppCore

/// Coach powered by Apple's on-device model (Apple Intelligence). Free, private,
/// works offline; the app has no cloud AI.
///
/// The model is small (about 4,000 tokens of context, 3B parameters), so it
/// is only asked the *open* questions: anything the app can answer from its
/// own numbers is answered by `CoachAnswers` without the model, and the model
/// is at most asked to say more about such an answer. Each open question gets
/// a fresh session with a short prompt: the question first, then six to ten
/// "Facts:" lines picked for the topic, then a one-line ask for a 2-4 sentence
/// answer. Apple's guidance for the 3B model is short, specific prompts; the
/// earlier design wrote the whole day's data into the prompt and got vague or
/// off-topic answers back.
///
/// The model declines anything it reads as health advice, so the prompt uses
/// training-log vocabulary (`CoachPromptVocabulary`: "readiness score", "rest",
/// "training load"; condition lines left out) and, when it still declines,
/// retries once with the facts stripped to training and food lines and the
/// question prefixed "For my workout log: ". The UI keeps the app's own words.
final class OnDeviceCoach {
    /// What happened on the last request, for the Coach status sheet.
    struct Diagnostics: Equatable, Sendable {
        /// "open question", "say more", or "from your data (no model)".
        var lastMode: String?
        var lastPromptCharacters: Int?
        var lastPrompt: String?
        /// The full error text, exactly as the framework gave it.
        var lastError: String?
        var lastFinishedAt: Date?
        /// The first attempt was declined and the stripped prompt was tried.
        var retriedAfterRefusal = false
        /// The model's own explanation of a final refusal (`Refusal.explanation`), when it gave one.
        var refusalExplanation: String?
    }

    private(set) var diagnostics = Diagnostics()

    /// The last question and answer, for follow-ups ("and for dinner?").
    private var lastExchange: (question: String, answer: String)?

    private static let log = Logger(subsystem: "com.lontraindustries.workoutapp", category: "coach")

    /// Longest answer, in tokens; the prompt asks for under 80 words.
    static let maximumResponseTokens = 220
    /// Characters of facts in an open question's prompt.
    static let factBudget = 900
    /// Low temperature: answers should stick to the facts, not improvise.
    static let temperature = 0.2

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

    /// Records an answer the app gave without the model, so a follow-up open
    /// question still knows what was just said.
    func remember(question: String, answer: String) {
        lastExchange = (question, answer)
        diagnostics = Diagnostics(lastMode: "from your data (no model)", lastPromptCharacters: nil, lastPrompt: nil,
                                  lastError: nil, lastFinishedAt: .now)
    }

    /// Answers an open question from the facts. Throws a `CoachError` with a
    /// plain-words message; the caller falls back to `CoachAnswers` where it can.
    func openAnswer(to message: String, topic: CoachIntent.Topic, facts: CoachFacts) async throws -> CoachReply {
        let lines = CoachAnswers.factLines(for: message, topic: topic, facts: facts, budget: Self.factBudget)
        let prompt = Self.openPrompt(message, facts: lines, recap: lastExchange)
        let retry = Self.openPrompt(Self.retryQuestion(message), facts: CoachPromptVocabulary.trainingOnly(lines), recap: nil)
        let reply = try await generate(prompt, retry: retry, mode: "open question")
        lastExchange = (message, reply.answer)
        return reply
    }

    /// Asks the model to say more about an answer the app already gave: to
    /// rephrase it and add one practical tip about training or food, so it
    /// paraphrases and explains facts instead of inventing them.
    func expand(question: String, answer: String, topic: CoachIntent.Topic, facts: CoachFacts) async throws -> String {
        let lines = CoachAnswers.factLines(for: question, topic: topic, facts: facts, budget: 600)
        let prompt = Self.expandPrompt(question: question, answer: answer, facts: lines)
        let retry = Self.expandPrompt(question: Self.retryQuestion(question), answer: answer, facts: CoachPromptVocabulary.trainingOnly(lines))
        let reply = try await generate(prompt, retry: retry, mode: "say more")
        lastExchange = (question, reply.answer)
        return reply.answer
    }

    // MARK: - Generation

    /// Runs `prompt`; when the model declines it and `retry` is given, runs
    /// `retry` once (the stripped, training-only prompt) before giving up.
    private func generate(_ prompt: String, retry: String?, mode: String) async throws -> CoachReply {
        diagnostics = Diagnostics(lastMode: mode, lastPromptCharacters: prompt.count, lastPrompt: prompt, lastError: nil, lastFinishedAt: nil)
        if let unavailable = Self.availabilityMessage {
            diagnostics.lastError = unavailable
            diagnostics.lastFinishedAt = .now
            throw CoachError.unavailable(unavailable)
        }
        Self.log.debug("Coach prompt (\(mode, privacy: .public)): \(prompt.count) characters")
        do {
            let reply = try await Self.respond(prompt)
            diagnostics.lastFinishedAt = .now
            return reply
        } catch {
            guard Self.isRefusal(error), let retry else {
                return try await fail(with: error)
            }
            Self.log.notice("Coach refusal on first attempt; retrying with training-only facts: \(String(describing: error), privacy: .public)")
            diagnostics.retriedAfterRefusal = true
            diagnostics.lastPrompt = prompt + "\n\n--- Declined; retried with ---\n\n" + retry
            diagnostics.lastPromptCharacters = retry.count
            do {
                let reply = try await Self.respond(retry)
                diagnostics.lastFinishedAt = .now
                return reply
            } catch {
                return try await fail(with: error)
            }
        }
    }

    /// Records a final failure in `diagnostics`, with the model's own
    /// explanation when it declined, and throws the plain-words error.
    private func fail(with error: Error) async throws -> CoachReply {
        diagnostics.lastError = String(describing: error)
        if Self.isRefusal(error) {
            diagnostics.refusalExplanation = await Self.refusalExplanation(error)
        }
        diagnostics.lastFinishedAt = .now
        throw Self.friendly(error)
    }

    /// Guided generation first (a clean answer plus one action); if the
    /// model can't produce the structure, plain text once, so a format
    /// problem never becomes "couldn't answer".
    private static func respond(_ prompt: String) async throws -> CoachReply {
        // The default model (general use case, default guardrails): there is no
        // looser setting for health content.
        let options = GenerationOptions(temperature: temperature, maximumResponseTokens: maximumResponseTokens)
        let session = LanguageModelSession(instructions: CoachPrompt.onDeviceInstructions)
        do {
            let response = try await session.respond(to: prompt, generating: CoachReply.self, options: options)
            return response.content.trimmed
        } catch where isRefusal(error) || isContextOverflow(error) {
            throw error
        } catch {
            log.error("Guided generation failed, retrying as text: \(String(describing: error), privacy: .public)")
            let plain = LanguageModelSession(instructions: CoachPrompt.onDeviceInstructions)
            let response = try await plain.respond(to: prompt, options: options)
            return CoachReply(answer: response.content.trimmingCharacters(in: .whitespacesAndNewlines), oneAction: "")
        }
    }

    // MARK: - Prompts

    /// The question as the retry asks it: training-log vocabulary, prefixed
    /// "For my workout log: ".
    static func retryQuestion(_ message: String) -> String {
        CoachPromptVocabulary.retryQuestionPrefix + (CoachPromptVocabulary.neutral(message) ?? message)
    }

    /// Question first, then the facts, then the ask. Everything is short on
    /// purpose: the 3B model answers specific prompts well and long ones badly.
    /// The facts and the recap are rewritten into training-log vocabulary.
    static func openPrompt(_ message: String, facts: [String], recap: (question: String, answer: String)?) -> String {
        var parts = ["Question: \(message.prefix(400))"]
        if let recap {
            let question = CoachPromptVocabulary.neutral(String(recap.question.prefix(120))) ?? ""
            let answer = CoachPromptVocabulary.neutral(String(recap.answer.prefix(200))) ?? ""
            if !question.isEmpty, !answer.isEmpty {
                parts.append("Earlier you were asked \"\(question)\" and answered \"\(answer)\".")
            }
        }
        let lines = CoachPromptVocabulary.neutral(facts)
        if !lines.isEmpty {
            parts.append("Training log:\n" + lines.map { "- \($0)" }.joined(separator: "\n"))
        }
        parts.append("Reply as a fitness coach, about training and food only, in 2-4 sentences using only the training log. If it doesn't cover the question, say so in one sentence and give one general training tip.")
        return parts.joined(separator: "\n\n")
    }

    /// "Say more": the app's answer, in training-log words, with the ask to
    /// rephrase it and add one tip; no new numbers.
    static func expandPrompt(question: String, answer: String, facts: [String]) -> String {
        let neutralAnswer = CoachPromptVocabulary.neutral(String(answer.prefix(700))) ?? String(answer.prefix(700))
        var parts = ["Question: \(question.prefix(300))", "The training log app answered: \"\(neutralAnswer)\""]
        let lines = CoachPromptVocabulary.neutral(facts)
        if !lines.isEmpty {
            parts.append("Training log:\n" + lines.map { "- \($0)" }.joined(separator: "\n"))
        }
        parts.append("Rephrase that answer in 2-4 plain sentences and add one practical tip about training or food. Use only the training log; do not add new numbers.")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Errors

    /// The prompt didn't fit the model's context, on either SDK's error type.
    static func isContextOverflow(_ error: Error) -> Bool {
        #if TENSILE_IOS27_SDK
        if #available(iOS 27.0, *), let modern = error as? LanguageModelError,
           case .contextSizeExceeded = modern { return true }
        #endif
        if let old = error as? LanguageModelSession.GenerationError, case .exceededContextWindowSize = old { return true }
        return false
    }

    /// The model, or Apple's guardrail, declined the question (either SDK's type).
    static func isRefusal(_ error: Error) -> Bool {
        if let coach = error as? CoachError, case .declined = coach { return true }
        #if TENSILE_IOS27_SDK
        if #available(iOS 27.0, *), let modern = error as? LanguageModelError {
            switch modern {
            case .refusal, .guardrailViolation: return true
            default: return false
            }
        }
        #endif
        if let old = error as? LanguageModelSession.GenerationError {
            switch old {
            case .refusal, .guardrailViolation: return true
            default: return false
            }
        }
        return false
    }

    /// The model's own reason for a refusal, when the error is a `.refusal`
    /// (not a guardrail): both SDKs carry a `Refusal` whose `explanation`
    /// asks the model for a sentence (`Response<String>`, async throws). It is
    /// a second model call, so it is only fetched once a refusal is final.
    @concurrent nonisolated static func refusalExplanation(_ error: Error) async -> String? {
        #if TENSILE_IOS27_SDK
        if #available(iOS 27.0, *), let modern = error as? LanguageModelError, case .refusal(let refusal) = modern {
            return (try? await refusal.explanation)?.content
        }
        #endif
        if let old = error as? LanguageModelSession.GenerationError, case .refusal(let refusal, _) = old {
            return (try? await refusal.explanation)?.content
        }
        return nil
    }

    /// Plain words for the model's errors, instead of an error code. The
    /// underlying description rides along in brackets for the less common
    /// cases, so the user can report what actually happened; every failure
    /// is logged in full and kept in `diagnostics`.
    ///
    /// Apple's docs: an app built with Xcode 26 receives `GenerationError`; one
    /// built with Xcode 27 or later receives `LanguageModelError` instead
    /// (iOS 27 SDK type), matched behind TENSILE_IOS27_SDK (on in project.yml;
    /// CI's Xcode 26 passes OTHER_SWIFT_FLAGS without it).
    static func friendly(_ error: Error) -> Error {
        if error is CoachError { return error }
        let detail = error.localizedDescription
        log.error("Coach generation failed: \(String(describing: error), privacy: .public)")
        let generic = "The coach couldn't answer that. Try again, or word it differently. (\(detail))"
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
            return CoachError.declined(guardrailMessage)
        case .refusal:
            // The model itself (not the guardrail) chose not to answer, twice: once as asked, once as a workout-log query.
            return CoachError.declined(refusalMessage + " (\(detail))")
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

    /// Shown only when the app has no data-backed answer to stand in.
    static let guardrailMessage = "Apple's on-device model declined that question, even reworded as a workout-log query. Try asking about one thing at a time, or ask about your training or food."
    static let refusalMessage = "Apple's on-device model declined to answer that one, even reworded as a workout-log query. Try asking about one thing at a time, or ask about your training or food."
}

#if TENSILE_IOS27_SDK
extension OnDeviceCoach {
    @available(iOS 27.0, *)
    static func friendlyModern(_ error: LanguageModelError, detail: String, generic: String) -> Error {
        switch error {
        case .guardrailViolation:
            return CoachError.declined(guardrailMessage)
        case .refusal:
            return CoachError.declined(refusalMessage + " (\(detail))")
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

/// The model's reply to an open question: a short answer and, when there is
/// one, a single next step. Guided generation (`@Generable`) keeps the shape
/// fixed so the UI never has to parse prose.
@Generable(description: "A short coaching answer and one optional next step.")
nonisolated struct CoachReply: Equatable {
    @Guide(description: "The answer: 2-4 plain sentences, under 80 words, using only the given training log.")
    var answer: String
    @Guide(description: "One concrete next step in under 15 words, or an empty string if there is none.")
    var oneAction: String

    /// Explicit, because the macro's own `init(_:)` would otherwise replace the memberwise one.
    init(answer: String, oneAction: String) {
        self.answer = answer
        self.oneAction = oneAction
    }

    /// Whitespace trimmed, and a placeholder action treated as none.
    var trimmed: CoachReply {
        var copy = self
        copy.answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = oneAction.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.oneAction = ["none", "n/a", "-", "no action"].contains(action.lowercased()) ? "" : action
        return copy
    }

    var action: String? { oneAction.isEmpty ? nil : oneAction }
}

/// Errors the coach shows in the chat, in plain words.
enum CoachError: LocalizedError {
    case unavailable(String)
    /// The model or Apple's guardrail declined the question.
    case declined(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .declined(let message): message
        }
    }
}

enum CoachPrompt {
    // Autonomy-supportive coaching (self-determination theory: Teixeira et al.
    // 2012; Ntoumanis et al. 2021; docs/research/behaviour-change.md rec. 5).
    /// Instructions for Apple's on-device model: a fitness training log
    /// assistant, under 600 characters. Apple's model declines what it reads
    /// as medical content, so "health", "recovery", "sleep", "illness" and
    /// "medication" stay out of the instructions and the fact lines
    /// (`CoachPromptVocabulary`, tested in AppCore for banned words). Food
    /// guidance (20-40 g protein after training) lives in `CoachAnswers`,
    /// which answers those questions without the model.
    static let onDeviceInstructions = CoachPromptVocabulary.instructions
}
