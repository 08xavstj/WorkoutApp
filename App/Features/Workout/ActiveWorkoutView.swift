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
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var showingPicker = false
    @State private var showingFinish = false
    @State private var showingDiscard = false
    @State private var expanded: Set<PersistentIdentifier> = []
    @State private var savedTemplate = false
    /// Exercise order → superset group for this session (`SupersetRegistry`).
    @State private var supersetGroups: [Int: Int] = [:]
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 52
    /// Strain number inside the ring; scales with Dynamic Type (ux-audit W5).
    @ScaledMetric(relativeTo: .title2) private var ringValueSize: CGFloat = 26
    /// At accessibility text sizes the strain ring goes under the timer
    /// instead of beside it, so neither is squeezed (ux-audit.md 4.8, P22).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerBar
                    titleBlock
                    LiveHeartRateBar(recorder: recorder, profile: metrics.heartRateProfile)
                    // Reads the shared timer each second, so +15s / Skip on the
                    // Lock Screen show up here too.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if let ends = RestTimerStore.endsAt {
                            RestTimerPill(endsAt: ends, length: RestTimerStore.length) { change in
                                if let change {
                                    RestTimerStore.adjust(by: change)
                                } else {
                                    RestTimerStore.stop()
                                }
                                Task { await WorkoutLiveActivity.refresh() }
                                WatchSync.shared.update(from: session) // Apple Watch rest timer
                            }
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
                .padding(.bottom, 32)
                .lockedToScreenWidth()
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
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exercise in add(exercise) }
            }
            .sheet(isPresented: $showingFinish) {
                FinishWorkoutSheet(session: session) {
                    WatchSync.shared.sessionFinished(session) // Apple Watch: end its recording
                    dismiss()
                }
                .presentationDetents([.medium])
            }
            // Apple Watch (`WatchSync`): the wrist gets the session whenever a set, exercise
            // or rest changes; the Watch's Finish opens the finish sheet here.
            .onChange(of: watchFingerprint, initial: true) { _, _ in
                WatchSync.shared.update(from: session)
            }
            .onChange(of: launcher.pendingFinish, initial: true) { _, pending in
                guard pending else { return }
                launcher.pendingFinish = false
                showingFinish = true
            }
            .task {
                supersetGroups = SupersetRegistry.groups(for: session.startedAt)
                guard session.isActive else { return }
                // Movement warm-up (`WarmUpRoutine`) for a session that just started, per the
                // Settings tier; ramp sets are separate (`WarmUp`). The session doesn't store
                // its focus, so the general tier applies.
                WarmUpStore.shared.prepareIfNeeded(
                    sessionStart: session.startedAt,
                    tier: settings.warmUpTier(for: nil),
                    firstSlots: session.orderedExercises.compactMap { ExerciseCatalog.slot(for: $0.exerciseID) },
                    gym: gym.profile
                )
                WatchSync.shared.update(from: session) // the first snapshot went out before the warm-up existed
                // Lock Screen / Dynamic Island: elapsed time, next set and rest timer.
                let next = nextSetText()
                await WorkoutActivityController.startIfNeeded(
                    name: session.name, startedAt: session.startedAt, exercise: next.exercise, detail: next.detail
                )
                // Live heart rate from AirPods Pro 3 or a Bluetooth strap while this workout runs.
                if recorder.sessionStart != session.startedAt {
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
            .alert("Added to saved workouts", isPresented: $savedTemplate) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Start it again any time from Log › Saved workouts (also under Fitness › Workouts). Weights will be suggested from what you lift.")
            }
            .confirmationDialog("Discard this workout?", isPresented: $showingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    if recorder.sessionStart == session.startedAt { recorder.discard() }
                    WatchSync.shared.sessionDiscarded(session) // Apple Watch: drop its recording
                    Task { await WorkoutLiveActivity.endAll() }
                    modelContext.delete(session)
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
    }

    // MARK: Header

    private var headerBar: some View {
        HStack {
            Menu {
                Button("Minimize", systemImage: "chevron.down") { dismiss() }
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
                Button("Discard workout", systemImage: "trash", role: .destructive) { showingDiscard = true }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: .circle)
                    .shadow(color: Color.black.opacity(0.07), radius: 9, y: 4)
            }
            .accessibilityLabel("Workout options")
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(Theme.recoveryLow).frame(width: 8, height: 8)
                Text("LIVE").tracking(1.5)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.recoveryLowText)
            Spacer()
            Button {
                showingFinish = true
            } label: {
                Text("Finish")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .frame(minHeight: 44)
                    .background(Theme.lifting, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(session.workingSets.isEmpty)
            .opacity(session.workingSets.isEmpty ? 0.5 : 1)
        }
        .padding(.top, 8)
    }

    private var titleBlock: some View {
        TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(session.startedAt))
            titleContent(elapsed: elapsed, live: liveStrain(elapsed: elapsed))
        }
    }

    /// Name, timer and progress beside the strain ring; stacked at
    /// accessibility text sizes.
    private func titleContent(elapsed: TimeInterval, live: Double) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center))
        return layout {
            titleText(elapsed: elapsed)
            if !stacked { Spacer() }
            strainRing(live)
        }
    }

    private func titleText(elapsed: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("Workout name", text: $session.name)
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.primaryText)
            Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2))))
                .font(.system(size: timerSize, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
                .accessibilityLabel("Elapsed time")
                .accessibilityValue(Duration.seconds(elapsed).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))
            Text("Elapsed · \(finishedExercises) of \(session.exercises.count) exercises")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            if session.workingSets.isEmpty {
                Text("Tick off a set to finish.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func strainRing(_ live: Double) -> some View {
        GradientRing(progress: ringProgress(live), colors: [Theme.strainLight, Theme.strain], lineWidth: 11) {
            VStack(spacing: 0) {
                Text("+\(strainText(live))")
                    .font(.system(size: ringValueSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("strain")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(Theme.primaryText)
        }
        .frame(width: 112, height: 112)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Strain added so far")
        .accessibilityValue("+\(strainText(live)), \(whole(ringProgress(live) * 100)) percent of the way to the top of today's range")
    }

    /// The ring fills as the session uses up the room left to the top of
    /// today's strain range (the whole 0-100 scale when there's no range
    /// yet). It used to be full at +40%, which looked like a cap.
    private func ringProgress(_ live: Double) -> Double {
        let current = metrics.strain?.strain ?? 0
        let top = metrics.targetStrain?.upperBound ?? StrainCalculator.maximum
        let room = top - current
        guard room > 1 else { return 1 }
        return min(1, max(0, live / room))
    }

    private var finishedExercises: Int {
        session.exercises.filter { !$0.sets.isEmpty && $0.sets.allSatisfy(\.isCompleted) }.count
    }

    /// Changes whenever a set is ticked, added or removed, so the Watch is told (`WatchSync`).
    private var watchFingerprint: String {
        let sets = session.exercises.flatMap(\.sets)
        return "\(session.exercises.count)/\(sets.count)/\(sets.filter(\.isCompleted).count)/\(session.name)"
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
    private var workoutUnit: WeightUnit { gym.profile.unit == .kg ? .kilograms : .pounds }

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
                previous: LiftHistory.previousSets(for: exercise.exerciseID, before: session.startedAt, in: sessions),
                bestBefore: LiftHistory.bestOneRepMax(for: exercise.exerciseID, before: session.startedAt, in: sessions),
                unit: workoutUnit,
                gym: gym.profile,
                onSetCompleted: { afterWarmUp in startRest(for: exercise, afterWarmUp: afterWarmUp) },
                onCollapse: { expanded.remove(exercise.persistentModelID) },
                supersetLabel: supersetLabel(exercise)
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
                    supersetLabel: supersetLabel(exercise)
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
        // Superset: no rest between the first lift and its partner, one rest after both
        // (paired sets, Iversen et al., Sports Med 2021; `Supersets`).
        if let mate = partner(of: exercise), mate.order > exercise.order,
           mate.sets.contains(where: { !$0.isCompleted }) {
            let next = nextSetText()
            Task { await WorkoutLiveActivity.refresh(exercise: next.exercise, detail: next.detail) }
            return
        }
        let seconds = RestPreferences.resolved(for: exercise.exerciseID, style: gym.style)
        RestTimerStore.start(seconds: Double(seconds))
        let next = nextSetText()
        Task { await WorkoutLiveActivity.refresh(exercise: next.exercise, detail: next.detail) }
    }

    /// The next set to do, for the Live Activity ("Bench Press", "Set 3 of 4 · 135 lb × 8";
    /// warm-up ramp sets read "Warm-up 2 of 3").
    private func nextSetText() -> (exercise: String, detail: String) {
        for exercise in session.orderedExercises {
            let sets = exercise.orderedSets
            guard let index = sets.firstIndex(where: { !$0.isCompleted }) else { continue }
            let set = sets[index]
            let same = sets.filter { $0.isWarmup == set.isWarmup }
            let number = (same.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0) + 1
            var detail = "\(set.isWarmup ? "Warm-up" : "Set") \(number) of \(same.count)"
            if set.weightKg > 0 || set.reps > 0 {
                detail += " · \(workoutUnit.format(set.weightKg)) \(workoutUnit.rawValue) × \(set.reps)"
            }
            return (exercise.name, detail)
        }
        return ("All sets done", "Tap Finish when you're ready")
    }

    private func add(_ exercise: Exercise) {
        let log = ExerciseLog(exerciseID: exercise.id, name: exercise.name, order: session.exercises.count)
        log.session = session
        modelContext.insert(log)
        let firstSet = SetLog(order: 0)
        firstSet.exercise = log
        modelContext.insert(firstSet)
        try? modelContext.save()
        expanded.insert(log.persistentModelID)
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
    /// Called with true after a warm-up ramp set, false after a working set.
    let onSetCompleted: (_ afterWarmUp: Bool) -> Void
    let onCollapse: () -> Void
    /// "A1" / "A2" when this exercise is half of a superset.
    var supersetLabel: String? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(ExerciseLibrary.self) private var library
    /// The set open in the editor (defaults to the next set to do).
    @State private var focusedSetID: PersistentIdentifier?
    @State private var showingRPEGuide = false
    @State private var confirmingRemove = false
    @State private var showingProgress = false
    @State private var showingGuide = false
    /// This exercise's own rest time (nil = automatic).
    @State private var restSeconds: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize }

    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            if let info = library.exercise(id: exercise.exerciseID) {
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
                Menu {
                    if !isCurrent {
                        Button("Collapse", systemImage: "chevron.up", action: onCollapse)
                    }
                    Button("How to do it", systemImage: "figure.strengthtraining.traditional") { showingGuide = true }
                    Button("Progress", systemImage: "chart.line.uptrend.xyaxis") { showingProgress = true }
                    Menu("Rest: \(restSeconds.map(RestPreferences.label) ?? "automatic")", systemImage: "timer") {
                        Button("Automatic (from your goal)") { setRest(nil) }
                        ForEach(RestTimer.choices, id: \.self) { seconds in
                            Button(RestPreferences.label(seconds)) { setRest(seconds) }
                        }
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
                    Button("Remove", role: .destructive) {
                        modelContext.delete(exercise)
                        try? modelContext.save()
                    }
                }
            }

            ForEach(sets, id: \.persistentModelID) { set in
                SetRow(
                    set: set,
                    label: set.isWarmup ? "W" : "\(workingNumber(set, in: sets))",
                    previous: set.isWarmup ? "" : previousText(index: workingNumber(set, in: sets) - 1),
                    unit: unit,
                    isEditing: set.persistentModelID == editing?.persistentModelID,
                    onTap: { focusedSetID = set.persistentModelID },
                    onToggle: { toggle(set) },
                    previousSet: set.isWarmup ? nil : previousSet(index: workingNumber(set, in: sets) - 1),
                    warmUp: set.isWarmup ? warmUpPosition(set, in: sets) : nil
                )
                .contextMenu {
                    Button(set.isWarmup ? "Make working set" : "Make warm-up set") { set.isWarmup.toggle() }
                    Button("Delete set", role: .destructive) {
                        modelContext.delete(set)
                        try? modelContext.save()
                    }
                }
            }

            if let editing {
                SetEditor(
                    set: editing,
                    title: editing.isWarmup ? "Warm-up" : "Set \(workingNumber(editing, in: sets))",
                    unit: unit,
                    step: { up in step(editing, up: up) },
                    plateHint: plateHint(for: editing),
                    onComplete: { toggle(editing) },
                    onShowGuide: { showingRPEGuide = true }
                )
            }

            Button {
                addSet()
            } label: {
                Text("+ Add set")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.cardRaised, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            if needsWeightFinding(sets) {
                // No history and nothing to estimate from, so no ramp sets: the first set finds the weight.
                Text("First set: find your weight. Start light and add weight until the reps feel like the plan's effort.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if !previous.isEmpty {
                Text("Last time: \(previous.map { "\(unit.format($0.weightKg)) × \($0.reps)" }.joined(separator: ", "))")
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
    }

    private func setRest(_ seconds: Int?) {
        RestPreferences.set(seconds, for: exercise.exerciseID)
        restSeconds = seconds
    }

    /// Completes (or un-completes) a set; completing starts rest (short after
    /// a warm-up ramp set) and moves to the next set.
    private func toggle(_ set: SetLog) {
        set.completedAt = set.isCompleted ? nil : .now
        try? modelContext.save()
        if set.isCompleted {
            focusedSetID = nil
            onSetCompleted(set.isWarmup)
        }
    }

    /// "Warm-up 1 of 3 · 50%": the ramp set's place and its share of the working weight.
    private func warmUpPosition(_ set: SetLog, in sets: [SetLog]) -> SetRow.WarmUpPosition {
        let ramps = sets.filter(\.isWarmup)
        let number = (ramps.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0) + 1
        let working = sets.first { !$0.isWarmup && $0.weightKg > 0 }?.weightKg
        let percent = working.map { Int((set.weightKg / $0 * 100).rounded()) }
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
        let best = exercise.sets.filter { $0.isCompleted && !$0.isWarmup }.map(\.estimatedOneRepMax).max() ?? 0
        return best > bestBefore + 0.01
    }

    private func workingNumber(_ set: SetLog, in sets: [SetLog]) -> Int {
        (sets.filter { !$0.isWarmup }.firstIndex { $0.persistentModelID == set.persistentModelID } ?? 0) + 1
    }

    /// Last session's working set with the same number (warm-ups don't count).
    private func previousText(index: Int) -> String {
        let working = previous.filter { !$0.isWarmup }
        guard index >= 0, index < working.count else { return "" }
        let set = working[index]
        return "\(unit.format(set.weightKg)) × \(set.reps)"
    }

    /// The same set from last session, for VoiceOver.
    private func previousSet(index: Int) -> SetLog? {
        let working = previous.filter { !$0.isWarmup }
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

    struct WarmUpPosition {
        var number: Int
        var count: Int
        var percent: Int?
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Fits "W" or "12" at every text size.
    @ScaledMetric(relativeTo: .headline) private var labelWidth: CGFloat = 26

    var body: some View {
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

    /// Number, weight × reps, last time and RPE. At accessibility text sizes
    /// the RPE pill moves under the weight so nothing is cut off.
    private var details: some View {
        HStack(spacing: 10) {
            if warmUp == nil {
                Text(label)
                    .font(.headline)
                    // Text colour for the amber accent (ux-audit.md X4, P24).
                    .foregroundStyle(set.isWarmup ? Theme.recoveryModerateText : Theme.primaryText)
                    .frame(width: labelWidth, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 1) {
                if let warmUp {
                    // "Warm-up 1 of 3 · 50%" instead of a bare "W" (user report: unclear).
                    Text(warmUpTitle(warmUp))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.recoveryModerateText)
                }
                Text(isFilled ? "\(unit.format(set.weightKg)) \(unit.rawValue) × \(set.reps)" : "Not set")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(isFilled ? Theme.primaryText : Theme.secondaryText)
                if !previous.isEmpty {
                    Text("Last: \(previous)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
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

    @ViewBuilder
    private var rpePill: some View {
        if let rpe = set.rpe {
            Text("RPE \(rpe.formatted())")
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

    /// "Warm-up 2 of 3 · 70%".
    private func warmUpTitle(_ warmUp: WarmUpPosition) -> String {
        "Warm-up \(warmUp.number) of \(warmUp.count)" + (warmUp.percent.map { " · \($0)%" } ?? "")
    }

    /// "Set 2", "Warm-up set 1 of 3" or "Warm-up set".
    private var spokenName: String {
        if let warmUp { return "Warm-up set \(warmUp.number) of \(warmUp.count)" }
        return self.set.isWarmup ? "Warm-up set" : "Set \(label)"
    }

    /// "Set 2, 8 reps at 60 kilograms, RPE 8, done".
    private var spokenSummary: String {
        var parts = [spokenName, spokenLoad(weightKg: set.weightKg, reps: set.reps) ?? "not set"]
        if let rpe = set.rpe { parts.append("RPE \(rpe.formatted())") }
        parts.append(set.isCompleted ? "done" : "not done")
        if let previousSet, let last = spokenLoad(weightKg: previousSet.weightKg, reps: previousSet.reps) {
            parts.append("last time \(last)")
        }
        return parts.joined(separator: ", ")
    }

    /// "8 reps at 60 kilograms"; nil when nothing is filled in.
    private func spokenLoad(weightKg: Double, reps: Int) -> String? {
        guard weightKg > 0 || reps > 0 else { return nil }
        let repsText = reps == 1 ? "1 rep" : "\(reps) reps"
        guard weightKg > 0 else { return repsText }
        return "\(repsText) at \(unit.format(weightKg)) \(unit.spokenName)"
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
    let unit: WeightUnit
    let step: (Bool) -> Void
    let plateHint: String?
    let onComplete: () -> Void
    let onShowGuide: () -> Void

    @FocusState private var typing: Field?
    private enum Field { case weight, reps }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.liftingText)
            steppers
            if let plateHint {
                Label(plateHint, systemImage: "circle.grid.2x1")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if !set.isWarmup {
                RPEPicker(rpe: $set.rpe, onShowGuide: onShowGuide)
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
        }
        .padding(14)
        .background(Theme.lifting.opacity(0.05), in: .rect(cornerRadius: 20))
    }

    /// Weight and reps side by side; one above the other at accessibility
    /// text sizes, so the numbers keep their size (ux-audit.md 4.8, P22).
    private var steppers: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            NumberStepper(label: unit.rawValue, spokenLabel: "weight") {
                TextField("0", value: weightBinding, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .focused($typing, equals: .weight)
                    .accessibilityLabel("Weight in \(unit.spokenName)")
            } minus: { step(false) } plus: { step(true) }
            NumberStepper(label: "reps") {
                TextField("0", value: $set.reps, format: .number)
                    .keyboardType(.numberPad)
                    .focused($typing, equals: .reps)
                    .accessibilityLabel("Reps")
            } minus: { set.reps = max(0, set.reps - 1) } plus: { set.reps += 1 }
        }
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { unit.display(set.weightKg) },
            set: { set.weightKg = unit.toKilograms($0) }
        )
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

/// Big 6-10 buttons plus a ½ toggle, with what the number means.
private struct RPEPicker: View {
    @Binding var rpe: Double?
    let onShowGuide: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private static let values = [6, 7, 8, 9, 10]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            buttons
                .sensoryFeedback(.selection, trigger: rpe)
            Text(rpe.map { value in
                let level = RPEScale.level(for: value)
                return "\(RPEScale.summary(value)). \(level?.feel ?? "")"
            } ?? "Optional. Pick how hard the set was: 8 means you had 2 reps left, 10 means none.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// Title and the guide link; stacked at accessibility text sizes.
    private var header: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout())
        return layout {
            Text("Effort (RPE)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            if !stacked { Spacer() }
            Button(action: onShowGuide) {
                Label("What's RPE?", systemImage: "questionmark.circle")
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
        }
    }

    /// One row of six; at accessibility text sizes two rows of three, so the
    /// numbers aren't cut off (ux-audit.md 4.8, P22).
    @ViewBuilder
    private var buttons: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Self.values, id: \.self) { value in
                    rpeButton(value)
                }
                halfButton(fillsWidth: true)
            }
        } else {
            HStack(spacing: 6) {
                ForEach(Self.values, id: \.self) { value in
                    rpeButton(value)
                }
                halfButton(fillsWidth: false)
            }
        }
    }

    private func rpeButton(_ value: Int) -> some View {
        let selected = rpe.map { Int($0.rounded(.down)) == value } ?? false
        return Button {
            if selected && rpe == Double(value) { rpe = nil } else { rpe = Double(value) }
        } label: {
            Text("\(value)")
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(selected ? .white : Theme.primaryText)
                .background(selected
                            ? AnyShapeStyle(LinearGradient(colors: Theme.strainButtonColors, startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(Theme.card), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.clear : Theme.separator))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("RPE \(value)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func halfButton(fillsWidth: Bool) -> some View {
        Button {
            guard let current = rpe, current < 10 else { return }
            rpe = current.truncatingRemainder(dividingBy: 1) == 0 ? current + 0.5 : current - 0.5
        } label: {
            Text("½")
                .font(.title3.weight(.bold))
                .frame(minWidth: 44, maxWidth: fillsWidth ? CGFloat.infinity : 44, minHeight: 48)
                .foregroundStyle(isHalf ? .white : Theme.primaryText)
                .background(isHalf ? AnyShapeStyle(Theme.lifting) : AnyShapeStyle(Theme.card), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isHalf ? Color.clear : Theme.separator))
        }
        .buttonStyle(.plain)
        .disabled(rpe == nil || rpe == 10)
        .accessibilityLabel("Add a half point")
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
                    Chip(text: "Up next")
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if isNext && !dynamicTypeSize.isAccessibilitySize {
                Chip(text: "Up next")
            } else if !isNext {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
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
        let working = exercise.sets.filter { !$0.isWarmup }
        if isDone, let best = working.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax }) {
            return "\(working.count) sets · \(unit.format(best.weightKg)) \(unit.rawValue) × \(best.reps) · done"
        }
        let first = exercise.orderedSets.first
        let reps = first.map { "\($0.reps)" } ?? "–"
        return "\(working.count) × \(reps)" + (first.map { $0.weightKg > 0 ? " · \(unit.format($0.weightKg)) \(unit.rawValue)" : "" } ?? "")
    }
}

private struct RestTimerPill: View {
    let endsAt: Date
    let length: TimeInterval
    /// +/- seconds, or nil to skip.
    let onChange: (TimeInterval?) -> Void

    /// At accessibility text sizes the buttons go under the time, so the
    /// pill doesn't clip (ux-audit.md 4.8, P22).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            content(remaining: remaining)
                .onChange(of: remaining == 0) { _, finished in
                    if finished { onChange(nil) }
                }
                .sensoryFeedback(.warning, trigger: remaining == 0) { _, finished in finished }
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
        let shape = stacked ? AnyShape(RoundedRectangle(cornerRadius: Theme.cornerRadius)) : AnyShape(Capsule())
        return layout {
            countdown(remaining: remaining)
            if !stacked { Spacer() }
            controls
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: Theme.strainButtonColors, startPoint: .leading, endPoint: .trailing), in: shape)
        .shadow(color: Theme.strain.opacity(0.3), radius: 12, y: 6)
    }

    private func countdown(remaining: TimeInterval) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.3), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: length > 0 ? remaining / length : 0)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
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
            Button("Skip") { onChange(nil) }
                .font(.headline)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
                .buttonStyle(.plain)
                .accessibilityLabel("Skip rest")
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
            .background(Color.white.opacity(0.2), in: .capsule)
            .contentShape(.capsule)
            .buttonStyle(.plain)
            .accessibilityLabel(spoken)
    }
}

/// Live heart rate from the iPhone workout session (AirPods Pro 3 or a chest strap).
private struct LiveHeartRateBar: View {
    let recorder: LiveWorkoutRecorder
    let profile: HeartRateProfile?
    /// Scales with Dynamic Type (ux-audit W5).
    @ScaledMetric(relativeTo: .title2) private var bpmSize: CGFloat = 26
    /// Avg and Max columns widen with the text instead of clipping.
    @ScaledMetric(relativeTo: .title3) private var statWidth: CGFloat = 56
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.title3)
                .foregroundStyle(Theme.recoveryLow)
                .symbolEffect(.pulse, isActive: recorder.heartRate != nil)
                .accessibilityHidden(true)
            if let bpm = recorder.heartRate {
                live(bpm)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recorder.isRecording ? "Waiting for heart rate…" : "Live heart rate off")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text(recorder.problem ?? "Wear AirPods Pro 3 (or connect a Bluetooth chest strap) to see heart rate here. It's saved with the workout so you can compare it with your watch.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    /// Current bpm and zone beside Avg and Max; Avg and Max go underneath at
    /// accessibility text sizes (ux-audit.md 4.8, P22).
    private func live(_ bpm: Double) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(whole(bpm))")
                        .font(.system(size: bpmSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("bpm").font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                .foregroundStyle(Theme.primaryText)
                Text(zoneText(bpm))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            if !stacked { Spacer() }
            HStack(spacing: 12) {
                StatView(label: "Avg", value: recorder.averageHeartRate.map { "\(whole($0))" } ?? "–")
                    .frame(width: statWidth)
                StatView(label: "Max", value: recorder.maximumHeartRate.map { "\(whole($0))" } ?? "–")
                    .frame(width: statWidth)
            }
        }
    }

    private func zoneText(_ bpm: Double) -> String {
        guard let profile else { return "Live" }
        guard let zone = profile.zone(for: bpm) else { return "Below zone 1" }
        return "Zone \(zone) · \(whole(profile.reserveFraction(for: bpm) * 100))% of reserve"
    }
}
