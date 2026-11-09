import Foundation
import SwiftData
import UIKit
import AppCore

/// Your gyms (equipment, plates, dumbbells, stacks, machine settings), saved
/// on the phone as JSON (`gyms.json`, `GymRegistry`). One is active: `profile`
/// is its equipment, so the planner, prescriptions, rounding and the Watch all
/// use the gym you're at. A travel gym ends on its date and the app goes back
/// to your regular gym.
@Observable
final class GymStore {
    private(set) var registry: GymRegistry

    /// The active gym's equipment.
    var profile: GymProfile { registry.active.profile }
    /// False until a gym has been saved at least once.
    var isConfigured: Bool { registry.isConfigured }
    var activeGym: SavedGym { registry.active }
    var activeGymID: UUID { registry.activeGymID }
    var gyms: [SavedGym] { registry.gyms }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let file: SafeJSONFile
    /// False while the file exists but couldn't be read (a background launch
    /// while the phone was locked): nothing is saved over it until it loads.
    @ObservationIgnored private var canSave = false
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    /// The single profile saved before gyms existed; still written (your
    /// regular gym) so an older build or a lost file keeps your equipment.
    private static let legacyKey = "gymProfile"

    init(defaults: UserDefaults = .standard, file: SafeJSONFile = .appSupport("gyms.json")) {
        self.defaults = defaults
        self.file = file
        registry = GymRegistry.migrating(legacy: nil, fallback: Self.defaultProfile(for: Self.settingsUnit(defaults)))
        reload()
        expireTravelGymIfNeeded()
        observe()
    }

    // MARK: Loading and saving

    /// Reads the file again if the last read failed (the phone was locked).
    func reloadIfUnavailable() {
        if !canSave { reload() }
    }

    private func reload() {
        let loaded = file.loadLogged(GymRegistry.self)
        canSave = loaded.state.canSave
        if let value = loaded.value {
            registry = value
            hasLoaded = true
        } else if canSave {
            // First launch with gyms (or nothing readable): the profile saved
            // before becomes your regular gym, so nothing is lost.
            let legacy = Self.legacyProfile(defaults)
            registry = GymRegistry.migrating(legacy: legacy, fallback: Self.defaultProfile(for: Self.settingsUnit(defaults)))
            hasLoaded = true
            if legacy != nil { write() }
        } else if !hasLoaded, let legacy = Self.legacyProfile(defaults) {
            // Locked: use the last profile in the meantime, without saving.
            registry = GymRegistry.migrating(legacy: legacy, fallback: legacy)
        }
    }

    private static func legacyProfile(_ defaults: UserDefaults) -> GymProfile? {
        guard let data = defaults.data(forKey: legacyKey) else { return nil }
        return try? JSONDecoder().decode(GymProfile.self, from: data)
    }

    private func write() {
        file.saveLogged(registry, canSave: canSave)
        guard canSave, registry.isConfigured else { return }
        // Your regular gym, for older builds and as a last resort.
        let home = registry.active.isTemporary
            ? (registry.returnGymID.flatMap { registry.gym(id: $0) } ?? registry.regularGyms.first)
            : registry.active
        if let home, let data = try? JSONEncoder().encode(home.profile) {
            defaults.set(data, forKey: Self.legacyKey)
        }
    }

    /// Every change: read first if the file couldn't be read, change, save.
    private func change(_ body: (inout GymRegistry) -> Void) {
        reloadIfUnavailable()
        var copy = registry
        body(&copy)
        guard copy != registry else { return }
        registry = copy
        write()
    }

