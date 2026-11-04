import Foundation
import HealthKit
import WatchConnectivity
import WatchKit

/// The Watch's view of a lifting session: runs the HKWorkoutSession that
/// records heart rate and calories (once, on the wrist), mirrors the phone's
/// session (`WatchSession`), and sends what you do back as `WatchCommand`s.
/// Works with the phone out of reach: commands queue, and the workout is
/// saved and summarised to the phone whenever it next connects.
@Observable
final class WatchWorkoutModel: NSObject {
    static let shared = WatchWorkoutModel()

    enum Phase: Equatable {
        case idle, starting, running, paused, ended
    }

    private(set) var phase: Phase = .idle
    private(set) var startedAt: Date?
    /// The phone session's start, when this recording was attached to one after it began.
    private(set) var displayStart: Date?
    private(set) var endedAt: Date?
    private(set) var heartRate: Double?
    private(set) var averageHeartRate: Double?
    private(set) var maximumHeartRate: Double?
    private(set) var activeKilocalories: Double?
    private(set) var problem: String?
    /// The phone's session, as last sent (nil: none running on the phone).
    private(set) var snapshot: WatchSession?
    /// Which phone session this recording belongs to (nil when started empty).
    private(set) var recordingSessionID: String?
    /// The workout saved to Apple Health when the recording ended.
    private(set) var summary: WatchWorkoutSummary?
    /// The rest timer running on the wrist.
    private(set) var restEndsAt: Date?
    private(set) var restLength = 90
    private(set) var phoneReachable = false
    /// Sets ticked on the wrist this workout (the end screen when the phone is away).
    private(set) var setsCompletedHere = 0
    /// The exercise on the live page; nil follows the next set to do.
    var selectedExercise: Int?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var workoutSession: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var connection: WCSession?
    /// Snapshots older than the last set ticked here are ignored, so a stale
    /// one can't un-tick it before the phone has applied the command.
    @ObservationIgnored private var lastLocalEdit = Date.distantPast
    @ObservationIgnored private var restStartedAt = Date.distantPast
    @ObservationIgnored private var restTask: Task<Void, Never>?

    var isRecording: Bool { phase == .running || phase == .paused }

    func activate() {
        guard connection == nil, WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        connection = session
    }

