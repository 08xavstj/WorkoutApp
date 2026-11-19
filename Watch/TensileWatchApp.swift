import HealthKit
import SwiftUI
import WatchConnectivity
import WatchKit

/// Tensile on the wrist: log sets, see the rest timer, and record heart rate
/// and calories for the gym session running on the iPhone; or record a
/// cardio workout with live heart-rate zones (`WatchCardioModel`).
@main
struct TensileWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @State private var model = WatchWorkoutModel.shared
    @State private var cardio = WatchCardioModel.shared

    init() {
        // Siri, Shortcuts and the controls run their intents through this (`WatchIntentRouter`).
        WatchIntentActions.install()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .environment(cardio)
                .task {
                    model.activate()
                    #if DEBUG
                    // Screenshot runs: a lift in progress (`loadDemoLift`).
                    if UserDefaults.standard.bool(forKey: "demoLift") { model.loadDemoLift() }
                    #endif
                }
                // A tapped complication (`tensile://start`) opens Home.
                .onOpenURL { url in
                    guard url.scheme == "tensile" else { return }
                    if model.phase == .ended { model.reset() }
                    if cardio.phase == .ended { cardio.reset() }
                }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// Workouts the lifting mode records; anything else is cardio or a sport.
    private static let strengthTypes: [HKWorkoutActivityType] = [.traditionalStrengthTraining, .functionalStrengthTraining]

    /// Activates WatchConnectivity on every launch, including background ones
    /// (complication data from the phone wakes the app without its UI).
    func applicationDidFinishLaunching() {
        WatchIntentActions.install()
        WatchWorkoutModel.shared.activate()
    }

    /// Background wake-ups for WatchConnectivity data: keep the task open
    /// until the data has been delivered (up to about 10 seconds).
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            guard let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask else {
                task.setTaskCompletedWithSnapshot(false)
                continue
            }
            WatchWorkoutModel.shared.activate()
            Task {
                var waits = 0
                while WCSession.default.hasContentPending, waits < 20 {
                    try? await Task.sleep(for: .milliseconds(500))
                    waits += 1
                }
                connectivity.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    /// "Start on Apple Watch" on the phone (`HKHealthStore.startWatchApp`) lands
    /// here with the workout configuration. Strength: the phone's session
    /// arrives through WatchConnectivity and the recording is attached to it.
    /// Anything else is a cardio activity or sport the phone picked
    /// (`WatchSync.startCardioOnWatch`): the cardio mode records it, with the
    /// Watch's own target setting for steady cardio.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        let model = WatchWorkoutModel.shared
        model.activate()
        if !Self.strengthTypes.contains(workoutConfiguration.activityType),
           let activity = CardioActivity.matching(workoutConfiguration.activityType, location: workoutConfiguration.locationType) {
            let cardio = WatchCardioModel.shared
            // Already recording here: say so on the Watch rather than ignore the phone.
            guard !cardio.isBusy else {
                cardio.refuseStartWhileRecording()
                return
            }
            if cardio.phase == .ended { cardio.reset() }
            let defaults = UserDefaults.standard
            defaults.set(activity.rawValue, forKey: WatchCardioModel.lastActivityKey)
            let target = CardioTarget(storage: defaults.string(forKey: WatchCardioModel.targetKey) ?? CardioTarget.off.storage)
            Task { await cardio.start(activity, target: target) }
            return
        }
        Task { await model.start(with: workoutConfiguration, sessionID: nil) }
    }

    /// The app was relaunched while a workout was recording (it crashed, or
    /// the system closed it). The session the system kept running goes back to
    /// the mode that records its kind: lifting for strength, else cardio. If
    /// neither can take it, it's ended and saved, so the workout isn't lost.
    func handleActiveWorkoutRecovery() {
        let lifting = WatchWorkoutModel.shared
        lifting.activate()
        lifting.willRecoverWorkout()
        Task {
            defer { lifting.didRecoverWorkout() }
            guard let recovered = try? await HKHealthStore().recoverActiveWorkoutSession() else { return }
            let taken: Bool
            if Self.strengthTypes.contains(recovered.workoutConfiguration.activityType) {
                taken = await lifting.recover(recovered)
            } else {
                taken = await WatchCardioModel.shared.recover(recovered)
            }
            if !taken { await Self.endAndSave(recovered) }
        }
    }

    /// Ends a recovered workout and saves what its builder recorded.
    private static func endAndSave(_ session: HKWorkoutSession) async {
        let builder = session.associatedWorkoutBuilder()
        let end = Date.now
        session.end()
        try? await builder.endCollection(at: end)
        _ = try? await builder.finishWorkout()
    }
}