    private func observe() {
        let center = NotificationCenter.default
        // Read again once the phone is unlocked.
        observers.append(center.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadIfUnavailable() }
        })
        // A travel gym that ended while the app was away: back to your regular gym.
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireTravelGymIfNeeded() }
        })
        // Until a gym is set up, its unit follows Settings (onboarding, Settings).
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.followSettingsUnit() }
        })
    }

    /// Settings' weight unit as saved, else the region's default (`WeightUnit.localeDefault`).
    private static func settingsUnit(_ defaults: UserDefaults) -> WeightUnit {
        WeightUnit(rawValue: defaults.string(forKey: "weightUnit") ?? "") ?? .localeDefault
    }

    private static func defaultProfile(for unit: WeightUnit) -> GymProfile {
        unit == .kilograms ? .commercialKilograms : .commercialPounds
    }

    /// Before a gym is set up, the default gym's unit follows Settings.
    private func followSettingsUnit() {
        guard !registry.isConfigured, registry.gyms.count == 1, !registry.active.isTemporary else { return }
        let wanted = Self.defaultProfile(for: Self.settingsUnit(defaults))
        guard profile.unit != wanted.unit else { return }
        var replaced = wanted
        replaced.name = registry.active.name
        // In memory only: nothing is saved until you set up a gym.
        registry.updateProfile(replaced, for: registry.activeGymID)
    }

    // MARK: Training

    /// Set from the user's goals (rep ranges and effort).
    var style: TrainingStyle = .balanced
    var planner: WorkoutPlanner {
        var planner = WorkoutPlanner(gym: profile, style: style)
        planner.progressionModes = ProgressionPreferences.overrides()
        // Rep ranges and variation swaps applied from the last block's report (`NextBlockStore`).
        planner.blockPreferences = NextBlockStore.shared.plannerPreferences
        return planner
    }

    /// The one unit every lifting screen shows weights in: the gym's, so the
    /// numbers match the plates on the bar (Settings' unit is for body weight).
    var liftingUnit: WeightUnit { profile.unit == .kg ? .kilograms : .pounds }

    // MARK: Gyms

    /// Saves the active gym's equipment (Gym equipment, the builder).
    func save(_ profile: GymProfile) {
        save(profile, for: registry.activeGymID)
    }

    /// Saves one gym's equipment and name.
    func save(_ profile: GymProfile, for id: UUID) {
        change { registry in
            registry.updateProfile(profile, for: id)
            registry.isConfigured = true
        }
    }

    /// Switches gym; the planner uses its equipment from now on.
    func activate(_ id: UUID) {
        change { registry in _ = registry.activate(id) }
    }

    /// Adds a regular gym (not active until you pick it).
    @discardableResult
    func addRegularGym(name: String, profile: GymProfile) -> UUID {
        var id = registry.activeGymID
        change { registry in
            id = registry.addRegular(name: name, profile: profile, activate: false)
            registry.isConfigured = true
        }
        return id
    }

    /// Adds a travel gym until `expiresAt` and switches to it.
    @discardableResult
    func addTravelGym(name: String, profile: GymProfile, expiresAt: Date) -> UUID {
        var id = registry.activeGymID
        change { registry in id = registry.addTravel(name: name, profile: profile, expiresAt: expiresAt) }
        return id
    }

    func reuseTravelGym(_ id: UUID, expiresAt: Date) {
        change { registry in _ = registry.reuseTravelGym(id, expiresAt: expiresAt) }
    }

    func setEnd(_ expiresAt: Date, for id: UUID) {
        change { registry in registry.setEnd(expiresAt, for: id) }
    }

    func rename(_ id: UUID, to name: String) {
        change { registry in registry.rename(id, to: name) }
    }

    func canDelete(_ id: UUID) -> Bool { registry.canDelete(id) }

    func delete(_ id: UUID) {
        change { registry in _ = registry.delete(id) }
    }

    /// Travel gyms that haven't ended, and those that have (kept for reuse).
    var currentTravelGyms: [SavedGym] { registry.currentTravelGyms(at: .now) }
    var pastTravelGyms: [SavedGym] { registry.pastTravelGyms(at: .now) }

    /// Back to your regular gym once a travel gym's last day is over.
    func expireTravelGymIfNeeded() {
        change { registry in _ = registry.expireIfNeeded() }
    }

    /// The travel gym that just ended, to ask whether to keep it.
    var endedTravelGym: SavedGym? { registry.endedTravelGym }

    func keepEndedTravelGym() {
        change { registry in registry.keepEndedTravelGym() }
    }

    /// "until Sun", "until today", "until 14 Nov" for a travel gym.
    static func untilText(_ expiresAt: Date?, now: Date = .now) -> String? {
        guard let expiresAt else { return nil }
        let last = TravelGymDates.lastDay(expiresAt: expiresAt)
        let calendar = Calendar.current
        if calendar.isDateInToday(last) { return "until tonight" }
        if calendar.isDateInTomorrow(last) { return "until tomorrow" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: last)).day ?? 0
        let day = days < 7
            ? last.formatted(.dateTime.weekday(.abbreviated))
            : last.formatted(.dateTime.day().month(.abbreviated))
        return "until \(day)"
    }

    // MARK: Machine settings

    /// Seat, pin, handles and pad for an exercise at the active gym.
    func machineNote(for exerciseID: String) -> MachineNote? {
        registry.machineNote(for: exerciseID)
    }

    /// Saves (or clears, when empty) an exercise's settings at the active gym.
    func setMachineNote(_ note: MachineNote?, for exerciseID: String) {
        change { registry in registry.setMachineNote(note, for: exerciseID) }
    }

    // MARK: Workouts

    /// Notes the active gym for a workout (once; switching later doesn't rewrite it).
    func recordSession(startedAt: Date) {
        guard registry.sessionGym(startedAt: startedAt) == nil else { return }
        change { registry in _ = registry.recordSession(startedAt: startedAt) }
    }

    /// The gym a workout was done at, when it was recorded.
    func gymName(forSessionStartedAt start: Date) -> String? {
        registry.sessionGym(startedAt: start)?.name
    }

    /// "Different gym from last time…" for a machine, cable or Smith lift whose
    /// last workout (`lastSessionStart`) was at another gym.
    func gymChangeNote(exerciseID: String, lastSessionStart: Date?, libraryEquipment: String?) -> String? {
        let load = ExerciseCatalog.exercise(id: exerciseID)?.load ?? EquipmentKind.fromLibrary(libraryEquipment)
        return registry.gymChangeNote(lastSessionStart: lastSessionStart, load: load)
    }
}

