import Foundation
import HealthKit
import SwiftUI
import WatchConnectivity
import WatchKit

/// The Watch's view of a lifting session: runs the HKWorkoutSession that
/// records heart rate and calories (once, on the wrist), mirrors the phone's
/// session (`WatchSession`), and sends what you do back as `WatchCommand`s.
/// Works with the phone out of reach: commands queue, and the workout is
/// saved and summarised to the phone whenever it next connects.
///
/// It can also run a session of its own (`isLocal`): a plan the phone sent
/// ahead, or a quick lift from the exercise library. Then nothing is sent
/// while it runs; sets are kept in a file after each one (so a crash keeps
/// the log) and go to the phone with the summary (`loggedExercises`).
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
    /// When the pause now running began; nil while the workout runs.
    private(set) var pausedAt: Date?
    /// Seconds of pauses already ended in this workout.
    private(set) var pausedSeconds: TimeInterval = 0
    /// Sets ticked on the wrist this workout (the end screen when the phone is away).
    private(set) var setsCompletedHere = 0
    /// The exercise on the live page; nil follows the next set to do.
    var selectedExercise: Int?
    /// The "Start lifting" control asked for lifting (`StartLiftingIntent`): Home
    /// opens the session preview, or Quick lift.
    var liftRequested = false
    /// Records from the exercise just finished here, shown for a few seconds.
    private(set) var recordNote: WatchRecordNote?
    /// A working set just ticked here, waiting for "Reps left?" (asked after the
    /// tick, so the rest starts at once and the question can be skipped).
    private(set) var pendingRating: PendingSet?
    /// Reps and weight changed on the wrist before Done, by set key
    /// (`WatchSession.setKey`), so they survive moving between pages.
    var setEdits: [String: SetEdit] = [:]
    /// The live heart-rate zone and time in each zone, for the Heart page: the
    /// same zones and counting rules as cardio and the phone (`CardioZoneTracker`).
    private(set) var tracker = CardioZoneTracker(scheme: .ageEstimate(age: WatchZoneStore.standInAge))
    /// Heart rate over the workout, for the Heart page's sparkline and the summary chart.
    private(set) var heartSeries = HeartRateSeries()
    /// Counts sets logged here; the pager moves to the Rest page when it changes.
    private(set) var logCount = 0
    /// The set just logged, for the "Set 3 logged" tick-over and Undo.
    private(set) var lastLogged: LoggedSet?
    /// Until when Undo is offered for the last set (nil: not now).
    private(set) var undoUntil: Date?
    /// When the last rest ran out on its own: the Rest page shows "Go".
    private(set) var restEndedAt: Date?
    /// When the rest now running began (the ring's start).
    private(set) var restStartedAt = Date.distantPast
    /// Record lines shown during this workout, for the summary.
    private(set) var recordLines: [String] = []
    /// The Heart page's note on wrist accuracy has been shown this workout.
    var heartCaptionSeen = false
    /// The session as it stood when the workout ended (the phone's finished
    /// snapshot, or the Watch's own), for the summary's sets.
    private(set) var finishedSession: WatchSession?
    /// The session running is the Watch's own (a plan sent ahead or a quick
    /// lift): no commands go to the phone; its log goes with the summary.
    private(set) var isLocal = false
    /// Today's planned session as the phone sent it ahead (`WatchMessage.plan`).
    private(set) var plannedSession: WatchSession?
    /// Recent exercises for Quick lift (`WatchMessage.library`).
    private(set) var library: WatchExerciseLibrary?
    /// The plan (by id) already run here today, so Home stops offering it.
    private(set) var planDoneID: String? = UserDefaults.standard.string(forKey: WatchWorkoutModel.planDoneKey)
    private static let planDoneKey = "watchPlanDone"
    /// Record notes already shown (each rides along in a minute of snapshots).
    @ObservationIgnored private var shownRecordIDs: Set<String> = []
    @ObservationIgnored private var recordTask: Task<Void, Never>?
    /// How long the record banner stays up (app choice: long enough to read two short lines).
    private static let recordSeconds = 6.0

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var workoutSession: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    /// When Pause or Resume was last tapped here (`sessionChanged` ignores older callbacks).
    @ObservationIgnored private var lastLocalPauseChange: Date?
    @ObservationIgnored private var connection: WCSession?
    /// Snapshots older than the last set ticked here are ignored, so a stale
    /// one can't un-tick it before the phone has applied the command.
    @ObservationIgnored private var lastLocalEdit = Date.distantPast
    @ObservationIgnored private var restTask: Task<Void, Never>?
    /// A logged set held back for the undo window, with what came after it.
    @ObservationIgnored private var held: HeldSet?
    @ObservationIgnored private var heldTask: Task<Void, Never>?
    @ObservationIgnored private var ratingTask: Task<Void, Never>?
    /// A stop that arrived while the recording was still starting: applied once
    /// it runs, instead of being acknowledged and lost.
    @ObservationIgnored private var stopRequestedWhileStarting: String?

    var isRecording: Bool { phase == .running || phase == .paused }

    func activate() {
        guard connection == nil, WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        connection = session
    }

    // MARK: The Watch's own sessions

    /// Starts today's plan on the Watch alone: the plan becomes the session,
    /// logged here and sent to the phone with the summary.
    func startPlanned(_ plan: WatchSession) async {
        guard phase == .idle || phase == .ended, !WatchCardioModel.shared.isBusy else { return }
        await startLocal(Self.localSession(from: plan, name: plan.name))
    }

    /// Quick lift: the chosen exercises from the library, logged here.
    func startQuickLift(_ exercises: [WatchSession.ExerciseSnapshot]) async {
        guard phase == .idle || phase == .ended, !WatchCardioModel.shared.isBusy, let library, !exercises.isEmpty else { return }
        let session = WatchSession(
            id: "", startedAt: .now, name: "Watch workout", exercises: exercises,
            currentExercise: nil, currentSet: nil,
            restSeconds: exercises.first?.restSeconds ?? RestCues.standaloneRestSeconds, restEndsAt: nil,
            unit: library.unit, isFinished: false, sentAt: .now, weightStepKg: library.weightStepKg
        )
        await startLocal(Self.localSession(from: session, name: session.name))
    }

    /// Adds an exercise from the library to the Watch's own session (Exercises page).
    func addExercise(_ exercise: WatchSession.ExerciseSnapshot) {
        guard isLocal, var current = snapshot else { return }
        var added = exercise
        added.id = (current.exercises.map(\.id).max() ?? -1) + 1
        added.supersetLabel = nil
        current.exercises.append(added)
        if let next = current.upNext() {
            current.currentExercise = next.exercise
            current.currentSet = next.set
        }
        snapshot = current
        selectedExercise = current.exercises.count - 1
        LocalLiftLog.save(current)
    }

    /// Whether `plan` is today's and not yet run here.
    func offersPlan(_ plan: WatchSession, at now: Date = .now) -> Bool {
        guard let plannedFor = plan.plannedFor else { return false }
        return Calendar.current.isDate(plannedFor, inSameDayAs: now) && planDoneID != plan.id
    }

    private func startLocal(_ session: WatchSession) async {
        snapshot = session
        isLocal = true
        selectedExercise = nil
        LocalLiftLog.save(session)
        await start(sessionID: nil)
        // Didn't start (Health refused, or another workout began): not a session after all.
        if !isRecording {
            snapshot = nil
            isLocal = false
            LocalLiftLog.clear()
        }
    }

    /// A plan or a pick from the library, as a session of the Watch's own:
    /// nothing done yet, ids in order, the next set up.
    private static func localSession(from source: WatchSession, name: String) -> WatchSession {
        var session = source
        let now = Date.now
        session.id = WatchSession.id(for: now)
        session.startedAt = now
        session.name = name
        session.sentAt = now
        session.isFinished = false
        session.plannedFor = nil
        session.restEndsAt = nil
        session.records = nil
        for index in session.exercises.indices {
            session.exercises[index].id = index
            session.exercises[index].key = nil
            for set in session.exercises[index].sets.indices {
                session.exercises[index].sets[set].isCompleted = false
                session.exercises[index].sets[set].order = session.exercises[index].sets[set].order ?? set
            }
        }
        if let next = session.upNext() {
            session.currentExercise = next.exercise
            session.currentSet = next.set
        }
        return session
    }

    /// Completed sets only, exercises with none left out, weights in kg.
    private static func logged(_ session: WatchSession) -> [WatchSession.ExerciseSnapshot] {
        session.exercises.compactMap { exercise in
            var done = exercise
            done.sets = exercise.sets.filter(\.isCompleted)
            return done.sets.isEmpty ? nil : done
        }
    }

    /// Sends a Watch-only log to the phone with no Health workout (a failed
    /// recording, or one recovered after a crash).
    private func sendLog(of session: WatchSession, start: Date, end: Date) {
        let logged = Self.logged(session)
        guard !logged.isEmpty else { return }
        var summary = WatchWorkoutSummary(sessionID: nil, workoutUUID: nil, start: start, end: max(start, end),
                                          averageHeartRate: nil, maximumHeartRate: nil, activeKilocalories: nil, sessionRPE: nil)
        summary.loggedExercises = logged
        summary.name = session.name
        if let data = WatchMessage.encode(summary) {
            connection?.transferUserInfo([WatchMessage.summary: data])
        }
    }

    /// A log left by a session that never ended (the app was closed or
    /// crashed): its sets go to the phone, so nothing lifted is lost.
    private func recoverLocalLog() {
        guard phase == .idle, let saved = LocalLiftLog.load() else { return }
        sendLog(of: saved.session, start: saved.session.startedAt, end: saved.savedAt)
        LocalLiftLog.clear()
    }

    private func received(plan: WatchSession?, clearsPlan: Bool, library: WatchExerciseLibrary?) {
        if plan != nil || clearsPlan { plannedSession = plan }
        if let library { self.library = library }
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
        // One workout at a time: a cardio workout is starting or recording here (`WatchCardioModel`).
        guard !WatchCardioModel.shared.isBusy else { return }
        guard phase == .idle || phase == .ended else {
            if recordingSessionID == nil, let sessionID { adopt(sessionID) }
            return
        }
        phase = .starting
        problem = nil
        // A finished run's end screen sits above the lifting pages in
        // `WatchRootView`, and its old message on the start screen: clear both.
        WatchCardioModel.shared.clearForLifting()
        await requestAuthorization()
        // The zones the Heart page counts in: the phone's, else Apple Health's, else from age.
        let zones = await WatchCardioModel.shared.resolveZones()
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
            heartSeries = HeartRateSeries()
            tracker = CardioZoneTracker(scheme: zones.scheme)
            recordLines = []
            heartCaptionSeen = false
            lastLogged = nil
            finishedSession = nil
            setEdits = [:]
            pausedAt = nil
            pausedSeconds = 0
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
            // The phone finished while this was starting: end now that it runs.
            if let id = stopRequestedWhileStarting {
                stopRequestedWhileStarting = nil
                if stopApplies(to: id) { await end(sessionRPE: nil) }
            }
        } catch {
            problem = "Couldn't start the workout: \(error.localizedDescription)"
            // A session whose activity started but whose collection failed
            // would otherwise keep running with nothing to end it.
            workoutSession?.end()
            workoutSession = nil
            builder = nil
            phase = .idle
            if let id = stopRequestedWhileStarting {
                stopRequestedWhileStarting = nil
                send(.recordingStopped, sessionID: id)
            }
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
        lastLocalPauseChange = .now
        beginPause()
    }

    func resume() {
        guard phase == .paused else { return }
        workoutSession?.resume()
        phase = .running
        lastLocalPauseChange = .now
        endPause()
    }

    /// A pause starts (Pause here, or the system pausing the session): the
    /// clock on the wrist stands still from now, and the phone is told once.
    private func beginPause(at date: Date = .now) {
        guard pausedAt == nil else { return }
        pausedAt = date
        tracker.pause(at: date)
        RepCounter.shared.stop()
        send(.pause)
    }

    private func endPause(at date: Date = .now) {
        guard let since = pausedAt else { return }
        pausedSeconds += max(0, date.timeIntervalSince(since))
        pausedAt = nil
        tracker.resume(at: date)
        send(.resume)
    }

    /// The clock's start moved on by the pauses already over, for a `Text`
    /// timer that the system keeps current in Always On (`WorkoutClockText`).
    var clockTimerStart: Date? {
        clockStart.map { $0.addingTimeInterval(pausedSeconds) }
    }

    /// The workout clock at `date`: time since `clockStart` without the
    /// pauses, so it stands still while paused and matches the workout saved
    /// to Apple Health (HealthKit leaves paused time out of its duration).
    func elapsed(at date: Date) -> TimeInterval? {
        guard let start = clockStart else { return nil }
        let running = pausedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return max(0, date.timeIntervalSince(start) - pausedSeconds - running)
    }

    /// Finish from the wrist: the phone opens its finish sheet (pre-filled with
    /// the session effort) and the workout is saved here.
    func finish(sessionRPE: Int?) async {
        flushHeld()
        send(.finish(sessionRPE: sessionRPE))
        await end(sessionRPE: sessionRPE)
    }

    /// Ends the HKWorkoutSession, saves the workout and sends its summary to the
    /// phone (queued until the phone is reachable).
    func end(sessionRPE: Int?) async {
        guard isRecording, let workoutSession, let builder else { return }
        // A set still inside its undo window is logged now.
        flushHeld()
        let end = Date.now
        tracker.end(at: end)
        workoutSession.end()
        var workout: HKWorkout?
        do {
            try await builder.endCollection(at: end)
            workout = try await builder.finishWorkout()
        } catch {
            problem = "Couldn't save the workout: \(error.localizedDescription)"
        }
        var summary = WatchWorkoutSummary(
            sessionID: recordingSessionID,
            workoutUUID: workout?.uuid,
            start: startedAt ?? end,
            end: end,
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            activeKilocalories: activeKilocalories,
            sessionRPE: sessionRPE
        )
        // Ended while paused: that pause runs to the end.
        let paused = pausedSeconds + (pausedAt.map { max(0, end.timeIntervalSince($0)) } ?? 0)
        if paused > 0 { summary.pausedSeconds = paused }
        // The Watch's own session: its sets go with the summary, and the phone makes the session.
        if isLocal, let snapshot {
            summary.sessionID = nil
            summary.loggedExercises = Self.logged(snapshot)
            summary.name = snapshot.name
            if let planned = plannedSession, snapshot.name == planned.name {
                planDoneID = planned.id
                UserDefaults.standard.set(planned.id, forKey: Self.planDoneKey)
            }
            LocalLiftLog.clear()
            // The summary keeps it; Home goes back to the phone's sessions.
            finishedSession = snapshot
            self.snapshot = nil
            isLocal = false
        }
        pausedAt = nil
        pausedSeconds = 0
        self.summary = summary
        if let snapshot { finishedSession = snapshot }
        let sets = max(setsCompletedHere, finishedSession?.completedSets ?? 0)
        WatchHistoryStore.save(WatchActivityRecord(
            kind: .lift, title: finishedSession?.name ?? "Workout", start: startedAt ?? end, end: end,
            minutes: summary.minutes, detail: sets == 1 ? "1 set" : "\(sets) sets",
            averageBpm: averageHeartRate.map { Int($0.rounded()) }, maximumBpm: maximumHeartRate.map { Int($0.rounded()) },
            activity: nil, saved: workout != nil))
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
        restEndedAt = nil
        pendingRating = nil
        undoUntil = nil
        RepCounter.shared.reset()
        if let data = WatchMessage.encode(summary) {
            connection?.transferUserInfo([WatchMessage.summary: data])
        }
        WKInterfaceDevice.current().play(.stop)
    }

    /// Stops without saving anything.
    func discard() {
        guard isRecording else { return }
        dropHeld()
        let wasLocal = isLocal
        if wasLocal { LocalLiftLog.clear() }
        defer {
            if wasLocal {
                snapshot = nil
                isLocal = false
            }
        }
        workoutSession?.end()
        builder?.discardWorkout()
        workoutSession = nil
        builder = nil
        phase = .idle
        pausedAt = nil
        pausedSeconds = 0
        clearRest()
        restEndedAt = nil
        pendingRating = nil
        setEdits = [:]
        RepCounter.shared.reset()
        send(.recordingStopped, sessionID: recordingSessionID)
        recordingSessionID = nil
        selectedExercise = nil
    }

    /// Workouts shorter than this ask before they're saved (HIG Workouts:
    /// "discard extremely brief workout sessions" or ask; 60 s is the app's choice).
    static let briefSeconds: TimeInterval = 60

    /// True while the workout is still under `briefSeconds` long.
    var isBrief: Bool {
        (elapsed(at: .now) ?? 0) < Self.briefSeconds
    }

    /// Back to the start screen after the end screen.
    func reset() {
        phase = .idle
        summary = nil
        if isLocal {
            snapshot = nil
            isLocal = false
        }
        pendingRating = nil
        restEndedAt = nil
        lastLogged = nil
        undoUntil = nil
        setEdits = [:]
        selectedExercise = nil
        recordingSessionID = nil
        setsCompletedHere = 0
        if snapshot?.isFinished == true { snapshot = nil }
        RepCounter.shared.reset()
    }

    // MARK: Sets

    /// Ticks a set with what was done; the phone logs it and the rest timer starts here.
    /// The set is found by its stable ids, so a snapshot that arrived while the
    /// effort sheet was open (a set added on the phone) can't shift it.
    func completeSet(_ pending: PendingSet, reps: Int, weightKg: Double, rpe: Double?) {
        guard var current = snapshot,
              let (exerciseIndex, setIndex) = current.locate(exerciseID: pending.exerciseID, setOrder: pending.setOrder,
                                                            exerciseIndex: pending.exerciseIndex, setIndex: pending.setIndex)
        else { return }
        var set = current.exercises[exerciseIndex].sets[setIndex]
        // Ticked on the phone meanwhile: nothing to do here.
        guard !set.isCompleted else { return }
        // A set logged inside the last one's undo window: the last one is final now.
        flushHeld()
        let before = HeldSet.Before(snapshot: current, pendingRating: pendingRating, setsCompletedHere: setsCompletedHere,
                                    selectedExercise: selectedExercise, restEndsAt: restEndsAt, restLength: restLength,
                                    restStartedAt: restStartedAt, edit: setEdits[pending.id])
        // Only values changed on the wrist (the crown or the rep counter)
        // overwrite the phone's: an untouched one may be older than an edit there.
        let repsEdited = reps != pending.baseReps
        let weightEdited = abs(weightKg - pending.baseWeightKg) > 0.001
        set.reps = reps
        set.weightKg = weightKg
        set.rpe = rpe ?? set.rpe
        set.isCompleted = true
        current.exercises[exerciseIndex].sets[setIndex] = set
        let exercise = current.exercises[exerciseIndex]
        // Point at the next set now, before the phone answers (the superset
        // partner after the first half, as the phone does).
        current.currentExercise = nil
        current.currentSet = nil
        if let next = current.upNext() {
            current.currentExercise = next.exercise
            current.currentSet = next.set
        }
        if selectedExercise == exerciseIndex, let partner = supersetNext(after: exerciseIndex, in: current) {
            selectedExercise = partner
        }
        let tappedAt = Date.now
        lastLocalEdit = tappedAt
        snapshot = current
        setsCompletedHere += 1
        setEdits[pending.id] = nil
        // Held for the undo window (`undoSeconds`), then sent with the tap's time,
        // so the phone's rest and `completedAt` use the real moment
        // (`LiveWorkoutRules.remainingRest`, `completedAt`). The stable exercise id
        // and the values the wrist showed let the phone put the tick on the right
        // exercise after a reorder and log what was lifted (`WatchCommand`).
        held = HeldSet(setKey: pending.id, before: before, messages: [])
        send(.completeSet(exerciseIndex: exerciseIndex, setIndex: setIndex, reps: reps, weightKg: weightKg, rpe: rpe,
                          exerciseOrder: exercise.id, setOrder: set.order,
                          repsEdited: repsEdited, weightEdited: weightEdited,
                          exerciseKey: exercise.key, baseReps: pending.baseReps, baseWeightKg: pending.baseWeightKg),
             sentAt: tappedAt)
        undoUntil = tappedAt.addingTimeInterval(Self.undoSeconds)
        heldTask?.cancel()
        heldTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoSeconds))
            guard !Task.isCancelled else { return }
            self?.flushHeld()
        }
        if isLocal { LocalLiftLog.save(current) }
        lastLogged = LoggedSet(id: pending.id, title: Self.loggedTitle(set: set, exercise: exercise, index: setIndex), at: tappedAt)
        logCount += 1
        restEndedAt = nil
        WKInterfaceDevice.current().play(.success)
        if !set.isWarmup {
            startRestIfNeeded(after: exerciseIndex, in: current)
        }
        // "Reps left?" after a working set, unless it was rated already, it's a hold
        // (timed), a drop stage or mini-set, or one of those comes straight after (no rest to answer in).
        let nextIsStage = exercise.sets.first(where: { !$0.isCompleted })?.isStage == true
        if rpe == nil, !set.isWarmup, !set.isStage, exercise.isHold != true, !nextIsStage {
            askRating(pending)
        } else {
            skipRating()
        }
    }

    /// "Set 3 logged", "Warm-up 1 logged", "Drop 1 logged".
    private static func loggedTitle(set: WatchSession.SetSnapshot, exercise: WatchSession.ExerciseSnapshot, index: Int) -> String {
        let words = (set.title ?? "").split(separator: " ")
        if words.count >= 2 { return "\(words[0]) \(words[1]) logged" }
        let number = exercise.sets[..<index].filter { $0.isWarmup == set.isWarmup }.count + 1
        return "\(set.isWarmup ? "Warm-up" : "Set") \(number) logged"
    }

    /// How long a logged set can be undone on the wrist before it goes to the
    /// phone (app's choice: long enough for a wrist raise, short enough not to
    /// hold the phone's log up; docs/research/watch-app-redesign-2026-11.md §4.4.7).
    /// After it, the set is changed on the phone, so no "un-tick" command is
    /// needed and the phone's set-by-set autoregulation never has to be undone.
    static let undoSeconds = 4.0
    /// "Reps left?" folds away after this long without an answer (app's choice:
    /// long enough to answer on a wrist raise, short enough to clear before the next set).
    static let ratingSeconds = 15.0

    var canUndo: Bool { undoUntil != nil }

    /// Undo within the window: the set is open again, its rest and question go,
    /// and nothing about it reaches the phone.
    func undoLastSet() {
        guard let held else { return }
        heldTask?.cancel()
        heldTask = nil
        self.held = nil
        undoUntil = nil
        let before = held.before
        snapshot = before.snapshot
        setsCompletedHere = before.setsCompletedHere
        selectedExercise = before.selectedExercise
        setEdits[held.setKey] = before.edit
        ratingTask?.cancel()
        pendingRating = before.pendingRating
        if let ends = before.restEndsAt, ends > .now {
            startRest(until: ends, length: before.restLength, startedAt: before.restStartedAt)
        } else {
            clearRest()
        }
        restEndedAt = nil
        lastLogged = nil
        lastLocalEdit = .now
        if isLocal { LocalLiftLog.save(before.snapshot) }
        // What happened after the set that isn't about it still goes (a pause, the warm-up).
        for message in held.messages where !Self.isAboutTheSet(message.command) {
            deliver(message)
        }
        WKInterfaceDevice.current().play(.click)
    }

    /// The undo window is over (or another set was logged, or the workout
    /// ends): send what was held, in order, with the times it happened.
    func flushHeld() {
        heldTask?.cancel()
        heldTask = nil
        guard let held else { return }
        self.held = nil
        undoUntil = nil
        // Snapshots the phone built before it heard are ignored from here (`apply`).
        lastLocalEdit = .now
        for message in held.messages { deliver(message) }
    }

    /// Drops a held set without sending it (the workout was discarded).
    private func dropHeld() {
        heldTask?.cancel()
        heldTask = nil
        held = nil
        undoUntil = nil
    }

    /// Commands about the held set and its rest, dropped by Undo.
    private static func isAboutTheSet(_ command: WatchCommand) -> Bool {
        switch command {
        case .completeSet, .rateSet, .skipRest, .adjustRest: true
        default: false
        }
    }

    /// Commands that wait behind a held set, so the phone sees them in order
    /// (a rest change sent before the tick would find no rest to change).
    private static func waitsBehindHeldSet(_ command: WatchCommand) -> Bool {
        switch command {
        case .recordingStarted, .recordingStopped: false
        default: true
        }
    }

    private func askRating(_ pending: PendingSet) {
        pendingRating = pending
        ratingTask?.cancel()
        ratingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.ratingSeconds))
            guard !Task.isCancelled, let self, self.pendingRating?.id == pending.id else { return }
            self.pendingRating = nil
        }
    }

    /// The effort for the set just ticked: kept here and sent to the phone,
    /// which runs its set-by-set check with it (`WatchCommand.rateSet`).
    func rateSet(_ pending: PendingSet, rpe: Double) {
        if pendingRating?.id == pending.id { skipRating() }
        if var current = snapshot,
           let (exerciseIndex, setIndex) = current.locate(exerciseID: pending.exerciseID, setOrder: pending.setOrder,
                                                         exerciseIndex: pending.exerciseIndex, setIndex: pending.setIndex) {
            current.exercises[exerciseIndex].sets[setIndex].rpe = rpe
            lastLocalEdit = .now
            snapshot = current
            if isLocal { LocalLiftLog.save(current) }
        }
        send(.rateSet(exerciseIndex: pending.exerciseIndex, setIndex: pending.setIndex, rpe: rpe,
                      exerciseOrder: pending.exerciseID, setOrder: pending.setOrder, exerciseKey: pending.exerciseKey))
    }

    /// "Reps left?" closed without an answer: the set stays logged without one.
    func skipRating() {
        pendingRating = nil
        ratingTask?.cancel()
        ratingTask = nil
    }

    /// The superset partner to show after a set of `index`, when you picked the
    /// exercise yourself: A2 after A1 once A1 is a round ahead, A1 after A2.
    /// Nil when there's no partner set left, or a drop stage of this set is next.
    private func supersetNext(after index: Int, in session: WatchSession) -> Int? {
        guard let partner = session.partnerIndex(of: index),
              session.exercises[partner].sets.contains(where: { !$0.isCompleted }),
              session.exercises[index].sets.first(where: { !$0.isCompleted })?.isStage != true else { return nil }
        if partner > index { return session.roundsDone(index) > session.roundsDone(partner) ? partner : nil }
        return partner
    }

    /// The exercise the live page shows (picked, or the next set to do).
    var shownExercise: Int? {
        guard let snapshot, let index = selectedExercise ?? snapshot.nextExerciseIndex,
              index < snapshot.exercises.count else { return nil }
        return index
    }

    /// The next exercise after the shown one that has a set left, wrapping
    /// round; nil when there's no other.
    var exerciseAfterShown: Int? {
        guard let snapshot, let shown = shownExercise else { return nil }
        let count = snapshot.exercises.count
        for step in 1..<max(1, count) {
            let index = (shown + step) % count
            if snapshot.exercises[index].sets.contains(where: { !$0.isCompleted }) { return index }
        }
        return nil
    }

    /// "Skip exercise": moves the live page to the next exercise with a set
    /// left. Nothing is deleted; the skipped sets stay open, and Finish drops
    /// any that are still unticked.
    func skipExercise() {
        guard let next = exerciseAfterShown else { return }
        selectedExercise = next
        RepCounter.shared.stop()
        WKInterfaceDevice.current().play(.click)
    }

    /// Shows a record note from the phone once, with a tap.
    private func showRecords(_ note: WatchRecordNote) {
        guard !shownRecordIDs.contains(note.id) else { return }
        shownRecordIDs.insert(note.id)
        recordNote = note
        recordLines += note.lines.map { "\(note.exercise): \($0)" }
        if !WatchCardioModel.shared.isActive { WKInterfaceDevice.current().play(.notification) }
        recordTask?.cancel()
        recordTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.recordSeconds))
            guard !Task.isCancelled, let self, self.recordNote?.id == note.id else { return }
            self.recordNote = nil
        }
    }

    func dismissRecords() {
        recordTask?.cancel()
        recordNote = nil
    }

    // MARK: Warm-up

    /// Next warm-up step (from the overview: start). Shown here straight away;
    /// the phone confirms with a snapshot. `fromStep` is sent so a timed step
    /// that ends on both devices advances once.
    func warmUpNext() {
        guard var current = snapshot, let index = current.warmUpStepIndex, let steps = current.warmUp,
              index < steps.count else { return }
        if current.warmUpStarted == false {
            current.warmUpStarted = true
            current.warmUpStepIndex = 0
            current.warmUpStepEndsAt = steps[0].seconds.map { Date.now.addingTimeInterval(Double($0)) }
            lastLocalEdit = .now
            snapshot = current
            send(.warmUpNext(fromStep: nil))
            WKInterfaceDevice.current().play(.click)
            return
        }
        current.warmUpStepIndex = index + 1
        current.warmUpStepEndsAt = index + 1 < steps.count
            ? steps[index + 1].seconds.map { Date.now.addingTimeInterval(Double($0)) } : nil
        lastLocalEdit = .now
        snapshot = current
        send(.warmUpNext(fromStep: index))
        WKInterfaceDevice.current().play(.click)
    }

    /// The timed step ran out on the wrist: advance once (the phone may have
    /// already moved on; `fromStep` makes it a no-op there if so).
    func warmUpTimedStepEnded(at index: Int) {
        guard let current = snapshot, current.warmUpStarted != false, current.warmUpStepIndex == index else { return }
        warmUpNext()
    }

    /// Back one step; from the first step, back to the overview.
    func warmUpBack() {
        guard var current = snapshot, let index = current.warmUpStepIndex, let steps = current.warmUp,
              current.isWarmingUp, current.warmUpStarted != false else { return }
        if index == 0 {
            current.warmUpStarted = false
            current.warmUpStepEndsAt = nil
        } else {
            current.warmUpStepIndex = index - 1
            current.warmUpStepEndsAt = steps[index - 1].seconds.map { Date.now.addingTimeInterval(Double($0)) }
        }
        lastLocalEdit = .now
        snapshot = current
        send(.warmUpBack)
        WKInterfaceDevice.current().play(.click)
    }

    /// Finish or skip the warm-up: the set view takes over.
    func warmUpFinish() {
        guard var current = snapshot, let steps = current.warmUp, current.isWarmingUp else { return }
        current.warmUpStepIndex = steps.count
        current.warmUpStepEndsAt = nil
        lastLocalEdit = .now
        snapshot = current
        send(.warmUpFinish)
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: Rest

    /// Superset: no rest between the first lift and its partner, one rest after
    /// both (the phone applies the same rule).
    private func startRestIfNeeded(after index: Int, in session: WatchSession) {
        // Next up is a drop stage or mini-set: no rest for a drop, a short one for
        // rest-pause and myo-reps (`SetKind.restBeforeSeconds` on the phone).
        if let next = session.exercises[index].sets.first(where: { !$0.isCompleted }),
           let seconds = next.restBeforeSeconds {
            if seconds > 0 {
                startRest(until: Date.now.addingTimeInterval(Double(seconds)), length: seconds)
            } else {
                clearRest()
            }
            return
        }
        if session.exercises[index].supersetLabel?.hasSuffix("1") == true,
           let partner = session.partnerIndex(of: index),
           session.exercises[partner].sets.contains(where: { !$0.isCompleted }) {
            return
        }
        // The exercise's own rest when the Watch runs the session (the phone's
        // `RestPreferences`, sent with the plan), else the phone's next rest.
        let seconds = session.exercises[index].restSeconds ?? session.restSeconds
        startRest(until: Date.now.addingTimeInterval(Double(seconds)), length: seconds)
    }

    private func startRest(until ends: Date, length: Int, startedAt: Date = .now) {
        RepCounter.shared.stop()
        restEndsAt = ends
        restLength = max(1, length)
        restStartedAt = min(startedAt, ends)
        restEndedAt = nil
        restTask?.cancel()
        // The warning tap 10 s before the end, then the end (`RestCues`).
        let cues = RestCues.schedule(endsAt: ends, startedAt: restStartedAt, now: .now)
        restTask = Task { [weak self] in
            for cue in cues {
                try? await Task.sleep(for: .seconds(max(0, cue.at.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                switch cue.cue {
                case .warning: self?.restWarning()
                case .end: self?.restEnded()
                }
            }
        }
    }

    /// Get set: one light tap 10 s before the end (not while a cardio
    /// workout records, nor when the phone's settings turn the Watch's rest buzz off).
    private func restWarning() {
        if snapshot?.restBuzz != false, WatchPreferences.restWarning, !WatchCardioModel.shared.isActive {
            WKInterfaceDevice.current().play(.click)
        }
    }

    /// The rest ran out: one strong tap on the wrist, on time even with the
    /// wrist down (the HKWorkoutSession keeps the app running in the background,
    /// where `play` still works). While the Watch records, the phone schedules
    /// no notification of its own, so this is the only buzz. Off when the phone's
    /// Settings › Rest timer alerts isn't "Watch, else phone" (`restBuzz`).
    /// The Rest page shows "Go" with the next set, and VoiceOver says it.
    private func restEnded() {
        restTask = nil
        restEndsAt = nil
        restEndedAt = .now
        // Not while a cardio workout records here: the same tap means "ease off" there.
        if snapshot?.restBuzz != false, !WatchCardioModel.shared.isActive {
            WKInterfaceDevice.current().play(.notification)
        }
        var announcement = "Rest over."
        if let next = nextSetLine { announcement += " Next: \(next)." }
        AccessibilityNotification.Announcement(announcement).post()
    }

    /// "Bench press, 82.5 kg × 8": the set Done would log next, for the rest and Go states.
    var nextSetLine: String? {
        guard let snapshot, let index = shownExercise,
              let setIndex = snapshot.exercises[index].sets.firstIndex(where: { !$0.isCompleted }) else { return nil }
        let exercise = snapshot.exercises[index]
        let set = exercise.sets[setIndex]
        let edit = setEdits[snapshot.setKey(exercise: index, set: setIndex)]
        let text = exercise.setText(reps: edit?.reps ?? set.reps, weightKg: edit?.weightKg ?? set.weightKg, unit: snapshot.unit)
        return "\(exercise.name), \(text)"
    }

    /// The Go state is done with (the next set started, or it was seen).
    func clearRestEnded() {
        restEndedAt = nil
    }

    func skipRest() {
        lastLocalEdit = .now
        clearRest()
        restEndedAt = nil
        send(.skipRest)
    }

    /// −15 / +15 on the wrist; the phone moves its timer too (it stops at 0,
    /// `RestTimerStore.adjust`), so a snapshot sent before it heard doesn't
    /// pull the end back. Taking off more than is left ends the rest.
    func adjustRest(by seconds: Int) {
        guard let ends = restEndsAt else { return }
        lastLocalEdit = .now
        let now = Date.now
        if let moved = RestCues.adjusted(endsAt: ends, by: seconds, now: now) {
            let length = RestCues.adjustedLength(restLength, by: seconds, remaining: moved.timeIntervalSince(now))
            startRest(until: moved, length: length, startedAt: moved.addingTimeInterval(-Double(length)))
        } else {
            clearRest()
            restEndedAt = nil
        }
        WKInterfaceDevice.current().play(.click)
        send(.adjustRest(seconds: seconds))
    }

    private func clearRest() {
        restTask?.cancel()
        restTask = nil
        restEndsAt = nil
    }

    // MARK: Phone → Watch

    private func apply(_ incoming: WatchSession) {
        // Running the Watch's own session: the phone's snapshots are for its own
        // session, not this one. (A plan arrives under its own key, `plan`.)
        if isLocal, isRecording || phase == .starting { return }
        // A set is held for its undo window: the phone hasn't heard of it, so its
        // snapshots would open the set again. Its next one, after the tick, is used.
        if held != nil {
            guard incoming.isFinished else { return }
            flushHeld()
        }
        guard incoming.sentAt >= lastLocalEdit else { return }
        if let current = snapshot, current.id == incoming.id, incoming.sentAt < current.sentAt { return }
        let previous = snapshot
        if incoming.isFinished {
            // Kept for the summary: the phone's final word on the sets.
            if isRecording, previous?.id == incoming.id || belongsToRecording(incoming.id) { finishedSession = incoming }
            if previous?.id == incoming.id || previous == nil { snapshot = nil }
            selectedExercise = nil
            // Finished on the phone: the Watch's recording of it ends too (no
            // second effort question; the phone already asked).
            if stopApplies(to: incoming.id) { Task { await end(sessionRPE: nil) } }
            return
        }
        snapshot = incoming
        if previous?.id != incoming.id { selectedExercise = nil }
        if let selectedExercise, selectedExercise >= incoming.exercises.count { self.selectedExercise = nil }
        // Records for an exercise just finished on the wrist (`WatchSync.noteRecords`).
        if let note = incoming.records { showRecords(note) }
        // The phone moved the warm-up on (its countdown ended, or a tap there): a tick on the wrist.
        if let previous, previous.id == incoming.id, previous.warmUp != nil,
           previous.warmUpStepIndex != incoming.warmUpStepIndex, !WatchCardioModel.shared.isActive {
            WKInterfaceDevice.current().play(.click)
        }
        if isRecording, recordingSessionID == nil { adopt(incoming.id) }
        // A set ticked on the phone starts the rest there; run it here too, with the
        // running rest's own length for the bar (older phones: the next exercise's rest).
        if let ends = incoming.restEndsAt, ends > .now {
            if restEndsAt.map({ abs($0.timeIntervalSince(ends)) > 2 }) ?? true {
                startRest(until: ends, length: incoming.restLengthSeconds ?? incoming.restSeconds)
            }
        } else if let current = restEndsAt, incoming.sentAt > restStartedAt.addingTimeInterval(2) {
            if current.timeIntervalSinceNow < 3 {
                // The phone's timer ran out a moment before this one (the two
                // clocks differ slightly): end it now, with the buzz.
                restTask?.cancel()
                restEnded()
            } else {
                // Skipped on the phone.
                clearRest()
            }
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
            if phase == .starting {
                // Not recording yet, so `stopApplies` can't tell; `start` applies it.
                stopRequestedWhileStarting = request.sessionID
                return
            }
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
        // The Watch's own session ends only on the wrist.
        if isLocal { return false }
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
        guard isRecording, !isLocal else { return false }
        if let recordingSessionID { return recordingSessionID == sessionID }
        guard let phoneStart = WatchSession.startDate(for: sessionID), let startedAt else { return false }
        return abs(startedAt.timeIntervalSince(phoneStart)) < 5 * 60
    }

    private func activated(snapshot: WatchSession?, reachable: Bool) {
        phoneReachable = reachable
        // Transfers need an activated session: now a log left by a crash can go.
        recoverLocalLog()
        if let snapshot { apply(snapshot) }
    }

    // MARK: Watch → Phone

    private func send(_ command: WatchCommand, sessionID: String? = nil, sentAt: Date = .now) {
        // The Watch's own session: the phone hears of it once, with the summary.
        if isLocal { return }
        let message = WatchCommandMessage(sessionID: sessionID ?? snapshot?.id ?? recordingSessionID, command: command, sentAt: sentAt)
        // Behind a set in its undo window, so the phone gets them in order.
        if held != nil, Self.waitsBehindHeldSet(command) {
            held?.messages.append(message)
            return
        }
        deliver(message)
    }

    private func deliver(_ message: WatchCommandMessage) {
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

    private func sessionChanged(to state: HKWorkoutSessionState, at date: Date = .now) {
        // A callback for a pause or resume from before the last tap here (a quick
        // Pause then Resume) would start the same pause again and count it twice.
        if let local = lastLocalPauseChange, date < local, state == .paused || state == .running, phase != .starting { return }
        switch state {
        case .running:
            if phase == .paused || phase == .starting { phase = .running }
            // Resumed by the system: the clock runs again (nothing to do unless paused).
            if phase == .running { endPause() }
        case .paused:
            phase = .paused
            beginPause()
        default: break
        }
    }

    private func fail(_ message: String) {
        problem = "Recording stopped: \(message)"
        // The sets themselves are the phone's: what was held still goes.
        flushHeld()
        // The Watch's own session: the sets logged so far still reach the phone.
        let wasLocal = isLocal
        if wasLocal {
            if let snapshot { sendLog(of: snapshot, start: startedAt ?? .now, end: .now) }
            LocalLiftLog.clear()
        }
        defer {
            if wasLocal {
                snapshot = nil
                isLocal = false
            }
        }
        builder?.discardWorkout()
        workoutSession = nil
        builder = nil
        phase = .idle
        pausedAt = nil
        pausedSeconds = 0
        clearRest()
        RepCounter.shared.reset()
        send(.recordingStopped, sessionID: recordingSessionID)
        recordingSessionID = nil
    }

    private func update(current: Double?, at date: Date?, average: Double?, maximum: Double?, energy: Double?) {
        heartRate = current ?? heartRate
        averageHeartRate = average ?? averageHeartRate
        maximumHeartRate = maximum ?? maximumHeartRate
        activeKilocalories = energy ?? activeKilocalories
        guard let current, isRecording else { return }
        let now = Date.now
        let when = min(now, date ?? now)
        heartSeries.add(current, at: when)
        // Zone time only while running (the tracker is paused with the workout).
        if phase == .running { _ = tracker.reading(bpm: current, at: when) }
    }
}

extension WatchWorkoutModel: HKWorkoutSessionDelegate {
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

extension WatchWorkoutModel: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var current: Double?
        var currentDate: Date?
        var average: Double?
        var maximum: Double?
        var energy: Double?
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
        guard current != nil || average != nil || maximum != nil || energy != nil else { return }
        Task { @MainActor in self.update(current: current, at: currentDate, average: average, maximum: maximum, energy: energy) }
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
        // And the heart-rate zones chosen on the phone, for cardio (`WatchZoneStore`).
        if let zones = WatchMessage.decode(HeartRateZoneScheme.self, from: session.receivedApplicationContext, key: WatchMessage.zones) {
            WatchZoneStore.save(zones)
        }
        // Today's plan, the exercise library and this week's hard cardio.
        receiveContext(session.receivedApplicationContext)
    }

    /// The phone's whole application context (at activation, or a new one):
    /// a key that's missing means the phone has none now (rest day, done).
    nonisolated private func receiveContext(_ context: [String: Any]) {
        let plan = WatchMessage.decode(WatchSession.self, from: context, key: WatchMessage.plan)
        let library = WatchMessage.decode(WatchExerciseLibrary.self, from: context, key: WatchMessage.library)
        let intervals = WatchMessage.decode(IntervalSession.self, from: context, key: WatchMessage.intervals)
            .flatMap { $0.version <= IntervalSession.currentVersion ? $0 : nil }
        Task { @MainActor in
            self.received(plan: plan, clearsPlan: true, library: library)
            WatchCardioModel.shared.received(intervals: intervals)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.phoneReachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
        receiveContext(applicationContext)
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
        // The heart-rate zones chosen on the phone, kept for cardio (`WatchZoneStore`).
        if let zones = WatchMessage.decode(HeartRateZoneScheme.self, from: payload, key: WatchMessage.zones) {
            WatchZoneStore.save(zones)
        }
    }
}

/// A set logged on the wrist, for the tick-over ("Set 3 logged") and Undo.
nonisolated struct LoggedSet: Equatable, Sendable {
    /// `WatchSession.setKey` of the set.
    var id: String
    var title: String
    var at: Date
}

/// A logged set held on the Watch for the undo window, with everything sent
/// after it, and what to put back if it's undone.
struct HeldSet {
    struct Before {
        var snapshot: WatchSession
        var pendingRating: PendingSet?
        var setsCompletedHere: Int
        var selectedExercise: Int?
        var restEndsAt: Date?
        var restLength: Int
        var restStartedAt: Date
        var edit: SetEdit?
    }

    var setKey: String
    var before: Before
    var messages: [WatchCommandMessage]
}

/// The Watch's own session kept in a file after every set, so a crash or a
/// closed app doesn't lose the log (`WatchWorkoutModel.recoverLocalLog`).
nonisolated enum LocalLiftLog {
    nonisolated struct Saved: Codable, Sendable {
        var session: WatchSession
        var savedAt: Date
    }

    private static var url: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("watch-local-lift.json")
    }

    static func save(_ session: WatchSession) {
        guard let url, let data = try? JSONEncoder().encode(Saved(session: session, savedAt: .now)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> Saved? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
