import SwiftUI
import SwiftData
import UIKit
import AppCore

/// The live logging screen.
struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(GymStore.self) private var gym
    @Environment(LiveWorkoutRecorder.self) private var recorder
    @Environment(WorkoutLauncher.self) private var launcher
    /// The training block's RIR target, when the session has no planned effort (`LiveSetCoach`).
    @Environment(WeeklyPlanStore.self) private var weeklyPlans
    /// Morning check-in pain, so an added abs finisher works around it (`PainGuard`).
    @Environment(CheckInStore.self) private var checkIns
    @Environment(\.healthClient) private var health
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    /// "Still training?" after hours without a tick (`LiveWorkoutRules.isForgotten`).
    @State private var askingStillTraining = false
    /// The end the finish sheet uses instead of now ("End at 6:42 PM" from "Still training?").
    @State private var finishEndOverride: Date?
    /// Set by Discard: the session is deleted once this screen has gone, not under it.
    @State private var discarding = false
    /// The quiet PR banner at the end of an exercise (`SetFeedback.records`).
    @State private var recordBanner: RecordBanner?
    /// Record lines already shown this visit, by exercise order: a later,
    /// better set can still show a new one.
    @State private var shownRecords: [Int: [String]] = [:]
    /// The exercise of the last ticked working set, so its records show once you move on.
    @State private var lastTickedOrder: Int?
    /// The exercise of the last set ticked (warm-ups too): "Next" follows it (`nextSetText`).
    @State private var lastActiveOrder: Int?
    /// Records not shown yet when Finish opens, listed in the finish sheet.
    @State private var finishRecords: [RecordBanner] = []
    @State private var showingPicker = false
    @State private var showingFinish = false
    @State private var showingDiscard = false
    @State private var expanded: Set<PersistentIdentifier> = []
    @State private var savedTemplate = false
    /// Exercise order → superset group for this session (`SupersetRegistry`).
    @State private var supersetGroups: [Int: Int] = [:]
    /// The set to bring to the middle of the screen once a set is ticked.
    @State private var scrollTarget: PersistentIdentifier?
    /// The elapsed time in the pinned header; scales with Dynamic Type.
    @ScaledMetric(relativeTo: .title2) private var timerSize: CGFloat = 24
    /// A working set ticked with the circle, so without an effort rating: the
    /// rest bar asks "reps left?" once, then runs the set-by-set check.
    @State private var pendingEffort: PersistentIdentifier?
    @State private var renaming = false
    @State private var draftName = ""
    @State private var reordering = false
    /// Settings › Rest timer, also offered in the options menu. 0 = automatic.
    @AppStorage(RestPreferences.globalKey) private var globalRestSeconds = 0
    /// The "what reps in the tank means" card shows once, the first time a
    /// workout has a reserve target; the ⓘ by each plan line opens it again.
    @AppStorage(RepsLeftIntroCard.seenKey) private var seenRepsLeftIntro = false

    var body: some View {
        NavigationStack {
            ScrollView {
                ScrollViewReader { proxy in
                    workoutContent
                        // A ticked set brings the next one (and its editor) to the
                        // middle of the screen, so you don't scroll between sets.
                        .onChange(of: scrollTarget) { _, target in
                            guard let target else { return }
                            Task {
                                // Let a newly opened exercise card lay out first.
                                try? await Task.sleep(for: .milliseconds(250))
                                withAnimation { proxy.scrollTo(target, anchor: .center) }
                                scrollTarget = nil
                            }
                        }
                }
            }
            // A solid edge under the pinned header, so the sets don't show through it.
            .scrollEdgeEffectStyle(.hard, for: .top)
            // Elapsed time, options and Finish stay pinned at the top with the
            // one-line session strip and the PR banner under them.
            .safeAreaBar(edge: .top, spacing: 0) {
                VStack(spacing: 6) {
                    headerBar
                    sessionStrip
                    if let recordBanner {
                        RecordBannerView(banner: recordBanner) { self.recordBanner = nil }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
            // The rest timer stays at the bottom, in thumb reach. It reads the shared
            // timer each second, so +15s / Skip on the Lock Screen show up here too.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    restBar
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollDismissesKeyboard(.interactively)
            // One keyboard "Done" for the whole screen (each set editor used to add its own).
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.peach, Theme.Wash.rose, Theme.Wash.butter])
            }
            .background(Theme.background)
            .toolbarVisibility(.hidden, for: .navigationBar)
            // PR at the end of an exercise: one firm tap and a banner that
            // fades after a few seconds; no confetti (behaviour-change.md).
            .sensoryFeedback(.impact(weight: .heavy), trigger: recordBanner) { _, banner in banner != nil }
            .task(id: recordBanner) {
                guard recordBanner != nil else { return }
                try? await Task.sleep(for: .seconds(8))
                withAnimation { recordBanner = nil }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exercise in add(exercise) }
            }
            .sheet(isPresented: $showingFinish, onDismiss: { finishEndOverride = nil }) {
                FinishWorkoutSheet(session: session, records: finishRecords, endOverride: finishEndOverride) {
                    WatchSync.shared.sessionFinished(session) // Apple Watch: end its recording
                    dismiss()
                }
                .presentationDetents([.medium])
            }
            // Apple Watch (`WatchSync`): the wrist gets the session whenever a set, exercise
            // or rest changes; the Watch's Finish opens the finish sheet here.
            .onChange(of: watchFingerprint, initial: true) { _, _ in
                WatchSync.shared.update(from: session)
                // The Lock Screen's "Next" line follows a +/- or typed change too.
                let next = nextSetText()
                Task { await WorkoutLiveActivity.refresh(exercise: next.exercise, detail: next.detail) }
            }
            .onChange(of: showingFinish) { _, showing in
                if showing { finishRecords = pendingRecords() }
            }
            // An exercise you've moved on from shows its records, even with sets left unticked.
            .onChange(of: currentExerciseID) { old, _ in
                if let old, let exercise = session.exercises.first(where: { $0.persistentModelID == old }) {
                    showRecords(for: exercise)
                }
            }
            .onChange(of: launcher.pendingFinish, initial: true) { _, pending in
                guard pending else { return }
                launcher.pendingFinish = false
                showingFinish = true
            }
            .task {
                supersetGroups = SupersetRegistry.groups(for: session.startedAt)
                guard session.isActive else { return }
                // The gym this workout is at, for history and "different gym" notes (`GymRegistry`).
                gym.recordSession(startedAt: session.startedAt)
                checkForgotten()
                // Movement warm-up (`WarmUpRoutine`) for a session that just started, per the
                // Settings tier for the planned focus (kept in `LiveSessionStore`); ramp sets
                // are separate (`WarmUp`).
                WarmUpStore.shared.prepareIfNeeded(
                    sessionStart: session.startedAt,
                    tier: settings.warmUpTier(for: LiveSessionStore.focus(for: session.startedAt)),
                    firstSlots: session.orderedExercises.compactMap { ExerciseCatalog.slot(for: $0.exerciseID) },
                    gym: gym.profile
                )
                WatchSync.shared.update(from: session) // the first snapshot went out before the warm-up existed
                // Lock Screen / Dynamic Island: elapsed time, next set and rest timer.
                let next = nextSetText()
                await WorkoutActivityController.startIfNeeded(
                    name: session.name, startedAt: session.startedAt, exercise: next.exercise, detail: next.detail
                )
                // Live heart rate from AirPods Pro 3 or a Bluetooth strap while this workout runs;
                // not when the Apple Watch already records it (its workout is the Health record).
                if recorder.sessionStart != session.startedAt, !WatchSync.shared.watchOwnsWorkout(session) {
                    await recorder.start(at: session.startedAt)
                }
                // Apple Watch: a workout just started on the phone starts on the wrist too,
                // from the same start time, so nothing has to be started twice.
                if settings.startWatchWithWorkout, WatchSync.shared.canStartAutomatically,
                   !WatchSync.shared.watchOwnsWorkout(session),
                   Date.now.timeIntervalSince(session.startedAt) < 5 * 60 {
                    await WatchSync.shared.startOnWatch(session)
                }
            }
            .alert("Apple Watch", isPresented: Binding(
                get: { WatchSync.shared.startProblem != nil },
                set: { if !$0 { WatchSync.shared.startProblem = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(WatchSync.shared.startProblem ?? "")
            }
            .alert("Rename workout", isPresented: $renaming) {
                TextField("Workout name", text: $draftName)
                Button("Save") {
                    let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        session.name = name
                        try? modelContext.save()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $reordering) {
                ReorderExercisesSheet(session: session) { mapping in
                    applyReorder(mapping)
                }
            }
            .alert("Added to saved workouts", isPresented: $savedTemplate) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Start it again any time from Log › Saved workouts (also under Fitness › Workouts). Weights will be suggested from what you lift.")
            }
            // Discard, "Still training?" and the checks around them, in one modifier
            // so this chain stays short enough to type-check quickly.
            .modifier(DiscardAndForgottenAlerts(
                showingDiscard: $showingDiscard,
                askingStillTraining: $askingStillTraining,
                discardMessage: discardMessage,
                lastTick: lastTick,
                onDiscard: { discard() },
                onEndAt: { last in
                    finishEndOverride = last
                    showingFinish = true
                },
                onKeepGoing: {
                    LiveSessionStore.update(for: session.startedAt) { $0.keptGoingAt = .now }
                },
                onActive: { checkForgotten() },
                onDisappear: { if discarding { deleteDiscarded() } }
            ))
        }
    }

    // MARK: Discard and forgotten workouts

    private var discardMessage: String {
        session.watchWorkoutUUID != nil
            ? "Its sets are deleted, and the workout your Apple Watch saved is removed from Apple Health."
            : "Its sets are deleted."
    }

    private func discard() {
        if recorder.sessionStart == session.startedAt { recorder.discard() }
        WatchSync.shared.sessionDiscarded(session) // Apple Watch: drop its recording
        Task { await WorkoutLiveActivity.endAll() }
        discarding = true
        dismiss()
    }

    private func deleteDiscarded() {
        discarding = false
        guard !session.isDeleted, session.modelContext != nil else { return }
        // A workout the Watch already saved (finished on the wrist) goes from Apple Health too:
        // only that one, by its id (the iPhone saved none for a live session).
        if let watchID = session.watchWorkoutUUID, let health {
            let start = session.startedAt
            Task { _ = await health.deleteOwnWorkouts(start: start, end: .now, watchWorkoutUUID: watchID, includePhone: false) }
        }
        modelContext.delete(session)
        try? modelContext.save()
    }

    /// When the last set was ticked; nil before any.
    private var lastTick: Date? {
        session.exercises.flatMap(\.sets).compactMap(\.completedAt).max()
    }

    /// Asks "Still training?" after `LiveWorkoutRules.forgottenAfter` without a
    /// tick (or since the last "Keep going").
    private func checkForgotten() {
        guard session.isActive, !showingFinish, !showingDiscard else { return }
        let keptGoing = LiveSessionStore.entry(for: session.startedAt).keptGoingAt
        let last = [lastTick, keptGoing].compactMap { $0 }.max()
        if LiveWorkoutRules.isForgotten(start: session.startedAt, lastTick: last, now: .now) {
            askingStillTraining = true
        }
    }


    /// The scrolling part: the movement warm-up and the exercises (name,
    /// sets, heart rate and strain are in the pinned strip).
    private var workoutContent: some View {
        VStack(spacing: 16) {
            // First workout with a reps-in-reserve target: what "3 reps in the tank" means, once.
            if !seenRepsLeftIntro, firstTargetRIR != nil {
                RepsLeftIntroCard {
                    withAnimation { seenRepsLeftIntro = true }
                }
            }
            // Movement warm-up before the first lift (`WarmUpStore`); the Watch
            // mirrors the current step and can advance it (`WatchSync`).
            WarmUpPhaseCard(sessionStart: session.startedAt) {
                WatchSync.shared.update(from: session)
            }
            ForEach(session.orderedExercises) { exercise in
                exerciseCard(exercise)
            }
            Button {
                showingPicker = true
            } label: {
                Label("Add exercise", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.card, in: .capsule)
                    .overlay(Capsule().strokeBorder(Theme.separator))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 32)
        .lockedToScreenWidth()
    }

    /// The first exercise's reps-in-reserve target, for the first-time explainer.
    private var firstTargetRIR: Double? {
        let blockRIR = weeklyPlans.blockWeek?.targetRIR
        for exercise in session.orderedExercises {
            if let rir = LiveSetCoach.targetRIR(sessionStart: session.startedAt, order: exercise.order, blockRIR: blockRIR) {
                return rir
            }
        }
        return nil
    }

    // MARK: Header

    /// Pinned at the top: Minimize, elapsed time, the options menu and Finish.
    private var headerBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: .circle)
                    .shadow(color: Color.black.opacity(0.07), radius: 9, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Minimize")
            .accessibilityHint("The workout keeps running")
            .accessibilityIdentifier("workout-minimize") // UI tests (ScreenshotTests)
            Spacer(minLength: 4)
            elapsedClock
            Spacer(minLength: 4)
            optionsMenu
            finishButton
        }
        .padding(.top, 4)
    }

    /// Rename, add or reorder exercises, the rest timer, the Watch and saving;
    /// Discard on its own at the bottom.
    private var optionsMenu: some View {
        Menu {
            Section {
                Button("Rename workout", systemImage: "pencil") {
                    draftName = session.name
                    renaming = true
                }
                Button("Add exercise", systemImage: "plus") { showingPicker = true }
                // 5 or 10 minutes of paired ab moves after the last exercise (`AbsFinisher`).
                Menu("Add abs finisher", systemImage: "figure.core.training") {
                    ForEach([AbsFinisher.Length.five, .ten]) { length in
                        Button(length.label) { addFinisher(length) }
                    }
                }
                if session.exercises.count > 1 {
                    Button("Reorder exercises", systemImage: "arrow.up.arrow.down") { reordering = true }
                }
                Picker(selection: $globalRestSeconds) {
                    Text("Automatic (from your goal)").tag(0)
                    ForEach(RestTimer.choices, id: \.self) { seconds in
                        Text(RestPreferences.label(seconds)).tag(seconds)
                    }
                } label: {
                    Label("Rest timer", systemImage: "timer")
                }
                .pickerStyle(.menu)
            }
            Section {
                // Apple Watch records heart rate and calories for this session (`WatchSync`).
                if WatchSync.shared.watchOwnsWorkout(session) {
                    Button("Recording on Apple Watch", systemImage: "applewatch") {}
                        .disabled(true)
                } else {
                    Button("Start on Apple Watch", systemImage: "applewatch") {
                        Task { await WatchSync.shared.startOnWatch(session) }
                    }
                }
                Button("Add to saved workouts", systemImage: "square.and.arrow.down") {
                    _ = WorkoutTemplate.from(session, in: modelContext)
                    savedTemplate = true
                }
                .disabled(session.exercises.isEmpty)
            }
            Section {
                Button("Discard workout", systemImage: "trash", role: .destructive) { showingDiscard = true }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
                .frame(width: 44, height: 44)
                .background(Theme.card, in: .circle)
                .shadow(color: Color.black.opacity(0.07), radius: 9, y: 4)
        }
        .accessibilityLabel("Workout options")
        .accessibilityIdentifier("workout-options") // UI tests (ScreenshotTests)
    }

    /// Working sets done and planned (drop stages and mini-sets aren't counted).
    private var setCounts: (done: Int, total: Int) {
        let working = session.exercises.flatMap(\.sets).filter { !$0.isWarmup && !$0.kind.isStage }
        return (working.filter(\.isCompleted).count, working.count)
    }

    /// Finish is outlined until most working sets are done, then filled, so
    /// it doesn't call for a tap at the start (app choice: three quarters).
    private static let finishFilledFraction = 0.75

    private var finishButton: some View {
        let counts = setCounts
        let filled = counts.total > 0 && Double(counts.done) >= Double(counts.total) * Self.finishFilledFraction
        let disabled = session.workingSets.isEmpty
        return Button {
            showingFinish = true
        } label: {
            Text("Finish")
                .font(.headline)
                .foregroundStyle(filled ? Color.white : Theme.liftingText)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .frame(minHeight: 44)
                .background(filled ? AnyShapeStyle(Theme.lifting) : AnyShapeStyle(Theme.lifting.opacity(0.12)), in: .capsule)
                .overlay {
                    if !filled { Capsule().strokeBorder(Theme.lifting.opacity(0.5)) }
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityHint(disabled ? "Tick off a working set first" : "")
    }

    /// A red "live" dot and the elapsed time, ticking each second: m:ss under
    /// an hour, h:mm:ss after (`workoutElapsedText`, as on Today and the Watch).
    private var elapsedClock: some View {
        TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(session.startedAt))
            HStack(spacing: 6) {
                Circle().fill(Theme.recoveryLow).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(workoutElapsedText(elapsed))
                    .font(.system(size: timerSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityLabel("Elapsed time")
                    .accessibilityValue(Duration.seconds(elapsed).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))
            }
        }
    }

    /// One line under the header: "Upper Body · 4/21 sets · ♥ 124 Zone 2 · +2% strain".
    /// Replaces the title, the 112 pt strain ring and the heart-rate card, so
    /// the sets start high on the screen.
    private var sessionStrip: some View {
        TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(session.startedAt))
            let counts = setCounts
            SessionStrip(name: session.name, doneSets: counts.done, totalSets: counts.total,
                         strainGain: liveStrain(elapsed: elapsed), recorder: recorder,
                         profile: metrics.heartRateProfile)
        }
    }

    // MARK: Rest bar

    /// The rest timer, and after a working set ticked without an effort
    /// rating a one-tap "reps left" strip; either can show on its own.
    @ViewBuilder
    private var restBar: some View {
        let ends = RestTimerStore.endsAt
        // Ran out by itself a moment ago: "Rest done" for a few seconds (`RestDonePill`).
        let done = ends == nil ? RestTimerStore.justFinishedAt : nil
        let asking = effortSet
        if ends != nil || asking != nil || done != nil {
            VStack(spacing: 8) {
                if let asking {
                    RepsLeftStrip(onPick: { left in logEffort(left: left, for: asking) },
                                  onDismiss: { pendingEffort = nil })
                }
                if let ends {
                    RestTimerPill(endsAt: ends, length: RestTimerStore.length, next: restNextLine) { change in
                        if let change {
                            RestTimerStore.adjust(by: change)
                        } else {
                            RestTimerStore.stop()
                        }
                        Task { await WorkoutLiveActivity.refresh() }
                        WatchSync.shared.update(from: session) // Apple Watch rest timer
                    }
                } else if done != nil {
                    RestDonePill(next: restNextLine) {
                        Task { await WorkoutLiveActivity.refresh() }
                        WatchSync.shared.update(from: session)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    /// "Next: Bench Press · Set 2 of 3 · 82.5 kg × 7" under the rest countdown.
    private var restNextLine: String? {
        let next = nextSetText()
        guard next.exercise != "All sets done" else { return nil }
        return "Next: \(next.exercise) · \(next.detail)"
    }

    /// The working set waiting for "reps left", while it's still ticked and unrated.
    private var effortSet: SetLog? {
        guard let pendingEffort else { return nil }
        for exercise in session.exercises {
            if let set = exercise.sets.first(where: { $0.persistentModelID == pendingEffort }) {
                return set.isCompleted && set.rpe == nil ? set : nil
            }
        }
        return nil
    }

    /// "Reps left" → RPE on the reps-in-reserve scale (RPE = 10 − reps left;
    /// Zourdos et al., J Strength Cond Res 2016; "4+" logs as 6), then the
    /// set-by-set check runs as if it had been rated in the editor.
    private func logEffort(left: Int, for set: SetLog) {
        pendingEffort = nil
        set.rpe = ReserveText.rpe(repsLeft: left)
        try? modelContext.save()
        if let exercise = set.exercise {
            LiveSetCoach.autoregulate(after: set, in: exercise, sessionStart: session.startedAt,
                                      gym: gym.profile, blockRIR: weeklyPlans.blockWeek?.targetRIR)
            try? modelContext.save()
        }
        WatchSync.shared.update(from: session)
    }

    /// A ticked working set: ask for its effort when it has none and its type uses one.
    private func askEffortIfNeeded(_ set: SetLog) {
        // A hold (plank) is timed: no "reps left" to ask.
        let isHold = set.exercise.map { LiveSetCoach.isHold($0.exerciseID) } ?? false
        guard set.isCompleted, !set.isWarmup, !set.kind.isStage, set.kind.allowsAutoregulation, set.rpe == nil, !isHold else {
            pendingEffort = nil
            return
        }
        pendingEffort = set.persistentModelID
    }

    // MARK: Reorder

    /// Moves the exercises to their new positions and the session's per-order
    /// data with them (targets, set-by-set changes, supersets).
    private func applyReorder(_ mapping: [Int: Int]) {
        guard !mapping.isEmpty else { return }
        // Read every old order first, so a swap doesn't see a half-moved list.
        let moves = session.exercises.compactMap { exercise in mapping[exercise.order].map { (exercise, $0) } }
        for (exercise, order) in moves { exercise.order = order }
        SessionTargets.remap(for: session.startedAt, mapping)
        AutoregulationLog.remap(for: session.startedAt, mapping)
        LiveSessionStore.remap(for: session.startedAt, mapping)
        var groups: [Int: Int] = [:]
        for (order, group) in supersetGroups { groups[mapping[order] ?? order] = group }
        SupersetRegistry.save(groups, for: session.startedAt)
        supersetGroups = groups
        shownRecords = [:]
        lastTickedOrder = nil
        lastActiveOrder = nil
        try? modelContext.save()
        WatchSync.shared.update(from: session)
    }

    /// Changes whenever a set is ticked, added, removed or edited (weight,
    /// reps, type, effort), so the Watch is told (`WatchSync`).
    private var watchFingerprint: String {
        let sets = session.orderedExercises.flatMap(\.orderedSets)
        let detail = sets.map { set in
            let rpe = set.rpe.map { "\($0)" } ?? "-"
            return "\(set.weightKg),\(set.reps),\(set.kind.rawValue),\(rpe),\(set.isCompleted ? 1 : 0)"
        }
        return "\(session.exercises.count)/\(session.name)/" + detail.joined(separator: ";")
    }

    /// Strain this session has added on top of today's strain, from time and effort.
    private func liveStrain(elapsed: TimeInterval) -> Double {
        let rpes = session.workingSets.compactMap(\.rpe)
        let rpe = rpes.isEmpty ? 7 : rpes.reduce(0, +) / Double(rpes.count)
        let load = StrainPlanner().liftingLoad(minutes: elapsed / 60, rpe: rpe)
        return metrics.strainGain(addedLoad: load)
    }

    // MARK: Exercises

    private var currentExerciseID: PersistentIdentifier? {
        session.orderedExercises.first { exercise in exercise.sets.contains { !$0.isCompleted } }?.persistentModelID
    }

    /// Weights in a workout show in the gym's unit, so the numbers, the +/-
    /// steps and the plates to load all match what's on the bar.
    private var workoutUnit: WeightUnit { gym.liftingUnit }

    @ViewBuilder
    private func exerciseCard(_ exercise: ExerciseLog) -> some View {
        let isCurrent = exercise.persistentModelID == currentExerciseID
        let isDone = !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.isCompleted)
        // A superset partner stays open with the current exercise: one set of each, then rest.
        let isPairedWithCurrent = partner(of: exercise)?.persistentModelID == currentExerciseID
        if isCurrent || isPairedWithCurrent || expanded.contains(exercise.persistentModelID) || exercise.sets.isEmpty {
            ExerciseCard(
                exercise: exercise,
                isCurrent: isCurrent,
                previous: LiftHistory.cachedPreviousSets(for: exercise.exerciseID, before: session.startedAt, in: sessions),
                bestBefore: LiftHistory.cachedBestOneRepMax(for: exercise.exerciseID, before: session.startedAt, in: sessions),
                unit: workoutUnit,
                gym: gym.profile,
                onSetCompleted: { set in
                    let afterWarmUp = set.isWarmup
                    // Before the rest starts, so its "Next" line follows this exercise.
                    lastActiveOrder = exercise.order
                    startRest(for: exercise, afterWarmUp: afterWarmUp)
                    if !afterWarmUp { workingSetTicked(in: exercise) }
                    askEffortIfNeeded(set)
                    scrollTarget = nextSetID(after: exercise)
                },
                onCollapse: { expanded.remove(exercise.persistentModelID) },
                onRemove: { remove(exercise) },
                swapOptions: swapOptions(for: exercise),
                onSwap: { choice in swap(exercise, to: choice) },
                supersetLabel: supersetLabel(exercise),
                sessionStart: session.startedAt,
                blockRIR: weeklyPlans.blockWeek?.targetRIR
            )
        } else {
            Button {
                expanded.insert(exercise.persistentModelID)
            } label: {
                CollapsedExerciseRow(
                    exercise: exercise,
                    isDone: isDone,
                    isNext: isNext(exercise),
                    unit: workoutUnit,
                    position: (session.orderedExercises.firstIndex(where: { $0.persistentModelID == exercise.persistentModelID }) ?? 0) + 1,
                    supersetLabel: supersetLabel(exercise),
                    target: SessionTargets.target(for: session.startedAt, order: exercise.order)
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows its sets")
        }
    }

    // MARK: Supersets

    /// "A1" / "A2" when the exercise was planned as half of a superset (`Supersets`).
    private func supersetLabel(_ exercise: ExerciseLog) -> String? {
        SupersetRegistry.label(order: exercise.order, groups: supersetGroups)
    }

    private func partner(of exercise: ExerciseLog) -> ExerciseLog? {
        guard let order = SupersetRegistry.partner(of: exercise.order, groups: supersetGroups) else { return nil }
        return session.exercises.first { $0.order == order }
    }

    /// The set to do after one in `exercise` is ticked: a superset partner's
    /// set first, else this exercise's next one (so an exercise done out of
    /// order doesn't jump back to an earlier one), else the first unticked set.
    private func nextSetID(after exercise: ExerciseLog) -> PersistentIdentifier? {
        LiveSetCoach.nextOpenSet(in: session, after: exercise, groups: supersetGroups)?.set.persistentModelID
    }

    private func isNext(_ exercise: ExerciseLog) -> Bool {
        let ordered = session.orderedExercises
        guard let currentIndex = ordered.firstIndex(where: { $0.persistentModelID == currentExerciseID }),
              let index = ordered.firstIndex(where: { $0.persistentModelID == exercise.persistentModelID }) else { return false }
        return index == currentIndex + 1
    }

    private func startRest(for exercise: ExerciseLog, afterWarmUp: Bool = false) {
        defer { WatchSync.shared.update(from: session) } // Apple Watch: rest timer and next set
        // After a ramp set: a short fixed rest, so the muscles stay warm for the
        // next one (`RestTimer.warmUpRestSeconds`; McGowan et al., Sports Med 2015).
        if afterWarmUp {
            RestTimerStore.start(seconds: Double(RestTimer.warmUpRestSeconds))
            let next = nextSetText()
            Task { await WorkoutLiveActivity.refresh(exercise: next.exercise, detail: next.detail) }
            return
        }
        // A drop stage or mini-set is next (`SetKind`): no rest before a drop (the
        // timer is skipped between drop stages), a short one for rest-pause and myo-reps.
        if let seconds = LiveSetCoach.stageRest(before: exercise) {
            if seconds > 0 {
                RestTimerStore.start(seconds: Double(seconds))
            } else {
                RestTimerStore.stop()
            }
            let next = nextSetText()
            Task { await WorkoutLiveActivity.refresh(exercise: next.exercise, detail: next.detail) }
            return
        }
        // Superset: no rest between the first lift and its partner, one rest after both
        // (paired sets, Iversen et al., Sports Med 2021; `Supersets`).
        if let mate = partner(of: exercise), mate.order > exercise.order,
           mate.sets.contains(where: { !$0.isCompleted }) {
            let next = nextSetText()
            Task { await WorkoutLiveActivity.refresh(exercise: next.exercise, detail: next.detail) }
            return
        }
        let seconds = RestPreferences.resolved(for: exercise.exerciseID, style: gym.style,
                                               sessionStart: session.startedAt, order: exercise.order)
        RestTimerStore.start(seconds: Double(seconds))
        let next = nextSetText()
        Task { await WorkoutLiveActivity.refresh(exercise: next.exercise, detail: next.detail) }
    }

    /// The next set to do, for the Live Activity ("Bench Press", "Set 3 of 4 · 135 lb × 8";
    /// warm-up ramp sets read "Warm-up 2 of 3"): after the last exercise ticked,
    /// as `nextSetID` picks it.
    private func nextSetText() -> (exercise: String, detail: String) {
        let ticked = lastActiveOrder.flatMap { order in session.exercises.first { $0.order == order } }
        guard let next = LiveSetCoach.nextOpenSet(in: session, after: ticked, groups: supersetGroups) else {
            return ("All sets done", "Tap Finish when you're ready")
        }
        return (next.exercise.name, LiveSetCoach.nextSetDetail(next.set, in: next.exercise, unit: workoutUnit))
    }

    /// A working set was ticked: the exercise's records once its sets are all
    /// done, and the last exercise's when you've moved on to another one (a
    /// superset partner doesn't count as moving on).
    private func workingSetTicked(in exercise: ExerciseLog) {
        if let previousOrder = lastTickedOrder, previousOrder != exercise.order,
           partner(of: exercise)?.order != previousOrder,
           let previous = session.exercises.first(where: { $0.order == previousOrder }) {
            showRecords(for: previous)
        }
        lastTickedOrder = exercise.order
        if !exercise.sets.isEmpty, exercise.sets.allSatisfy(\.isCompleted) {
            showRecords(for: exercise)
        }
    }

    /// e1RM, rep and volume PRs against earlier sessions from the exercise's
    /// ticked working sets, as a short banner; only lines not shown yet.
    private func showRecords(for exercise: ExerciseLog) {
        guard let banner = newRecords(for: exercise) else { return }
        shownRecords[exercise.order, default: []].append(contentsOf: banner.lines)
        withAnimation { recordBanner = banner }
        AccessibilityNotification.Announcement(banner.spokenText).post()
    }

    /// Records from the exercise's ticked working sets that haven't been shown; nil if none.
    private func newRecords(for exercise: ExerciseLog) -> RecordBanner? {
        guard exercise.sets.contains(where: { $0.isCompleted && !$0.isWarmup }) else { return nil }
        let shown = shownRecords[exercise.order] ?? []
        let lines = LiveSetCoach.records(for: exercise, sessionStart: session.startedAt, sessions: sessions, unit: workoutUnit)
            .map { $0.message(unit: workoutUnit.rawValue) }
            .filter { !shown.contains($0) }
        guard !lines.isEmpty else { return nil }
        return RecordBanner(order: exercise.order, exercise: exercise.name, lines: lines)
    }

    /// Records not shown yet across the workout, for the finish sheet.
    private func pendingRecords() -> [RecordBanner] {
        session.orderedExercises.compactMap(newRecords(for:))
    }

    /// Appends an abs finisher (`AbsFinisher`): moves the gym and today's pain
    /// allow, none already in the session, rotating away from recent ones; paired
    /// as supersets with a short rest, then synced to the Watch.
    private func addFinisher(_ length: AbsFinisher.Length) {
        var planner = gym.planner
        let reports = PainLogStore.shared.allReports(checkIns: checkIns, health: [])
        planner.exerciseFilter = ExerciseFilter(neverAgain: ExerciseExclusions.shared.ids, reports: reports, today: .now)
        let unit = gym.profile.unit
        let finisher = AbsFinisher.make(
            length: length,
            planner: planner,
            history: LiftHistory.make(from: sessions, unit: unit),
            recentExerciseIDs: LiftHistory.recentExerciseIDs(sessions, days: 10),
            excluding: Set(session.exercises.map(\.exerciseID)),
            firstGroup: (supersetGroups.values.max() ?? 0) + 1
        )
        guard let finisher else { return }
        let orders = launcher.append(finisher.exercises, to: session, unit: unit, in: modelContext)
        supersetGroups = SupersetRegistry.groups(for: session.startedAt)
        // Show the first finisher exercise open.
        if let first = orders.first, let log = session.exercises.first(where: { $0.order == first }) {
            expanded.insert(log.persistentModelID)
        }
        WatchSync.shared.update(from: session)
    }

    // MARK: Add, swap, remove

    /// The planner with never-again lifts and today's pain applied (`ExerciseFilter`).
    private var filteredPlanner: WorkoutPlanner {
        var planner = gym.planner
        let reports = PainLogStore.shared.allReports(checkIns: checkIns, health: [])
        planner.exerciseFilter = ExerciseFilter(neverAgain: ExerciseExclusions.shared.ids, reports: reports, today: .now)
        return planner
    }

    /// Today's effort target, as the builder plans it (recovery and the block's week).
    private var sessionRPE: Double {
        WorkoutPlanner.targetRPE(recovery: metrics.recovery?.score, block: weeklyPlans.blockWeek)
    }

    /// What an added or swapped-in exercise starts with: the planner's
    /// prescription for a catalog lift (history, double progression, pain cap),
    /// else last time's weight × reps and sets (`LiveSwap.prefilled`).
    private func prescription(id: String, name: String, sets: Int?) -> PlannedExercise {
        let history = LiftHistory.make(from: sessions, unit: gym.profile.unit)
        if let choice = ExerciseCatalog.exercise(id: id),
           let planned = LiveSwap.prescription(for: choice, planner: filteredPlanner, sets: sets,
                                               sessionRPE: sessionRPE, history: history) {
            return planned
        }
        return LiveSwap.prefilled(exerciseID: id, name: name, history: history[id], sets: sets, rpe: sessionRPE)
    }

    private func add(_ exercise: Exercise) {
        // Its order is past every order the session has used (`LiveSessionStore.nextOrder`),
        // so it never inherits a removed exercise's target, superset or Watch tick.
        let planned = prescription(id: exercise.id, name: exercise.name, sets: nil)
        let log = launcher.add(planned, to: session, unit: gym.profile.unit, in: modelContext)
        expanded.insert(log.persistentModelID)
        WatchSync.shared.update(from: session)
    }

    /// Other lifts for the same movement the gym supports, without never-again
    /// lifts, painful ones and ones already in the workout (`LiveSwap.options`).
    /// Empty once a working set is ticked (add an exercise instead) or outside the catalog.
    private func swapOptions(for exercise: ExerciseLog) -> [CatalogExercise] {
        guard !exercise.sets.contains(where: { $0.isCompleted && !$0.isWarmup }) else { return [] }
        let used = Set(session.exercises.map(\.exerciseID))
        return Array(LiveSwap.options(for: exercise.exerciseID, planner: filteredPlanner, excluding: used).prefix(6))
    }

    private func swap(_ exercise: ExerciseLog, to choice: CatalogExercise) {
        let working = exercise.sets.filter { !$0.isWarmup && !$0.kind.isStage }.count
        let planned = prescription(id: choice.id, name: choice.name, sets: max(1, working))
        launcher.swap(exercise, to: planned, in: session, unit: gym.profile.unit, context: modelContext)
        if lastTickedOrder == exercise.order { lastTickedOrder = nil }
        if lastActiveOrder == exercise.order { lastActiveOrder = nil }
        shownRecords[exercise.order] = nil
        WatchSync.shared.update(from: session)
    }

    /// Removes an exercise and everything the session kept by its order
    /// (`LiveSetCoach.exerciseRemoved`), so an exercise added later starts clean
    /// and its superset partner is no longer labelled A1.
    private func remove(_ exercise: ExerciseLog) {
        let order = exercise.order
        supersetGroups = LiveSetCoach.exerciseRemoved(order: order, sessionStart: session.startedAt)
        if lastTickedOrder == order { lastTickedOrder = nil }
        if lastActiveOrder == order { lastActiveOrder = nil }
        shownRecords[order] = nil
        expanded.remove(exercise.persistentModelID)
        modelContext.delete(exercise)
        try? modelContext.save()
        WatchSync.shared.update(from: session)
    }
}

// MARK: - Exercise card

private struct ExerciseCard: View {
    @Bindable var exercise: ExerciseLog
    let isCurrent: Bool
    let previous: [SetLog]
    let bestBefore: Double
    let unit: WeightUnit
    let gym: GymProfile
    /// Called with the set just ticked (a warm-up ramp set or a working set).
    let onSetCompleted: (_ set: SetLog) -> Void
    let onCollapse: () -> Void
    /// Removes the exercise and what the session kept for it (`LiveSetCoach.exerciseRemoved`).
    let onRemove: () -> Void
    /// Other lifts for the same movement (`LiveSwap.options`); empty hides "Swap exercise".
    var swapOptions: [CatalogExercise] = []
    var onSwap: (CatalogExercise) -> Void = { _ in }
    /// "A1" / "A2" when this exercise is half of a superset.
    var supersetLabel: String? = nil
    /// The session's start, the key for its planned targets (`SessionTargets`).
    var sessionStart: Date = .distantPast
    /// The training block's RIR target, used when the session has no planned effort.
    var blockRIR: Int? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(ExerciseLibrary.self) private var library
    /// Machine settings and "different gym" notes for the gym you're at.
    @Environment(GymStore.self) private var gymStore
    @State private var editingMachineNote = false
    /// The plan's reps and effort for this exercise (`SessionTargets`).
    @State private var target: SessionTargets.Target?
    /// The one set-by-set load change made this session (`Autoregulation`).
    @State private var adjustment: AutoregulationLog.Entry?
    /// How the planner progresses this lift (`ProgressionPreferences`).
    @State private var progression: ProgressionMode = .load
    /// The set open in the editor (defaults to the next set to do).
    @State private var focusedSetID: PersistentIdentifier?
    @State private var showingRPEGuide = false
    @State private var confirmingRemove = false
    @State private var showingProgress = false
    @State private var showingGuide = false
    /// Ticked warm-ups shown in full instead of folded into one row.
    @State private var showingWarmUps = false
    /// Ramp sets left out because a working set was ticked first, for Undo.
    @State private var skippedWarmUps: [SkippedWarmUp] = []
    /// This exercise's own rest time (nil = automatic).
    @State private var restSeconds: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            if let planLine {
                // The plan once, here: sets × rep goal · weight. The reps-in-reserve
                // target stays behind the scenes; each set shows its rep goal (`RepGoal`).
                Text(planLine)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.liftingText)
                    .fixedSize(horizontal: false, vertical: true)
                if let progressionNote = target?.progressionNote {
                    // How the weight moved since last time (`WorkoutPlanner.progression`).
                    Text(progressionNote)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let info = library.exercise(id: exercise.exerciseID) {
                Text([info.equipment?.capitalized, info.primaryMuscleLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let supersetLabel {
                Chip(text: "\(supersetLabel) · superset", color: Theme.sleep)
                    .padding(.top, 2)
            }
            if isNewPR && stacked {
                prLabel
                    .padding(.top, 2)
            }
        }
    }

    private var prLabel: some View {
        Label("New PR", systemImage: "star.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.liftingText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.lifting.opacity(0.12), in: .capsule)
    }

    var body: some View {
        let sets = exercise.orderedSets
        let currentSet = sets.first { !$0.isCompleted }
        let editing = sets.first { $0.persistentModelID == focusedSetID } ?? currentSet
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // At accessibility text sizes the badge goes and the PR label
                // moves under the name, so the name keeps the width (ux-audit.md 4.8).
                // Tap the exercise for how to do it, with form videos.
                Button { showingGuide = true } label: {
                    HStack(alignment: .top, spacing: 12) {
                        if !stacked {
                            IconBadge(systemName: "dumbbell.fill", color: Theme.lifting, size: 46)
                        }
                        titleColumn
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows how to do it, with form videos")
                .sheet(isPresented: $showingGuide) {
                    ExerciseGuideSheet(exerciseID: exercise.exerciseID, name: exercise.name)
                }
                Spacer(minLength: 0)
                if isNewPR && !stacked {
                    prLabel
                }
                optionsMenu
                    .sheet(isPresented: $showingProgress) {
                        NavigationStack {
                            LiftProgressView(exerciseID: exercise.exerciseID, name: exercise.name)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { showingProgress = false }
                                    }
                                }
                        }
                    }
                    .onAppear { restSeconds = RestPreferences.seconds(for: exercise.exerciseID) }
                    .confirmationDialog("Remove \(exercise.name) and its sets?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                        Button("Remove", role: .destructive, action: onRemove)
                    }
            }

            gymLines

            setList(sets, editing: editing)

            // A change to a set other than the one being edited shows under the sets.
            if let adjustment = shownAdjustment(in: sets), adjustment.setOrder != editing?.order {
                adjustmentNote(adjustment)
            }

            AddSetButtons(canAddStage: canAddStage(to: sets), onAddSet: addSet, onAddStage: addStage)

            if needsWeightFinding(sets) {
                // No history and nothing to estimate from, so no ramp sets: the first set finds the weight.
                Text("First set: find your weight, starting light.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if supersetLabel?.hasSuffix("1") == true {
                Text("Superset: one set of this, one of the next, then rest.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
        .sheet(isPresented: $showingRPEGuide) {
            RPEGuideView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $editingMachineNote) {
            MachineNoteEditor(exerciseID: exercise.exerciseID, exerciseName: exercise.name)
        }
        .onAppear(perform: loadLiveState)
        // A set ticked on the Watch can make the change too (`LiveSetCoach.autoregulate`).
        .onChange(of: completedCount) { _, _ in
            adjustment = AutoregulationLog.entry(for: sessionStart, order: exercise.order)
        }
        // Effort logged from the rest bar's "reps left" strip can make the change too.
        .onChange(of: exercise.orderedSets.map(\.rpe)) { _, _ in
            adjustment = AutoregulationLog.entry(for: sessionStart, order: exercise.order)
        }
    }

    private var completedCount: Int { exercise.sets.filter(\.isCompleted).count }

    /// "Seat 4 · Pin 7" at this gym, and before the first set, a note when
    /// last time was at another gym (`GymRegistry.gymChangeNote`).
    @ViewBuilder
    private var gymLines: some View {
        MachineNoteLine(note: gymStore.machineNote(for: exercise.exerciseID)) { editingMachineNote = true }
        if completedCount == 0, let note = gymChangeNote {
            Label(note, systemImage: "building.2")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var gymChangeNote: String? {
        let lastStart = previous.first?.exercise?.session?.startedAt
        let equipment = library.exercise(id: exercise.exerciseID)?.equipment
        return gymStore.gymChangeNote(exerciseID: exercise.exerciseID, lastSessionStart: lastStart, libraryEquipment: equipment)
    }

    /// Collapse, how-to, progress, rest, progression, swap and remove.
    private var optionsMenu: some View {
        Menu {
            if !isCurrent {
                Button("Collapse", systemImage: "chevron.up", action: onCollapse)
            }
            Button("How to do it", systemImage: "figure.strengthtraining.traditional") { showingGuide = true }
            Button("Progress", systemImage: "chart.line.uptrend.xyaxis") { showingProgress = true }
            // Seat, pin, handles and pad at this gym (`MachineNote`).
            Button("Machine settings", systemImage: "slider.horizontal.3") { editingMachineNote = true }
            restMenu
            // Load, reps or sets (Plotkin et al., PeerJ 2022); the planner uses it next time.
            Picker(selection: progressionBinding) {
                ForEach(ProgressionMode.allCases) { mode in
                    Text(progressionLabel(mode)).tag(mode)
                }
            } label: {
                Label("Progress by", systemImage: "chart.bar.xaxis")
            }
            .pickerStyle(.menu)
            if !swapOptions.isEmpty {
                swapMenu
            }
            Button("Remove exercise", systemImage: "trash", role: .destructive) {
                confirmingRemove = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("Exercise options")
    }

    private var restMenu: some View {
        let current = restSeconds.map(RestPreferences.label) ?? "automatic"
        return Menu("Rest: \(current)", systemImage: "timer") {
            Button("Automatic (from your goal)") { setRest(nil) }
            ForEach(RestTimer.choices, id: \.self) { seconds in
                Button(RestPreferences.label(seconds)) { setRest(seconds) }
            }
        }
    }

    /// Another lift for the same movement your gym has (never-again and
    /// painful lifts left out), started from your history (`LiveSwap`).
    private var swapMenu: some View {
        Menu("Swap exercise", systemImage: "arrow.triangle.2.circlepath") {
            ForEach(swapOptions, id: \.id) { option in
                Button(option.name) { onSwap(option) }
            }
        }
    }

    /// Ticked (or skipped) warm-ups as one row at the top, then each set.
    @ViewBuilder
    private func setList(_ sets: [SetLog], editing: SetLog?) -> some View {
        let ramps = sets.filter(\.isWarmup)
        let folded = !ramps.isEmpty && ramps.allSatisfy(\.isCompleted)
        if folded || (ramps.isEmpty && !skippedWarmUps.isEmpty) {
            WarmUpsDoneRow(count: ramps.count, skipped: skippedWarmUps.count, isOpen: showingWarmUps,
                           onToggle: { withAnimation(.snappy) { showingWarmUps.toggle() } },
                           onUndoSkip: skippedWarmUps.isEmpty ? nil : { restoreWarmUps() })
        }
        ForEach(sets, id: \.persistentModelID) { set in
            setSlot(set, in: sets, editing: editing, folded: folded)
        }
    }

    // MARK: Set rows and set types

    /// One set: its row, or the editor in its place when it's the set being
    /// edited (so the controls sit where you're looking and the set isn't
    /// drawn twice). Ticked warm-ups fold into one row at the top. The id lets
    /// the screen scroll the next set into view.
    @ViewBuilder
    private func setSlot(_ set: SetLog, in sets: [SetLog], editing: SetLog?, folded: Bool) -> some View {
        let isEditing = set.persistentModelID == editing?.persistentModelID
        if !folded || !set.isWarmup || showingWarmUps || isEditing {
            Group {
                if isEditing {
                    VStack(spacing: 10) {
                        if let adjustment = shownAdjustment(in: sets), adjustment.setOrder == set.order {
                            adjustmentNote(adjustment)
                        }
                        setEditor(set, in: sets)
                    }
                } else {
                    setRow(set, in: sets)
                }
            }
            .id(set.persistentModelID)
        }
    }

    private func setEditor(_ editing: SetLog, in sets: [SetLog]) -> some View {
        SetEditor(
            set: editing,
            title: editorTitle(for: editing, in: sets),
            subtitle: editorSubtitle(for: editing, in: sets),
            kind: editing.isWarmup || isHold ? nil : kindBinding(for: editing),
            unit: unit,
            step: { up in
                step(editing, up: up)
                markTouched(editing)
            },
            plateHint: plateHint(for: editing),
            // No reps-in-reserve target shown: the set's rep goal is the target.
            targetRPE: nil,
            isHold: isHold,
            isPerHand: isPerHand,
            onEdited: { markTouched(editing) },
            onComplete: { toggle(editing) },
            onShowGuide: { showingRPEGuide = true },
            onToggleWarmUp: {
                editing.isWarmup.toggle()
                try? modelContext.save()
            },
            onDelete: { delete(editing) }
        )
    }

    private func adjustmentNote(_ adjustment: AutoregulationLog.Entry) -> some View {
        AdjustmentNote(text: adjustment.message,
                       onUndo: adjustment.restore?.isEmpty == false ? { undoAdjustment(adjustment) } : nil,
                       isPainHold: adjustment.restore == nil)
    }

    /// One set's row with its context menu (warm-up, set type, delete).
    private func setRow(_ set: SetLog, in sets: [SetLog]) -> some View {
        let position = structurePosition(of: set, in: sets)
        let ghostIndex = (position.number ?? 1) - 1
        let isWorking = !set.isWarmup && !position.isStage
        return SetRow(
            set: set,
            label: rowLabel(set, position: position),
            previous: isWorking ? previousText(index: ghostIndex) : "",
            unit: unit,
            isEditing: false,
            onTap: { focusedSetID = set.persistentModelID },
            onToggle: { toggle(set) },
            previousSet: isWorking ? previousSet(index: ghostIndex) : nil,
            warmUp: set.isWarmup ? warmUpPosition(set, in: sets) : nil,
            verdict: isWorking && !isHold ? verdict(for: set, index: ghostIndex) : nil,
            verdictTargetReps: isWorking ? verdictTargetReps(for: set) : nil,
            kindLine: Self.kindLine(set.kind, isStage: position.isStage),
            isHold: isHold,
            isPerHand: isPerHand
        )
        .contextMenu {
            Button(set.isWarmup ? "Make working set" : "Make warm-up set") { set.isWarmup.toggle() }
            if !set.isWarmup {
                Picker(selection: kindBinding(for: set)) {
                    ForEach(SetKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                } label: {
                    Label("Set type", systemImage: "square.stack.3d.down.right")
                }
                .pickerStyle(.menu)
            }
            Button("Delete set", role: .destructive) { delete(set) }
        }
    }

    private func delete(_ set: SetLog) {
        if set.persistentModelID == focusedSetID { focusedSetID = nil }
        modelContext.delete(set)
        try? modelContext.save()
    }

    /// Puts back the ramp sets that ticking a working set first left out.
    private func restoreWarmUps() {
        for ramp in skippedWarmUps {
            let set = SetLog(order: ramp.order, weightKg: ramp.weightKg, reps: ramp.reps, rpe: nil, isWarmup: true)
            set.exercise = exercise
            modelContext.insert(set)
        }
        skippedWarmUps = []
        try? modelContext.save()
    }

    /// Ticking a working set while ramp sets before it are still open means
    /// you've warmed up your own way: they're left out (with Undo), so focus
    /// goes to the next working set instead of back to a warm-up.
    private func skipOpenWarmUps(before set: SetLog) {
        let open = exercise.orderedSets.filter { $0.isWarmup && !$0.isCompleted && $0.order < set.order }
        guard !open.isEmpty else { return }
        skippedWarmUps += open.map { SkippedWarmUp(order: $0.order, weightKg: $0.weightKg, reps: $0.reps) }
        for ramp in open { modelContext.delete(ramp) }
    }

    private func structurePosition(of set: SetLog, in sets: [SetLog]) -> SetStructure.Position {
        let positions = SetStructure.positions(LiveSetCoach.structureItems(sets))
        let index = sets.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0
        return index < positions.count ? positions[index] : SetStructure.Position(number: 1)
    }

    /// "W", the set number, or "D" / "RP" / "M" for a drop stage or mini-set.
    private func rowLabel(_ set: SetLog, position: SetStructure.Position) -> String {
        if set.isWarmup { return "W" }
        if position.isStage { return set.kind.shortLabel }
        return "\(position.number ?? 1)"
    }

    /// "Drop · no rest", "Mini-set · about 20 s rest", "To failure"; nil for a normal set.
    static func kindLine(_ kind: SetKind, isStage: Bool) -> String? {
        switch kind {
        case .straight: return nil
        case .failure: return "To failure"
        case .drop: return isStage ? "Drop · no rest, lighter" : "Drop set"
        case .restPause: return isStage ? "Rest-pause · about \(SetKind.restPauseRestSeconds) s rest" : "Rest-pause"
        // How good the evidence is sits behind the editor's ⓘ (`SetKind.evidence`).
        case .myoRep: return isStage ? "Myo-rep · 3-5 breaths" : "Myo-reps"
        }
    }

    /// "Set 2", "Set 3 · To failure", "Warm-up 1 of 3" or "Drop 1 of 2" above the editor.
    private func editorTitle(for set: SetLog, in sets: [SetLog]) -> String {
        if set.isWarmup {
            let position = warmUpPosition(set, in: sets)
            return "Warm-up \(position.number) of \(position.count)"
        }
        let position = structurePosition(of: set, in: sets)
        if position.isStage { return LiveSetCoach.title(for: set, in: sets) }
        let number = "Set \(position.number ?? 1)"
        return set.kind == .straight ? number : number + " · " + set.kind.title
    }

    /// The row's second line, kept in the editor's header: last time's same
    /// set ("Last: 82.5 × 6 · 3 left") or the ramp set's share of the working weight.
    private func editorSubtitle(for set: SetLog, in sets: [SetLog]) -> String? {
        if set.isWarmup {
            return warmUpPosition(set, in: sets).percent.map { "\($0)% of the working weight" }
        }
        let position = structurePosition(of: set, in: sets)
        guard !position.isStage else { return Self.kindLine(set.kind, isStage: true) }
        let last = previousText(index: (position.number ?? 1) - 1)
        return last.isEmpty ? nil : "Last: \(last)"
    }

    /// The set type, from the editor or the row's context menu. Marking a set
    /// "to failure" fills its effort as 10; changing it back clears that 10
    /// again (left in, it would read as harder than planned and cut the load).
    /// Which 10s were filled this way is kept with the session (`LiveSessionStore`),
    /// so it holds after the card is collapsed and opened again.
    private func kindBinding(for set: SetLog) -> Binding<SetKind> {
        Binding(
            get: { set.kind },
            set: { kind in
                let order = exercise.order
                if set.kind == .failure, kind != .failure,
                   LiveSessionStore.isAutoFilledRPE(order: order, setOrder: set.order, for: sessionStart) {
                    if set.rpe == 10 { set.rpe = nil }
                    LiveSessionStore.setAutoFilledRPE(false, order: order, setOrder: set.order, for: sessionStart)
                }
                set.kind = kind
                if kind == .failure, set.rpe == nil {
                    set.rpe = 10
                    LiveSessionStore.setAutoFilledRPE(true, order: order, setOrder: set.order, for: sessionStart)
                }
                try? modelContext.save()
            }
        )
    }

    /// The weight or reps of a set were changed by hand: Finish asks about it if it's left unticked.
    private func markTouched(_ set: SetLog) {
        LiveSessionStore.markTouched(order: exercise.order, setOrder: set.order, for: sessionStart)
    }

    /// A plank or side plank: "reps" are seconds (`LiveSetCoach.isHold`).
    private var isHold: Bool { LiveSetCoach.isHold(exercise.exerciseID) }

    /// Dumbbells and kettlebells are weighed per hand (`Prescription.isPerHand`).
    private var isPerHand: Bool {
        Prescription.isPerHand(ExerciseCatalog.exercise(id: exercise.exerciseID)?.load)
    }

    /// A drop stage or mini-set needs a working set to follow.
    private func canAddStage(to sets: [SetLog]) -> Bool {
        sets.last.map { !$0.isWarmup } ?? false
    }

    /// Adds a drop stage (at least 20% lighter, `TimeSaver.dropFraction`, rounded to the gym's
    /// loads: `TimeSaver.dropLoads`) or a rest-pause / myo-rep mini-set at the
    /// same weight after the last set.
    private func addStage(_ kind: SetKind) {
        guard let last = exercise.orderedSets.last, !last.isWarmup else { return }
        var weightKg = last.weightKg
        var reps = TimeSaver.stageReps(for: kind, reps: max(1, last.reps)...max(1, last.reps))
        if kind == .drop {
            reps = last.reps
            let loadKind = ExerciseCatalog.exercise(id: exercise.exerciseID)?.load ?? libraryLoadKind
            let current = gym.unit.fromKilograms(last.weightKg)
            if let loadKind, gym.has(loadKind),
               let lighter = TimeSaver.dropLoads(from: current, kind: loadKind, gym: gym, stages: 1).first {
                weightKg = gym.unit.toKilograms(lighter)
            } else if let loadKind, let rounded = gym.load(atMost: current * (1 - TimeSaver.dropFraction), on: loadKind),
                      rounded > 0 {
                weightKg = gym.unit.toKilograms(rounded)
            } else {
                weightKg = last.weightKg * (1 - TimeSaver.dropFraction)
            }
        }
        let set = SetLog(order: last.order + 1, weightKg: weightKg, reps: reps, rpe: nil, kind: kind)
        set.exercise = exercise
        modelContext.insert(set)
        try? modelContext.save()
    }

    private func loadLiveState() {
        target = SessionTargets.target(for: sessionStart, order: exercise.order)
        adjustment = AutoregulationLog.entry(for: sessionStart, order: exercise.order)
        progression = ProgressionPreferences.resolved(for: exercise.exerciseID, gym: gym, atKilograms: workingWeightKg)
    }

    // MARK: Targets and feedback

    /// The first working set's weight, for judging the gym's next jump.
    private var workingWeightKg: Double {
        exercise.orderedSets.first { !$0.isWarmup && $0.weightKg > 0 }?.weightKg ?? 0
    }

    /// Reps in reserve the plan asks for: the session's planned effort, else the block's week.
    private var targetRIR: Double? {
        // A hold is timed: no reps in reserve.
        guard !isHold else { return nil }
        return target?.targetRIR ?? blockRIR.map { Double($0) }
    }

    /// "3 × 7 · 82.5 kg" under the exercise name (`Prescription`,
    /// as in the builder): the plan's target shows once, beside last time's
    /// sets on the rows, so last time isn't the only goal (feature spec §3.1).
    /// Nil without a plan (an exercise added during the workout).
    private var planLine: String? {
        guard let target else { return nil }
        let working = exercise.sets.filter { !$0.isWarmup && !$0.kind.isStage }.count
        if isHold { return "\(max(1, working)) × \(target.repsToday) s hold" }
        var parts = [Prescription.sets(max(1, working), repsLow: target.repsLow, repsHigh: target.repsHigh,
                                       targetReps: target.repsToday, rpe: nil)]
        if let kg = target.loadKg, kg > 0 {
            let kind = ExerciseCatalog.exercise(id: exercise.exerciseID)?.load ?? libraryLoadKind
            // To 0.1, as the set rows show it (`WeightUnit.format`).
            parts.append(Prescription.load((unit.display(kg) * 10).rounded() / 10, unit: unit.rawValue, kind: kind))
        }
        return parts.joined(separator: " · ")
    }

    /// The verdict once a working set is ticked (`SetFeedback.verdict`).
    private func verdict(for set: SetLog, index: Int) -> SetFeedback.Verdict? {
        guard set.isCompleted, !set.isWarmup, !set.kind.isStage else { return nil }
        let logged = LiftProgress.LoggedSet(weight: unit.display(set.weightKg), reps: set.reps, rpe: set.rpe)
        let last = previousSet(index: index).map { LiftProgress.LoggedSet(weight: unit.display($0.weightKg), reps: $0.reps, rpe: $0.rpe) }
        // A set to failure is RPE 10 on purpose, and as many reps as you can:
        // no "harder than planned" and no "short".
        let targetRPE = set.kind == .failure ? nil : targetRIR.map { 10 - $0 }
        return SetFeedback.verdict(logged: logged, last: last,
                                   targetReps: verdictTargetReps(for: set),
                                   targetRPE: targetRPE)
    }

    /// The reps a ticked set is judged against; none for a set to failure.
    private func verdictTargetReps(for set: SetLog) -> Int? {
        set.kind == .failure ? nil : LiveSetCoach.targetReps(for: set, target: target, entry: adjustment)
    }

    /// The set-by-set change (or pain hold), while the set it changed is still to do.
    private func shownAdjustment(in sets: [SetLog]) -> AutoregulationLog.Entry? {
        guard let adjustment, adjustment.isShown,
              let changed = sets.first(where: { $0.order == adjustment.setOrder }),
              !changed.isCompleted else { return nil }
        return adjustment
    }

    /// Puts back the weights or reps the set-by-set change moved.
    private func undoAdjustment(_ entry: AutoregulationLog.Entry) {
        LiveSetCoach.undo(entry, in: exercise, sessionStart: sessionStart)
        adjustment = AutoregulationLog.entry(for: sessionStart, order: exercise.order)
        try? modelContext.save()
    }

    private func progressionLabel(_ mode: ProgressionMode) -> String {
        let suggested = ProgressionPreferences.suggested(for: exercise.exerciseID, gym: gym, atKilograms: workingWeightKg)
        return mode == suggested ? "\(mode.title) (suggested)" : mode.title
    }

    private var progressionBinding: Binding<ProgressionMode> {
        Binding(
            get: { progression },
            set: { mode in
                ProgressionPreferences.set(mode, for: exercise.exerciseID)
                progression = mode
            }
        )
    }

    private func setRest(_ seconds: Int?) {
        RestPreferences.set(seconds, for: exercise.exerciseID)
        restSeconds = seconds
    }

    /// Completes (or un-completes) a set; completing starts rest (short after
    /// a warm-up ramp set) and moves to the next set.
    private func toggle(_ set: SetLog) {
        set.completedAt = set.isCompleted ? nil : .now
        if set.isCompleted, !set.isWarmup { skipOpenWarmUps(before: set) }
        try? modelContext.save()
        if set.isCompleted {
            // Set-by-set effort check: may move the next set's load (`Autoregulation`).
            if !set.isWarmup, let entry = LiveSetCoach.autoregulate(after: set, in: exercise, sessionStart: sessionStart,
                                                                    gym: gym, blockRIR: blockRIR) {
                adjustment = entry
                try? modelContext.save()
            }
            focusedSetID = nil
            onSetCompleted(set)
        }
    }

    /// "Warm-up 1 of 3 · 50%": the ramp set's place and its share of the working weight.
    private func warmUpPosition(_ set: SetLog, in sets: [SetLog]) -> SetRow.WarmUpPosition {
        let ramps = sets.filter(\.isWarmup)
        let number = (ramps.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0) + 1
        let working = sets.first { !$0.isWarmup && $0.weightKg > 0 }?.weightKg
        // To the nearest 5%: the load is rounded to your plates, so "69%" was false precision.
        let percent = working.map { Int((set.weightKg / $0 * 20).rounded()) * 5 }
        return SetRow.WarmUpPosition(number: number, count: ramps.count, percent: percent)
    }

    /// A loaded catalog lift with no weight and no ramp sets: the planner had
    /// nothing to estimate from (`LoadEstimator`), so the first set finds it.
    private func needsWeightFinding(_ sets: [SetLog]) -> Bool {
        guard previous.isEmpty, !sets.contains(where: \.isWarmup),
              let first = sets.first, first.weightKg == 0, !first.isCompleted else { return false }
        return ExerciseCatalog.exercise(id: exercise.exerciseID)?.load != nil
    }

    /// Next/previous weight you can actually load with your gym's plates,
    /// dumbbells or stacks (falls back to 5 lb / 2.5 kg).
    private func step(_ set: SetLog, up: Bool) {
        let kind = ExerciseCatalog.exercise(id: exercise.exerciseID)?.load ?? libraryLoadKind
        let current = gym.unit.fromKilograms(set.weightKg)
        var next: Double?
        if let kind, gym.has(kind) {
            if up {
                next = gym.nextLoad(above: current + 0.001, on: kind)
            } else if let lighter = gym.achievableLoads(for: kind).last(where: { $0 < current - 0.001 }) {
                next = lighter
            }
            // Nothing lighter on this equipment (e.g. an empty 45 lb bar):
            // keep stepping down in small jumps, for a lighter or technique bar.
        }
        let fallback = gym.unit == .kg ? 2.5 : 5
        let value = next ?? max(0, current + (up ? fallback : -fallback))
        set.weightKg = gym.unit.toKilograms(value)
    }

    private var isNewPR: Bool {
        guard bestBefore > 0 else { return false }
        let best = exercise.sets.filter { $0.isCompleted && !$0.isWarmup && !$0.kind.isStage }.map(\.estimatedOneRepMax).max() ?? 0
        return best > bestBefore + 0.01
    }

    /// Last session's working set with the same number (warm-ups, drop stages and mini-sets don't count).
    private func previousText(index: Int) -> String {
        let working = previous.filter { !$0.isWarmup && !$0.kind.isStage }
        guard index >= 0, index < working.count else { return "" }
        let set = working[index]
        if isHold { return "\(set.reps) s" }
        // Reps left first, as the plan says it ("3 left"), not an RPE number.
        let effort = set.rpe.map { " · \(ReserveText.short(rpe: $0))" } ?? ""
        return "\(unit.format(set.weightKg)) × \(set.reps)\(effort)"
    }

    /// The same set from last session, for VoiceOver.
    private func previousSet(index: Int) -> SetLog? {
        let working = previous.filter { !$0.isWarmup && !$0.kind.isStage }
        guard index >= 0, index < working.count else { return nil }
        return working[index]
    }

    /// "45 + 25 per side" for barbell lifts, using your gym's plates.
    private func plateHint(for set: SetLog) -> String? {
        let plateKinds: [EquipmentKind] = [.barbell, .ezBar, .smithMachine]
        guard set.weightKg > 0,
              let kind = ExerciseCatalog.exercise(id: exercise.exerciseID)?.load ?? libraryLoadKind,
              plateKinds.contains(kind) else { return nil }
        let total = (gym.unit.fromKilograms(set.weightKg) * 4).rounded() / 4
        guard let plates = gym.plateBreakdown(total: total, on: kind) else {
            return "Can't make \(total.formatted()) \(gym.unit.rawValue) with your plates"
        }
        if plates.isEmpty { return "Empty bar" }
        return "Load \(plates.map { $0.formatted() }.joined(separator: " + ")) \(gym.unit.rawValue) per side"
    }

    private var libraryLoadKind: EquipmentKind? {
        switch library.exercise(id: exercise.exerciseID)?.equipment {
        case "barbell": .barbell
        case "e-z curl bar": .ezBar
        default: nil
        }
    }

    private func addSet() {
        let last = exercise.orderedSets.last
        let set = SetLog(order: (last?.order ?? -1) + 1, weightKg: last?.weightKg ?? 0, reps: last?.reps ?? 0, rpe: nil)
        set.exercise = exercise
        modelContext.insert(set)
        try? modelContext.save()
    }
}

/// A ramp set left out by ticking a working set first, kept for Undo.
private struct SkippedWarmUp: Equatable {
    var order: Int
    var weightKg: Double
    var reps: Int
}

/// "+ Add set", and beside it a "Set type" menu to add a drop stage,
/// rest-pause or myo-rep mini-set after the last set (`SetKind`). What each
/// one is and how good the evidence is sits behind the set editor's ⓘ.
private struct AddSetButtons: View {
    let canAddStage: Bool
    let onAddSet: () -> Void
    let onAddStage: (SetKind) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onAddSet) {
                Text("+ Add set")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.cardRaised, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            if canAddStage {
                stageMenu
            }
        }
    }

    private var stageMenu: some View {
        Menu {
            ForEach(SetKind.stageKinds) { kind in
                Button(kind.title) { onAddStage(kind) }
            }
        } label: {
            Label("Set type", systemImage: "plus.square.on.square")
                .font(.headline)
                .foregroundStyle(Theme.liftingText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.lifting.opacity(0.12), in: .rect(cornerRadius: 14))
        }
        .accessibilityLabel("Add a drop set, rest-pause or myo-rep mini-set")
    }
}

/// "3 warm-ups done ✓" (tap to show them), "1 warm-up done · 2 skipped",
/// or "2 warm-ups skipped" with Undo after a working set was ticked first.
private struct WarmUpsDoneRow: View {
    let count: Int
    var skipped = 0
    let isOpen: Bool
    let onToggle: () -> Void
    /// Puts the skipped ramp sets back; nil when none were skipped.
    var onUndoSkip: (() -> Void)? = nil

    private var text: String {
        let done = count == 1 ? "1 warm-up done" : "\(count) warm-ups done"
        let skip = skipped == 1 ? "1 warm-up skipped" : "\(skipped) warm-ups skipped"
        if skipped == 0 { return done }
        return count == 0 ? skip : "\(done) · \(skipped) skipped"
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    if count > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.recoveryHigh)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 4)
                    if count > 0 {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
            .accessibilityHint(count == 0 ? "" : (isOpen ? "Hides the warm-up sets" : "Shows the warm-up sets"))
            if let onUndoSkip {
                Button("Undo", action: onUndoSkip)
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Put the skipped warm-ups back")
            }
        }
        .padding(.horizontal, 12)
        .background(Theme.recoveryHigh.opacity(0.1), in: .rect(cornerRadius: 16))
    }
}

/// One set as a compact line; tap to edit it in the SetEditor.
///
/// VoiceOver reads the set as one element, e.g. "Set 2, 8 reps at 60
/// kilograms, RPE 8, done", and the tick button stays its own element so
/// VoiceOver and Voice Control can reach it (ux-audit.md 4.8, P27).
private struct SetRow: View {
    @Bindable var set: SetLog
    let label: String
    let previous: String
    let unit: WeightUnit
    let isEditing: Bool
    let onTap: () -> Void
    let onToggle: () -> Void
    /// Last session's matching set, for VoiceOver.
    var previousSet: SetLog? = nil
    /// For a warm-up ramp set: its place in the ramp and its share of the working weight.
    var warmUp: WarmUpPosition? = nil
    /// The one-line verdict once the set is ticked (`SetFeedback`).
    var verdict: SetFeedback.Verdict? = nil
    /// The reps the verdict was judged against ("2 short of 8").
    var verdictTargetReps: Int? = nil
    /// "Drop · no rest, lighter", "To failure": the set type (`SetKind`); nil for a normal set.
    var kindLine: String? = nil
    /// A plank or side plank: the reps are seconds.
    var isHold = false
    /// Dumbbells or kettlebells: the weight is per hand.
    var isPerHand = false

    struct WarmUpPosition {
        var number: Int
        var count: Int
        var percent: Int?
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Fits "W" or "12" at every text size.
    @ScaledMetric(relativeTo: .headline) private var labelWidth: CGFloat = 26

    var body: some View {
        if let warmUp {
            compactWarmUp(warmUp)
        } else {
            fullRow
        }
    }

    /// A ramp set on one line: "W2  50 kg × 5  70%  ○", still 44 pt tall to tap.
    private func compactWarmUp(_ warmUp: WarmUpPosition) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("W\(warmUp.number)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: labelWidth, alignment: .leading)
                Text(loadText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isFilled ? Theme.primaryText : Theme.secondaryText)
                if let percent = warmUp.percent {
                    Text("\(percent)%")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 4)
            }
            .contentShape(.rect)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenSummary)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Edit this set")
            .accessibilityAction { onTap() }
            .onTapGesture(perform: onTap)
            toggleButton
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 2)
        .background(rowBackground, in: .rect(cornerRadius: 14))
    }

    private var fullRow: some View {
        HStack(spacing: 10) {
            details
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenSummary)
                .accessibilityAddTraits(isEditing ? [.isButton, .isSelected] : [.isButton])
                .accessibilityHint("Edit this set")
                .accessibilityAction { onTap() }
            toggleButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground, in: .rect(cornerRadius: 16))
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.lifting.opacity(0.7), lineWidth: 2)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onTap)
    }

    private var isFilled: Bool { self.set.weightKg > 0 || set.reps > 0 }

    /// "60 kg × 8", "20 kg per hand × 10", "30 s" for a hold, or "Not set".
    private var loadText: String {
        guard isFilled else { return "Not set" }
        if isHold { return "\(set.reps) s" }
        let perHand = isPerHand ? " per hand" : ""
        return "\(unit.format(set.weightKg)) \(unit.rawValue)\(perHand) × \(set.reps)"
    }

    /// Number, weight × reps, last time and RPE. At accessibility text sizes
    /// the RPE pill moves under the weight so nothing is cut off.
    private var details: some View {
        HStack(spacing: 10) {
            if warmUp == nil {
                Text(label)
                    .font(.headline)
                    .foregroundStyle(set.isWarmup ? Theme.secondaryText : Theme.primaryText)
                    // "RP" for a rest-pause mini-set fits the number's width.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: labelWidth, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 1) {
                if let kindLine {
                    Text(kindLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.liftingText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(loadText)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(isFilled ? Theme.primaryText : Theme.secondaryText)
                ghostLine
                if let verdictText {
                    // Green for a good set, amber when short or past the plan's effort.
                    Text(verdictText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(verdict?.isCaution == true ? Theme.recoveryModerateText : Theme.recoveryHighText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    rpePill
                }
            }
            Spacer(minLength: 4)
            if !dynamicTypeSize.isAccessibilitySize {
                rpePill
            }
        }
    }

    /// Last session's same set in grey ("Last: 82.5 × 6 · 3 left"); the
    /// target is said once under the exercise name.
    @ViewBuilder
    private var ghostLine: some View {
        if !previous.isEmpty {
            Text("Last: \(previous)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
    }

    private var verdictText: String? {
        guard set.isCompleted, let verdict else { return nil }
        return verdict.message(unit: unit.rawValue, targetReps: verdictTargetReps)
    }

    @ViewBuilder
    private var rpePill: some View {
        if let rpe = set.rpe {
            Text(ReserveText.short(rpe: rpe))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.liftingText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.lifting.opacity(0.12), in: .capsule)
        }
    }

    private var toggleButton: some View {
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .fill(set.isCompleted ? Theme.recoveryHigh : Color.clear)
                Circle()
                    .strokeBorder(set.isCompleted ? Theme.recoveryHigh : Theme.secondaryText.opacity(0.4), lineWidth: 2)
                if set.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: set.isCompleted) { _, completed in completed }
        .accessibilityLabel(set.isCompleted ? "Undo \(spokenName.lowercased())" : "Mark \(spokenName.lowercased()) done")
    }

    /// "Set 2", "Warm-up set 1 of 3" or "Warm-up set".
    private var spokenName: String {
        if let warmUp { return "Warm-up set \(warmUp.number) of \(warmUp.count)" }
        return self.set.isWarmup ? "Warm-up set" : "Set \(label)"
    }

    /// "Set 2, 8 reps at 60 kilograms, 2 reps left, done".
    private var spokenSummary: String {
        var parts = [spokenName]
        if let kindLine { parts.append(kindLine) }
        parts.append(spokenLoad(weightKg: set.weightKg, reps: set.reps) ?? "not set")
        if let rpe = set.rpe { parts.append(ReserveText.spoken(rpe: rpe)) }
        parts.append(set.isCompleted ? "done" : "not done")
        if let previousSet, let last = spokenLoad(weightKg: previousSet.weightKg, reps: previousSet.reps) {
            parts.append("last time \(last)")
        }
        if let verdictText { parts.append(verdictText) }
        return parts.joined(separator: ", ")
    }

    /// "8 reps at 60 kilograms"; nil when nothing is filled in.
    private func spokenLoad(weightKg: Double, reps: Int) -> String? {
        guard weightKg > 0 || reps > 0 else { return nil }
        if isHold { return "\(reps) seconds" }
        let repsText = reps == 1 ? "1 rep" : "\(reps) reps"
        guard weightKg > 0 else { return repsText }
        let perHand = isPerHand ? " per hand" : ""
        return "\(repsText) at \(unit.format(weightKg)) \(unit.spokenName)\(perHand)"
    }

    private var rowBackground: Color {
        if set.isCompleted { return Theme.recoveryHigh.opacity(0.1) }
        if isEditing { return Theme.lifting.opacity(0.07) }
        return Theme.cardRaised.opacity(0.5)
    }
}

extension WeightUnit {
    /// The unit as VoiceOver should say it ("kilograms", "pounds").
    var spokenName: String {
        self == .kilograms ? "kilograms" : "pounds"
    }
}

/// Big, thumb-friendly controls for the set you're on: weight and reps with
/// +/- (weights step to what your gym can load), RPE buttons and Complete.
private struct SetEditor: View {
    @Bindable var set: SetLog
    let title: String
    /// The row's second line, kept here: "Last: 82.5 × 6 · 3 left", or the ramp's share.
    var subtitle: String? = nil
    /// The set type, settable here; nil for a warm-up.
    let kind: Binding<SetKind>?
    let unit: WeightUnit
    let step: (Bool) -> Void
    let plateHint: String?
    /// The plan's effort (RPE), marked on the picker; nil for none or a set to failure.
    var targetRPE: Double? = nil
    /// A plank or side plank: one seconds field, no weight and no effort.
    var isHold = false
    /// Dumbbells or kettlebells: the weight is per hand.
    var isPerHand = false
    /// The weight or reps were changed here (Finish asks about such a set if it's left unticked).
    var onEdited: () -> Void = {}
    let onComplete: () -> Void
    let onShowGuide: () -> Void
    /// The row's context-menu actions, since the row isn't drawn while editing.
    var onToggleWarmUp: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @FocusState private var typing: Field?
    private enum Field { case weight, reps }
    @State private var showingKindInfo = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            steppers
            if let plateHint {
                Label(plateHint, systemImage: "circle.grid.2x1")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            // Effort is rated once the set is done (the "reps left" strip asks after the tick);
            // a drop stage or mini-set is as many good reps as you can, and a hold is timed.
            if set.isCompleted, !set.isWarmup, !set.kind.isStage, !isHold {
                RPEPicker(rpe: $set.rpe, targetRPE: targetRPE, onShowGuide: onShowGuide)
            }
            Button(action: {
                typing = nil
                onComplete()
            }) {
                Label(set.isCompleted ? "Completed · tap to undo" : "Complete set", systemImage: set.isCompleted ? "arrow.uturn.backward" : "checkmark")
                    .font(.headline)
                    .foregroundStyle(set.isCompleted ? Theme.primaryText : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(set.isCompleted
                                ? AnyShapeStyle(Theme.cardRaised)
                                : AnyShapeStyle(LinearGradient(colors: Theme.recoveryButtonColors, startPoint: .leading, endPoint: .trailing)),
                                in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("complete-set") // UI tests (ScreenshotTests)
        }
        .padding(14)
        .background(Theme.lifting.opacity(0.07), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.lifting.opacity(0.7), lineWidth: 2))
    }

    /// "SET 2 · TO FAILURE" with last time under it, an ⓘ for a set type
    /// (how to do it, how good the evidence is) and a menu with the set type,
    /// warm-up and delete.
    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.liftingText)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
            if set.kind != .straight, !set.isWarmup {
                Button { showingKindInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(set.kind.title)")
                .popover(isPresented: $showingKindInfo) {
                    SetKindInfo(kind: set.kind)
                        .presentationCompactAdaptation(.popover)
                }
            }
            Spacer(minLength: 0)
            setMenu
        }
    }

    private var setMenu: some View {
        Menu {
            if let kind {
                Picker(selection: kind) {
                    ForEach(SetKind.allCases) { option in
                        Text(option.title).tag(option)
                    }
                } label: {
                    Label("Set type", systemImage: "square.stack.3d.down.right")
                }
                .pickerStyle(.menu)
            }
            if let onToggleWarmUp {
                Button(set.isWarmup ? "Make working set" : "Make warm-up set", action: onToggleWarmUp)
            }
            if let onDelete {
                Button("Delete set", systemImage: "trash", role: .destructive, action: onDelete)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("Set options")
    }

    /// Weight and reps side by side; one above the other at accessibility
    /// text sizes, so the numbers keep their size (ux-audit.md 4.8, P22).
    private var steppers: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if !isHold {
                NumberStepper(label: isPerHand ? "\(unit.rawValue) per hand" : unit.rawValue, spokenLabel: "weight") {
                    // Applied as you type, so a tick here or on the Watch uses it (`LiveNumberField`).
                    LiveNumberField(value: unit.display(set.weightKg), decimals: true, isFocused: typing == .weight) { value in
                        set.weightKg = unit.toKilograms(value)
                        onEdited()
                    }
                    .focused($typing, equals: .weight)
                    .accessibilityLabel("Weight in \(unit.spokenName)")
                } minus: { step(false) } plus: { step(true) }
            }
            NumberStepper(label: isHold ? "seconds" : "reps") {
                LiveNumberField(value: Double(set.reps), decimals: false, isFocused: typing == .reps) { value in
                    set.reps = Int(value)
                    onEdited()
                }
                .focused($typing, equals: .reps)
                .accessibilityLabel(isHold ? "Seconds" : "Reps")
            } minus: {
                set.reps = max(0, set.reps - 1)
                onEdited()
            } plus: {
                set.reps += 1
                onEdited()
            }
        }
    }
}

/// A weight or rep count typed into a text field and applied as you type
/// (`LiveWorkoutRules.parseNumber`, which takes "62,5" too). A value-format
/// text field only commits when it loses focus, and the decimal pad has no
/// return key, so a tick (here or on the Watch) used to log the old number.
/// While the field isn't being typed in, it follows the value (+/-, the Watch).
private struct LiveNumberField: View {
    let value: Double
    let decimals: Bool
    let isFocused: Bool
    let onChange: (Double) -> Void

    @State private var text = ""

    var body: some View {
        TextField("0", text: $text)
            .keyboardType(decimals ? .decimalPad : .numberPad)
            .onAppear { text = Self.format(value, decimals: decimals) }
            .onChange(of: value) { _, newValue in
                // Moved elsewhere (+/-, the Watch): show it, unless it's what's being typed.
                if let typed = LiveWorkoutRules.parseNumber(text), abs(typed - newValue) < 0.005 { return }
                text = Self.format(newValue, decimals: decimals)
            }
            .onChange(of: text) { _, newText in
                guard isFocused, let parsed = LiveWorkoutRules.parseNumber(newText) else { return }
                onChange(decimals ? parsed : parsed.rounded(.down))
            }
            .onChange(of: isFocused) { _, focused in
                // Done typing: tidy the text ("62." → "62", an emptied field back to the value).
                if !focused { text = Self.format(value, decimals: decimals) }
            }
    }

    private static func format(_ value: Double, decimals: Bool) -> String {
        decimals
            ? value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
            : value.formatted(.number.grouping(.never).precision(.fractionLength(0)))
    }
}

/// How to do a set type and how good the evidence for it is (`SetKind`).
private struct SetKindInfo: View {
    let kind: SetKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.title)
                .font(.headline)
            Text(kind.howTo)
                .font(.subheadline)
            Text(kind.evidence)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 320, alignment: .leading)
        .padding()
    }
}

/// [-]  value  [+] with large tap targets; tap the number to type.
private struct NumberStepper<Field: View>: View {
    let label: String
    /// What VoiceOver calls the value on the +/- buttons ("weight"); `label` if nil.
    var spokenLabel: String? = nil
    @ViewBuilder var field: Field
    let minus: () -> Void
    let plus: () -> Void
    /// Scales with Dynamic Type (ux-audit W5).
    @ScaledMetric(relativeTo: .title) private var valueSize: CGFloat = 28

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                stepButton("minus", action: minus)
                field
                    .font(.system(size: valueSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .minimumScaleFactor(0.6)
                stepButton("plus", action: plus)
            }
            .padding(4)
            .background(Theme.card, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.separator))
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.lifting)
                .frame(width: 44, height: 44)
                .background(Theme.lifting.opacity(0.12), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == "plus" ? "Increase \(spokenLabel ?? label)" : "Decrease \(spokenLabel ?? label)")
    }
}

/// "How many more reps could you have done?" with big 0 / 1 / 2 / 3 / 4+
/// buttons and a ½ toggle ("2½ left"). Reps left lead because lifters found
/// RPE numbers confusing; the RPE is the small label under each button and is
/// what's stored (RPE = 10 − reps left; Zourdos et al., J Strength Cond Res
/// 2016; `ReserveText.rpe(repsLeft:)`). The plan's target is outlined and
/// marked "plan", not filled in: an effort you didn't log isn't logged.
private struct RPEPicker: View {
    @Binding var rpe: Double?
    var targetRPE: Double? = nil
    let onShowGuide: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            buttons
                .sensoryFeedback(.selection, trigger: rpe)
            // One line: the reps left, then the RPE. What each feels like is in the guide.
            Text(rpe.map { RPEScale.summary($0) } ?? emptyHint)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// "Plan: 3 left · optional" with no effort logged yet; the target is outlined.
    private var emptyHint: String {
        guard let targetRPE else { return "Optional · 0 = you couldn't do another rep" }
        return "Plan: \(ReserveText.short(rpe: targetRPE)) · optional"
    }

    /// The button the plan's target falls on, for the outline.
    private var targetChoice: Int? {
        targetRPE.map { ReserveText.choice(rpe: $0) }
    }

    /// The question (wraps at large text sizes) and an ⓘ for the guide.
    private var header: some View {
        HStack(alignment: .center, spacing: 4) {
            Text("How many more reps could you have done?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onShowGuide) {
                Image(systemName: "info.circle")
                    .font(.subheadline)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("What reps left means")
        }
    }

    /// One row of six; at accessibility text sizes two rows of three, so the
    /// numbers aren't cut off (ux-audit.md 4.8, P22).
    @ViewBuilder
    private var buttons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(ReserveText.repsLeftChoices, id: \.self) { left in
                    leftButton(left)
                }
                halfButton(fillsWidth: true)
            }
        } else {
            HStack(spacing: 6) {
                ForEach(ReserveText.repsLeftChoices, id: \.self) { left in
                    leftButton(left)
                }
                halfButton(fillsWidth: false)
            }
        }
    }

    private func leftButton(_ left: Int) -> some View {
        let value = ReserveText.rpe(repsLeft: left)
        let selected = rpe.map { ReserveText.choice(rpe: $0) == left } ?? false
        let isTarget = targetChoice == left
        let outlined = rpe == nil && isTarget
        let caption = isTarget ? "plan" : "RPE \(value.formatted())"
        return Button {
            if selected && rpe == value { rpe = nil } else { rpe = value }
        } label: {
            VStack(spacing: 0) {
                Text(ReserveText.choiceLabel(left))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : (isTarget ? Theme.liftingText : Theme.secondaryText))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(selected ? .white : Theme.primaryText)
            .background(selected ? AnyShapeStyle(Theme.lifting) : AnyShapeStyle(Theme.card), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Color.clear : (outlined ? Theme.lifting : Theme.separator), lineWidth: outlined ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(left >= 4 ? "4 or more reps left" : ReserveText.spoken(rpe: value))
        .accessibilityHint(isTarget ? "The plan's target" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Half a rep more left: 2 → "2½ left" (RPE 8 → 7.5), and back.
    private func halfButton(fillsWidth: Bool) -> some View {
        Button {
            guard let current = rpe, current > 6 else { return }
            rpe = current.truncatingRemainder(dividingBy: 1) == 0 ? current - 0.5 : current + 0.5
        } label: {
            Text("½")
                .font(.title3.weight(.bold))
                .frame(minWidth: 44, maxWidth: fillsWidth ? CGFloat.infinity : 44, minHeight: 52)
                .foregroundStyle(isHalf ? .white : Theme.primaryText)
                .background(isHalf ? AnyShapeStyle(Theme.lifting) : AnyShapeStyle(Theme.card), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isHalf ? Color.clear : Theme.separator))
        }
        .buttonStyle(.plain)
        .disabled(rpe.map { $0 <= 6 } ?? true)
        .accessibilityLabel("Add half a rep left")
        .accessibilityAddTraits(isHalf ? .isSelected : [])
    }

    private var isHalf: Bool {
        rpe.map { $0.truncatingRemainder(dividingBy: 1) != 0 } ?? false
    }
}

private struct CollapsedExerciseRow: View {
    let exercise: ExerciseLog
    let isDone: Bool
    let isNext: Bool
    let unit: WeightUnit
    /// 1-based position in the workout.
    var position: Int
    /// "A1" / "A2" when this exercise is half of a superset.
    var supersetLabel: String? = nil
    /// The plan's reps and effort (`SessionTargets`), for the same line the builder shows.
    var target: SessionTargets.Target? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Fits "A1" or "12" at every text size.
    @ScaledMetric(relativeTo: .headline) private var badgeSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 14) {
            badge
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                // At accessibility text sizes the chip goes under the name (ux-audit.md 4.8).
                if isNext && dynamicTypeSize.isAccessibilitySize {
                    Chip(text: "Up next", color: Theme.lifting)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if isNext && !dynamicTypeSize.isAccessibilitySize {
                Chip(text: "Up next", color: Theme.lifting)
            }
            // Always there, "Up next" or not: the row opens.
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .card()
    }

    @ViewBuilder
    private var badge: some View {
        if isDone {
            Image(systemName: "checkmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: badgeSize, height: badgeSize)
                .background(Theme.recoveryHigh, in: .circle)
                .accessibilityLabel("Done")
        } else {
            Text(supersetLabel ?? "\(position)")
                .font(.headline)
                // Text colour for the superset accent (ux-audit.md X4, P24).
                .foregroundStyle(supersetLabel == nil ? Theme.secondaryText : Theme.sleepText)
                .frame(width: badgeSize, height: badgeSize)
                .background(Theme.cardRaised, in: .circle)
        }
    }

    private var summary: String {
        let working = exercise.sets.filter { !$0.isWarmup && !$0.kind.isStage }
        // A plank or side plank: seconds, no weight or reps in reserve.
        if LiveSetCoach.isHold(exercise.exerciseID) {
            let seconds = working.map(\.reps).max() ?? target?.repsToday ?? 0
            return "\(working.count) × \(seconds) s hold" + (isDone ? " · done" : "")
        }
        if isDone, let best = working.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }) {
            let perHand = Prescription.isPerHand(ExerciseCatalog.exercise(id: exercise.exerciseID)?.load) ? " per hand" : ""
            return "\(working.count) sets · \(unit.format(best.weightKg)) \(unit.rawValue)\(perHand) × \(best.reps) · done"
        }
        // The first working set still to do (else the first), not a warm-up ramp or a drop stage:
        // "3 × 7 · 82.5 kg", as the exercise header says it (`Prescription`).
        let ordered = working.sorted { $0.order < $1.order }
        let first = ordered.first(where: { !$0.isCompleted }) ?? ordered.first
        let reps = first?.reps ?? target?.repsToday
        var parts = [reps.map { "\(working.count) × \($0)" } ?? "\(working.count) sets"]
        if let first, first.weightKg > 0 {
            let kind = ExerciseCatalog.exercise(id: exercise.exerciseID)?.load
            let value = (unit.display(first.weightKg) * 10).rounded() / 10
            parts.append(Prescription.load(value, unit: unit.rawValue, kind: kind))
        }
        return parts.joined(separator: " · ")
    }
}

/// The rest countdown, what's next ("Next: Bench Press · Set 2 of 3 · 82.5 kg
/// × 7") and −15s / +15s / Skip, in thumb reach. Neutral colours: pink is the
/// set you're on, green what's done.
private struct RestTimerPill: View {
    let endsAt: Date
    let length: TimeInterval
    var next: String? = nil
    /// +/- seconds, or nil to skip.
    let onChange: (TimeInterval?) -> Void

    /// At accessibility text sizes the buttons go under the time, so the
    /// pill doesn't clip (ux-audit.md 4.8, P22).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            // At zero the screen swaps this for `RestDonePill` (green, one tap).
            content(remaining: remaining)
        }
    }

    /// One line when it fits; otherwise the buttons go under the time
    /// (large text, small phones), never wrapping inside a button.
    private func content(remaining: TimeInterval) -> some View {
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                pill(remaining: remaining, stacked: false)
            }
            pill(remaining: remaining, stacked: true)
        }
    }

    private func pill(remaining: TimeInterval, stacked: Bool) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        // A capsule for one line; rounded when it wraps or has the "Next" line.
        let shape = stacked || next != nil ? AnyShape(RoundedRectangle(cornerRadius: 22)) : AnyShape(Capsule())
        return VStack(alignment: .leading, spacing: 4) {
            layout {
                countdown(remaining: remaining)
                if !stacked { Spacer() }
                controls
            }
            if let next {
                Text(next)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(stacked ? 3 : 1)
                    .truncationMode(.middle)
            }
        }
        .foregroundStyle(Theme.primaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: shape)
        .overlay(shape.stroke(Theme.separator))
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
    }

    private func countdown(remaining: TimeInterval) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: length > 0 ? remaining / length : 0)
                    .stroke(Theme.lifting, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
            Text("Rest \(Duration.seconds(remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond)))")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("Rest")
                .accessibilityValue(Duration.seconds(remaining.rounded(.up)).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// −15s, +15s and Skip, each at least 44 × 44 pt (HIG; ux-audit.md 4.8, P23).
    private var controls: some View {
        HStack(spacing: 8) {
            pillButton("−15s", spoken: "15 seconds less") { onChange(-15) }
            pillButton("+15s", spoken: "15 seconds more") { onChange(15) }
            pillButton("Skip", spoken: "Skip rest") { onChange(nil) }
        }
    }

    private func pillButton(_ title: String, spoken: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(minWidth: 44, minHeight: 44)
            .background(Theme.cardRaised, in: .capsule)
            .contentShape(.capsule)
            .buttonStyle(.plain)
            .accessibilityLabel(spoken)
    }
}

/// One line under the pinned header: "Upper Body · 4/21 sets · ♥ 124 Zone 1 ·
/// +2% strain". Progress is in working sets, not exercises; heart rate comes
/// from the iPhone workout session (AirPods Pro 3 or a chest strap), its zone
/// from heart-rate reserve (`HeartRateProfile.zone`). Parts drop off, the
/// zone first, when the line doesn't fit.
private struct SessionStrip: View {
    let name: String
    let doneSets: Int
    let totalSets: Int
    /// Strain this session has added so far (`DailyMetricsModel.strainGain`), 0-100.
    let strainGain: Double
    let recorder: LiveWorkoutRecorder
    let profile: HeartRateProfile?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(showName: true, showZone: true)
            line(showName: true, showZone: false)
            line(showName: false, showZone: false)
        }
        .font(.subheadline)
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func line(showName: Bool, showZone: Bool) -> some View {
        HStack(spacing: 6) {
            if showName {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                dot
            }
            Text("\(doneSets)/\(totalSets) sets")
                .monospacedDigit()
                .fixedSize()
            heart(showZone: showZone)
            dot
            Text(strainLabel)
                .monospacedDigit()
                .fixedSize()
        }
        .lineLimit(1)
    }

    private var dot: some View {
        Text("·").accessibilityHidden(true)
    }

    @ViewBuilder
    private func heart(showZone: Bool) -> some View {
        if let bpm = recorder.heartRate {
            dot
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.heart)
                    .symbolEffect(.pulse)
                Text("\(whole(bpm))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
                if showZone, let zone = zoneText(bpm) {
                    Text(zone)
                }
            }
            .fixedSize()
        } else if recorder.problem != nil {
            dot
            Image(systemName: "heart.slash")
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// "Zone 2" (heart-rate reserve zones), or nil without a profile or below zone 1.
    private func zoneText(_ bpm: Double) -> String? {
        guard let zone = profile?.zone(for: bpm) else { return nil }
        return "Zone \(zone)"
    }

    /// "+2% strain"; "+<1% strain" until it rounds to 1, so the start doesn't read "+0%".
    private var strainLabel: String {
        strainGain < 0.5 ? "+<1% strain" : "+\(strainText(strainGain)) strain"
    }

    private var spoken: String {
        var parts = [name, "\(doneSets) of \(totalSets) working sets done"]
        if let bpm = recorder.heartRate {
            var heart = "heart rate \(whole(bpm))"
            if let zone = zoneText(bpm) { heart += ", \(zone)" }
            if let average = recorder.averageHeartRate { heart += ", average \(whole(average))" }
            parts.append(heart)
        } else if let problem = recorder.problem {
            parts.append(problem)
        }
        parts.append(strainGain < 0.5 ? "under 1 percent strain added" : "\(whole(strainGain)) percent strain added")
        return parts.joined(separator: ", ")
    }
}

/// "How many more reps could you have done?" with 0 / 1 / 2 / 3 / 4+ after
/// a working set ticked with the circle (no effort logged): one tap logs it
/// and sets the next set's rep goal (`RepGoal`), as rating it in the editor
/// would. No plan number is marked: the lifter works to the rep goal.
private struct RepsLeftStrip: View {
    let onPick: (Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        // The question above the buttons, so each button stays at least 44 pt wide.
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                question
                Spacer(minLength: 0)
                dismissButton
            }
            buttons
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .background(Theme.card, in: .rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Theme.separator))
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How many more reps could you have done?")
    }

    private var question: some View {
        Text("How many more reps could you have done?")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.primaryText)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            ForEach(ReserveText.repsLeftChoices, id: \.self) { left in
                choiceButton(left)
            }
        }
        .padding(.trailing, 10)
    }

    private func choiceButton(_ left: Int) -> some View {
        Button { onPick(left) } label: {
            Text(ReserveText.choiceLabel(left))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.liftingText)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                .background(Theme.lifting.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(left >= 4 ? "4 or more reps left" : ReserveText.spoken(rpe: ReserveText.rpe(repsLeft: left)))
        .accessibilityHint("Sets the next set's rep goal")
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Don't log effort")
    }
}

