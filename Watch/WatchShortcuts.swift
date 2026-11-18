import AppIntents

/// The phrases Siri answers to without any setup. The intents themselves are
/// in Shared/WatchIntents.swift (shared with the controls in WatchWidgets);
/// what they do is `WatchIntentActions`. Siri on watchOS 27 runs apps' actions
/// through App Intents; a workout session can only start with the app in front,
/// so each intent opens it.
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
