import CoreMotion
import Foundation
import Observation
import WatchKit
#if canImport(AppCore)
import AppCore
#endif

/// The experimental rep counter (lifting-features.md, Pick 8): reads the
/// Watch's device motion during one set of a barbell squat or deadlift and
/// runs `RepDetection` on the vertical acceleration. It starts on "Start set"
/// (`WatchRepCounterView`), runs only while the set is in progress (no rest
/// timer, workout not paused) and stops when the set
/// is ticked, after `maximumSeconds`, or when the view goes away, to save
/// battery. Nothing leaves the Watch.
///
/// CoreMotion (watchOS 2+, checked against Apple's docs): `CMMotionManager`
/// `startDeviceMotionUpdates(to:withHandler:)`, `deviceMotionUpdateInterval`,
/// `isDeviceMotionAvailable`; `CMDeviceMotion.userAcceleration` and
/// `.gravity` in g. The running `HKWorkoutSession` keeps the app running with
/// the wrist down, so updates continue. watchOS 27.2 adds
/// `CMMotionManager.authorizationStatus`, so the Watch's Info.plist should
/// carry an `NSMotionUsageDescription`.
@Observable
final class RepCounter {
    static let shared = RepCounter()

    /// About 50 Hz: enough for squat and deadlift reps (well under 5 Hz).
    static let sampleRate = 50.0
    /// Stop on our own if the set is never ticked (3 min is a very long set).
    static let maximumSeconds = 180.0
    /// Re-run the analysis every half second of samples.
    static let analysisEvery = 25

    /// The set being counted ("exercise-set" index key, as in `WatchLiveView`).
    private(set) var setKey: String?
    private(set) var isRunning = false
    private(set) var analysis = RepDetection.Analysis.empty
    /// The count shown: nil before 3 reps; follows the latest analysis.
    private(set) var count: Int?
    /// The one "slowing" tap has been played for this set.
    private(set) var hasSignalledSlowing = false

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var samples: [Double] = []
    @ObservationIgnored private var firstTimestamp: TimeInterval?
    @ObservationIgnored private var lastTimestamp: TimeInterval = 0
    @ObservationIgnored private var sinceAnalysis = 0
    /// Bumped on every start, so a stale caller can't stop a newer run.
    @ObservationIgnored private var runID = 0

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    /// The counted reps for a set, to pre-fill its reps field (nil: nothing
    /// counted, or the counter was on another set).
    func countedReps(forSet key: String) -> Int? {
        setKey == key ? count : nil
    }

    var isSlowing: Bool { analysis.isSlowing }

    /// Starts counting a set and returns the run's id for `stop(run:)`. A new
    /// key clears the last set's reps; the same key carries on from them.
    @discardableResult
    func start(setKey key: String) -> Int {
        if setKey != key {
            stop()
            clear()
            setKey = key
        }
        guard !isRunning, motion.isDeviceMotionAvailable else { return runID }
        runID += 1
        motion.deviceMotionUpdateInterval = 1 / Self.sampleRate
        isRunning = true
        // Delivered on the main queue, so the handler is on the main actor.
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            let user = data.userAcceleration
            let gravity = data.gravity
            let timestamp = data.timestamp
            MainActor.assumeIsolated {
                guard let counter = self else { return }
                counter.receive(user: user, gravity: gravity, at: timestamp)
            }
        }
        return runID
    }

    /// Stops `run` if it is still the current one.
    func stop(run: Int) {
        guard run == runID else { return }
        stop()
    }

    /// Stops the motion updates and keeps the count (for the reps field).
    func stop() {
        guard isRunning else { return }
        motion.stopDeviceMotionUpdates()
        isRunning = false
        // A last look at the samples for the reps field; no tap once the set is over.
        refresh(signalSlowing: false)
    }

    /// Stops and forgets the set (e.g. the workout ended).
    func reset() {
        stop()
        clear()
        setKey = nil
    }

    private func clear() {
        samples = []
        firstTimestamp = nil
        lastTimestamp = 0
        sinceAnalysis = 0
        analysis = .empty
        count = nil
        hasSignalledSlowing = false
    }

    private func receive(user: CMAcceleration, gravity: CMAcceleration, at timestamp: TimeInterval) {
        guard isRunning else { return }
        samples.append(RepDetection.verticalAcceleration(
            userX: user.x, userY: user.y, userZ: user.z,
            gravityX: gravity.x, gravityY: gravity.y, gravityZ: gravity.z
        ))
        if firstTimestamp == nil { firstTimestamp = timestamp }
        lastTimestamp = timestamp
        sinceAnalysis += 1
        if sinceAnalysis >= Self.analysisEvery {
            refresh()
        }
        if Double(samples.count) >= Self.maximumSeconds * Self.sampleRate {
            stop()
        }
    }

    /// Re-runs the analysis at the rate the samples actually arrived.
    private func refresh(signalSlowing: Bool = true) {
        sinceAnalysis = 0
        var rate = Self.sampleRate
        if let firstTimestamp, lastTimestamp > firstTimestamp, samples.count > 1 {
            rate = Double(samples.count - 1) / (lastTimestamp - firstTimestamp)
        }
        let result = RepDetection.analyze(samples, sampleRate: rate)
        analysis = result
        // Follows the analysis, which can drop a stray early bout once the set's
        // longer run of reps shows (`RepDetection.longestBout`).
        if let shown = result.shownCount {
            count = shown
        }
        if signalSlowing, result.isSlowing, !hasSignalledSlowing {
            hasSignalledSlowing = true
            WKInterfaceDevice.current().play(.directionDown)
        }
    }
}