/// Drag the exercises into a new order. The session's per-order data
/// (targets, set-by-set changes, supersets) moves with them (`applyReorder`).
private struct ReorderExercisesSheet: View {
    let session: WorkoutSession
    /// Old order → new order, for the exercises that moved.
    let onDone: ([Int: Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [Item] = []

    struct Item: Identifiable, Equatable {
        var id: Int { order }
        var order: Int
        var name: String
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    Text(item.name)
                }
                .onMove { from, to in items.move(fromOffsets: from, toOffset: to) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(mapping)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            items = session.orderedExercises.map { Item(order: $0.order, name: $0.name) }
        }
    }

    /// The old orders, sorted, handed out in the new sequence (so orders stay unique).
    private var mapping: [Int: Int] {
        let slots = items.map(\.order).sorted()
        var result: [Int: Int] = [:]
        for (index, item) in items.enumerated() where slots[index] != item.order {
            result[item.order] = slots[index]
        }
        return result
    }
}

// MARK: - Set feedback

/// The PRs shown when an exercise's last set is ticked.
struct RecordBanner: Equatable {
    /// The exercise's order in the session.
    var order: Int
    var exercise: String
    /// "Best estimated 1RM: 103 kg", "Most reps at 80 kg: 9"...
    var lines: [String]

    var spokenText: String {
        "Personal record, \(exercise). " + lines.joined(separator: ". ")
    }
}

/// A short, factual PR banner: no confetti, no streak (behaviour-change.md;
/// feature spec §3.1). It goes after a few seconds or on tap of ×.
private struct RecordBannerView: View {
    let banner: RecordBanner
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemName: "star.fill", color: Theme.lifting, size: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Personal record · \(banner.exercise)")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                ForEach(banner.lines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .card()
    }
}

