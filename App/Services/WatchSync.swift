import Foundation
import HealthKit
import SwiftData
import SwiftUI
import WatchConnectivity
import AppCore

/// The iPhone side of the Apple Watch app. Sends the live session to the
/// wrist (`WatchSession`), applies the Watch's commands to the SwiftData
/// session, and takes the Watch's workout summary so a workout is recorded
/// once: when the Watch records heart rate and calories, its HKWorkout is the
/// record and the phone doesn't save one of its own.
@Observable
final class WatchSync: NSObject {
    static let shared = WatchSync()

    /// The session id the Watch is running an HKWorkoutSession for.
    private(set) var recordingSessionID: String?
    /// Sessions finished on the phone whose Watch recording hasn't confirmed it
    /// stopped yet: the stop is sent again whenever the Watch reconnects.
    private var pendingStops: Set<String> = []
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var isReachable = false
    /// Why "Start on Watch" failed, for the workout screen.
    var startProblem: String?

    @ObservationIgnored private var connection: WCSession?
    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var gym: GymStore?
    @ObservationIgnored private var launcher: WorkoutLauncher?
    @ObservationIgnored private var health: HealthKitClient?
    @ObservationIgnored private var lastSnapshot: WatchSession?
    /// The complications' data as last sent, and when.
    @ObservationIgnored private var lastFace: WatchFaceData?
    @ObservationIgnored private var lastFaceSentAt = Date.distantPast

    /// Called once from the root view, so commands can reach the database.
    func configure(context: ModelContext, gym: GymStore, launcher: WorkoutLauncher, health: HealthKitClient?) {
        self.context = context
        self.gym = gym
        self.launcher = launcher
        self.health = health
        guard connection == nil, WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        connection = session
    }

    /// A paired Watch with Tensile installed: starting it can happen without asking.
    var canStartAutomatically: Bool { isPaired && isWatchAppInstalled }

    /// True when the Watch's workout is (or will be) the Health record for this session.
    func watchOwnsWorkout(_ session: WorkoutSession) -> Bool {
        session.watchWorkoutUUID != nil || recordingSessionID == WatchSession.id(for: session.startedAt)
    }

    // MARK: Phone → Watch

    /// Sends the session to the Watch if anything changed. Cheap to call often.
    func update(from session: WorkoutSession) {
        let snapshot = makeSnapshot(session, finished: !session.isActive)
        send(snapshot)
    }

    /// The user finished on the phone: the Watch ends its recording (its summary comes back
    /// through `apply(_ summary:)`) and clears the session from its start screen.
    func sessionFinished(_ session: WorkoutSession) {
        let id = WatchSession.id(for: session.startedAt)
        pendingStops.insert(id)
        sendRequest(WatchRequest(kind: .stopRecording, sessionID: id, sentAt: .now))
        send(makeSnapshot(session, finished: true))
    }

    /// The user discarded the workout on the phone: the Watch drops its recording too.
    func sessionDiscarded(_ session: WorkoutSession) {
        let id = WatchSession.id(for: session.startedAt)
        sendRequest(WatchRequest(kind: .discardRecording, sessionID: id, sentAt: .now))
        if recordingSessionID == id { recordingSessionID = nil }
        send(makeSnapshot(session, finished: true))
    }

