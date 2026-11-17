import SwiftUI
import AppCore

// One hard cardio session a week (`HardCardio`, `IntervalSession`): the offer
// and the choice in the weekly plan, the session's row in Fitness › This week,
// and its steps. Offered, never scheduled by default, and only when a reason
// applies; it promises vigorous minutes, not a VO2 max number.

/// What the offer needs from the app's models.
enum HardCardioInputs {
    /// The offer for `plan`'s week, or nil when nothing calls for it or the
    /// week can't take it (`HardCardio.offer`).
    static func offer(plan: WeeklyPlan, settings: UserSettings, vitals: VitalsModel, gym: GymProfile?,
                      blockLength: Int?, restMode: Bool, isDeloadWeek: Bool, now: Date = .now) -> HardCardio.Offer? {
        let goals = settings.goalsSet ? settings.goals : nil
        let history = vitals.vo2MaxHistory.map { DayValue(date: $0.date, value: $0.value) }
        // Zero, not nil, without heart rate: the day series says whether there was any (as `LongevityAssembler`).
        var vigorous: Int?
        if let minutes = vitals.intensityMinutes, vitals.stat("intensity")?.series.isEmpty == false {
            vigorous = minutes.vigorous
        }
        return HardCardio.offer(plan: plan, goals: goals, gym: gym, vo2: vitals.vo2ForScores?.value,
                                age: settings.ageIsSet ? settings.age : nil, sex: settings.sexIsSet ? settings.sex : nil,
                                vo2History: history, blockWeeks: blockLength ?? 6, weeklyVigorousMinutes: vigorous,
                                restMode: restMode, isDeloadWeek: isDeloadWeek, now: now)
    }

    /// The zones the user picked, as the Watch's cardio mode uses them.
    static func scheme(metrics: DailyMetricsModel, settings: UserSettings) -> HeartRateZoneScheme {
        ZonePreferences.resolution(profile: metrics.heartRateProfile ?? settings.heartRateProfile(restingHeartRate: nil)).scheme
    }

    /// A day that reads as easy: 7-day HRV below normal or recovery in the low band.
    static func lowRecovery(metrics: DailyMetricsModel) -> Bool {
        if metrics.trainEasyToday { return true }
        guard let recovery = metrics.recovery, !metrics.recoveryIsFromYesterday else { return false }
        return recovery.score <= RecoveryCalculator.lowBand.upperBound
    }
}

// MARK: - Weekly plan

/// The weekly plan's "One hard cardio session" section: shown when the offer
/// applies or the session is already chosen; nothing otherwise.
struct HardCardioPlanSection: View {
    @Binding var choice: HardCardio.Choice?
    /// The week as edited, with the choice in its cardio.
    let draft: WeeklyPlan
    let offer: HardCardio.Offer?
    let blocker: HardCardio.Blocker?
    let modalities: [IntervalSession.Modality]
    let scheme: HeartRateZoneScheme?