/// "Next set 62.5 kg (you had 3 reps in the tank)": the set-by-set change
/// (`Autoregulation`), already applied to the next set and editable there,
/// with Undo; or "Held: easing your knee" when the pain cap stopped one.
/// Why it can be off sits behind ⓘ.
private struct AdjustmentNote: View {
    let text: String
    /// Puts the sets back; nil when nothing was changed (a pain hold).
    let onUndo: (() -> Void)?
    /// The pain cap held the load (`PainGuard.loadCapFraction`), rather than a change.
    var isPainHold = false

    @State private var showingInfo = false

    private var info: String {
        let percent = Int(((1 - PainGuard.loadCapFraction) * 100).rounded())
        return isPainHold
            ? "While it hurts, the plan keeps this lift about \(percent)% lighter and doesn't add weight or reps. That cap is an app choice, not a tested number."
            : "From your effort rating, which can be a rep or so off (Halperin et al., Sports Med 2022). Change the weight if it feels wrong."
    }

    var body: some View {
        HStack(spacing: 8) {
            Label(text, systemImage: isPainHold ? "hand.raised" : "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.liftingText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { showingInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPainHold ? "Why the load is held" : "Why the next set changed")
            .popover(isPresented: $showingInfo) {
                Text(info)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300, alignment: .leading)
                    .padding()
                    .presentationCompactAdaptation(.popover)
            }
            if let onUndo {
                Button("Undo", action: onUndo)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityLabel("Undo the change to the next set")
            }
        }
    }
}