    // MARK: Recording

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            problem = "Health access failed: \(error.localizedDescription)"
        }
    }

    /// Starts recording an indoor strength workout, for the phone's session with
    /// `sessionID` (nil: the phone's running session if there is one, else empty).
    func start(sessionID: String?) async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        await start(with: configuration, sessionID: sessionID)
    }

    func start(with configuration: HKWorkoutConfiguration, sessionID: String?) async {
        guard phase == .idle || phase == .ended else {
            if recordingSessionID == nil, let sessionID { adopt(sessionID) }
            return
        }
        phase = .starting
        problem = nil
        await requestAuthorization()
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            workoutSession = session
            self.builder = builder
            // Start from the phone session's start time when it's recent, so the
            // Watch's clock, heart rate and calories line up with the phone's
            // workout instead of beginning when the Watch caught up.
            let start = Self.recordingStart(for: sessionID ?? snapshot.flatMap { $0.isFinished ? nil : $0.id })
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            heartRate = nil
            averageHeartRate = nil
            maximumHeartRate = nil
            activeKilocalories = nil
            summary = nil
            endedAt = nil
            setsCompletedHere = 0
            startedAt = start
            displayStart = nil
            phase = .running
            let active = snapshot.flatMap { $0.isFinished ? nil : $0.id }
            recordingSessionID = sessionID ?? recordingSessionID ?? active
            // The phone's session arrived only while starting: count the clock from its start.
            if let id = recordingSessionID, Self.recordingStart(for: id, now: start) < start {
                displayStart = Self.recordingStart(for: id, now: start)
            }
            send(.recordingStarted, sessionID: recordingSessionID)
            WKInterfaceDevice.current().play(.start)
        } catch {
            problem = "Couldn't start the workout: \(error.localizedDescription)"
            workoutSession = nil
            builder = nil
            phase = .idle
        }
    }

    /// A recording started empty now belongs to the phone's session. The
    /// clock on the wrist switches to the phone's start, so both show the
    /// same elapsed time (the Health workout keeps its real start).
    private func adopt(_ sessionID: String) {
        recordingSessionID = sessionID
        if let phoneStart = WatchSession.startDate(for: sessionID), phoneStart <= .now {
            displayStart = phoneStart
        }
        send(.recordingStarted, sessionID: sessionID)
    }

    /// When to start recording: the phone session's start if it began within
    /// the last 15 minutes, otherwise now.
    static func recordingStart(for sessionID: String?, now: Date = .now) -> Date {
        guard let sessionID, let phoneStart = WatchSession.startDate(for: sessionID),
              phoneStart <= now, now.timeIntervalSince(phoneStart) < 15 * 60 else { return now }
        return phoneStart
    }

    /// The start the wrist's clock counts from: the phone session's when this
    /// recording belongs to one, else the recording's own.
    var clockStart: Date? { displayStart ?? startedAt }

    func pause() {
        guard phase == .running else { return }
        workoutSession?.pause()
        phase = .paused
        send(.pause)
    }

    func resume() {
        guard phase == .paused else { return }
        workoutSession?.resume()
        phase = .running
        send(.resume)
    }

    /// Finish from the wrist: the phone opens its finish sheet (pre-filled with
    /// the session effort) and the workout is saved here.
    func finish(sessionRPE: Int?) async {
        send(.finish(sessionRPE: sessionRPE))
        await end(sessionRPE: sessionRPE)
    }

    /// Ends the HKWorkoutSession, saves the workout and sends its summary to the
    /// phone (queued until the phone is reachable).
    func end(sessionRPE: Int?) async {
        guard isRecording, let workoutSession, let builder else { return }
        let end = Date.now
        workoutSession.end()
        var workout: HKWorkout?
        do {
            try await builder.endCollection(at: end)
            workout = try await builder.finishWorkout()
        } catch {
            problem = "Couldn't save the workout: \(error.localizedDescription)"
        }
        let summary = WatchWorkoutSummary(
            sessionID: recordingSessionID,
            workoutUUID: workout?.uuid,
            start: startedAt ?? end,
            end: end,
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            activeKilocalories: activeKilocalories,
            sessionRPE: sessionRPE
        )
        self.summary = summary
        endedAt = end
        phase = .ended
        // Today's planned session is done: the "next session" complication moves on.
        // (10 minutes is the app's own cut-off so a quick test recording doesn't count.)
        if workout != nil, end.timeIntervalSince(startedAt ?? end) >= 10 * 60 {
            WatchComplications.workoutEnded(at: end)
        }
        self.workoutSession = nil
        self.builder = nil
        clearRest()
        if let data = WatchMessage.encode(summary) {
            connection?.transferUserInfo([WatchMessage.summary: data])
        }
        WKInterfaceDevice.current().play(.stop)
    }

    /// Stops without saving anything.
    func discard() {
        guard isRecording else { return }
        workoutSession?.end()
        builder?.discardWorkout()
        workoutSession = nil
        builder = nil
        phase = .idle
        clearRest()
        send(.recordingStopped, sessionID: recordingSessionID)
        recordingSessionID = nil
        selectedExercise = nil
    }

    /// Back to the start screen after the end screen.
    func reset() {
        phase = .idle
        summary = nil
        selectedExercise = nil
        recordingSessionID = nil
        setsCompletedHere = 0
        if snapshot?.isFinished == true { snapshot = nil }
    }

    // MARK: Sets

    /// Ticks a set with what was done; the phone logs it and the rest timer starts here.
    func completeSet(exerciseIndex: Int, setIndex: Int, reps: Int, weightKg: Double, rpe: Double?) {
        guard var current = snapshot, exerciseIndex < current.exercises.count,
              setIndex < current.exercises[exerciseIndex].sets.count else { return }
        var set = current.exercises[exerciseIndex].sets[setIndex]
        set.reps = reps
        set.weightKg = weightKg
        set.rpe = rpe ?? set.rpe
        set.isCompleted = true
        current.exercises[exerciseIndex].sets[setIndex] = set
        // Point at the next set now, before the phone answers.
        current.currentExercise = nil
        current.currentSet = nil
        if let next = current.nextExerciseIndex {
            current.currentExercise = next
            current.currentSet = current.exercises[next].sets.firstIndex { !$0.isCompleted }
        }
        lastLocalEdit = .now
        snapshot = current
        setsCompletedHere += 1
        send(.completeSet(exerciseIndex: exerciseIndex, setIndex: setIndex, reps: reps, weightKg: weightKg, rpe: rpe))
        WKInterfaceDevice.current().play(.success)
        if !set.isWarmup { startRestIfNeeded(after: exerciseIndex, in: current) }
    }

    /// Skips the rest of the current exercise on the phone.
    func skipExercise() {
        send(.nextExercise)
        selectedExercise = nil
    }

    // MARK: Rest

    /// Superset: no rest between the first lift and its partner, one rest after
    /// both (the phone applies the same rule).
    private func startRestIfNeeded(after index: Int, in session: WatchSession) {
        if session.exercises[index].supersetLabel?.hasSuffix("1") == true,
           let partner = session.partnerIndex(of: index),
           session.exercises[partner].sets.contains(where: { !$0.isCompleted }) {
            return
        }
        startRest(until: Date.now.addingTimeInterval(Double(session.restSeconds)), length: session.restSeconds)
    }

    private func startRest(until ends: Date, length: Int) {
        restEndsAt = ends
        restLength = max(1, length)
        restStartedAt = .now
        restTask?.cancel()
        let wait = max(0, ends.timeIntervalSinceNow)
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.restEnded()
        }
    }

    private func restEnded() {
        restEndsAt = nil
        WKInterfaceDevice.current().play(.notification)
    }

    func skipRest() {
        clearRest()
        send(.skipRest)
    }

    func extendRest(by seconds: Int) {
        guard let restEndsAt else { return }
        startRest(until: restEndsAt.addingTimeInterval(Double(seconds)), length: restLength + seconds)
    }

    private func clearRest() {
        restTask?.cancel()
        restTask = nil
        restEndsAt = nil
    }

    // MARK: Phone → Watch

    private func apply(_ incoming: WatchSession) {
        guard incoming.sentAt >= lastLocalEdit else { return }
        if let current = snapshot, current.id == incoming.id, incoming.sentAt < current.sentAt { return }
        let previous = snapshot
        if incoming.isFinished {
            if previous?.id == incoming.id || previous == nil { snapshot = nil }
            selectedExercise = nil
            // Finished on the phone: the Watch's recording of it ends too (no
            // second effort question; the phone already asked).
            if stopApplies(to: incoming.id) { Task { await end(sessionRPE: nil) } }
            return
        }
        snapshot = incoming
        if previous?.id != incoming.id { selectedExercise = nil }
        if isRecording, recordingSessionID == nil { adopt(incoming.id) }
        // A set ticked on the phone starts the rest there; run it here too.
        if let ends = incoming.restEndsAt, ends > .now {
            if restEndsAt.map({ abs($0.timeIntervalSince(ends)) > 2 }) ?? true {
                startRest(until: ends, length: incoming.restSeconds)
            }
        } else if restEndsAt != nil, incoming.sentAt > restStartedAt.addingTimeInterval(2) {
            // Skipped on the phone.
            clearRest()
        }
    }

    private func handle(_ request: WatchRequest) {
        // A start queued long ago (phone out of reach) shouldn't start a workout now;
        // stops and discards always apply.
        if request.kind == .startRecording, request.sentAt <= Date.now.addingTimeInterval(-10 * 60) { return }
        switch request.kind {
        case .startRecording:
            switch phase {
            case .idle, .ended:
                Task { await start(sessionID: request.sessionID) }
            case .starting:
                if recordingSessionID == nil { recordingSessionID = request.sessionID }
            case .running, .paused:
                if recordingSessionID == nil || recordingSessionID == request.sessionID { adopt(request.sessionID) }
            }
        case .stopRecording:
            guard stopApplies(to: request.sessionID) else {
                // Already ended here: confirm, so the phone stops resending.
                if !isRecording { send(.recordingStopped, sessionID: request.sessionID) }
                return
            }
            Task { await end(sessionRPE: nil) }
        case .discardRecording:
            guard belongsToRecording(request.sessionID) else { return }
            discard()
        }
    }

    /// Whether the phone finishing `sessionID` should end this recording. The
    /// usual test (`belongsToRecording`), plus a recording that holds a different
    /// id but started within 30 minutes of the phone session: the phone can only
    /// run one workout at a time, so its stop means this one. The recording
    /// takes the phone's id first, so its summary joins that session instead of
    /// becoming a second workout.
    private func stopApplies(to sessionID: String) -> Bool {
        if belongsToRecording(sessionID) { return true }
        guard isRecording, let phoneStart = WatchSession.startDate(for: sessionID), let startedAt,
              abs(startedAt.timeIntervalSince(phoneStart)) < 30 * 60 else { return false }
        recordingSessionID = sessionID
        return true
    }

    /// Whether a phone session is the one being recorded: its id matches, or the
    /// recording was started from the phone before the session was attached and
    /// began within a few minutes of it.
    private func belongsToRecording(_ sessionID: String) -> Bool {
        guard isRecording else { return false }
        if let recordingSessionID { return recordingSessionID == sessionID }
        guard let phoneStart = WatchSession.startDate(for: sessionID), let startedAt else { return false }
        return abs(startedAt.timeIntervalSince(phoneStart)) < 5 * 60
    }

    private func activated(snapshot: WatchSession?, reachable: Bool) {
        phoneReachable = reachable
        if let snapshot { apply(snapshot) }
    }

    // MARK: Watch → Phone

    private func send(_ command: WatchCommand, sessionID: String? = nil) {
        let message = WatchCommandMessage(sessionID: sessionID ?? snapshot?.id ?? recordingSessionID, command: command, sentAt: .now)
        guard let data = WatchMessage.encode(message), let connection else { return }
        if connection.isReachable {
            // Falls back to the queue if the phone drops off mid-send.
            connection.sendMessage([WatchMessage.command: data], replyHandler: nil) { _ in
                WCSession.default.transferUserInfo([WatchMessage.command: data])
            }
        } else {
            connection.transferUserInfo([WatchMessage.command: data])
        }
    }

    // MARK: HealthKit callbacks (hop to the main actor)

    private func sessionChanged(to state: HKWorkoutSessionState) {
        switch state {
        case .running: if phase == .paused || phase == .starting { phase = .running }
        case .paused: phase = .paused
        default: break
        }
    }

    private func fail(_ message: String) {
        problem = "Recording stopped: \(message)"
        builder?.discardWorkout()
        workoutSession = nil
        builder = nil
        phase = .idle
        clearRest()
        send(.recordingStopped, sessionID: recordingSessionID)
        recordingSessionID = nil
    }

    private func update(current: Double?, average: Double?, maximum: Double?, energy: Double?) {
        heartRate = current ?? heartRate
        averageHeartRate = average ?? averageHeartRate
        maximumHeartRate = maximum ?? maximumHeartRate
        activeKilocalories = energy ?? activeKilocalories
    }
}