    /// Opens the Watch app and starts its HKWorkoutSession for this session, so heart
    /// rate and calories are recorded on the wrist (once). The phone's own AirPods
    /// recorder can keep running; it just won't save a second workout.
    func startOnWatch(_ session: WorkoutSession) async {
        startProblem = nil
        guard let health else {
            startProblem = "Apple Health isn't available."
            return
        }
        guard let connection, connection.isPaired else {
            startProblem = "No Apple Watch is paired with this iPhone."
            return
        }
        guard connection.isWatchAppInstalled else {
            startProblem = "Install Tensile on your Watch first (Watch app → Available Apps)."
            return
        }
        send(makeSnapshot(session, finished: false), force: true)
        let id = WatchSession.id(for: session.startedAt)
        sendRequest(WatchRequest(kind: .startRecording, sessionID: id, sentAt: .now))
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let store = health.store
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                store.startWatchApp(with: configuration) { started, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if !started {
                        continuation.resume(throwing: WatchSyncError.notStarted)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            startProblem = "Couldn't start the Watch app: \(error.localizedDescription)"
        }
    }

    private func send(_ snapshot: WatchSession, force: Bool = false) {
        var previous = lastSnapshot
        previous?.sentAt = snapshot.sentAt
        guard force || previous != snapshot else { return }
        lastSnapshot = snapshot
        guard let data = WatchMessage.encode(snapshot) else { return }
        deliver(key: WatchMessage.snapshot, data: data, queued: false)
        // The latest state also waits for the Watch app if it isn't running.
        updateContext(key: WatchMessage.snapshot, data: data)
    }

    /// The application context is one dictionary: replaces one key and keeps
    /// the others (the session snapshot and the complications' data).
    private func updateContext(key: String, data: Data) {
        guard let connection, connection.activationState == .activated else { return }
        var context = connection.applicationContext
        context[key] = data
        try? connection.updateApplicationContext(context)
    }

    private func sendRequest(_ request: WatchRequest) {
        guard let data = WatchMessage.encode(request) else { return }
        deliver(key: WatchMessage.request, data: data, queued: true)
    }

    /// Immediate when the Watch is reachable; `queued` ones are kept until it is.
    private func deliver(key: String, data: Data, queued: Bool) {
        guard let connection, connection.activationState == .activated else { return }
        if connection.isReachable {
            connection.sendMessage([key: data], replyHandler: nil) { _ in
                if queued { WCSession.default.transferUserInfo([key: data]) }
            }
        } else if queued {
            connection.transferUserInfo([key: data])
        }
    }

    // MARK: Complications

    /// Sends today's recovery, strain and planned sessions to the Watch's
    /// complications. Called after every metrics refresh; sends only when
    /// something on the face changed, or every 30 minutes.
    /// Sessions from the last 8 days, for this week's flexible-plan progress on the face.
    private func recentSessions(now: Date = .now) -> [WorkoutSession] {
        guard let context else { return [] }
        let since = now.addingTimeInterval(-8 * 86_400)
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.startedAt >= since })
        return (try? context.fetch(descriptor)) ?? []
    }

    func updateFace(metrics: DailyMetricsModel, plans: WeeklyPlanStore, lastWorkoutEnd: Date?, now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let horizon = today.addingTimeInterval(8 * 86_400)
        // From the start of today, so today's session stays on the face (done or not).
        let slots = plans.upcomingSlots(now: today, trainingDays: WeeklyPlanStore.trainingDays(sessions: recentSessions(), extra: metrics.recentTrainingDays))
            .filter { $0.start < horizon }
            .map { slot in
                WatchFaceData.Slot(start: slot.start, title: slot.day.focus.title,
                                   shortTitle: slot.day.focus.shortTitle, symbol: Self.symbol(for: slot.day.focus))
            }
        let target = metrics.targetStrain
        updateFace(WatchFaceData(
            recovery: metrics.recovery?.score,
            band: metrics.recovery?.status.rawValue,
            calibrating: metrics.recovery.map { !$0.isCalibrated } ?? false,
            strain: metrics.strain?.strain,
            targetLower: target?.lowerBound,
            targetUpper: target?.upperBound,
            easyDay: metrics.trainEasyToday,
            slots: slots,
            lastWorkoutEnd: lastWorkoutEnd,
            updated: now
        ))
    }

    func updateFace(_ data: WatchFaceData) {
        guard let connection, connection.activationState == .activated,
              connection.isPaired, connection.isWatchAppInstalled else { return }
        let changed = lastFace.map { !data.looksSame(as: $0) } ?? true
        guard changed || data.updated.timeIntervalSince(lastFaceSentAt) >= 30 * 60 else { return }
        guard let encoded = WatchMessage.encode(data) else { return }
        lastFace = data
        lastFaceSentAt = data.updated
        // A change wakes the Watch app in the background while a Tensile
        // complication is on the face (about 50 of these a day).
        if changed, connection.isComplicationEnabled, connection.remainingComplicationUserInfoTransfers > 3 {
            connection.transferCurrentComplicationUserInfo([WatchMessage.faceData: encoded])
        }
        // The latest data also waits in the context for the next time the Watch app runs.
        updateContext(key: WatchMessage.faceData, data: encoded)
    }

    /// SF Symbol for a planned session's focus.
    private static func symbol(for focus: WorkoutFocus) -> String {
        switch focus {
        case .legs, .lower: "figure.strengthtraining.functional"
        case .fullBody: "figure.strengthtraining.traditional"
        case .push, .pull, .upper: "dumbbell.fill"
        }
    }

    // MARK: Snapshot

    private func makeSnapshot(_ session: WorkoutSession, finished: Bool) -> WatchSession {
        let profile = gym?.profile ?? .commercialKilograms
        let groups = SupersetRegistry.groups(for: session.startedAt)
        let ordered = session.orderedExercises
        var current: (exercise: Int, set: Int)?
        var exercises: [WatchSession.ExerciseSnapshot] = []
        for (index, exercise) in ordered.enumerated() {
            let sets = exercise.orderedSets
            if current == nil, let setIndex = sets.firstIndex(where: { !$0.isCompleted }) {
                current = (index, setIndex)
            }
            let planned = sets.first { !$0.isCompleted }?.weightKg ?? sets.last?.weightKg ?? 0
            exercises.append(WatchSession.ExerciseSnapshot(
                id: exercise.order,
                name: exercise.name,
                supersetLabel: SupersetRegistry.label(order: exercise.order, groups: groups),
                sets: sets.map { set in
                    WatchSession.SetSnapshot(reps: set.reps, weightKg: set.weightKg, isCompleted: set.isCompleted,
                                             isWarmup: set.isWarmup, rpe: set.rpe)
                },
                achievableLoadsKg: loads(for: exercise.exerciseID, around: planned, profile: profile)
            ))
        }
        let restSeconds: Int
        if let current {
            restSeconds = RestPreferences.resolved(for: ordered[current.exercise].exerciseID, style: gym?.style ?? .balanced)
        } else {
            restSeconds = RestPreferences.global > 0 ? RestPreferences.global : 90
        }
        var snapshot = WatchSession(
            id: WatchSession.id(for: session.startedAt),
            startedAt: session.startedAt,
            name: session.name,
            exercises: exercises,
            currentExercise: current?.exercise,
            currentSet: current?.set,
            restSeconds: restSeconds,
            restEndsAt: finished ? nil : RestTimerStore.endsAt,
            unit: profile.unit.rawValue,
            isFinished: finished,
            sentAt: .now,
            weightStepKg: profile.unit == .kg ? 2.5 : profile.unit.toKilograms(5)
        )
        // Movement warm-up (`WarmUpStore`): the steps, which one is up, whether
        // it has started, and when the timed step ends.
        if !finished, let warmUp = WarmUpStore.shared.entry(for: session.startedAt) {
            snapshot.warmUp = warmUp.routine.steps.map {
                WatchWarmUpStep(name: $0.name, dose: $0.dose.text, cue: $0.cue, why: $0.why, seconds: $0.dose.seconds)
            }
            snapshot.warmUpStepIndex = warmUp.isDone ? warmUp.routine.steps.count : warmUp.stepIndex
            snapshot.warmUpStepEndsAt = warmUp.stepEndsAt
            snapshot.warmUpStarted = warmUp.hasStarted
            snapshot.warmUpMinutes = warmUp.routine.minutes
        }
        return snapshot
    }

    /// Up to 20 loads either side of the planned weight that the gym can make, in kg.
    private func loads(for exerciseID: String, around weightKg: Double, profile: GymProfile) -> [Double]? {
        guard let kind = ExerciseCatalog.exercise(id: exerciseID)?.load, profile.has(kind) else { return nil }
        let all = profile.achievableLoads(for: kind)
        guard !all.isEmpty else { return nil }
        let target = profile.unit.fromKilograms(weightKg)
        let position = all.firstIndex { $0 >= target - 0.001 } ?? all.count
        let window = all[max(0, position - 20)..<min(all.count, position + 20)]
        return window.map { profile.unit.toKilograms($0) }
    }

    /// The next set, for the Live Activity ("Bench Press", "Set 3 of 4 · 135 lb × 8").
    private func nextSetText(_ session: WorkoutSession) -> (exercise: String, detail: String) {
        let unit = gym?.profile.unit ?? .kg
        for exercise in session.orderedExercises {
            let sets = exercise.orderedSets
            guard let index = sets.firstIndex(where: { !$0.isCompleted }) else { continue }
            let set = sets[index]
            let same = sets.filter { $0.isWarmup == set.isWarmup }
            let number = (same.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0) + 1
            var detail = "\(set.isWarmup ? "Warm-up" : "Set") \(number) of \(same.count)"
            if set.weightKg > 0 || set.reps > 0 {
                let weight = unit.fromKilograms(set.weightKg).formatted(.number.precision(.fractionLength(0...1)))
                detail += " · \(weight) \(unit.rawValue) × \(set.reps)"
            }
            return (exercise.name, detail)
        }
        return ("All sets done", "Tap Finish when you're ready")
    }

    // MARK: Watch → Phone

    private func apply(_ message: WatchCommandMessage) {
        guard let context else { return }
        switch message.command {
        case .recordingStarted:
            recordingSessionID = message.sessionID ?? activeSession(matching: nil).map { WatchSession.id(for: $0.startedAt) }
            return
        case .recordingStopped:
            if recordingSessionID == message.sessionID || message.sessionID == nil { recordingSessionID = nil }
            if let id = message.sessionID { pendingStops.remove(id) } else { pendingStops.removeAll() }
            return
        default:
            break
        }
        guard let session = activeSession(matching: message.sessionID) else { return }
        switch message.command {
        case let .completeSet(exerciseIndex, setIndex, reps, weightKg, rpe):
            let exercises = session.orderedExercises
            guard exerciseIndex < exercises.count else { return }
            let exercise = exercises[exerciseIndex]
            let sets = exercise.orderedSets
            guard setIndex < sets.count else { return }
            let set = sets[setIndex]
            if reps > 0 { set.reps = reps }
            if weightKg > 0 { set.weightKg = weightKg }
            if let rpe { set.rpe = rpe }
            // Idempotent: a command delivered twice (queued, then live) ticks the set once.
            guard !set.isCompleted else { return }
            set.completedAt = .now
            try? context.save()
            if set.isWarmup {
                // Short rest after a ramp set, as on the phone (`RestTimer.warmUpRestSeconds`).
                RestTimerStore.start(seconds: Double(RestTimer.warmUpRestSeconds))
                Task { await WorkoutLiveActivity.refresh() }
            } else {
                startRest(after: exercise, in: session)
            }
        case .skipRest:
            RestTimerStore.stop()
            Task { await WorkoutLiveActivity.refresh() }
        case .nextExercise:
            // Drops the current exercise's untouched sets (the finish sheet would drop them anyway).
            guard let exercise = session.orderedExercises.first(where: { $0.sets.contains { !$0.isCompleted } }) else { return }
            for set in exercise.sets where !set.isCompleted {
                context.delete(set)
            }
            try? context.save()
            let next = nextSetText(session)
            Task { await WorkoutLiveActivity.refresh(exercise: next.exercise, detail: next.detail) }
        case .pause, .resume:
            // The Watch pauses its own HKWorkoutSession; the phone's log has no pause.
            break
        case let .warmUpNext(fromStep):
            WarmUpStore.shared.advance(for: session.startedAt, fromStep: fromStep)
        case .warmUpBack:
            WarmUpStore.shared.back(for: session.startedAt)
        case .warmUpFinish:
            WarmUpStore.shared.finish(for: session.startedAt)
        case let .finish(sessionRPE):
            if let sessionRPE { session.sessionRPE = max(1, min(10, sessionRPE)) }
            try? context.save()
            if let launcher {
                if launcher.activeSession?.persistentModelID != session.persistentModelID {
                    launcher.activeSession = session
                }
                launcher.pendingFinish = true
            }
        case .recordingStarted, .recordingStopped:
            break
        }
        update(from: session)
    }

    /// Rest after a set, the way the workout screen starts it: none between the
    /// two halves of a superset (`Supersets`), else the exercise's rest preference.
    private func startRest(after exercise: ExerciseLog, in session: WorkoutSession) {
        let groups = SupersetRegistry.groups(for: session.startedAt)
        if let mateOrder = SupersetRegistry.partner(of: exercise.order, groups: groups), mateOrder > exercise.order,
           let mate = session.exercises.first(where: { $0.order == mateOrder }),
           mate.sets.contains(where: { !$0.isCompleted }) {
            let next = nextSetText(session)
            Task { await WorkoutLiveActivity.refresh(exercise: next.exercise, detail: next.detail) }
            return
        }
        let seconds = RestPreferences.resolved(for: exercise.exerciseID, style: gym?.style ?? .balanced)
        RestTimerStore.start(seconds: Double(seconds))
        let next = nextSetText(session)
        Task { await WorkoutLiveActivity.refresh(exercise: next.exercise, detail: next.detail) }
    }

    /// Stores the Watch's workout on the session it belongs to. With no matching
    /// session (the Watch was started on its own), one is created so the workout
    /// still counts.
    private func apply(_ summary: WatchWorkoutSummary) {
        guard let context else { return }
        if recordingSessionID == summary.sessionID || summary.sessionID == nil { recordingSessionID = nil }
        if let id = summary.sessionID { pendingStops.remove(id) } else { pendingStops.removeAll() }
        let session: WorkoutSession
        if let found = matchingSession(for: summary) {
            session = found
        } else {
            // No session to join and no Health workout (the Watch's save failed):
            // nothing to record, and an empty session would never be swept.
            guard summary.workoutUUID != nil else { return }
            session = WorkoutSession(name: "Watch workout, \(summary.minutes) min", startedAt: summary.start)
            session.endedAt = summary.end
            context.insert(session)
        }
        // A failed save mustn't erase an earlier recording's id.
        if let id = summary.workoutUUID {
            session.watchWorkoutUUID = id
            session.savedToHealth = true
        }
        if session.sessionRPE == nil, let rpe = summary.sessionRPE { session.sessionRPE = max(1, min(10, rpe)) }
        try? context.save()
        // A session already finished on the phone skipped its effort score while the Watch
        // was still recording; write it now, over the session's time (`HealthKitClient+Writes`).
        if let end = session.endedAt, let rpe = session.sessionRPE, summary.workoutUUID != nil, let health {
            let start = session.startedAt
            Task { try? await health.saveWorkoutEffort(score: rpe, start: start, end: end) }
        }
        if session.isActive { update(from: session) }
    }

    private func matchingSession(for summary: WatchWorkoutSummary) -> WorkoutSession? {
        guard let context else { return nil }
        let all = (try? context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? []
        let recording = DateInterval(start: summary.start, end: max(summary.start, summary.end))
        func interval(_ session: WorkoutSession) -> DateInterval {
            DateInterval(start: session.startedAt, end: max(session.startedAt, session.endedAt ?? .now))
        }
        // The id names the session, as long as it's open or shares time with the
        // recording (a stale id from an older workout mustn't claim it).
        if let id = summary.sessionID, let match = all.first(where: { WatchSession.id(for: $0.startedAt) == id }),
           match.isActive || recording.intersects(interval(match)) {
            return match
        }
        // Ids that don't agree, or none: the session sharing the most time with the
        // recording (`WorkoutLinking.sessionIndex`), so a Watch left running after
        // the phone finished joins its session instead of becoming a second workout.
        let nearby = all.filter { $0.startedAt > summary.start.addingTimeInterval(-86_400) && $0.startedAt < summary.end }
        if let index = WorkoutLinking.sessionIndex(for: recording, sessions: nearby.map(interval)) {
            return nearby[index]
        }
        // Started on the Watch while a phone session was open: it's that session's workout.
        return all.first { $0.isActive && $0.startedAt < summary.end }
    }

    private func activeSession(matching id: String?) -> WorkoutSession? {
        guard let context else { return nil }
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let active = (try? context.fetch(descriptor)) ?? []
        guard let id else { return active.first }
        return active.first { WatchSession.id(for: $0.startedAt) == id }
    }

    private func refreshState() {
        guard let connection else { return }
        isPaired = connection.isPaired
        isWatchAppInstalled = connection.isWatchAppInstalled
        isReachable = connection.isReachable
        // A freshly reachable Watch gets the latest state straight away.
        if isReachable, let lastSnapshot, let data = WatchMessage.encode(lastSnapshot) {
            connection.sendMessage([WatchMessage.snapshot: data], replyHandler: nil, errorHandler: nil)
        }
        // A stop that may have been missed goes again until the Watch confirms it.
        if isReachable {
            for id in pendingStops {
                sendRequest(WatchRequest(kind: .stopRecording, sessionID: id, sentAt: .now))
            }
        }
    }
}

nonisolated enum WatchSyncError: LocalizedError {
    case notStarted

    var errorDescription: String? {
        "The Watch app didn't open. Open Tensile on your Watch and try again."
    }
}

// MARK: - WCSessionDelegate (called off the main thread)

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched to another Watch: activate again for the new one.
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }

    /// Decodes into Sendable values here, then hops to the main actor.
    nonisolated private func receive(_ payload: [String: Any]) {
        if let command = WatchMessage.decode(WatchCommandMessage.self, from: payload, key: WatchMessage.command) {
            Task { @MainActor in self.apply(command) }
        }
        if let summary = WatchMessage.decode(WatchWorkoutSummary.self, from: payload, key: WatchMessage.summary) {
            Task { @MainActor in self.apply(summary) }
        }
    }
}

/// Wires `WatchSync` to the database and stores once the root view is up.
struct WatchSyncBootstrap: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(GymStore.self) private var gym
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(\.healthClient) private var health

    func body(content: Content) -> some View {
        content.task {
            WatchSync.shared.configure(context: modelContext, gym: gym, launcher: launcher, health: health)
        }
    }
}
