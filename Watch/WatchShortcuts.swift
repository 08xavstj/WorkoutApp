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
        // A cardio workout is recording (`WatchCardioModel`): opening the app is all there is to do.
        let cardio = WatchCardioModel.shared
        if cardio.isBusy { return .result() }
        if cardio.phase == .ended { cardio.reset() }
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

/// "Start cardio in Tensile": opens the Watch app on its cardio list, with
/// the last activity on top (one tap or a double tap starts it). It doesn't
/// start a workout by itself: a run, a ride and a row are saved as different
/// workouts, and a wrong guess would have to be discarded.
struct StartCardioIntent: AppIntent {
    static let title: LocalizedStringResource = "Start cardio"
    static let description = IntentDescription(
        "Opens the cardio list on your Apple Watch, with your last activity on top."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let lifting = WatchWorkoutModel.shared
        let cardio = WatchCardioModel.shared
        lifting.activate()
        // Already recording, either kind: opening the app is all there is to do.
        if cardio.isBusy || lifting.isRecording || lifting.phase == .starting { return .result() }
        if lifting.phase == .ended { lifting.reset() }
        if cardio.phase == .ended { cardio.reset() }
        cardio.pickerRequested = true
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
        AppShortcut(
            intent: StartCardioIntent(),
            phrases: [
                "Start cardio in \(.applicationName)",
                "Start a cardio workout in \(.applicationName)",
                "Open cardio in \(.applicationName)",
            ],
            shortTitle: "Start cardio",
            systemImageName: "figure.run"
        )
    }
}
