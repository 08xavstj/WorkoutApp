import AppIntents

// The Watch's App Intents, for Siri, Shortcuts, the Smart Stack and the
// watchOS 26 controls (Control Center, the Smart Stack; WWDC25 "What's new
// in watchOS 26"). Compiled into the Watch app and its widget extension
// (project.yml), so `WatchWidgets/StartControls.swift` can name them. Each
// opens the app (`openAppWhenRun`): a workout session can only start with the
// app in front. The work itself is the app's (`WatchIntentActions`), handed
// over through `WatchIntentRouter` when the app launches, so this file needs
// nothing from the app and the extension compiles it as it is.

/// What each intent does, set by the Watch app at launch. Nil in the widget
/// extension, where the intents only ask the system to open the app.
@MainActor
enum WatchIntentRouter {
    static var startWorkout: (() async -> Void)?
    static var openLifting: (() -> Void)?
    static var openCardioList: (() -> Void)?
    static var startLastCardio: (() async -> Void)?
}

/// "Start a workout in Tensile": today's session when one is waiting on the
/// iPhone, today's plan sent ahead, else a recording without sets.
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start workout"
    static let description = IntentDescription(
        "Starts today's session on your Apple Watch: the one waiting on your iPhone, the plan it sent ahead, or a recording without sets."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await WatchIntentRouter.startWorkout?()
        return .result()
    }
}

/// The "Start lifting" control: opens Tensile on today's session, or Quick lift.
struct StartLiftingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start lifting"
    static let description = IntentDescription("Opens Tensile on today's session, or on Quick lift.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchIntentRouter.openLifting?()
        return .result()
    }
}

/// "Start cardio in Tensile": opens the activity list, with the last
/// activity on top. It doesn't start a workout by itself: a run, a ride and
/// a row are saved as different workouts, and a wrong guess would have to be
/// discarded.
struct StartCardioIntent: AppIntent {
    static let title: LocalizedStringResource = "Start cardio"
    static let description = IntentDescription(
        "Opens the cardio list on your Apple Watch, with your last activity on top."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchIntentRouter.openCardioList?()
        return .result()
    }
}

/// The "Start last cardio" control: starts the activity started last, with its target.
struct StartLastCardioIntent: AppIntent {
    static let title: LocalizedStringResource = "Start last cardio"
    static let description = IntentDescription("Starts the cardio activity you did last, with the same target.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await WatchIntentRouter.startLastCardio?()
        return .result()
    }
}