extension WatchWorkoutModel: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in self.sessionChanged(to: toState) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.fail(message) }
    }
}

extension WatchWorkoutModel: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var current: Double?
        var average: Double?
        var maximum: Double?
        var energy: Double?
        let heartType = HKQuantityType(.heartRate)
        if collectedTypes.contains(heartType), let statistics = workoutBuilder.statistics(for: heartType) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            current = statistics.mostRecentQuantity()?.doubleValue(for: unit)
            average = statistics.averageQuantity()?.doubleValue(for: unit)
            maximum = statistics.maximumQuantity()?.doubleValue(for: unit)
        }
        let energyType = HKQuantityType(.activeEnergyBurned)
        if collectedTypes.contains(energyType), let statistics = workoutBuilder.statistics(for: energyType) {
            energy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
        guard current != nil || average != nil || maximum != nil || energy != nil else { return }
        Task { @MainActor in self.update(current: current, average: average, maximum: maximum, energy: energy) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension WatchWorkoutModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        // The phone's latest session waits here even when the Watch app wasn't running.
        let snapshot = WatchMessage.decode(WatchSession.self, from: session.receivedApplicationContext, key: WatchMessage.snapshot)
        let reachable = session.isReachable
        Task { @MainActor in self.activated(snapshot: snapshot, reachable: reachable) }
        // The complications' latest data waits there too.
        if let face = WatchMessage.decode(WatchFaceData.self, from: session.receivedApplicationContext, key: WatchMessage.faceData) {
            Task { @MainActor in WatchComplications.store(face) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.phoneReachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }

    /// Decodes into Sendable values here, then hops to the main actor.
    nonisolated private func receive(_ payload: [String: Any]) {
        if let snapshot = WatchMessage.decode(WatchSession.self, from: payload, key: WatchMessage.snapshot) {
            Task { @MainActor in self.apply(snapshot) }
        }
        if let request = WatchMessage.decode(WatchRequest.self, from: payload, key: WatchMessage.request) {
            Task { @MainActor in self.handle(request) }
        }
        // Complication data: by message, context, or `transferCurrentComplicationUserInfo` (arrives as user info).
        if let face = WatchMessage.decode(WatchFaceData.self, from: payload, key: WatchMessage.faceData) {
            Task { @MainActor in WatchComplications.store(face) }
        }
    }
}
