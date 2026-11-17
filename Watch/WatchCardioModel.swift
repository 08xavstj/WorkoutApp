import Foundation
import HealthKit
import WatchKit

/// A cardio workout on the wrist: a run, a ride, a row. Runs its own
/// HKWorkoutSession (one HKWorkout with the activity's type and
/// indoor/outdoor), keeps the live heart-rate zone and the time in each zone
/// (`CardioZoneTracker`), and taps the wrist when heart rate leaves or
/// re-enters the target band.
///
/// Separate from `WatchWorkoutModel`, which stays lifting-only: only one of
/// the two records at a time. Nothing is sent to the phone when a cardio
/// workout ends. The phone reads the saved workout from Apple Health like any
/// other watch workout (`HealthKitClient.externalWorkouts`), so it shows once
/// and never becomes a lifting session (a `WatchWorkoutSummary` would make one).
///
/// No GPS route is recorded: that needs location permission and a route
/// builder that could not be tested here. Distance comes from the Watch's own
/// workout data.
@Observable
final class WatchCardioModel: NSObject {
    static let shared = WatchCardioModel()

    enum Phase: Equatable {
        case idle, starting, running, paused, ended
    }

    /// Metadata on the saved workout: the `CardioActivity` (the phone's
    /// `HealthKitClient.watchCardioMetadataKey` is the same string).
    static let metadataKey = "TensileCardioActivity"

    private(set) var phase: Phase = .idle
    private(set) var activity = CardioActivity.outdoorRun
    private(set) var target = CardioTarget.off
    private(set) var startedAt: Date?
    private(set) var heartRate: Double?
    private(set) var averageHeartRate: Double?
    private(set) var maximumHeartRate: Double?
    private(set) var activeKilocalories: Double?
    private(set) var distanceMeters: Double?
    /// Zone clock and target taps for the workout in progress.
    private(set) var tracker = CardioZoneTracker(scheme: .ageEstimate(age: WatchZoneStore.standInAge))
    /// Where the workout's zones came from.
    private(set) var zoneSource = WatchZoneStore.Source.standIn
    /// The zones a workout started now would use, for the start sheet.
    private(set) var preview: WatchZoneStore.Choice?
    /// What the workout came to, once it has ended.
    private(set) var summary: CardioSummary?
    private(set) var problem: String?
    /// When the pause now running began; nil while the workout runs.
    private(set) var pausedAt: Date?
    /// Seconds of pauses already ended in this workout.
    private(set) var pausedSeconds: TimeInterval = 0
    /// Siri asked for cardio (`StartCardioIntent`): the start screen opens the activity list.
    var pickerRequested = false

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var workoutSession: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    /// When the workout last began running (its start, or the latest resume).
    @ObservationIgnored private var runningSince: Date?
    /// End was tapped and the save is under way.
    @ObservationIgnored private var isEnding = false

    var isActive: Bool { phase == .running || phase == .paused }
    /// Starting or recording: the lifting model must not start a workout now.
    var isBusy: Bool { phase == .starting || isActive }

