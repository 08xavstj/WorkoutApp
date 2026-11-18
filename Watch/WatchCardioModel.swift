import Foundation
import HealthKit
import WatchKit

/// A cardio workout on the wrist: a run, a ride, a row, or a sport (squash,
/// indoor soccer, cross-country skiing...). Runs its own
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
/// Outdoors, the GPS route is recorded with an `HKWorkoutRouteBuilder`
/// (`WatchRouteRecorder`) and saved with the workout; distance comes from the
/// Watch's own workout data. Laps and splits (`LapTracker`) are saved as
/// workout events, runs pause with the system's auto-pause, and Water Lock
/// can be turned on for rain, sweat and gloves
/// (docs/research/watch-app-redesign-2026-11.md §4.5).
@Observable
final class WatchCardioModel: NSObject {
    static let shared = WatchCardioModel()

    enum Phase: Equatable {
        case idle, starting, running, paused, ended
    }

    /// Metadata on the saved workout: the `CardioActivity` (the phone's
    /// `HealthKitClient.watchCardioMetadataKey` is the same string).
    static let metadataKey = "TensileCardioActivity"
    /// UserDefaults keys the activity list keeps (`ActivityPickerView`'s `@AppStorage`).
    static let lastActivityKey = "cardioLastActivity"
    static let targetKey = "cardioTarget"

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
    /// Laps, splits and current pace for this workout.
    private(set) var laps = LapTracker(start: .now, autoLapMeters: nil)
    /// Heart rate over the workout, for the charts.
    private(set) var heartSeries = HeartRateSeries()
    /// Altitude, climb and the 30-minute profile, outdoors.
    private(set) var elevation = RunningElevation()
    /// A short message over the metric pages: a split, a lap, auto-pause.
    private(set) var banner: CardioBanner?
    /// HealthKit's auto-pause has stopped the clock (the session itself runs on).
    private(set) var isAutoPaused = false
    /// The system's auto-pause has fired in this workout, so the controls say where it's set.
    private(set) var autoPauseSeen = false
    /// The fastest current speed so far (m/s, the 20 s window), for the Speed page.
    private(set) var topSpeed: Double?
    /// The saved workout's UUID, for Handoff from the summary.
    private(set) var savedWorkoutID: UUID?
    /// Clears a timed banner.
    @ObservationIgnored private var bannerTask: Task<Void, Never>?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var workoutSession: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    /// When the workout last began running (its start, or the latest resume).
    @ObservationIgnored private var runningSince: Date?
    /// End was tapped and the save is under way.
    @ObservationIgnored private var isEnding = false
    /// When Pause or Resume was last tapped here (`sessionChanged` ignores older callbacks).
    @ObservationIgnored private var lastLocalPauseChange: Date?
    /// The GPS route of an outdoor workout (`CardioActivity.isOutdoor`); nil indoors.
    @ObservationIgnored private var route: WatchRouteRecorder?

    var isActive: Bool { phase == .running || phase == .paused }
    /// Starting or recording: the lifting model must not start a workout now.
    var isBusy: Bool { phase == .starting || isActive }

