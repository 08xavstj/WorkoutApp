import SwiftUI
import WatchKit

/// The set to lift, on one page that doesn't scroll
/// (docs/research/watch-app-redesign-2026-11.md §4.4.2): exercise, "Set 3 of 4 ·
/// Goal 8", the weight big, the reps, last time's set, and Done.
///
/// - The Digital Crown steps the weight through the loads the gym can make
///   (`LoadStepper`, from the phone's `achievableLoadsKg`), with a detent per
///   load. Tap the reps and the crown moves to them (0-50); tap the weight to
///   move it back. A hold's crown sets its seconds in 5 s steps.
/// - Done (or double tap, on this page only) logs the set at once; Undo stays
///   in the toolbar for 4 s.
/// - With VoiceOver or Switch Control on, −/+ buttons back up the crown, and
///   the weight and reps are adjustable by swipe.
struct LiftSetPage: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The page is in front: only then does double tap press Done and the
    /// crown change the set.
    let isFront: Bool

    var body: some View {
        Group {
            if let session = model.snapshot, let step = session.currentWarmUpStep {
                // The movement warm-up runs before the first set (`WatchWarmUpView`).
                WatchWarmUpView(session: session, step: step, isFront: isFront)
            } else if let set = model.currentPendingSet, let session = model.snapshot {
                SetCard(session: session, set: set, isFront: isFront)
            } else if let session = model.snapshot, let index = model.shownExercise,
                      session.exercises[index].sets.allSatisfy(\.isCompleted), session.nextExerciseIndex != nil {
                ExerciseDoneCard(name: session.exercises[index].name,
                                 next: session.nextExerciseIndex.map { session.exercises[$0].name }, isFront: isFront)
            } else if model.snapshot != nil {
                AllDoneCard()
            } else {
                NoSetsCard()
            }
        }
        .overlay(alignment: .top) {
            if let note = model.recordNote {
                WatchRecordBanner(note: note) { model.dismissRecords() }
            }
        }
    }
}

/// Which value the Digital Crown changes.
private enum CrownField: Hashable {
    case weight, reps
}

