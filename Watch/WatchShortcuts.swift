import AppIntents

/// "Start a workout in Tensile", for Siri, the Shortcuts app and the Smart
/// Stack's suggestions. Opens the Watch app and starts recording: today's
/// session when one is waiting on the iPhone, an empty workout otherwise
/// (what the Start button on the first screen does).
///
/// Siri on watchOS 27 runs apps' actions through App Intents; a workout
/// session can only start with the app in front, so the intent opens it.
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start workout"
    static let description = IntentDescription(
        "Starts today's session on your Apple Watch, or an empty workout when none is waiting on your iPhone."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = WatchWorkoutModel.shared
        model.activate()
        switch model.phase {
        case .starting, .running, .paused:
            // Already recording: opening the app is all there is to do.
            return .result()
        case .ended:
            model.reset()
        case .idle:
            break
        }
        let waiting = model.snapshot.flatMap { $0.isFinished ? nil : $0.id }
        await model.start(sessionID: waiting)
        return .result()
    }
}

/// The phrases Siri answers to without any setup.
struct TensileWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start a workout in \(.applicationName)",
                "Start my \(.applicationName) workout",
                "Start lifting with \(.applicationName)",
            ],
            shortTitle: "Start workout",
            systemImageName: "figure.strengthtraining.traditional"
        )
    }
}