    // MARK: Zones

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceCrossCountrySkiing),
            // Split times and current pace need the distance as it comes in (above).
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
    /// Health's own zones (watchOS 27); else Tensile's zones from a maximum
    /// heart rate estimated from age (`HeartRateZoneScheme.ageEstimate`).
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
    func start(_ activity: CardioActivity, target chosenTarget: CardioTarget) async {
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
        savedWorkoutID = nil
        self.activity = activity
        // Sports record with no target (`CardioActivity.takesTarget`).
        let target = activity.takesTarget ? chosenTarget : .off
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
            // The session failed (or was discarded) while this waited: `fail` has
            // already reset everything, and a "running" workout with no session
            // could never be ended.
            guard phase == .starting, self.workoutSession === session else {
                session.end()
                builder.discardWorkout()
                return
            }
            // Marks the workout as Tensile's cardio, with which activity (treadmill and outdoor run share a type).
            builder.addMetadata([Self.metadataKey: activity.rawValue]) { _, _ in }
            heartRate = nil
            averageHeartRate = nil
            maximumHeartRate = nil
            activeKilocalories = nil
            distanceMeters = nil
            pausedAt = nil
            pausedSeconds = 0
            isAutoPaused = false
            autoPauseSeen = false
            topSpeed = nil
            banner = nil
            heartSeries = HeartRateSeries()
            elevation = RunningElevation()
            // Auto laps every 1 km (1 mi) where the activity has a distance (`LapTracker`).
            laps = LapTracker(start: start, autoLapMeters: activity.movement == .stationary
                              ? nil : LapTracker.autoLapMeters(miles: watchUsesMiles()))
            tracker = CardioZoneTracker(scheme: zones.scheme, target: target)
            zoneSource = zones.source
            startedAt = start
            runningSince = start
            phase = .running
            if activity.isOutdoor == true {
                let recorder = WatchRouteRecorder(store: store)
                // Altitude for the Elevation page, as the fixes come in.
                recorder.onPoints = { [weak self] points in self?.received(points) }
                recorder.start()
                route = recorder
            }
            WKInterfaceDevice.current().play(.start)
        } catch {
            problem = "Couldn't start the workout: \(error.localizedDescription)"
            // A session whose activity started but whose collection failed
            // would otherwise keep running with nothing to end it.
            workoutSession?.end()
            workoutSession = nil
            builder = nil
            phase = .idle
        }
    }

    func pause() {
        guard phase == .running, !isEnding else { return }
        workoutSession?.pause()
        phase = .paused
        lastLocalPauseChange = .now
        // Auto-paused already: that pause carries on as this one, and the
        // builder's auto pause is closed so the session's own pause pairs up.
        if isAutoPaused {
            isAutoPaused = false
            addEvent(HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: .now, duration: 0), metadata: nil))
            clearBanner()
        }
        beginPause()
        WKInterfaceDevice.current().play(.stop)
    }

    func resume() {
        guard phase == .paused, !isEnding else { return }
        workoutSession?.resume()
        phase = .running
        lastLocalPauseChange = .now
        endPause()
        WKInterfaceDevice.current().play(.start)
    }

    private func beginPause(at date: Date = .now) {
        guard pausedAt == nil else { return }
        route?.isPaused = true
        pausedAt = date
        tracker.pause(at: date)
        laps.pause(at: date)
    }

    private func endPause(at date: Date = .now) {
        guard let since = pausedAt else { return }
        route?.isPaused = false
        pausedSeconds += max(0, date.timeIntervalSince(since))
        pausedAt = nil
        runningSince = date
        tracker.resume(at: date)
        laps.resume(at: date)
    }

    /// The clock's start moved on by the pauses already over, for a `Text`
    /// timer the system keeps current in Always On (`WorkoutClockText`).
    var clockTimerStart: Date? {
        startedAt.map { $0.addingTimeInterval(pausedSeconds) }
    }

    // MARK: Auto-pause, laps and Water Lock

    /// HealthKit's `.motionPaused` / `.motionResumed`, which come during running
    /// workouts when Settings › Workout › Auto-Pause is on (HKWorkoutEventType
    /// docs). Apple's advice is not to pause the session for them but to add
    /// pause and resume events to the live builder, so the workout's time leaves
    /// the stop out (Apple Developer Forums thread 649276). The clock, zones,
    /// route and laps stand still, with a `.stop` / `.start` tap like a pause by hand.
    private func generated(_ type: HKWorkoutEventType, at date: Date) {
        guard isActive, !isEnding else { return }
        switch type {
        case .motionPaused:
            guard phase == .running, !isAutoPaused else { return }
            isAutoPaused = true
            autoPauseSeen = true
            beginPause(at: date)
            addEvent(HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: date, duration: 0), metadata: nil))
            showBanner("Auto-paused", seconds: nil)
            WKInterfaceDevice.current().play(.stop)
        case .motionResumed:
            guard phase == .running, isAutoPaused else { return }
            isAutoPaused = false
            endPause(at: date)
            addEvent(HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: date, duration: 0), metadata: nil))
            showBanner("Resumed", seconds: Self.bannerSeconds)
            WKInterfaceDevice.current().play(.start)
        default:
            break
        }
    }

    /// The Lap button: closes the lap now running and saves it as a segment
    /// (`HKWorkoutEventType.segment`, a period of interest; `.lap` is for equal
    /// distances such as the auto laps). In a sport it marks a period.
    func markLap() {
        guard phase == .running, !isEnding else { return }
        let now = Date.now
        guard let lap = laps.markLap(at: now) else { return }
        addEvent(HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: lap.start, end: lap.end), metadata: nil))
        if WatchPreferences.splitTaps { WKInterfaceDevice.current().play(.navigationGenericManeuver) }
        let miles = watchUsesMiles()
        var text = "\(activity.movement == .stationary ? "Period" : "Lap") \(lap.number) · \(workoutElapsedText(lap.seconds))"
        if activity.movement != .stationary, let pace = paceOrSpeedText(lap: lap, miles: miles) { text += " · \(pace)" }
        showBanner(text, seconds: Self.bannerSeconds)
    }

    /// Auto laps finished by the latest distance: saved as `.lap` events with
    /// their start and end, one tap each, and a banner with the split.
    private func autoLapped(_ finished: [LapTracker.Lap]) {
        guard let lap = finished.last else { return }
        for lap in finished {
            addEvent(HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: lap.start, end: lap.end), metadata: nil))
        }
        if WatchPreferences.splitTaps { WKInterfaceDevice.current().play(.navigationGenericManeuver) }
        let miles = watchUsesMiles()
        var text = "\(miles ? "Mile" : "Km") \(lap.number) · \(workoutElapsedText(lap.seconds))"
        if let pace = paceOrSpeedText(lap: lap, miles: miles) { text += " · \(pace)" }
        showBanner(text, seconds: Self.bannerSeconds)
    }

    /// "5:12 /km" on foot, "24.6 km/h" on a bike.
    func paceOrSpeedText(lap: LapTracker.Lap, miles: Bool) -> String? {
        if activity.movement.showsSpeed {
            return lap.speed(miles: miles).map { CardioSummary.speedText($0, miles: miles) }
        }
        return lap.pace(miles: miles).map { CardioSummary.paceText($0, miles: miles) }
    }

    private func addEvent(_ event: HKWorkoutEvent) {
        builder?.addWorkoutEvents([event]) { _, _ in }
    }

    /// How long a split or lap banner stays (app's choice). In Always On it
    /// stays until the wrist is raised (`CardioBannerView`).
    static let bannerSeconds = 3.0

    /// Shows a banner over the metric pages; `seconds` nil keeps it until replaced or cleared.
    func showBanner(_ text: String, seconds: Double?) {
        let banner = CardioBanner(text: text, at: .now)
        self.banner = banner
        bannerTask?.cancel()
        guard let seconds else { return }
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.clearBanner(banner)
        }
    }

    /// Clears `banner` if it's still the one showing.
    func clearBanner(_ shown: CardioBanner? = nil) {
        guard shown == nil || banner == shown else { return }
        banner = nil
    }

    /// Water Lock for an outdoor run (rain, sweat) and snow (gloves, sleeves):
    /// the app's choice; Apple turns it on by itself only for swims. Allowed in
    /// the foreground during a workout on a water-resistant Watch
    /// (`WKInterfaceDevice.enableWaterLock`, watchOS 6.1); the crown unlocks it.
    var offersWaterLock: Bool {
        activity == .outdoorRun || activity.category == .snow
    }

    func enableWaterLock() {
        guard isActive else { return }
        WKInterfaceDevice.current().enableWaterLock()
    }

    /// Whether this activity has laps: distance activities and sports (as periods).
    var hasLaps: Bool {
        activity.movement != .stationary || activity.category == .sport
    }

    /// GPS fixes from the route recorder (main actor): altitude for the Elevation page.
    private func received(_ points: [RoutePoint]) {
        guard isActive else { return }
        for point in points {
            if let altitude = point.altitude { elevation.add(altitude: altitude, at: point.time) }
        }
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
        // A lap still running at the end is saved as the last one (if it has any time).
        if hasLaps, activity.movement != .stationary, laps.currentLap(at: end).meters >= LapTracker.minimumMetersForPace,
           let lap = laps.markLap(at: end) {
            builder.addWorkoutEvents([HKWorkoutEvent(type: lap.isAuto ? .lap : .segment,
                                                     dateInterval: DateInterval(start: lap.start, end: lap.end), metadata: nil)]) { _, _ in }
        }
        workoutSession.end()
        var saved = false
        var workout: HKWorkout?
        do {
            try await builder.endCollection(at: end)
            workout = try await builder.finishWorkout()
            saved = workout != nil
            savedWorkoutID = workout?.uuid
        } catch {
            problem = "Couldn't save the workout: \(error.localizedDescription)"
        }
        let recorder = route
        route = nil
        if let recorder {
            if let workout { await recorder.finish(with: workout) } else { recorder.discard() }
        }
        var summary = CardioSummary(
            activity: activity, target: target, tracker: tracker, activeSeconds: active,
            distanceMeters: distanceMeters, averageBpm: averageHeartRate, maximumBpm: maximumHeartRate,
            activeKilocalories: activeKilocalories, saved: saved
        )
        if let points = recorder?.points, points.count >= 2 {
            let path = CardioRoute(points: points)
            summary.elevationGainMeters = path.elevation?.gain
            summary.maximumSpeed = path.maximumSpeed
            summary.hasRoute = true
        }
        self.summary = summary
        WatchHistoryStore.save(WatchActivityRecord(
            kind: .cardio, title: activity.title, start: startedAt ?? end, end: end,
            minutes: max(1, Int(active / 60)), detail: Self.historyDetail(summary),
            averageBpm: summary.averageBpm.map { Int($0.rounded()) }, maximumBpm: summary.maximumBpm.map { Int($0.rounded()) },
            activity: activity.rawValue, saved: saved))
        pausedAt = nil
        pausedSeconds = 0
        isAutoPaused = false
        bannerTask?.cancel()
        banner = nil
        self.workoutSession = nil
        self.builder = nil
        isEnding = false
        phase = .ended
        WKInterfaceDevice.current().play(.stop)
    }

    /// Stops without saving anything.
    func discard() {
        guard isActive, !isEnding else { return }
        isAutoPaused = false
        bannerTask?.cancel()
        banner = nil
        route?.discard()
        route = nil
        workoutSession?.end()
        builder?.discardWorkout()
        workoutSession = nil
        builder = nil
        pausedAt = nil
        pausedSeconds = 0
        phase = .idle
    }

    /// A lifting workout is starting: the end screen of a finished run would
    /// sit above its pages (`WatchRootView`), and an old message here would
    /// show on the start screen afterwards.
    func clearForLifting() {
        if phase == .ended {
            phase = .idle
            summary = nil
        }
        if !isBusy { problem = nil }
    }

    /// "5.02 km · 5:12 /km", or the calories where there's no distance.
    private static func historyDetail(_ summary: CardioSummary) -> String {
        let miles = watchUsesMiles()
        if summary.activity.movement != .stationary, let meters = summary.distanceMeters {
            let distance = CardioSummary.distanceText(meters: meters, miles: miles)
            return [distance, summary.paceOrSpeedText(miles: miles)].compactMap { $0 }.joined(separator: " · ")
        }
        return summary.activeKilocalories.map { "\(Int($0.rounded())) kcal" } ?? "Heart rate and zones"
    }

    /// Workouts shorter than this ask before they're saved (HIG Workouts; the
    /// 60 s is the app's choice, the same as lifting's).
    var isBrief: Bool {
        (elapsed(at: .now) ?? 0) < WatchWorkoutModel.briefSeconds
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
        // A callback for a pause or resume from before the last tap here (a quick
        // Pause then Resume) would start the same pause again and count it twice.
        if let local = lastLocalPauseChange, date < local { return }
        switch state {
        case .running:
            // Resumed by the system.
            if phase == .paused {
                phase = .running
                endPause(at: date)
            }
            // A running session while auto-paused is expected: the stop is the builder's, not the session's.
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
        isAutoPaused = false
        banner = nil
        route?.discard()
        route = nil
        builder?.discardWorkout()
        workoutSession?.end()
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
        if let distance {
            distanceMeters = distance
            let finished = laps.add(meters: distance, at: .now)
            if !finished.isEmpty { autoLapped(finished) }
            if let speed = laps.currentSpeed(at: .now), speed.isFinite, speed > (topSpeed ?? 0) { topSpeed = speed }
        }
        guard let current else { return }
        heartRate = current
        let now = Date.now
        heartSeries.add(current, at: min(now, date ?? now))
        guard phase == .running, !isAutoPaused else { return }
        // The reading's own time, kept inside the stretch now running: one
        // that arrives late must not reach back across a pause.
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

    /// Auto-pause and resume during a run (`generated(_:at:)`).
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didGenerate event: HKWorkoutEvent) {
        let type = event.type
        let date = event.dateInterval.start
        Task { @MainActor in self.generated(type, at: date) }
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
        // A workout collects one of these: on foot, on a bike, or on cross-country skis.
        let distanceTypes = [
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceCrossCountrySkiing),
        ]
        for distanceType in distanceTypes {
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

/// A short message over the cardio pages ("Km 3 · 5:12 /km", "Auto-paused").
nonisolated struct CardioBanner: Equatable, Sendable {
    var text: String
    var at: Date
}
