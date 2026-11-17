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

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .environment(cardio)
                .task { model.activate() }
                // A tapped complication (`tensile://start`) opens the start screen.
                .onOpenURL { url in
                    guard url.scheme == "tensile" else { return }
                    if model.phase == .ended { model.reset() }
                    if cardio.phase == .ended { cardio.reset() }
                }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// Activates WatchConnectivity on every launch, including background ones
    /// (complication data from the phone wakes the app without its UI).
    func applicationDidFinishLaunching() {
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
    /// here with the workout configuration; the phone's session arrives through
    /// WatchConnectivity and the recording is attached to it.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        let model = WatchWorkoutModel.shared
        model.activate()
        Task { await model.start(with: workoutConfiguration, sessionID: nil) }
    }
}