    // MARK: Zones

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling),
            // For zones from age, when the phone has sent none.
            HKCharacteristicType(.dateOfBirth),
        ]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            problem = "Health access failed: \(error.localizedDescription)"
        }
    }

    /// Asks for Health access and works out the zones, for the start sheet.
    func prepare() async {
        guard phase == .idle || phase == .ended else { return }
        await requestAuthorization()
        preview = await resolveZones()
    }

    /// The zones to use now: the phone's choice as last received; else Apple
    /// Health's own zones (watchOS 27); else percent of a maximum heart rate
    /// estimated from age (`HeartRateZoneScheme.ageEstimate`).
    func resolveZones() async -> WatchZoneStore.Choice {
        if let scheme = WatchZoneStore.fromPhone {
            return WatchZoneStore.Choice(scheme: scheme, source: .phone)
        }
        let age = ageFromHealth()
        let estimate = HeartRateZoneScheme.ageEstimate(age: age ?? WatchZoneStore.standInAge)
        if let scheme = await healthZones(easyBand: estimate.easyBand) {
            return WatchZoneStore.Choice(scheme: scheme, source: .health)
        }
        return WatchZoneStore.Choice(scheme: estimate, source: age == nil ? .standIn : .ageEstimate)
    }

    private func ageFromHealth() -> Int? {
        guard let birth = try? store.dateOfBirthComponents(),
              let date = Calendar.current.date(from: birth),
              let years = Calendar.current.dateComponents([.year], from: date, to: .now).year,
              (13...100).contains(years) else { return nil }
        return years
    }

    /// Apple Health's heart-rate zones on watchOS 27
    /// (`HKHealthStore.preferredWorkoutZoneConfiguration(for:)`), as the
    /// phone reads them in `HealthKitClient.preferredHeartRateZones`.
    private func healthZones(easyBand: HeartRateBand) async -> HeartRateZoneScheme? {
        #if compiler(>=6.4)
        if #available(iOS 27, watchOS 27, *) {
            guard let configuration = try? await store.preferredWorkoutZoneConfiguration(for: HKQuantityType(.heartRate)) else {
                return nil
            }
            let unit = HKUnit.count().unitDivided(by: .minute())
            let zones = configuration.zones.sorted { $0.index < $1.index }
            guard zones.count >= 2 else { return nil }
            var boundaries: [Double] = []
            // Each zone starts where it says, or where the one below ends.
            for (lower, upper) in zip(zones, zones.dropFirst()) {
                guard let edge = upper.minimum ?? lower.maximum, edge.is(compatibleWith: unit) else { return nil }
                boundaries.append(edge.doubleValue(for: unit))
            }
            var floor: Double?
            if let minimum = zones[0].minimum, minimum.is(compatibleWith: unit) {
                floor = minimum.doubleValue(for: unit)
            }
            return HeartRateZoneScheme.appleHealth(floor: floor, boundaries: boundaries, easyBand: easyBand)
        }
        #endif
        return nil
    }

    /// watchOS 27: saves the workout with the zones the wrist showed
    /// (`HKWorkoutBuilder.setCustomZoneConfiguration(_:for:)`, called before
    /// collection begins), so Apple's Fitness app splits the time the same
    /// way. Apple's zone 1 has no lower limit, so time under Tensile's zone 1
    /// counts as zone 1 there. Skipped for Apple Health's own zones, which the
    /// builder uses anyway. A failure changes nothing on the wrist.
    private func applyZones(_ scheme: HeartRateZoneScheme, to builder: HKLiveWorkoutBuilder) async {
        #if compiler(>=6.4)
        if #available(iOS 27, watchOS 27, *) {
            guard scheme.kind != .appleHealth else { return }
            let unit = HKUnit.count().unitDivided(by: .minute())
            let type = HKQuantityType(.heartRate)
            let boundaries = scheme.boundaries.map { HKQuantity(unit: unit, doubleValue: $0) }
            guard let configuration = try? HKWorkoutZoneConfiguration(quantityType: type, zoneBoundaries: boundaries) else { return }
            try? await builder.setCustomZoneConfiguration(configuration, for: type)
        }
        #endif
    }

    // MARK: Recording

    /// Starts recording `activity`, holding heart rate to `target` if one is set.
    func start(_ activity: CardioActivity, target: CardioTarget) async {
        guard phase == .idle || phase == .ended else { return }
        // One workout at a time.
        let lifting = WatchWorkoutModel.shared
        guard lifting.phase == .idle || lifting.phase == .ended else {
            problem = "Finish the lifting workout first."
            return
        }
        phase = .starting
        problem = nil
        summary = nil
        self.activity = activity
        self.target = target
        await requestAuthorization()
        let zones = await resolveZones()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity.healthType
        configuration.locationType = activity.locationType
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            workoutSession = session
            self.builder = builder
            await applyZones(zones.scheme, to: builder)
            let start = Date.now
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            // Marks the workout as Tensile's cardio, with which activity (treadmill and outdoor run share a type).
            builder.addMetadata([Self.metadataKey: activity.rawValue]) { _, _ in }
            heartRate = nil
            averageHeartRate = nil
            maximumHeartRate = nil
            activeKilocalories = nil
            distanceMeters = nil
            pausedAt = nil
            pausedSeconds = 0
            tracker = CardioZoneTracker(scheme: zones.scheme, target: target)
            zoneSource = zones.source
            startedAt = start
            runningSince = start
            phase = .running
            WKInterfaceDevice.current().play(.start)
        } catch {
            problem = "Couldn't start the workout: \(error.localizedDescription)"
            workoutSession = nil
            builder = nil
            phase = .idle
        }
    }

    func pause() {
        guard phase == .running, !isEnding else { return }
        workoutSession?.pause()
        phase = .paused
        beginPause()
        WKInterfaceDevice.current().play(.stop)
    }

    func resume() {
        guard phase == .paused, !isEnding else { return }
        workoutSession?.resume()
        phase = .running
        endPause()
        WKInterfaceDevice.current().play(.start)
    }

    private func beginPause(at date: Date = .now) {
        guard pausedAt == nil else { return }
        pausedAt = date
        tracker.pause(at: date)
    }

    private func endPause(at date: Date = .now) {
        guard let since = pausedAt else { return }
        pausedSeconds += max(0, date.timeIntervalSince(since))
        pausedAt = nil
        runningSince = date
        tracker.resume(at: date)
    }

    /// The workout clock at `date`: time since the start without the pauses,
    /// as Apple Health counts the workout's length.
    func elapsed(at date: Date) -> TimeInterval? {
        guard let start = startedAt else { return nil }
        let running = pausedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return max(0, date.timeIntervalSince(start) - pausedSeconds - running)
    }

    /// Ends the workout and saves it to Apple Health.
    func end() async {
        guard isActive, !isEnding, let workoutSession, let builder else { return }
        isEnding = true
        let end = Date.now
        let active = elapsed(at: end) ?? 0
        tracker.end(at: end)
        workoutSession.end()
        var saved = false
        do {
            try await builder.endCollection(at: end)
            saved = try await builder.finishWorkout() != nil
        } catch {
            problem = "Couldn't save the workout: \(error.localizedDescription)"
        }
        summary = CardioSummary(
            activity: activity, target: target, tracker: tracker, activeSeconds: active,
            distanceMeters: distanceMeters, averageBpm: averageHeartRate, maximumBpm: maximumHeartRate,
            activeKilocalories: activeKilocalories, saved: saved
        )
        pausedAt = nil
        pausedSeconds = 0
        self.workoutSession = nil
        self.builder = nil
        isEnding = false
        phase = .ended
        WKInterfaceDevice.current().play(.stop)
    }

    /// Stops without saving anything.
    func discard() {
        guard isActive, !isEnding else { return }
        workoutSession?.end()
        builder?.discardWorkout()
        workoutSession = nil
        builder = nil
        pausedAt = nil
        pausedSeconds = 0
        phase = .idle
    }

    /// Back to the start screen after the end screen.
    func reset() {
        guard phase == .ended else { return }
        phase = .idle
        summary = nil
        problem = nil
    }

    // MARK: HealthKit callbacks (hop to the main actor)

    private func sessionChanged(to state: HKWorkoutSessionState, at date: Date) {
        guard isActive, !isEnding else { return }
        switch state {
        case .running:
            // Resumed by the system.
            if phase == .paused {
                phase = .running
                endPause(at: date)
            }
        case .paused:
            if phase == .running {
                phase = .paused
                beginPause(at: date)
            }
        default: break
        }
    }

    private func fail(_ message: String) {
        guard isBusy, !isEnding else { return }
        problem = "Recording stopped: \(message)"
        builder?.discardWorkout()
        workoutSession = nil
        builder = nil
        pausedAt = nil
        pausedSeconds = 0
        phase = .idle
    }

    private func update(current: Double?, at date: Date?, average: Double?, maximum: Double?, energy: Double?, distance: Double?) {
        guard isActive else { return }
        averageHeartRate = average ?? averageHeartRate
        maximumHeartRate = maximum ?? maximumHeartRate
        activeKilocalories = energy ?? activeKilocalories
        distanceMeters = distance ?? distanceMeters
        guard let current else { return }
        heartRate = current
        guard phase == .running else { return }
        // The reading's own time, kept inside the stretch now running: one
        // that arrives late must not reach back across a pause.
        let now = Date.now
        let when = min(now, max(date ?? now, runningSince ?? now))
        if let alert = tracker.reading(bpm: current, at: when) { play(alert) }
    }

    /// The wrist taps for the target band (`CardioZoneTracker.Alert`). The
    /// strongest tap is for "above": going too hard is the one that matters.
    private func play(_ alert: CardioZoneTracker.Alert) {
        let device = WKInterfaceDevice.current()
        switch alert {
        case .above: device.play(.notification)
        case .below: device.play(.directionUp)
        case .inBand: device.play(.success)
        }
    }
}

