import Foundation
import FoundationModels

/// Coach powered by Apple's on-device model (Apple Intelligence). Free, private,
/// works offline. The model reads your data through tools instead of a long
/// prompt, because its context window is small.
final class OnDeviceCoach {
    private var session: LanguageModelSession?
    private var sessionSnapshot: CoachSnapshot?

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
        session = nil
        sessionSnapshot = nil
    }

    func reply(to message: String, snapshot: CoachSnapshot) async throws -> String {
        if let unavailable = Self.availabilityMessage {
            throw CoachError.unavailable(unavailable)
        }
        // When the data changes, rebuild the tools with fresh numbers but keep
        // the conversation so follow-ups ("make it 30 min") still make sense.
        // The snapshot's timestamp changes every message, so it's ignored here.
        if let current = session, let previous = sessionSnapshot {
            var comparable = snapshot
            comparable.date = previous.date
            if comparable != previous {
                session = LanguageModelSession(tools: tools(for: snapshot), transcript: current.transcript)
                sessionSnapshot = snapshot
            }
        } else {
            session = makeSession(snapshot: snapshot)
            sessionSnapshot = snapshot
        }
        guard let session else { throw CoachError.unavailable("Couldn't start the coach.") }

        do {
            return try await session.respond(to: message).content
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // The on-device context is small; start over and retry once.
            let fresh = makeSession(snapshot: snapshot)
            self.session = fresh
            return try await fresh.respond(to: message).content
        }
    }

    private func tools(for snapshot: CoachSnapshot) -> [any Tool] {
        [TodayMetricsTool(snapshot: snapshot), RecentWorkoutsTool(snapshot: snapshot), TrainerTool(snapshot: snapshot)]
    }

    private func makeSession(snapshot: CoachSnapshot) -> LanguageModelSession {
        LanguageModelSession(tools: tools(for: snapshot), instructions: CoachPrompt.onDeviceInstructions)
    }
}

struct TodayMetricsTool: Tool {
    let name = "getTodayMetrics"
    let description = "Get today's strain, recovery, HRV, resting heart rate and last night's sleep."
    let snapshot: CoachSnapshot

    @Generable
    struct Arguments {
        @Guide(description: "What the user asked about, e.g. 'recovery' or 'sleep'")
        var topic: String
    }

    func call(arguments: Arguments) async throws -> String {
        snapshot.todaySummary
    }
}

struct RecentWorkoutsTool: Tool {
    let name = "getRecentWorkouts"
    let description = "Get the gym sessions logged in the last 14 days, with exercises and best sets."
    let snapshot: CoachSnapshot

    @Generable
    struct Arguments {
        @Guide(description: "Muscle group or exercise the user asked about, or 'all'")
        var focus: String
    }

    func call(arguments: Arguments) async throws -> String {
        snapshot.workoutsSummary
    }
}

struct TrainerTool: Tool {
    let name = "getGymAndPlannedWorkout"
    let description = "Get the user's gym equipment, plates and weight increments, and the workout the trainer planned for today."
    let snapshot: CoachSnapshot

    @Generable
    struct Arguments {
        @Guide(description: "What the user asked for, e.g. 'leg day' or 'shorter workout'")
        var request: String
    }

    func call(arguments: Arguments) async throws -> String {
        snapshot.trainerSummary
    }
}