/// Builds the trainer's view of your lifting history from logged sessions.
enum LiftHistory {
    /// Best e1RM and most recent top set per exercise, in the gym's unit.
    static func make(from sessions: [WorkoutSession], unit: LoadUnit) -> [String: ExerciseHistory] {
        var result: [String: ExerciseHistory] = [:]
        // Oldest first so the newest session wins for "last" values.
        for session in sessions.filter({ !$0.isActive }).sorted(by: { $0.startedAt < $1.startedAt }) {
            for exercise in session.exercises {
                // Drop stages and mini-sets are lighter or fatigued by design: not the lift's top set.
                let working = exercise.sets.filter { $0.isCompleted && !$0.isWarmup && !$0.kind.isStage && $0.reps > 0 }
                guard let top = working.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }) else { continue }
                // Double progression needs every set at the top weight to reach the reps, not just the best one.
                let atTop = working.filter { abs($0.weightKg - top.weightKg) < 0.01 }
                let e1RM = unit.fromKilograms(top.estimatedOneRepMax)
                let previous = result[exercise.exerciseID]
                let previousBest = previous?.bestEstimatedOneRepMax ?? 0
                let topWeight = unit.fromKilograms(top.weightKg)
                // The last few top weights and last session's sets, for rep and set progression.
                result[exercise.exerciseID] = ExerciseHistory(
                    bestEstimatedOneRepMax: max(previousBest, e1RM),
                    lastWeight: topWeight,
                    lastReps: atTop.map(\.reps).min() ?? top.reps,
                    lastRPE: atTop.compactMap(\.rpe).max() ?? top.rpe,
                    lastDate: session.startedAt,
                    recentWeights: ExerciseHistory.appending(topWeight, to: previous?.recentWeights ?? []),
                    lastSets: working.count
                )
            }
        }
        return result
    }

    /// Completed sets from the most recent finished session that included this exercise.
    static func previousSets(for exerciseID: String, before date: Date, in sessions: [WorkoutSession]) -> [SetLog] {
        let previous = sessions
            .filter { !$0.isActive && $0.startedAt < date }
            .sorted { $0.startedAt > $1.startedAt }
            .lazy
            .compactMap { session in session.exercises.first { $0.exerciseID == exerciseID } }
            .first
        return previous?.orderedSets.filter(\.isCompleted) ?? []
    }

    // MARK: Live-workout cache

    /// The live workout asks for every open card's history on each render;
    /// sorting all sessions each time is wasted work, so answers are kept per
    /// session start and session count (a finished or deleted session resets it).
    private static var cacheKey = ""
    private static var previousCache: [String: [SetLog]] = [:]
    private static var bestCache: [String: Double] = [:]

    private static func resetCache(before date: Date, sessions: [WorkoutSession]) {
        let key = "\(date.timeIntervalSinceReferenceDate)/\(sessions.count)"
        guard key != cacheKey else { return }
        cacheKey = key
        previousCache = [:]
        bestCache = [:]
    }

    /// `previousSets`, cached for the live workout.
    static func cachedPreviousSets(for exerciseID: String, before date: Date, in sessions: [WorkoutSession]) -> [SetLog] {
        resetCache(before: date, sessions: sessions)
        if let cached = previousCache[exerciseID] { return cached }
        let sets = previousSets(for: exerciseID, before: date, in: sessions)
        previousCache[exerciseID] = sets
        return sets
    }

    /// `bestOneRepMax`, cached for the live workout.
    static func cachedBestOneRepMax(for exerciseID: String, before date: Date, in sessions: [WorkoutSession]) -> Double {
        resetCache(before: date, sessions: sessions)
        if let cached = bestCache[exerciseID] { return cached }
        let best = bestOneRepMax(for: exerciseID, before: date, in: sessions)
        bestCache[exerciseID] = best
        return best
    }

    /// Best e1RM (kg) before a date, for PR detection.
    static func bestOneRepMax(for exerciseID: String, before date: Date, in sessions: [WorkoutSession]) -> Double {
        sessions
            .filter { !$0.isActive && $0.startedAt < date }
            .flatMap { $0.exercises.filter { $0.exerciseID == exerciseID } }
            .flatMap { $0.sets.filter { $0.isCompleted && !$0.isWarmup && !$0.kind.isStage } }
            .map(\.estimatedOneRepMax)
            .max() ?? 0
    }

    /// Exercise IDs from sessions in the last `days` days, newest first.
    static func recentExerciseIDs(_ sessions: [WorkoutSession], days: Int = 4, now: Date = .now) -> [String] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return sessions
            .filter { !$0.isActive && $0.startedAt >= cutoff }
            .sorted { $0.startedAt > $1.startedAt }
            .flatMap { $0.orderedExercises.map(\.exerciseID) }
    }
}