/// The workout screen's "Discard this workout?" dialog and "Still training?"
/// alert, with what runs around them: asking again when the app comes back
/// to the foreground, and deleting a discarded session once the screen has
/// gone (deleting it under a visible screen could crash a view still reading
/// it). A modifier of its own to keep `ActiveWorkoutView`'s chain short.
private struct DiscardAndForgottenAlerts: ViewModifier {
    @Binding var showingDiscard: Bool
    @Binding var askingStillTraining: Bool
    let discardMessage: String
    /// When the last set was ticked; nil before any.
    let lastTick: Date?
    let onDiscard: () -> Void
    /// "End at 6:42 PM": the finish sheet opens with that end.
    let onEndAt: (Date) -> Void
    let onKeepGoing: () -> Void
    /// Back in the foreground: check for a forgotten workout.
    let onActive: () -> Void
    let onDisappear: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Discard this workout?", isPresented: $showingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { onDiscard() }
            } message: {
                Text(discardMessage)
            }
            .alert("Still training?", isPresented: $askingStillTraining) {
                stillTrainingButtons
            } message: {
                Text("No sets logged for over 4 hours.")
            }
            // Back from the background hours later: ask then too.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { onActive() }
            }
            .onDisappear { onDisappear() }
    }

    /// End at the last set, or discard when nothing was logged; or keep going.
    @ViewBuilder
    private var stillTrainingButtons: some View {
        if let last = lastTick {
            Button("End at \(last.formatted(date: .omitted, time: .shortened))") { onEndAt(last) }
        } else {
            Button("Discard workout", role: .destructive) { showingDiscard = true }
        }
        Button("Keep going", role: .cancel) { onKeepGoing() }
    }
}
