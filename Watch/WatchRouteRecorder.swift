import CoreLocation
import HealthKit

/// Records the GPS route of an outdoor cardio workout: every fix goes to an
/// `HKWorkoutRouteBuilder`, which is attached to the saved workout at the end
/// (Apple Health, Fitness and the iPhone app's map then show it). Fixes are
/// also kept here for the end screen's elevation and top speed
/// (`CardioRoute`).
///
/// Location is used only while an outdoor workout records, with "While
/// Using" permission: the running workout session keeps the app active.
/// The route stays in Apple Health on the user's devices.
final class WatchRouteRecorder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let store: HKHealthStore
    private var builder: HKWorkoutRouteBuilder?
    /// Fixes while running (none while paused), for the summary.
    private(set) var points: [RoutePoint] = []
    var isPaused = false
    /// New fixes as they're kept (main actor), for the live Elevation page.
    var onPoints: (([RoutePoint]) -> Void)?

    init(store: HKHealthStore) {
        self.store = store
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone
    }

    /// Asks for location once; the workout starts either way and the route
    /// begins as soon as permission is given.
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    var isDenied: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    func start() {
        builder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        points = []
        isPaused = false
        requestPermission()
        manager.startUpdatingLocation()
    }

    /// Stops and attaches the route to the saved workout.
    func finish(with workout: HKWorkout) async {
        onPoints = nil
        manager.stopUpdatingLocation()
        guard let builder else { return }
        self.builder = nil
        guard !points.isEmpty else {
            builder.discard()
            return
        }
        _ = try? await builder.finishRoute(with: workout, metadata: nil)
    }

    /// Stops without saving a route.
    func discard() {
        onPoints = nil
        manager.stopUpdatingLocation()
        builder?.discard()
        builder = nil
    }

    private func add(_ locations: [CLLocation]) {
        guard !isPaused, let builder else { return }
        // The same limit the map uses (`CardioRoute.maximumAccuracyMeters`).
        let usable = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= CardioRoute.maximumAccuracyMeters }
        guard !usable.isEmpty else { return }
        let added = usable.map { location in
            RoutePoint(
                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                time: location.timestamp, horizontalAccuracy: location.horizontalAccuracy
            )
        }
        points += added
        builder.insertRouteData(usable) { _, _ in }
        onPoints?(added)
    }

    // The manager was made on the main thread, so it calls back there.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { self.add(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