private struct SetCard: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var reduced
    let session: WatchSession
    let set: PendingSet
    let isFront: Bool

    @FocusState private var focus: CrownField?
    @State private var weightCrown = 0.0
    @State private var repsCrown = 0.0
    /// Shows the machine note instead of last time's set.
    @State private var showsMachineNote = false
    @State private var tick: LoggedSet?

    private var exercise: WatchSession.ExerciseSnapshot { session.exercises[set.exerciseIndex] }
    private var snapshotSet: WatchSession.SetSnapshot { exercise.sets[set.setIndex] }
    private var showsSteppers: Bool { voiceOver || switchControl }
    /// At the accessibility text sizes the page scrolls, so double tap is off (HIG Gestures).
    private var scrolls: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }
            } else {
                content
            }
        }
        .overlay { tickOver }
        .onChange(of: set.id, initial: true) {
            syncCrown()
            claimCrown()
        }
        // The phone changed the plan (a set-by-set change): the crown starts from the new value.
        .onChange(of: set.weightKg) {
            let index = set.stepper.nearestIndex(to: set.weightKg)
            if Int(weightCrown.rounded()) != index { weightCrown = Double(index) }
        }
        .onChange(of: set.reps) {
            let value = set.isHold ? set.reps / LoadStepper.holdStepSeconds : set.reps
            if Int(repsCrown.rounded()) != value { repsCrown = Double(value) }
        }
        .onChange(of: isFront, initial: true) { claimCrown() }
        .onChange(of: model.phase) { claimCrown() }
        .task(id: model.lastLogged) {
            guard let logged = model.lastLogged, Date.now.timeIntervalSince(logged.at) < 1 else { return }
            withAnimation(reduceMotion ? nil : .snappy) { tick = logged }
            try? await Task.sleep(for: .seconds(LiftPagesView.tickSeconds))
            withAnimation(reduceMotion ? nil : .easeOut) { tick = nil }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Paused: everything but Resume dims, a look distinct from running (HIG Workouts).
            VStack(alignment: .leading, spacing: 2) {
                header
                Spacer(minLength: 0)
                weightRow
                repsRow
                guideLine
            }
            .opacity(model.phase == .paused ? 0.45 : 1)
            Spacer(minLength: 2)
            primaryButton
        }
    }

    /// The crown goes to the weight (a hold's seconds) on the page in front
    /// while the workout runs; off-screen or paused, nothing takes it, so a
    /// turn can't change the set unseen.
    private func claimCrown() {
        guard isFront, model.phase == .running else {
            focus = nil
            return
        }
        if focus == nil { focus = set.isHold ? .reps : .weight }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(exercise.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if let chip = supersetChip {
                    Text(chip)
                        .font(.footnote.weight(.bold))
                        .padding(.horizontal, 5)
                        .background(WatchPalette.lifting.opacity(0.3), in: Capsule())
                        .accessibilityLabel("Superset \(chip.replacingOccurrences(of: "→", with: "then"))")
                }
            }
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(snapshotSet.isStage ? WatchPalette.lifting : .secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// "A1 → A2" for the first half of a superset, else "A2".
    private var supersetChip: String? {
        guard let label = exercise.supersetLabel else { return nil }
        if label.hasSuffix("1"), let partner = session.partnerIndex(of: set.exerciseIndex),
           let other = session.exercises[partner].supersetLabel {
            return "\(label) → \(other)"
        }
        return label
    }

    /// "Set 3 of 4 · Goal 8", "Drop 1 of 2", "Warm-up 1 of 2", "Set 2 of 3 · Target 30 s".
    private var subtitle: String {
        let same = exercise.sets.filter { $0.isWarmup == snapshotSet.isWarmup }
        let number = exercise.sets[..<set.setIndex].filter { $0.isWarmup == snapshotSet.isWarmup }.count + 1
        let fallback = "\(snapshotSet.isWarmup ? "Warm-up" : "Set") \(number) of \(same.count)"
        var parts = [snapshotSet.title ?? fallback]
        if set.isHold {
            if let target = snapshotSet.holdTargetLine { parts.append(target) }
        } else if !snapshotSet.isWarmup, let goal = snapshotSet.targetReps {
            parts.append("Goal \(goal)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Weight

    @ViewBuilder
    private var weightRow: some View {
        if !set.isHold {
            HStack(alignment: .center, spacing: 4) {
                if showsSteppers { stepButton("minus", label: "Lighter") { stepWeight(-1) } }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(set.weightKg > 0 ? watchWeightNumber(set.weightKg, unit: set.unit) : "Body")
                        .numeral(.primary)
                        .alwaysOnPrimary(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if set.weightKg > 0 {
                        Text(exercise.perHand == true ? "\(set.unit) each" : set.unit)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Weight")
                .accessibilityValue(spokenWeight)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: stepWeight(1)
                    case .decrement: stepWeight(-1)
                    @unknown default: break
                    }
                }
                Spacer(minLength: 0)
                if showsSteppers { stepButton("plus", label: "Heavier") { stepWeight(1) } }
            }
            .padding(.horizontal, 6)
            .background { focusRing(.weight) }
            .focusable(isFront)
            .focused($focus, equals: .weight)
            .digitalCrownRotation($weightCrown, from: 0, through: Double(max(1, set.loads.count - 1)), by: 1,
                                  sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: weightCrown) { crownMovedWeight() }
            .onTapGesture { focus = .weight }
        }
    }

    /// "82.5 kilograms", "20 kilograms each", "Bodyweight".
    private var spokenWeight: String {
        guard set.weightKg > 0 else { return "Bodyweight" }
        return watchSpokenWeight(set.weightKg, unit: set.unit) + (exercise.perHand == true ? " each" : "")
    }

    // MARK: Reps

    private var repsRow: some View {
        HStack(alignment: .center, spacing: 4) {
            if showsSteppers { stepButton("minus", label: set.isHold ? "Shorter" : "Fewer reps") { stepReps(-1) } }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if !set.isHold {
                    Text("×")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("\(set.reps)")
                    .numeral(set.isHold ? .primary : .secondary)
                    .alwaysOnPrimary(.primary)
                    .lineLimit(1)
                Text(set.isHold ? "s" : (set.reps == 1 ? "rep" : "reps"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(set.isHold ? "Seconds" : "Reps")
            .accessibilityValue(set.isHold ? "\(set.reps) seconds" : "\(set.reps)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: stepReps(1)
                case .decrement: stepReps(-1)
                @unknown default: break
                }
            }
            Spacer(minLength: 0)
            if showsSteppers { stepButton("plus", label: set.isHold ? "Longer" : "More reps") { stepReps(1) } }
            if exercise.repCounting == true, !set.isHold, !set.isWarmup {
                RepCountControl(setKey: set.id)
            }
        }
        .padding(.horizontal, 6)
        .background { focusRing(.reps) }
        .focusable(isFront)
        .focused($focus, equals: .reps)
        .digitalCrownRotation($repsCrown, from: 0, through: repsCrownTop, by: 1,
                              sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: repsCrown) { crownMovedReps() }
        .onTapGesture { focus = .reps }
    }

    private var repsCrownTop: Double {
        self.set.isHold ? Double(LoadStepper.maximumHoldSeconds / LoadStepper.holdStepSeconds) : Double(LoadStepper.repRange.upperBound)
    }

    // MARK: Guide line

    /// Last time's set (or the phone's set-by-set note), or the machine
    /// settings; tap to swap. While the rep counter runs: its dots.
    @ViewBuilder
    private var guideLine: some View {
        if RepCountDetail.isActive(for: set.id) {
            RepCountDetail(setKey: set.id)
                .padding(.horizontal, 6)
        } else if let line = guideText {
            Text(line)
                .font(.footnote)
                .foregroundStyle(showsMachineNote || snapshotSet.note != nil ? WatchPalette.lifting : .secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard exercise.machineNote != nil, ghostText != nil else { return }
                    showsMachineNote.toggle()
                }
                .accessibilityLabel(spokenGuide ?? line)
                .accessibilityHint(exercise.machineNote != nil && ghostText != nil ? "Shows the machine settings or last time's set" : "")
        }
    }

    private var ghostText: String? {
        if let note = snapshotSet.note { return note }
        guard !snapshotSet.isWarmup else { return nil }
        return set.isHold ? snapshotSet.holdGhostLine : snapshotSet.ghostLine(unit: set.unit)
    }

    private var guideText: String? {
        if showsMachineNote, let machine = exercise.machineNote { return machine }
        return ghostText ?? exercise.machineNote
    }

    private var spokenGuide: String? {
        guard !showsMachineNote, snapshotSet.note == nil, !set.isHold else { return nil }
        return snapshotSet.spokenGhost(unit: set.unit)
    }

    // MARK: Done / Resume

    @ViewBuilder
    private var primaryButton: some View {
        if model.phase == .paused {
            PrimaryWideButton(title: "Resume", systemImage: "play.fill", tint: WatchPalette.recovery,
                              primaryAction: isFront && !scrolls, accessibilityLabel: "Paused. Resume") {
                model.resume()
            }
        } else {
            PrimaryWideButton(title: "Done", systemImage: "checkmark", tint: WatchPalette.recovery,
                              primaryAction: isFront && !scrolls, accessibilityLabel: spokenDone) {
                focus = nil
                model.logCurrentSet()
            }
            .disabled(model.phase != .running)
        }
    }

    /// "Log set 3 of 4, 82.5 kilograms, 8 reps".
    private var spokenDone: String {
        var parts = ["Log \(subtitle.split(separator: "·").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? "set")"]
        if !set.isHold, set.weightKg > 0 { parts.append(watchSpokenWeight(set.weightKg, unit: set.unit)) }
        parts.append(set.isHold ? "\(set.reps) seconds" : "\(set.reps) \(set.reps == 1 ? "rep" : "reps")")
        return parts.joined(separator: ", ")
    }

    // MARK: Tick-over

    @ViewBuilder
    private var tickOver: some View {
        if let tick {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(WatchPalette.recovery)
                Text(tick.title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.9))
            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: Crown and steppers

    @ViewBuilder
    private func focusRing(_ field: CrownField) -> some View {
        if focus == field, isFront, !reduced {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(WatchPalette.lifting, lineWidth: 2)
        }
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .background(WatchPalette.lifting.opacity(0.2), in: Circle())
        .accessibilityLabel(label)
    }

    private func syncCrown() {
        weightCrown = Double(set.stepper.nearestIndex(to: set.weightKg))
        repsCrown = set.isHold ? Double(set.reps / LoadStepper.holdStepSeconds) : Double(set.reps)
    }

    private func crownMovedWeight() {
        guard isFront, focus == .weight else { return }
        let load = set.stepper.load(atCrown: weightCrown)
        guard abs(load - set.weightKg) > 0.001 else { return }
        model.edit(set, weightKg: load)
    }

    private func crownMovedReps() {
        guard isFront, focus == .reps else { return }
        let value = Int(repsCrown.rounded())
        let reps = set.isHold
            ? min(LoadStepper.maximumHoldSeconds, max(0, value * LoadStepper.holdStepSeconds))
            : min(LoadStepper.repRange.upperBound, max(0, value))
        guard reps != set.reps else { return }
        model.edit(set, reps: reps)
    }

    private func stepWeight(_ steps: Int) {
        let load = set.stepper.step(from: set.weightKg, by: steps)
        model.edit(set, weightKg: load)
        weightCrown = Double(set.stepper.nearestIndex(to: load))
        WKInterfaceDevice.current().play(.click)
    }

    private func stepReps(_ steps: Int) {
        let reps = set.isHold ? LoadStepper.holdSeconds(set.reps, by: steps) : LoadStepper.reps(set.reps, by: steps)
        model.edit(set, reps: reps)
        repsCrown = set.isHold ? Double(reps / LoadStepper.holdStepSeconds) : Double(reps)
        WKInterfaceDevice.current().play(.click)
    }
}

/// The picked exercise is done but others aren't.
private struct ExerciseDoneCard: View {
    @Environment(WatchWorkoutModel.self) private var model
    let name: String
    let next: String?
    let isFront: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(name) done", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(WatchPalette.recovery)
            Spacer(minLength: 0)
            if let next {
                Text("Next: \(next)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            PrimaryWideButton(title: "Next exercise", systemImage: "arrow.right", tint: WatchPalette.lifting,
                              primaryAction: isFront) {
                model.selectedExercise = nil
            }
        }
    }
}

/// Every set is logged.
private struct AllDoneCard: View {
    @Environment(WatchWorkoutModel.self) private var model
    @State private var finishing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("All sets done", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(WatchPalette.recovery)
            Text("\(model.snapshot?.completedSets ?? 0) sets logged")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            // Not on double tap: finishing deserves a deliberate tap.
            PrimaryWideButton(title: "Finish", systemImage: "flag.checkered", tint: WatchPalette.lifting) {
                finishing = true
            }
        }
        .sheet(isPresented: $finishing) {
            WatchSessionEffortSheet()
        }
    }
}

/// Recording with no session from the phone: heart rate and calories only.
private struct NoSetsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Recording", systemImage: "heart.fill")
                .font(.headline)
                .foregroundStyle(WatchPalette.heart)
            Text("Heart rate and calories only. Start your workout on your iPhone and its sets appear here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

/// New records after the exercise finished on the wrist; tap to close.
struct WatchRecordBanner: View {
    let note: WatchRecordNote
    let onClose: () -> Void

    private var spoken: String {
        (["New record"] + note.lines).joined(separator: ". ")
    }

    var body: some View {
        Button(action: onClose) {
            VStack(alignment: .leading, spacing: 2) {
                Label("New record", systemImage: "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(WatchPalette.lifting)
                ForEach(note.lines.prefix(2), id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WatchPalette.lifting, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityHint("Closes the banner")
    }
}
