import Foundation
import HealthKit

/// Runs an iPhone workout session (iOS 26+) while you lift, so heart rate from
/// AirPods Pro 3 (or a Bluetooth chest strap) streams in live and is saved to
/// Apple Health with the workout.
@Observable
final class LiveWorkoutRecorder: NSObject {
    private(set) var heartRate: Double?
    private(set) var averageHeartRate: Double?
    private(set) var maximumHeartRate: Double?
    private(set) var isRecording = false
    private(set) var problem: String?
    /// The logged session this recording belongs to.
    private(set) var sessionStart: Date?

    @ObservationIgnored private var workoutSession: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private let store: HKHealthStore

    init(store: HKHealthStore) {
        self.store = store
        super.init()
    }

    /// Starts recording for a gym session that began at `start`. A recording
    /// left over from a different session is discarded first, so its start
    /// time is never saved with this workout.
    func start(at start: Date) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if isRecording {
            if sessionStart == start { return }
            discard()
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            workoutSession = session
            self.builder = builder
            session.prepare()
            let begin = min(start, .now)
            session.startActivity(with: begin)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                builder.beginCollection(withStart: begin) { _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            sessionStart = start
            isRecording = true
            problem = nil
        } catch {
            problem = "Live heart rate isn't available: \(error.localizedDescription)"
            workoutSession = nil
            builder = nil
        }
    }

    /// Ends the session and saves the workout (with heart rate) to Apple Health.
    func finish(at end: Date) async throws {
        guard let workoutSession, let builder else { return }
        workoutSession.end()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: end) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.finishWorkout { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        reset()
    }

    /// Stops without saving anything.
    func discard() {
        workoutSession?.end()
        builder?.discardWorkout()
        reset()
    }

    private func reset() {
        workoutSession = nil
        builder = nil
        isRecording = false
        sessionStart = nil
        heartRate = nil
        averageHeartRate = nil
        maximumHeartRate = nil
    }

    fileprivate func update(current: Double?, average: Double?, maximum: Double?) {
        heartRate = current ?? heartRate
        averageHeartRate = average ?? averageHeartRate
        maximumHeartRate = maximum ?? maximumHeartRate
    }

    /// The session failed (e.g. the system ended it): stop showing it as live
    /// so a new recording can start.
    fileprivate func fail(_ message: String) {
        builder?.discardWorkout()
        reset()
        problem = message
    }
}

extension LiveWorkoutRecorder: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = "Live heart rate stopped: \(error.localizedDescription)"
        Task { @MainActor in self.fail(message) }
    }
}

extension LiveWorkoutRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let type = HKQuantityType(.heartRate)
        guard collectedTypes.contains(type), let statistics = workoutBuilder.statistics(for: type) else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let current = statistics.mostRecentQuantity()?.doubleValue(for: unit)
        let average = statistics.averageQuantity()?.doubleValue(for: unit)
        let maximum = statistics.maximumQuantity()?.doubleValue(for: unit)
        Task { @MainActor in self.update(current: current, average: average, maximum: maximum) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