extension WatchCardioModel: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in self.sessionChanged(to: toState, at: date) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.fail(message) }
    }
}

extension WatchCardioModel: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var current: Double?
        var currentDate: Date?
        var average: Double?
        var maximum: Double?
        var energy: Double?
        var distance: Double?
        let heartType = HKQuantityType(.heartRate)
        if collectedTypes.contains(heartType), let statistics = workoutBuilder.statistics(for: heartType) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            current = statistics.mostRecentQuantity()?.doubleValue(for: unit)
            currentDate = statistics.mostRecentQuantityDateInterval()?.end
            average = statistics.averageQuantity()?.doubleValue(for: unit)
            maximum = statistics.maximumQuantity()?.doubleValue(for: unit)
        }
        let energyType = HKQuantityType(.activeEnergyBurned)
        if collectedTypes.contains(energyType), let statistics = workoutBuilder.statistics(for: energyType) {
            energy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
        // A workout collects one of the two: on foot, or on a bike.
        for distanceType in [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)] {
            if collectedTypes.contains(distanceType), let sum = workoutBuilder.statistics(for: distanceType)?.sumQuantity() {
                distance = sum.doubleValue(for: .meter())
            }
        }
        guard current != nil || average != nil || maximum != nil || energy != nil || distance != nil else { return }
        Task { @MainActor in
            self.update(current: current, at: currentDate, average: average, maximum: maximum, energy: energy, distance: distance)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension CardioActivity {
    /// The Apple Health workout type the activity is saved as.
    var healthType: HKWorkoutActivityType {
        switch self {
        case .outdoorRun, .treadmill: .running
        case .outdoorWalk: .walking
        case .outdoorCycle, .indoorCycle: .cycling
        case .rower: .rowing
        case .elliptical: .elliptical
        case .stairs: .stairClimbing
        case .hiit: .highIntensityIntervalTraining
        case .other: .other
        }
    }

    var locationType: HKWorkoutSessionLocationType {
        switch isOutdoor {
        case .some(true): .outdoor
        case .some(false): .indoor
        case .none: .unknown
        }
    }
}