    var body: some View {
        if choice != nil || offer != nil {
            Section {
                Toggle("Intervals once a week", isOn: isOn)
                    .accessibilityIdentifier("plan.hardCardio")
                if let choice {
                    Picker("On", selection: modality) {
                        ForEach(modalities) { option in
                            Label(option.label, systemImage: option.systemImage).tag(option)
                        }
                    }
                    .accessibilityIdentifier("plan.hardCardio.modality")
                    Toggle("Shorter version (3 rounds)", isOn: isShort)
                        .accessibilityIdentifier("plan.hardCardio.short")
                    Text(HardCardio.placementText(weekday: draft.isFlexible ? nil : HardCardio.weekday(for: draft),
                                                  replacesEasy: (draft.cardio?.sessionsPerWeek ?? 0) > 0))
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                    if let blocker {
                        Text(blocker.text)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    NavigationLink {
                        IntervalSessionView(session: choice.session, scheme: scheme)
                    } label: {
                        Text("The session, step by step")
                    }
                    .accessibilityIdentifier("plan.hardCardio.steps")
                } else if let offer {
                    Text(offer.reasonText + " One interval session a week, in place of an easy one, is the best-tested way to raise cardio fitness.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("One hard cardio session")
            } footer: {
                Text(footer)
            }
        }
    }

    private var footer: String {
        let session = (choice ?? HardCardio.Choice(modality: modalities.first ?? .outdoorRun)).session
        // Milanović 2015 and Wen 2019 (intervals and VO2 max); Schumann 2022 (beside lifting); Ahmadi 2022 (minutes).
        return HardCardio.promise(session)
            + " Intervals raised VO2 max more than steady cardio across 28 trials (Milanović 2015). On a separate day from heavy legs they cost no muscle or maximal strength (Schumann 2022)."
    }

    private var isOn: Binding<Bool> {
        Binding(
            get: { choice != nil },
            set: { on in choice = on ? HardCardio.Choice(modality: modalities.first ?? .outdoorRun) : nil }
        )
    }

    private var modality: Binding<IntervalSession.Modality> {
        Binding(
            get: { choice?.modality ?? modalities.first ?? .outdoorRun },
            set: { choice?.modality = $0 }
        )
    }

    private var isShort: Binding<Bool> {
        Binding(get: { choice?.isShort ?? false }, set: { choice?.isShort = $0 })
    }
}

// MARK: - Gym equipment

/// Gym equipment › Cardio machines: the bike, rower and treadmill the gym has,
/// so the interval session is only offered on what's there (`GymProfile.cardioMachines`).
struct CardioMachinesSection: View {
    @Binding var machines: Set<CardioMachine>?

    var body: some View {
        Section {
            ForEach(CardioMachine.allCases) { machine in
                Toggle(machine.label, isOn: Binding(
                    get: { machines?.contains(machine) ?? false },
                    set: { isOn in
                        var updated = machines ?? []
                        if isOn { updated.insert(machine) } else { updated.remove(machine) }
                        machines = updated
                    }
                ))
                .accessibilityIdentifier("gym.cardio.\(machine.rawValue)")
            }
        } header: {
            Text("Cardio machines")
        } footer: {
            Text("Only for the weekly interval session, if you take it: it's planned on these, or outdoors.")
        }
    }
}

// MARK: - This week

/// Fitness › This week: the chosen interval session, its day and a tick once
/// Apple Health has it; tapping shows the steps. On its day, when the day
/// reads as easy, it says to wait; in rest mode or the deload week it says
/// why it isn't on.
struct HardCardioWeekRow: View {
    @Environment(WeeklyPlanStore.self) private var store
    @Environment(MuscleModel.self) private var muscles
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @State private var showingSteps = false

    var body: some View {
        if let plan = store.current, let slot = HardCardio.slot(for: plan, goals: metrics.goals) {
            let blocker = HardCardio.blocker(plan: plan, goals: metrics.goals, restMode: settings.isRestMode,
                                             isDeloadWeek: store.projectedBlockWeek(hrvBelowNormal: metrics.trainEasyToday)?.isDeload ?? false)
            let isDone = HardCardio.weekDone(plan: plan, goals: metrics.goals,
                                             workouts: WeeklyPlanStore.cardioWorkouts(muscles: muscles, metrics: metrics)).hard
            let day = slot.weekday.map { WeeklyPlan.weekdayName($0) } ?? "Any day"
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    showingSteps = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isDone ? Theme.recoveryHigh : Theme.secondaryText)
                        Label("Intervals · \(slot.session.title)", systemImage: slot.choice.modality.systemImage)
                            .font(.subheadline)
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        Text(day)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Intervals, \(slot.session.title), \(day): \(isDone ? "done" : "planned")")
                .accessibilityHint("Shows the session step by step")
                .accessibilityIdentifier("thisWeek.hardCardio")
                if !isDone, let note = note(slot: slot, blocker: blocker) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .sheet(isPresented: $showingSteps) {
                NavigationStack {
                    IntervalSessionView(session: slot.session, scheme: HardCardioInputs.scheme(metrics: metrics, settings: settings))
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingSteps = false }
                            }
                        }
                }
            }
        }
    }

    private func note(slot: HardCardio.Slot, blocker: HardCardio.Blocker?) -> String? {
        if let blocker, blocker == .restMode || blocker == .deloadWeek {
            return blocker.text + " An easy \(EasyCardio.standardMinutes) minutes instead, if you like."
        }
        let today = Calendar.current.component(.weekday, from: .now)
        return HardCardio.dayNote(slot: slot, weekday: today, lowRecovery: HardCardioInputs.lowRecovery(metrics: metrics))
    }
}

// MARK: - Steps

/// The interval session step by step: each step's length, heart-rate band in
/// your zones (the same ones the Watch's cardio mode uses), effort and cue.
struct IntervalSessionView: View {
    let session: IntervalSession
    let scheme: HeartRateZoneScheme?

    var body: some View {
        List {
            Section {
                ForEach(session.steps) { step in
                    IntervalStepRow(step: step, rounds: session.rounds, scheme: scheme)
                }
            } header: {
                Text("\(session.totalMinutes) min · \(session.hardMinutes) min hard")
            } footer: {
                Text("Effort leads: heart rate takes a minute or two to climb in each hard round. Any timer works, or the machine's own interval programme.")
            }
            Section {
                Text(HardCardio.promise(session))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } header: {
                Text("What it gives")
            } footer: {
                // Helgerud 2007 (4 × 4 at 90-95% of max, 3 min at 70%); Wen 2019 (long intervals, 15+ hard minutes).
                Text("The four-by-four comes from a trial in which it raised VO2 max more than the same work done steadily (Helgerud 2007). Intervals of two minutes or more, with 15 or more hard minutes, did most across 53 trials (Wen 2019).")
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("intervalSession.steps")
    }
}

private struct IntervalStepRow: View {
    let step: IntervalSession.Step
    let rounds: Int
    let scheme: HeartRateZoneScheme?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(step.title(rounds: rounds))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(step.phase.isHard ? Theme.strainTextColor : Theme.primaryText)
                Spacer(minLength: 8)
                Text(step.lengthText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
            Text("\(step.target.band.text(in: scheme)) · \(step.target.effortText)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text(step.target.cue)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
