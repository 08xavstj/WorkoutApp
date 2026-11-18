import Foundation
#if canImport(AppCore)
import AppCore
#endif

/// What the App Intents in Shared/WatchIntents.swift do in the app, handed
/// to them through `WatchIntentRouter` at launch (`install()`).
enum WatchIntentActions {
    static func install() {
        WatchIntentRouter.startWorkout = { await startWorkout() }
        WatchIntentRouter.openLifting = { openLifting() }
        WatchIntentRouter.openCardioList = { openCardioList() }
        WatchIntentRouter.startLastCardio = { await startLastCardio() }
    }

    /// Clears a finished workout's summary; false while one records or starts.
    private static func readyToStart() -> Bool {
        let model = WatchWorkoutModel.shared
        let cardio = WatchCardioModel.shared
        model.activate()
        // Already recording, either kind: opening the app is all there is to do.
        if cardio.isBusy || model.isRecording || model.phase == .starting { return false }
        if model.phase == .ended { model.reset() }
        if cardio.phase == .ended { cardio.reset() }
        return true
    }

    /// The phone's waiting session, else today's plan sent ahead, else a
    /// recording without sets (what Start on Home does).
    static func startWorkout() async {
        guard readyToStart() else { return }
        let model = WatchWorkoutModel.shared
        if let waiting = model.snapshot, !waiting.isFinished {
            await model.start(sessionID: waiting.id)
        } else if let plan = model.plannedSession, model.offersPlan(plan) {
            await model.startPlanned(plan)
        } else {
            await model.start(sessionID: nil)
        }
    }

    /// Home opens the session preview, or Quick lift.
    static func openLifting() {
        guard readyToStart() else { return }
        WatchWorkoutModel.shared.liftRequested = true
    }

    /// Home opens the activity list.
    static func openCardioList() {
        guard readyToStart() else { return }
        WatchCardioModel.shared.pickerRequested = true
    }

    /// The activity started last, with its stored target.
    static func startLastCardio() async {
        guard readyToStart() else { return }
        let defaults = UserDefaults.standard
        let activity = CardioActivity(rawValue: defaults.string(forKey: WatchCardioModel.lastActivityKey) ?? "") ?? .outdoorRun
        let target = CardioTarget(storage: defaults.string(forKey: WatchCardioModel.targetKey) ?? CardioTarget.off.storage)
        await WatchCardioModel.shared.start(activity, target: target)
    }
}
