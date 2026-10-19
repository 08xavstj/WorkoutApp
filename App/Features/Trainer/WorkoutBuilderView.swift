import SwiftUI
import SwiftData
import AppCore

/// The trainer: builds a session from your gym's equipment, your lift history
/// and today's recovery, with weights you can actually load.
struct WorkoutBuilderView: View {
    var initialFocus: WorkoutFocus?
    var initialMinutes: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(GymStore.self) private var gym
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(MedicationsModel.self) private var medications
    @Environment(CheckInStore.self) private var checkIns
    @Environment(MuscleModel.self) private var muscles
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var focus: WorkoutFocus?
    @State private var minutes = 45
    @State private var plan: PlannedWorkout?
    @State private var showingGym = false
    @State private var didSetUp = false

    private let durations = [30, 45, 60, 75]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !gym.isConfigured {
                        gymPrompt
                    }
                    if medications.has(.tendonCaution) {
                        Label("A medication you take raises tendon injury risk. Skip jumps and sprints, and don't add weight in big jumps.", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.primaryText)
                            .card(tint: Theme.recoveryModerate)
                    }
                    focusPicker
                    durationPicker
                    if let plan {
                        if plan.exercises.isEmpty {
                            ContentUnavailableView(
                                "Nothing fits this focus",
                                systemImage: "dumbbell",
                                description: Text("No exercises match this focus with your equipment. Pick another focus, or add equipment in My Gym.")
                            )
                        } else {
                            summaryCard(plan)
                            ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                                PlannedExerciseRow(
                                    index: index + 1, exercise: exercise, unit: plan.unit,
                                    onSwap: canSwap(at: index, in: plan) ? { swap(at: index) } : nil
                                )
                            }
                        }
                    }
                }
                .padding()
                .lockedToScreenWidth()
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(Theme.background)
            .navigationTitle("Build a workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingGym = true
                    } label: {
                        Label("My Gym", systemImage: "dumbbell")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let plan else { return }
                    launcher.start(plan, in: modelContext)
                    dismiss()
                } label: {
                    Label("Start workout", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.card)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.ink, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(plan?.exercises.isEmpty ?? true)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .sheet(isPresented: $showingGym, onDismiss: rebuild) {
                MyGymView()
            }
            .onAppear {
                // Only once, so coming back from My Gym doesn't reset your choices.
                guard !didSetUp else { return }
                didSetUp = true
                focus = initialFocus
                minutes = initialMinutes ?? 45
                rebuild()
            }
            .onChange(of: focus) { rebuild() }
            .onChange(of: minutes) { rebuild() }
        }
    }

    /// Your pick, else what sore or tired muscles allow, else what you haven't trained lately.
    private var resolvedFocus: WorkoutFocus {
        focus ?? checkIns.suggestedFocus ?? muscles.suggestedFocus
            ?? WorkoutPlanner.suggestedFocus(recentExerciseIDs: LiftHistory.recentExerciseIDs(sessions))
    }

    private var autoReason: String {
        if checkIns.suggestedFocus != nil { return "because of the soreness you reported this morning" }
        if muscles.suggestedFocus != nil { return "to rest the muscles that are still recovering" }
        return "based on what you've trained recently"
    }

    private func rebuild() {
        let history = LiftHistory.make(from: sessions, unit: gym.profile.unit)
        plan = gym.planner.plan(focus: resolvedFocus, minutes: minutes, recovery: metrics.recoveryForTraining, history: history)
    }

    /// True when there's another exercise for the same movement to swap to.
    private func canSwap(at index: Int, in plan: PlannedWorkout) -> Bool {
        guard index < plan.exercises.count,
              let slot = ExerciseCatalog.slot(for: plan.exercises[index].exerciseID) else { return false }
        return gym.planner.alternatives(for: slot).count > 1
    }

    /// Replaces an exercise with the next option for the same movement.
    private func swap(at index: Int) {
        guard var current = plan, index < current.exercises.count,
              let slot = ExerciseCatalog.slot(for: current.exercises[index].exerciseID) else { return }
        let options = gym.planner.alternatives(for: slot)
        guard options.count > 1,
              let position = options.firstIndex(where: { $0.id == current.exercises[index].exerciseID }) else { return }
        let next = options[(position + 1) % options.count]
        let history = LiftHistory.make(from: sessions, unit: gym.profile.unit)
        current.exercises[index] = gym.planner.prescribe(next, slot: slot, minutes: minutes, sessionRPE: current.targetRPE, history: history)
        plan = current
    }

    private var gymPrompt: some View {
        Button {
            showingGym = true
        } label: {
            HStack(spacing: 12) {
                IconBadge(systemName: "slider.horizontal.3", color: Theme.lifting, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up My Gym")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text("Tell the trainer your equipment, plates and dumbbells so every weight is one you can load.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var focusPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "Focus")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    SelectChip(title: "Auto", isSelected: focus == nil) { focus = nil }
                    ForEach(WorkoutFocus.allCases) { option in
                        SelectChip(title: option.shortTitle, isSelected: focus == option) { focus = option }
                    }
                }
            }
            .scrollIndicators(.hidden)
            Text(focus == nil ? "Auto picks \(resolvedFocus.title.lowercased()) \(autoReason)." : resolvedFocus.muscles)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "Time")
            HStack(spacing: 8) {
                ForEach(durations, id: \.self) { value in
                    SelectChip(title: "\(value) min", isSelected: minutes == value) { minutes = value }
                }
            }
        }
    }

    private func summaryCard(_ plan: PlannedWorkout) -> some View {
        let planner = StrainPlanner()
        let estimated = WorkoutPlanner.estimatedMinutes(plan.exercises)
        let gain = metrics.strainGain(addedLoad: planner.liftingLoad(minutes: Double(estimated), rpe: plan.targetRPE))
        let current = metrics.strain?.strain ?? 0
        let landsAt = current + gain
        return VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Suggested", color: Theme.lifting)
            Text(plan.title)
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.primaryText)
            HStack(spacing: 18) {
                StatView(label: "Time", value: "~\(estimated) min")
                StatView(label: "Effort", value: "\(plan.targetRPE.formatted())/10")
                StatView(label: "Strain", value: "≈+\(strainText(gain))", color: Theme.strainTextColor)
            }
            if let target = metrics.targetStrain {
                let inRange = target.contains(landsAt)
                Text("Lands you around \(strainText(landsAt)) strain (target \(strainRangeText(target)))\(inRange ? ", right on target." : ".")")
                    .font(.subheadline)
                    .foregroundStyle(inRange ? Theme.recoveryHighText : Theme.secondaryText)
            }
        }
        .card()
    }
}

struct SelectChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? Theme.card : Theme.primaryText)
                .background(isSelected ? Theme.ink : Theme.card, in: .capsule)
                .shadow(color: Color.black.opacity(isSelected ? 0 : 0.06), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One exercise in a plan: name, prescription, load and plates.
struct PlannedExerciseRow: View {
    let index: Int
    let exercise: PlannedExercise
    let unit: LoadUnit
    var onSwap: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.headline)
                .foregroundStyle(Theme.liftingText)
                .frame(width: 34, height: 34)
                .background(Theme.lifting.opacity(0.12), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text("\(exercise.sets) × \(exercise.reps.lowerBound)–\(exercise.reps.upperBound) · stop with \(exercise.repsInReserve.replacingOccurrences(of: " in reserve", with: " left"))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                if let load = exercise.load {
                    Text("\(load.formatted(.number.precision(.fractionLength(0...2)))) \(unit.rawValue)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.strainTextColor)
                }
                if let note = exercise.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
            if let onSwap {
                Button(action: onSwap) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 44, height: 44)
                        .background(Theme.cardRaised, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap \(exercise.name)")
            }
        }
        .card()
    }
}
