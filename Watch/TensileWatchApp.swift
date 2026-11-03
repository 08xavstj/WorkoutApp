import HealthKit
import SwiftUI
import WatchKit

/// Tensile on the wrist: log sets, see the rest timer, and record heart rate
/// and calories for the gym session running on the iPhone.
@main
struct TensileWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @State private var model = WatchWorkoutModel.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .task { model.activate() }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// "Start on Apple Watch" on the phone (`HKHealthStore.startWatchApp`) lands
    /// here with the workout configuration; the phone's session arrives through
    /// WatchConnectivity and the recording is attached to it.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        let model = WatchWorkoutModel.shared
        model.activate()
        Task { await model.start(with: workoutConfiguration, sessionID: nil) }
    }
}