/// Starting a workout from a plan, from anywhere in the app.
@Observable
final class WorkoutLauncher {
    var activeSession: WorkoutSession?
    /// Set to open the workout builder sheet.
    var builderRequest: BuilderRequest?
    /// Set when the Apple Watch asks to finish (`WatchSync`): the workout
    /// screen opens its finish sheet and clears it.
    var pendingFinish = false
    /// The workout in progress, kept current by the app from its sessions. Every
    /// start (Today, Log, Fitness, Coach, the Watch) resumes it instead of
    /// starting a second one.
    var running: WorkoutSession?

    /// The running workout, if it still exists and hasn't ended.
    private var resumable: WorkoutSession? {
        guard let running, !running.isDeleted, running.modelContext != nil, running.isActive else { return nil }
        return running
    }

    /// Opens the workout in progress instead of starting another; false when none runs.
    private func resumeIfRunning() -> Bool {
        guard let resumable else { return false }
        builderRequest = nil
        activeSession = resumable
        return true
    }

    struct BuilderRequest: Identifiable, Equatable {
        let id = UUID()
        var focus: WorkoutFocus?
        var minutes: Int?
    }

    func openBuilder(focus: WorkoutFocus? = nil, minutes: Int? = nil) {
        if resumeIfRunning() { return }
        builderRequest = BuilderRequest(focus: focus, minutes: minutes)
    }

