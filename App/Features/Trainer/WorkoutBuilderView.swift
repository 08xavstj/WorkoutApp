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
    /// The warm-up tier for this focus (`WarmUpPlanRow`): its minutes count in the plan's length.
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(MedicationsModel.self) private var medications
    @Environment(CheckInStore.self) private var checkIns
    @Environment(MuscleModel.self) private var muscles
    @Environment(WeeklyPlanStore.self) private var plans
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var focus: WorkoutFocus?
    @State private var minutes = 45
    @State private var plan: PlannedWorkout?
    /// The plan before any time-saving sets (`TimeSaver`); `plan` is this, or
    /// this with the small lifts' sets as one drop / rest-pause / myo-rep set.
    @State private var basePlan: PlannedWorkout?
    @State private var useTimeSaver = false
    @State private var timeSaverKind: SetKind = .drop
    /// What the short session can offer (`TimeSaver.options`), worked out with the plan.
    @State private var timeSaverOptions: [TimeSaver.Option] = []
    @State private var showingGym = false
    @State private var didSetUp = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Pain and "never again" (`PainGuard`, `ExerciseFilter`).
    @Environment(\.healthClient) private var health
    @State private var exclusions = ExerciseExclusions.shared
    @State private var painLog = PainLogStore.shared
    /// Lower back pain other apps logged in Apple Health.
    @State private var healthPains: [PainReport] = []
    @State private var showingPainLog = false
    /// Current pain and areas hurting 2+ weeks, worked out in `rebuild` (not on every redraw).
    @State private var activePains: [PainReport] = []
    @State private var clinicianAreas: [PainArea] = []

    /// Session length. Short sessions are fitted with fewer sets, then paired
    /// exercises (`Supersets`).
    private let durations = [15, 20, 30, 45, 60, 75]

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
                    // "Something hurts?": the trainer avoids or eases lifts that load it.
                    PainGuardRow(pains: activePains, clinicianAreas: clinicianAreas, neverAgainCount: exclusions.items.count) {
                        showingPainLog = true
                    }
                    if let plan {
                        if plan.exercises.isEmpty {
                            ContentUnavailableView(
                                "Nothing fits this focus",
                                systemImage: "dumbbell",
                                description: Text("No exercises match this focus with your equipment. Pick another focus, or add equipment under Gym equipment (top right).")
                            )
                        } else {
                            summaryCard(plan)
                            timeSaverSection
                            // Optional movement warm-up before the first lift (`WarmUpRoutine`).
                            WarmUpPlanRow(focus: plan.focus, slots: WarmUpRoutine.slots(of: plan))
                            ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                                PlannedExerciseRow(
                                    index: index + 1, exercise: exercise, unit: plan.unit,
                                    onSwap: canSwap(at: index, in: plan) ? { swap(at: index) } : nil,
                                    label: Supersets.label(for: index, in: plan.exercises),
                                    onNeverAgain: { neverAgain(exercise) },
                                    equipment: equipment(for: exercise),
                                    onMissingEquipment: { removeEquipment($0) }
                                )
                            }
                        }
                    }
                    // The way out sits after the plan, so the plan comes first (ux-audit W1, 4.6).
                    ownWorkoutLink
                }
                .padding()
                .lockedToScreenWidth()
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(Theme.background)
            .navigationTitle("Start workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingGym = true
                    } label: {
                        Label("Gym equipment", systemImage: "dumbbell")
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
                .opacity((plan?.exercises.isEmpty ?? true) ? 0.5 : 1)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            // A push inside this sheet's stack, never a sheet on a sheet (ux-audit 4.1 rule 5).
            .navigationDestination(isPresented: $showingGym) {
                MyGymView(pushed: true)
            }
            .onChange(of: showingGym) { _, showing in
                if !showing { rebuild() }
            }
            .navigationDestination(isPresented: $showingPainLog) {
                PainLogView(current: activePains, exclusions: exclusions) { changed in
                    logPain(changed)
                }
            }
            .onChange(of: showingPainLog) { _, showing in
                if !showing { rebuild() }
            }
            .task { await loadHealthPains() }
            .onAppear {
                // Only once, so coming back from Gym equipment doesn't reset your choices.
                guard !didSetUp else { return }
                didSetUp = true
                focus = initialFocus
                minutes = initialMinutes ?? 45
                rebuild()
            }
            .onChange(of: focus) { rebuild() }
            .onChange(of: minutes) { rebuild() }
            .onChange(of: useTimeSaver) { applyTimeSaver() }
            .onChange(of: timeSaverKind) { applyTimeSaver() }
            .onChange(of: settings.warmUpTier(for: resolvedFocus)) { rebuild() }
        }
    }

    /// Your pick, else what sore or tired muscles allow, else what you haven't trained lately.
    private var resolvedFocus: WorkoutFocus {
        focus ?? checkIns.suggestedFocus ?? muscles.suggestedFocus ?? coverage?.focus
            ?? WorkoutPlanner.suggestedFocus(recentExerciseIDs: LiftHistory.recentExerciseIDs(sessions))
    }

    /// The session that closes this week's biggest gap to 10-20 hard sets per
    /// muscle (`MuscleCoverage`), when nothing more pressing picks the focus.
    private var coverage: MuscleCoverage.Result? {
        guard focus == nil, checkIns.suggestedFocus == nil, muscles.suggestedFocus == nil else { return nil }
        let left = plans.progress(sessions: sessions)?.remaining ?? 2
        return muscles.coverage(sessionsLeft: max(1, left), preferred: nil)
    }

    private var autoReason: String {
        if checkIns.suggestedFocus != nil { return "because of the soreness you reported this morning" }
        if muscles.suggestedFocus != nil { return "to rest the muscles that are still recovering" }
        if let reason = coverage?.reason { return reason }
        return "based on what you've trained recently"
    }

    /// Minutes of movement warm-up before the first lift for the chosen tier
    /// (`WarmUpRoutine`): 0 for off and ramp-only, so only real warm-up time counts.
    private var warmUpMinutes: Int {
        WarmUpRoutine.make(tier: settings.warmUpTier(for: resolvedFocus), firstSlots: resolvedFocus.slots, gym: gym.profile).minutes
    }

    private func rebuild() {
        refreshPains()
        let history = LiftHistory.make(from: sessions, unit: gym.profile.unit)
        // This week in the training block scales the sets and sets the RIR target;
        // recovery still lowers the effort on a low day (`TrainingBlock`, `WorkoutPlanner.targetRPE`).
        plans.trainingStyle = gym.style
        let block = plans.refreshBlock(hrvBelowNormal: metrics.trainEasyToday)
        // Body weight, sex and training status give first-time lifts a starting weight (`LoadEstimator`);
        // the warm-up tier's minutes count toward the time.
        basePlan = gym.planner.plan(focus: resolvedFocus, minutes: minutes, recovery: metrics.recoveryForTraining, history: history, block: block,
                                focusReason: focus == nil ? autoReason : nil,
                                prioritySlots: coverage?.prioritySlots ?? [],
                                bodyMassKg: metrics.bodyMassKg, sex: metrics.sex,
                                trainingStatus: metrics.trainingStatus ?? .novice,
                                warmUpMinutes: warmUpMinutes,
                                exerciseFilter: exerciseFilter.isEmpty ? nil : exerciseFilter,
                                muscleSetGoals: plans.sessionSetGoals(focus: resolvedFocus, minutes: minutes, muscles: muscles,
                                                                      sessions: sessions, extra: metrics.recentTrainingDays))
        applyTimeSaver()
    }

    // MARK: Time-saving sets

    /// The goals the evidence is tailored to (nil until you've set them).
    private var goals: Goals? { settings.goalsSet ? settings.goals : nil }

    /// `plan` from `basePlan`: with the time-saving style when it's on and on
    /// offer for this session (short, a goal it suits, eligible small lifts).
    private func applyTimeSaver() {
        guard let basePlan else {
            plan = nil
            timeSaverOptions = []
            return
        }
        let options = TimeSaver.options(for: basePlan, minutes: minutes, goals: goals, gym: gym.profile,
                                        style: gym.style, warmUpMinutes: warmUpMinutes)
        timeSaverOptions = options
        if let first = options.first, !options.contains(where: { $0.kind == timeSaverKind }) {
            timeSaverKind = first.kind
        }
        if useTimeSaver, options.contains(where: { $0.kind == timeSaverKind }) {
            plan = TimeSaver.apply(timeSaverKind, to: basePlan, gym: gym.profile, style: gym.style, warmUpMinutes: warmUpMinutes)
        } else {
            plan = basePlan
        }
    }

    /// "Same work, less time" on a short session, or why a strength-only
    /// goal keeps straight sets.
    @ViewBuilder
    private var timeSaverSection: some View {
        if !timeSaverOptions.isEmpty {
            TimeSaverCard(options: timeSaverOptions, isOn: $useTimeSaver, kind: $timeSaverKind,
                          strengthNote: TimeSaver.strengthNote(goals))
        } else if minutes <= TimeSaver.shortSessionMinutes, !TimeSaver.suitsGoals(goals),
                  let note = TimeSaver.strengthNote(goals) {
            Text(note)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// True when there's another exercise for the same movement to swap to.
    private func canSwap(at index: Int, in plan: PlannedWorkout) -> Bool {
        guard index < plan.exercises.count,
              let slot = ExerciseCatalog.slot(for: plan.exercises[index].exerciseID) else { return false }
        return planner.alternatives(for: slot).count > 1
    }

    /// Replaces an exercise with the next option for the same movement.
    private func swap(at index: Int) {
        guard var current = basePlan, index < current.exercises.count,
              let slot = ExerciseCatalog.slot(for: current.exercises[index].exerciseID) else { return }
        let options = planner.alternatives(for: slot)
        guard options.count > 1,
              let position = options.firstIndex(where: { $0.id == current.exercises[index].exerciseID }) else { return }
        let next = options[(position + 1) % options.count]
        let history = LiftHistory.make(from: sessions, unit: gym.profile.unit)
        // Same starting-weight estimate as the plan (`LoadEstimator`) for a lift with no history.
        let lifter = LoadEstimator.Lifter(bodyMassKg: metrics.bodyMassKg, sex: metrics.sex,
                                          status: metrics.trainingStatus ?? .novice)
        var replacement = planner.prescribe(next, slot: slot, minutes: minutes, sessionRPE: current.targetRPE,
                                            history: history, lifter: lifter)
        // A lighter load on a lift that loads a 3-5/10 area (`PainGuard`).
        exerciseFilter.capLoad(&replacement, slot: slot, gym: gym.profile)
        // Keep the fitted set count and any superset pairing; redo the warm-up ramp for the new lift.
        replacement.sets = current.exercises[index].sets
        replacement.supersetGroup = current.exercises[index].supersetGroup
        current.exercises[index] = replacement
        gym.planner.addWarmUps(&current.exercises)
        current.estimatedMinutes = WorkoutPlanner.estimatedMinutes(current.exercises, style: gym.style, warmUpMinutes: warmUpMinutes)
        // Swaps change the plan before time-saving sets, which are then redone (`TimeSaver`).
        basePlan = current
        applyTimeSaver()
    }

    // MARK: Pain and never again

    /// Everything logged: the trainer's pain log, the morning check-ins and Apple Health.
    private var painReports: [PainReport] {
        painLog.allReports(checkIns: checkIns, health: healthPains)
    }

    /// Pain still current (newest per area, 7 days; `PainGuard.active`) and
    /// areas that have hurt for 2+ weeks (the clinician line).
    private func refreshPains() {
        let reports = painReports
        let active = PainGuard.active(reports, today: .now)
        activePains = active
        clinicianAreas = active.map(\.area).filter { PainGuard.seeClinician($0, reports: reports, today: .now) }
    }

    private var exerciseFilter: ExerciseFilter {
        ExerciseFilter(neverAgain: exclusions.ids, pains: activePains)
    }

    /// The gym's planner with the filter set, so swaps skip never-again and painful lifts.
    private var planner: WorkoutPlanner {
        var planner = gym.planner
        planner.exerciseFilter = exerciseFilter
        return planner
    }

    private func loadHealthPains() async {
        guard let health else { return }
        let start = Calendar.current.date(byAdding: .day, value: -PainLogStore.keepDays, to: .now) ?? .now
        let found = (try? await health.reportedPain(from: start, to: .now)) ?? []
        guard !found.isEmpty else { return }
        healthPains = found
        rebuild()
    }

    private func logPain(_ changed: [PainReport]) {
        painLog.log(changed)
        // Lower back pain → Apple Health's symptom type, the only area it has.
        if let back = changed.first(where: { $0.area == .lowerBack }), let health {
            let level = back.level
            Task { try? await health.saveLowerBackPain(level: level, date: .now) }
        }
    }

    private func neverAgain(_ exercise: PlannedExercise) {
        exclusions.add(id: exercise.exerciseID, name: exercise.name)
        rebuild()
    }

    /// What an exercise needs, for "Needs equipment I don't have".
    private func equipment(for exercise: PlannedExercise) -> [EquipmentKind] {
        let needs = ExerciseCatalog.exercise(id: exercise.exerciseID)?.requires ?? []
        return needs.filter { $0 != .bodyweight }.sorted { $0.label < $1.label }
    }

    /// Takes equipment out of the gym profile (it can go back under Gym equipment).
    private func removeEquipment(_ kind: EquipmentKind) {
        var profile = gym.profile
        profile.equipment.remove(kind)
        gym.save(profile)
        rebuild()
    }

    /// Saved workouts or an empty one, as a plain row after the plan (ux-audit 4.6, 4.7).
    private var ownWorkoutLink: some View {
        NavigationLink {
            MyWorkoutsView(onStart: { dismiss() })
        } label: {
            HStack(spacing: 12) {
                Text("Saved workouts or empty workout")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var gymPrompt: some View {
        Button {
            showingGym = true
        } label: {
            HStack(spacing: 12) {
                IconBadge(systemName: "slider.horizontal.3", color: Theme.lifting, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up your gym equipment")
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

    /// One time control. Under 30 minutes the plan keeps the same exercises
    /// with fewer sets, then pairs them (A1/A2): paired sets keep growth and
    /// most strength while cutting time by about a third (Iversen et al.,
    /// Sports Med 2021).
    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "Time")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(durations, id: \.self) { value in
                        SelectChip(title: "\(value) min", isSelected: minutes == value) { minutes = value }
                    }
                }
            }
            .scrollIndicators(.hidden)
            if minutes < 30 {
                Text("Short on time: fewer sets, then paired exercises (A1/A2) with one rest after both.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func summaryCard(_ plan: PlannedWorkout) -> some View {
        let planner = StrainPlanner()
        let estimated = plan.estimatedMinutes ?? WorkoutPlanner.estimatedMinutes(plan.exercises, style: gym.style)
        let gain = metrics.strainGain(addedLoad: planner.liftingLoad(minutes: Double(estimated), rpe: plan.targetRPE))
        let current = metrics.strain?.strain ?? 0
        let landsAt = current + gain
        return VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Suggested", color: Theme.liftingText)
            Text(plan.title)
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.primaryText)
            planStats(minutes: estimated, rpe: plan.targetRPE, gain: gain)
            if let target = metrics.targetStrain {
                let inRange = target.contains(landsAt)
                let line: String = inRange
                    ? "Lands you around \(strainText(landsAt)) strain, inside today's range (\(strainRangeText(target)))."
                    : "Lands you around \(strainText(landsAt)) strain. Today's range: \(strainRangeText(target))."
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(inRange ? Theme.recoveryHighText : Theme.secondaryText)
            }
            blockLine(plan)
            whyLine(plan)
            musclesRow(plan)
        }
        .card()
    }

    /// Why this session today (`PlannedWorkout.rationale`).
    @ViewBuilder
    private func whyLine(_ plan: PlannedWorkout) -> some View {
        if !plan.rationale.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Why this session")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(plan.rationale)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The muscles the session covers, as chips ("Chest · Shoulders · Triceps").
    @ViewBuilder
    private func musclesRow(_ plan: PlannedWorkout) -> some View {
        let muscles = plan.musclesCovered
        if !muscles.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(muscles, id: \.self) { muscle in
                        Chip(text: muscle, color: Theme.lifting)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Muscles: \(muscles.joined(separator: ", "))")
        }
    }

    /// Time, effort and strain side by side; stacked at accessibility text
    /// sizes so none is cut off (ux-audit.md 4.8, P22).
    private func planStats(minutes: Int, rpe: Double, gain: Double) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 18))
        return layout {
            StatView(label: "Time", value: "~\(minutes) min")
            StatView(label: "Effort", value: "\(rpe.formatted())/10")
            StatView(label: "Strain", value: "≈+\(strainText(gain))", color: Theme.strainTextColor)
        }
    }

    /// "Block week 3 of 5 · RIR 1" and what it means, plus the superset note.
    @ViewBuilder
    private func blockLine(_ plan: PlannedWorkout) -> some View {
        if let week = plan.blockWeek {
            VStack(alignment: .leading, spacing: 4) {
                Chip(text: week.label, color: week.isDeload ? Theme.oxygen : Theme.lifting)
                Text(week.note)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        if plan.hasSupersets {
            Text("Paired exercises (A1/A2): one set of each, then rest. About a third less time for the same work (Iversen et al. 2021).")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// "Same work, less time": the short session's small lifts as one drop set,
/// rest-pause or myo-rep set each, with the time it saves. One line up front;
/// which lifts, the evidence and the safety rule behind "Details"
/// (`TimeSaver`, `SetKind.evidence`). A converted set counts as the straight
/// sets it replaces for weekly volume (`SetStructure.hardSetCredit`), so the
/// headline says "same sets".
struct TimeSaverCard: View {
    let options: [TimeSaver.Option]
    @Binding var isOn: Bool
    @Binding var kind: SetKind
    var strengthNote: String?

    private var selected: TimeSaver.Option? {
        options.first { $0.kind == kind } ?? options.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "Same work, less time", color: Theme.liftingText)
            Toggle(isOn: $isOn) {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
            }
            .tint(Theme.lifting)
            if options.count > 1 {
                Picker("Style", selection: $kind) {
                    ForEach(options) { option in
                        Text(option.kind.title).tag(option.kind)
                    }
                }
                .pickerStyle(.segmented)
            }
            DisclosureGroup("Details") {
                details
            }
            .font(.caption)
            .tint(Theme.secondaryText)
        }
        .card()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let selected {
                Text(lifts(selected))
                Text(selected.kind.evidence)
            }
            // Safety: multi-joint lifts keep straight sets (`TimeSaver.isEligible`).
            Text("Big lifts (squats, presses, rows, deadlifts) keep straight sets: no-rest sets under a heavy bar are where form slips.")
            if let strengthNote { Text(strengthNote) }
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    /// "Same sets, about 2 min less".
    private var headline: String {
        guard let selected else { return "" }
        return "Same sets, about \(selected.minutesSaved) min less"
    }

    /// "Lateral Raise, Curl as one drop set each; it counts as the sets it replaces."
    private func lifts(_ option: TimeSaver.Option) -> String {
        let names = option.exerciseNames.joined(separator: ", ")
        let each = option.exerciseNames.count > 1 ? " each" : ""
        return "\(names) as one \(option.kind.title.lowercased())\(each); it counts as the sets it replaces."
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
                .frame(minHeight: 44)
                .contentShape(.rect)
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
    /// "A1" / "A2" when the exercise is in a superset; the number otherwise.
    var label: String? = nil
    /// "Never again": the trainer never plans or offers it again.
    var onNeverAgain: (() -> Void)? = nil
    /// What the exercise needs, for "Needs equipment I don't have".
    var equipment: [EquipmentKind] = []
    var onMissingEquipment: ((EquipmentKind) -> Void)? = nil

    /// Supersets are shown in the sleep colour so the pair stands out from the numbering.
    private var badgeColor: Color { label == nil ? Theme.lifting : Theme.sleep }
    /// Text colours that pass 4.5:1 on the tinted badge in light and dark
    /// (`sleepDeep` was too dark in dark mode; ux-audit.md X4, P24).
    private var badgeTextColor: Color { label == nil ? Theme.liftingText : Theme.sleepText }
    /// Fits "A1" or "12" at every text size.
    @ScaledMetric(relativeTo: .headline) private var badgeSize: CGFloat = 34
    @State private var showingGuide = false
    /// The ⓘ: muscles, plates, how the weight moved, stages and warm-up.
    @State private var showingDetails = false
    @Environment(ExerciseLibrary.self) private var library

    /// "Lats, biceps": the exercise library's primary then secondary muscles
    /// when it knows the exercise, else the catalog's (`PlannedExercise.muscles`).
    private var muscleLine: String? {
        var names = exercise.muscles
        if let entry = library.exercise(id: exercise.exerciseID) {
            names = entry.primaryMuscles + entry.secondaryMuscles
        }
        guard !names.isEmpty else { return nil }
        let line = names.prefix(4).map { $0.lowercased() }.joined(separator: ", ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Tap the exercise for how to do it, with form videos.
                Button { showingGuide = true } label: {
                    summary
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows how to do it, with form videos")
                Spacer(minLength: 0)
                if !detailLines.isEmpty {
                    infoButton
                }
                if onSwap != nil || onNeverAgain != nil {
                    optionsMenu
                }
            }
            if showingDetails {
                detailsList
                    .padding(.leading, badgeSize + 12)
            }
        }
        .card()
        .sheet(isPresented: $showingGuide) {
            ExerciseGuideSheet(exerciseID: exercise.exerciseID, name: exercise.name)
        }
    }

    /// Swap, "Needs equipment I don't have" and "Never again".
    private var optionsMenu: some View {
        Menu {
            if let onSwap {
                Button("Swap for another", systemImage: "arrow.triangle.2.circlepath", action: onSwap)
            }
            if let onMissingEquipment, !equipment.isEmpty {
                Menu("Needs equipment I don't have", systemImage: "wrench.and.screwdriver") {
                    ForEach(equipment) { kind in
                        Button("Remove \(kind.label.lowercased()) from my gym") { onMissingEquipment(kind) }
                    }
                }
            }
            if let onNeverAgain {
                Button("Never again", systemImage: "nosign", role: .destructive, action: onNeverAgain)
            }
        } label: {
            Image(systemName: onSwap == nil ? "ellipsis" : "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 44, height: 44)
                .background(Theme.cardRaised, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Options for \(exercise.name)")
        .accessibilityHint("Swap it, mark equipment you don't have, or never plan it again")
    }

    /// "3 × 6–8 · 2 in reserve · 60 kg": the one line that matters.
    private var prescription: String {
        let reserve = ReserveText.text(rpe: exercise.rpe)
        var line = "\(exercise.sets) × \(exercise.reps.lowerBound)–\(exercise.reps.upperBound) · \(reserve)"
        if let load = exercise.load {
            line += " · \(load.formatted(.number.precision(.fractionLength(0...2)))) \(unit.rawValue)"
        }
        return line
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label ?? "\(index)")
                .font(.headline)
                .foregroundStyle(badgeTextColor)
                .frame(width: badgeSize, height: badgeSize)
                .background(badgeColor.opacity(0.12), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(prescription)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.strainTextColor)
            }
        }
    }

    /// Everything else, behind the ⓘ: how the weight moved (double
    /// progression, `WorkoutPlanner.suggestedLoad`), plates and notes, drop
    /// stages or mini-sets (`TimeSaver`), ramp sets (`WarmUp`; Ribeiro et al.
    /// 2020) and the muscles.
    private var detailLines: [String] {
        var lines: [String] = []
        if let progression = exercise.progressionNote { lines.append(progression) }
        if let note = exercise.note { lines.append(note) }
        if let stages = TimeSaver.describe(exercise, unit: unit) { lines.append(stages) }
        if let warmUps = exercise.warmUpSets, !warmUps.isEmpty { lines.append("Warm-up: \(WarmUp.summary(warmUps))") }
        if let muscleLine { lines.append(muscleLine) }
        return lines
    }

    private var detailsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(detailLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var infoButton: some View {
        Button {
            withAnimation(.snappy) { showingDetails.toggle() }
        } label: {
            Image(systemName: showingDetails ? "info.circle.fill" : "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showingDetails ? "Hide details" : "Show details")
        .accessibilityHint("How the weight moved, plates, warm-up and muscles")
    }
}

/// "Something hurts?" above the plan: what the trainer is working around,
/// or the prompt to log it.
struct PainGuardRow: View {
    let pains: [PainReport]
    let clinicianAreas: [PainArea]
    let neverAgainCount: Int
    let action: () -> Void

    /// Pain the trainer acts on (3/10 and up, `PainGuard.response`).
    private var acted: [PainReport] { pains.filter { PainGuard.response(to: $0) != .unchanged } }

    /// "Something hurts?", "Working around pain", or for 1-2/10 only
    /// "Logged: knee 2/10", where nothing in the plan changes.
    private var title: String {
        if pains.isEmpty { return "Something hurts?" }
        if !acted.isEmpty { return "Working around pain" }
        let logged = pains.map { "\($0.area.title.lowercased()) \($0.level)/10" }.joined(separator: ", ")
        return "Logged: " + logged
    }

    private var summary: String {
        var parts: [String] = []
        if pains.isEmpty {
            parts.append("Log a sore joint and the trainer works around it")
        } else if acted.isEmpty {
            parts.append("No changes below \(PainGuard.regressFrom)/10")
        } else {
            parts = acted.map { report in "\(report.area.title) \(report.level)/10" }
        }
        if neverAgainCount > 0 {
            let plural = neverAgainCount == 1 ? "" : "s"
            parts.append("\(neverAgainCount) never-again exercise\(plural)")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemName: "bandage.fill", color: Theme.recoveryLow, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                    ForEach(clinicianAreas) { area in
                        Text(PainGuard.clinicianText(area))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.recoveryLowText)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Log pain so the trainer can work around it")
    }
}

/// Log pain from the trainer, the 5/10 rule in plain words, and the
/// never-again list. Pushed inside the builder's stack (no sheet on a sheet).
struct PainLogView: View {
    let current: [PainReport]
    let exclusions: ExerciseExclusions
    /// Reports that are new or changed, to save.
    let onSave: ([PainReport]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: [PainReport]?

    init(current: [PainReport], exclusions: ExerciseExclusions, onSave: @escaping ([PainReport]) -> Void) {
        self.current = current
        self.exclusions = exclusions
        self.onSave = onSave
        _draft = State(initialValue: current.isEmpty ? nil : current)
    }

    var body: some View {
        Form {
            PainQuestions(pains: $draft)
            Section("Where the rule comes from") {
                Text(PainGuard.sourceText)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if !exclusions.items.isEmpty {
                neverAgainSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Something hurts?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(changed)
                    dismiss()
                }
            }
        }
    }

    /// Only what's new or different, so opening and saving doesn't renew old
    /// answers. An area you deselected is saved as 0/10, which clears it
    /// (`PainGuard.active`); otherwise it would stay avoided for 7 days.
    private var changed: [PainReport] {
        let reports = draft ?? []
        let edited = reports.filter { report in
            guard let before = current.first(where: { $0.area == report.area }) else { return true }
            return before.level != report.level || (before.worseAfterTraining ?? false) != (report.worseAfterTraining ?? false)
        }
        let cleared = current
            .filter { before in !reports.contains { $0.area == before.area } }
            .map { PainReport(area: $0.area, level: 0, loggedAt: .now) }
        return edited + cleared
    }

    private var neverAgainSection: some View {
        Section {
            ForEach(exclusions.items) { item in
                HStack {
                    Text(item.name)
                        .foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 8)
                    Button("Allow again") { exclusions.remove(id: item.id) }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Never again")
        } footer: {
            Text("The trainer won't plan or offer these. Allow one again to bring it back.")
        }
    }
}
