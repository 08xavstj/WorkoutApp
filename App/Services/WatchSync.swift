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
    /// The training block, for its week's target reps in reserve when the
    /// session has no planned effort (`LiveSetCoach.targetRIR`), as on the phone.
    @ObservationIgnored private var plans: WeeklyPlanStore?
    /// Records from the last exercise finished on the wrist, and when; sent in
    /// snapshots for `recordNoteSeconds` so the Watch can show them once.
    @ObservationIgnored private var watchRecords: (note: WatchRecordNote, at: Date)?
    /// How long a record note rides along in snapshots (app choice: long enough
    /// to reach a Watch that briefly dropped off; the Watch dedupes by id).
    private static let recordNoteSeconds: TimeInterval = 60
    @ObservationIgnored private var lastSnapshot: WatchSession?
    /// The complications' data as last sent, and when.
    @ObservationIgnored private var lastFace: WatchFaceData?
    @ObservationIgnored private var lastFaceSentAt = Date.distantPast

    /// Called once from the root view, so commands can reach the database.
    func configure(context: ModelContext, gym: GymStore, launcher: WorkoutLauncher, health: HealthKitClient?,
                   plans: WeeklyPlanStore? = nil) {
        self.context = context
        self.gym = gym
        self.launcher = launcher
        self.health = health
        if let plans { self.plans = plans }
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
        var exercises: [WatchSession.ExerciseSnapshot] = []
        let repCounting = UserDefaults.standard.bool(forKey: "watchRepCounting")
        let blockRIR = plans?.blockWeek?.targetRIR
        for exercise in ordered {
            let sets = exercise.orderedSets
            let planned = sets.first { !$0.isCompleted }?.weightKg ?? sets.last?.weightKg ?? 0
            // Each set with last time's matching set, the plan's target and any
            // set-by-set load change (`LiveSetCoach.watchSets`, in `orderedSets` order).
            var watchSets = LiveSetCoach.watchSets(for: exercise, sessionStart: session.startedAt, context: context)
            for index in watchSets.indices where index < sets.count {
                // Stable id, so a queued command finds this set after adds or deletes.
                watchSets[index].order = sets[index].order
                // No planned effort: the block week's reps in reserve, as the phone shows it.
                if watchSets[index].targetRIR == nil, !watchSets[index].isWarmup, !watchSets[index].isStage,
                   let rir = LiveSetCoach.targetRIR(sessionStart: session.startedAt, order: exercise.order, blockRIR: blockRIR) {
                    watchSets[index].targetRIR = rir
                }
            }
            exercises.append(WatchSession.ExerciseSnapshot(
                id: exercise.order,
                name: exercise.name,
                supersetLabel: SupersetRegistry.label(order: exercise.order, groups: groups),
                sets: watchSets,
                achievableLoadsKg: loads(for: exercise.exerciseID, around: planned, profile: profile),
                repCounting: repCounting && RepDetection.supports(exerciseID: exercise.exerciseID)
            ))
        }
        var snapshot = WatchSession(
            id: WatchSession.id(for: session.startedAt),
            startedAt: session.startedAt,
            name: session.name,
            exercises: exercises,
            currentExercise: nil,
            currentSet: nil,
            restSeconds: 0,
            restEndsAt: finished ? nil : RestTimerStore.endsAt,
            unit: profile.unit.rawValue,
            isFinished: finished,
            sentAt: .now,
            weightStepKg: profile.unit == .kg ? 2.5 : profile.unit.toKilograms(5)
        )
        // The next set, with the superset partner up once the first half is a
        // round ahead (no rest between the halves, as `startRest` does).
        if let current = snapshot.upNext() {
            snapshot.currentExercise = current.exercise
            snapshot.currentSet = current.set
            let up = ordered[current.exercise]
            snapshot.restSeconds = RestPreferences.resolved(for: up.exerciseID, style: gym?.style ?? .balanced,
                                                            sessionStart: session.startedAt, order: up.order)
        } else {
            snapshot.restSeconds = RestPreferences.global > 0 ? RestPreferences.global : 90
        }
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
        if !finished, let watchRecords, watchRecords.note.id.hasPrefix(snapshot.id + "-"),
           Date.now.timeIntervalSince(watchRecords.at) < Self.recordNoteSeconds {
            snapshot.records = watchRecords.note
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
            // "Set 2 of 3", "Warm-up 1 of 3", "Drop 1 of 2" (`SetStructure`).
            var detail = LiveSetCoach.title(for: set, in: sets)
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
        case let .completeSet(exerciseIndex, setIndex, reps, weightKg, rpe, exerciseOrder, setOrder, repsEdited, weightEdited):
            guard let (exercise, set) = Self.target(in: session, exerciseIndex: exerciseIndex, setIndex: setIndex,
                                                    exerciseOrder: exerciseOrder, setOrder: setOrder) else { return }
            // Idempotent: a command delivered twice (queued, then live) ticks the set once,
            // and never rewrites a set that's already logged.
            guard !set.isCompleted else { return }
            // Only what the wrist changed: an untouched value may be stale (edited on the
            // phone since the Watch's snapshot). Older Watches send no flags: as before,
            // anything above zero. An explicit 0 reps (a failed set) is kept.
            if repsEdited ?? (reps > 0) { set.reps = max(0, reps) }
            if weightEdited ?? (weightKg > 0) { set.weightKg = max(0, weightKg) }
            if let rpe { set.rpe = rpe }
            set.completedAt = .now
            try? context.save()
            if !set.isWarmup, let profile = gym?.profile {
                LiveSetCoach.autoregulate(after: set, in: exercise, sessionStart: session.startedAt, gym: profile,
                                          blockRIR: plans?.blockWeek?.targetRIR)
                try? context.save()
            }
            noteRecords(for: exercise, in: session)
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
            // From older Watches. Nothing is deleted: it used to drop the first open
            // exercise's sets, which wasn't always the one on the wrist. The Watch
            // moves on by itself, and the finish sheet drops unticked sets.
            break
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

    /// The exercise and set a Watch command means: by stable id (`ExerciseLog.order`,
    /// `SetLog.order`) when the Watch sent them, so a command queued while sets were
    /// added or removed on the phone still ticks the right one; by position from
    /// older Watches. An id that no longer exists (deleted) matches nothing.
    private static func target(in session: WorkoutSession, exerciseIndex: Int, setIndex: Int,
                               exerciseOrder: Int?, setOrder: Int?) -> (ExerciseLog, SetLog)? {
        let exercises = session.orderedExercises
        let exercise: ExerciseLog
        if let exerciseOrder {
            // Orders can repeat after a delete and an add: prefer the one at the sent position.
            if exerciseIndex < exercises.count, exercises[exerciseIndex].order == exerciseOrder {
                exercise = exercises[exerciseIndex]
            } else if let found = exercises.first(where: { $0.order == exerciseOrder }) {
                exercise = found
            } else {
                return nil
            }
        } else {
            guard exerciseIndex < exercises.count else { return nil }
            exercise = exercises[exerciseIndex]
        }
        let sets = exercise.orderedSets
        if let setOrder {
            if setIndex < sets.count, sets[setIndex].order == setOrder { return (exercise, sets[setIndex]) }
            guard let found = sets.first(where: { $0.order == setOrder }) else { return nil }
            return (exercise, found)
        }
        guard setIndex < sets.count else { return nil }
        return (exercise, sets[setIndex])
    }

    /// Once a Watch tick finishes an exercise: its e1RM, rep and volume records
    /// (`LiveSetCoach.records`), as short lines for the Watch to show with a tap.
    private func noteRecords(for exercise: ExerciseLog, in session: WorkoutSession) {
        guard let context, !exercise.sets.isEmpty, exercise.sets.allSatisfy(\.isCompleted) else { return }
        let id = "\(WatchSession.id(for: session.startedAt))-\(exercise.order)"
        guard watchRecords?.note.id != id else { return }
        let start = session.startedAt
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.startedAt < start })
        let earlier = (try? context.fetch(descriptor)) ?? []
        let unit = gym?.liftingUnit ?? .kilograms
        let records = LiveSetCoach.records(for: exercise, sessionStart: start, sessions: earlier, unit: unit)
        guard !records.isEmpty else { return }
        let note = WatchRecordNote(id: id, exercise: exercise.name, lines: records.map { $0.message(unit: unit.rawValue) })
        watchRecords = (note, .now)
    }

    /// Rest after a set, the way the workout screen starts it: the stage's
    /// short rest (none for a drop) when a drop stage or mini-set is next
    /// (`SetKind`), none between the two halves of a superset (`Supersets`),
    /// else the exercise's rest preference.
    private func startRest(after exercise: ExerciseLog, in session: WorkoutSession) {
        if let seconds = LiveSetCoach.stageRest(before: exercise) {
            if seconds > 0 {
                RestTimerStore.start(seconds: Double(seconds))
            } else {
                RestTimerStore.stop()
            }
            let next = nextSetText(session)
            Task { await WorkoutLiveActivity.refresh(exercise: next.exercise, detail: next.detail) }
            return
        }
        let groups = SupersetRegistry.groups(for: session.startedAt)
        if let mateOrder = SupersetRegistry.partner(of: exercise.order, groups: groups), mateOrder > exercise.order,
           let mate = session.exercises.first(where: { $0.order == mateOrder }),
           mate.sets.contains(where: { !$0.isCompleted }) {
            let next = nextSetText(session)
            Task { await WorkoutLiveActivity.refresh(exercise: next.exercise, detail: next.detail) }
            return
        }
        let seconds = RestPreferences.resolved(for: exercise.exerciseID, style: gym?.style ?? .balanced,
                                               sessionStart: session.startedAt, order: exercise.order)
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
    @Environment(WeeklyPlanStore.self) private var plans

    func body(content: Content) -> some View {
        content.task {
            WatchSync.shared.configure(context: modelContext, gym: gym, launcher: launcher, health: health, plans: plans)
        }
    }
}