    /// Creates a session pre-filled with the plan's exercises and sets.
    func start(_ plan: PlannedWorkout, in context: ModelContext) {
        start(name: plan.title, exercises: plan.exercises, unit: plan.unit, focus: plan.focus, in: context)
    }

    /// Starts one of your own workouts. Your exercises, sets, reps and any
    /// weights you set are used as they are; missing weights are suggested
    /// from your history (loadable with your gym's plates where it knows how).
    func start(_ template: WorkoutTemplate, gym: GymStore, sessions: [WorkoutSession], library: ExerciseLibrary, in context: ModelContext) {
        if resumeIfRunning() { return }
        let unit = gym.profile.unit
        let history = LiftHistory.make(from: sessions, unit: unit)
        let items = template.orderedExercises.map { exercise in
            TemplateItem(
                exerciseID: exercise.exerciseID,
                name: exercise.name,
                sets: exercise.sets,
                reps: exercise.reps,
                rpe: exercise.targetRPE,
                weight: exercise.weightKg.map { unit.fromKilograms($0) },
                libraryLoad: EquipmentKind.fromLibrary(library.exercise(id: exercise.exerciseID)?.equipment)
            )
        }
        // Saved workouts follow the same never-again and pain rules as planned ones.
        let planned = gym.planner.prescribe(template: items, history: history,
                                            exerciseFilter: ExerciseFilter(neverAgain: ExerciseExclusions.shared.ids,
                                                                           reports: PainLogStore.shared.reports, today: .now))
        template.lastUsedAt = .now
        start(name: template.name, exercises: planned, unit: unit, in: context)
    }

    private func start(name: String, exercises: [PlannedExercise], unit: LoadUnit, focus: WorkoutFocus? = nil,
                       in context: ModelContext) {
        if resumeIfRunning() { return }
        let session = WorkoutSession(name: name)
        context.insert(session)
        for (order, planned) in exercises.enumerated() {
            Self.insertLog(planned, order: order, in: session, unit: unit, context: context)
        }
        // Superset pairs (`Supersets`) for the live view: exercise order → group.
        SupersetRegistry.save(SupersetRegistry.groups(in: exercises), for: session.startedAt)
        SessionTargets.save(exercises, for: session.startedAt, unit: unit)
        // The focus picks its warm-up tier (Settings › Training); orders are never reused (`LiveSessionStore`).
        LiveSessionStore.update(for: session.startedAt) { entry in
            entry.focus = focus?.rawValue
            entry.highestOrder = exercises.isEmpty ? nil : exercises.count - 1
        }
        try? context.save()
        running = session
        activeSession = session
    }

    /// One planned exercise as an `ExerciseLog` with its sets, in the session.
    @discardableResult
    private static func insertLog(_ planned: PlannedExercise, order: Int, in session: WorkoutSession, unit: LoadUnit,
                                  context: ModelContext) -> ExerciseLog {
        let log = ExerciseLog(exerciseID: planned.exerciseID, name: planned.name, order: order)
        log.session = session
        context.insert(log)
        insertSets(planned, into: log, unit: unit, context: context)
        return log
    }

    /// The planned exercise's sets on a log: ramp sets, working sets, then any drop stages or mini-sets.
    private static func insertSets(_ planned: PlannedExercise, into log: ExerciseLog, unit: LoadUnit, context: ModelContext) {
        let weightKg = planned.load.map { unit.toKilograms($0) } ?? 0
        // Warm-up ramp sets first (`WarmUp`), marked so they stay out of volume, strain and PRs.
        let warmUps = planned.warmUpSets ?? []
        for (index, ramp) in warmUps.enumerated() {
            let set = SetLog(order: index, weightKg: unit.toKilograms(ramp.load), reps: ramp.reps, rpe: nil, isWarmup: true)
            set.exercise = log
            context.insert(set)
        }
        for index in 0..<max(1, planned.sets) {
            let set = SetLog(order: warmUps.count + index, weightKg: weightKg, reps: planned.repsToday, rpe: nil)
            set.exercise = log
            context.insert(set)
        }
        // Time-saving sets (`TimeSaver`): the drop stages or mini-sets after the last set.
        if let kind = planned.lastSetKind, let stages = planned.stages {
            let first = warmUps.count + max(1, planned.sets)
            for (index, stage) in stages.enumerated() {
                let stageKg = stage.load.map { unit.toKilograms($0) } ?? weightKg
                let set = SetLog(order: first + index, weightKg: stageKg, reps: stage.reps, rpe: nil, kind: kind)
                set.exercise = log
                context.insert(set)
            }
        }
    }

    /// Adds planned exercises (the abs finisher, `AbsFinisher`) to the end of a
    /// running session: orders continue past the highest, and their targets
    /// and superset pairs join the session's (`SessionTargets`, `SupersetRegistry`).
    /// Returns the orders used.
    @discardableResult
    func append(_ exercises: [PlannedExercise], to session: WorkoutSession, unit: LoadUnit, in context: ModelContext) -> [Int] {
        guard !exercises.isEmpty else { return [] }
        // Past every order the session has used (removed exercises included): targets,
        // supersets, records and the Watch are keyed by it (`LiveWorkoutRules.nextOrder`).
        let first = LiveWorkoutRules.nextOrder(existing: session.exercises.map(\.order),
                                               highestUsed: LiveSessionStore.entry(for: session.startedAt).highestOrder)
        let orders = exercises.indices.map { first + $0 }
        LiveSessionStore.noteOrders(orders, for: session.startedAt)
        for (planned, order) in zip(exercises, orders) {
            Self.insertLog(planned, order: order, in: session, unit: unit, context: context)
        }
        var groups = SupersetRegistry.groups(for: session.startedAt)
        for (planned, order) in zip(exercises, orders) {
            if let group = planned.supersetGroup { groups[order] = group }
        }
        SupersetRegistry.save(groups, for: session.startedAt)
        SessionTargets.add(exercises, orders: orders, for: session.startedAt, unit: unit)
        try? context.save()
        return orders
    }

    /// Adds one exercise mid-session (Add exercise), its sets prefilled from the
    /// plan the trainer would give it (`LiveSwap.prescription`) or from last time
    /// (`LiveWorkoutRules.prefill`), with its target saved like a planned one's.
    /// Returns the log.
    @discardableResult
    func add(_ planned: PlannedExercise, to session: WorkoutSession, unit: LoadUnit, in context: ModelContext) -> ExerciseLog {
        let order = LiveSessionStore.nextOrder(existing: session.exercises.map(\.order), for: session.startedAt)
        let log = Self.insertLog(planned, order: order, in: session, unit: unit, context: context)
        // Nothing to aim for without a plan or history (0 reps): no target, as before.
        if planned.reps.upperBound > 0 {
            SessionTargets.add([planned], orders: [order], for: session.startedAt, unit: unit)
        }
        try? context.save()
        return log
    }

    /// "Swap exercise": the log becomes the new lift in the same place (and
    /// superset), its sets replaced by the new prescription. Everything the
    /// session kept for the old lift by its order goes first (`LiveSetCoach.exerciseRemoved`),
    /// so its target, set-by-set change and any queued Watch tick don't carry over.
    func swap(_ log: ExerciseLog, to planned: PlannedExercise, in session: WorkoutSession, unit: LoadUnit,
              context: ModelContext) {
        LiveSetCoach.exerciseRemoved(order: log.order, sessionStart: session.startedAt, keepSuperset: true)
        for set in Array(log.sets) {
            context.delete(set)
        }
        log.exerciseID = planned.exerciseID
        log.name = planned.name
        var unramped = planned
        unramped.warmUpSets = nil
        Self.insertSets(unramped, into: log, unit: unit, context: context)
        SessionTargets.replace(planned, order: log.order, for: session.startedAt, unit: unit)
        try? context.save()
    }

    func startEmpty(in context: ModelContext) {
        if resumeIfRunning() { return }
        let hour = Calendar.current.component(.hour, from: .now)
        let name = hour < 12 ? "Morning Workout" : (hour < 17 ? "Afternoon Workout" : "Evening Workout")
        let session = WorkoutSession(name: name)
        context.insert(session)
        try? context.save()
        running = session
        activeSession = session
    }
}
