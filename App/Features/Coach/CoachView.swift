import SwiftUI
import SwiftData
import AppCore

/// Chat with the AI coach. Training questions come back with a workout card
/// built from your gym and recovery, ready to start.
struct CoachView: View {
    @Environment(CoachModel.self) private var coach
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(GymStore.self) private var gym
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(MedicationsModel.self) private var medications
    @Environment(LabsModel.self) private var labs
    @Environment(CheckInStore.self) private var checkIns
    @Environment(ConditionsModel.self) private var conditions
    @Environment(VitalsModel.self) private var vitals
    @Environment(MuscleModel.self) private var muscles
    @Environment(WeeklyPlanStore.self) private var weeklyPlans
    @Environment(BodyMeasurementsStore.self) private var measurements
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var draft = ""
    /// The send button grows with Dynamic Type and never drops below 44 pt (HIG Accessibility; ux-audit.md P23).
    @ScaledMetric(relativeTo: .headline) private var sendButtonSize: CGFloat = 44
    @FocusState private var inputFocused: Bool
    @State private var showingStatus = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        modeLine
                        if let message = OnDeviceCoach.availabilityMessage {
                            ModelStatusBanner(message: message)
                        }
                        contextChips
                        // Messages the coach sent first (`CoachNudges`), with their follow-up question.
                        CoachInboxSection(ask: { question in Task { await send(question) } })
                        if coach.messages.isEmpty {
                            emptyState
                        }
                        ForEach(coach.messages) { message in
                            MessageView(
                                message: message,
                                onStart: { plan in launcher.start(plan, in: modelContext) },
                                onRetry: retryAction(for: message),
                                onSayMore: sayMoreAction(for: message)
                            )
                            .id(message.id)
                        }
                        if coach.isThinking {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Thinking…").foregroundStyle(Theme.secondaryText)
                            }
                            .id("thinking")
                        }
                        if !coach.messages.isEmpty && !coach.isThinking {
                            followUps
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .lockedToScreenWidth()
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: coach.messages.last?.id) {
                    guard let lastID = coach.messages.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastID, anchor: .top) }
                }
                .onChange(of: coach.isThinking) { _, thinking in
                    guard thinking else { return }
                    withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                }
            }
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.lavender, Theme.Wash.rose, Theme.Wash.sky])
            }
            .background(Theme.background)
            // System navigation bar with a large title and a compose button
            // (docs/research/ux-audit.md 4.1 rule 1, 4.6 Coach; HIG Toolbars).
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New conversation", systemImage: "square.and.pencil") {
                        coach.newConversation()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Coach status", systemImage: "waveform.path.ecg") { showingStatus = true }
                    }
                }
            }
            .sheet(isPresented: $showingStatus) {
                CoachDiagnosticsView(diagnostics: coach.diagnostics)
            }
            .tabToolbar()
            .safeAreaInset(edge: .bottom) { inputBar }
            // Load the model's assets while the user reads, so the first answer is quicker.
            .onAppear { OnDeviceCoach.prewarm() }
            .task(id: coach.pendingQuestion) {
                if let question = coach.pendingQuestion {
                    coach.pendingQuestion = nil
                    await send(question)
                }
            }
        }
    }

    /// What the coach knows and where it runs; the title is in the navigation bar.
    private var modeLine: some View {
        Text("Answers come from your data; Apple's on-device model handles the rest")
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryText)
    }

    private var contextChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if let recovery = metrics.recovery {
                    ContextChip(color: RecoveryWording.color(for: recovery.status), label: "Recovery",
                                value: recovery.isCalibrated ? "\(recovery.score)% · \(RecoveryWording.label(for: recovery.status))" : "\(recovery.score)%")
                }
                if let strain = metrics.strain {
                    let target = metrics.targetStrain.map { " · range " + strainRangeText($0) } ?? ""
                    ContextChip(color: Theme.strain, label: "Strain", value: "\(strainText(strain.strain))\(target)")
                }
                if let protein = metrics.nutritionToday?.proteinGrams {
                    ContextChip(color: Theme.nutrition, label: "Protein", value: "\(whole(protein)) g")
                }
                // Same numbers as Today's calorie card, eaten against the target with no
                // "over" verdict; hidden with the Settings switch.
                if !settings.hideCalories, let target = metrics.calorieTarget, let eaten = metrics.calories?.eaten {
                    ContextChip(color: Theme.lifting, label: "Calories", value: "\(whole(eaten)) / \(whole(target)) kcal")
                }
            }
        }
        .scrollIndicators(.hidden)
        .edgeToEdgeChips()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about training, recovery, sleep or food.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text(gym.isConfigured
                 ? "Workouts are built from \(gym.profile.name) and rounded to the weights you can load."
                 : "Add your gym equipment in Settings so workouts use what you have.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            ForEach(CoachModel.suggestions, id: \.self) { suggestion in
                Button {
                    Task { await send(suggestion) }
                } label: {
                    Text(suggestion)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .frame(minHeight: 44)
                        .background(Theme.card, in: .capsule)
                        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
    }

    private var followUps: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(CoachIntent.followUps(after: coach.messages.last { $0.role == .coach }?.question), id: \.self) { text in
                    Button {
                        Task { await send(text) }
                    } label: {
                        Text(text)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .background(Theme.card, in: .capsule)
                            .overlay(Capsule().strokeBorder(Theme.separator))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .edgeToEdgeChips()
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask your coach…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit { Task { await sendDraft() } }
            Button {
                Task { await sendDraft() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: sendButtonSize, height: sendButtonSize)
                    .background(LinearGradient(colors: [Theme.sleep, Theme.lifting], startPoint: .bottomLeading, endPoint: .topTrailing), in: .circle)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coach.isThinking)
            .accessibilityLabel("Send")
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func sendDraft() async {
        let text = draft
        draft = ""
        await send(text)
    }

    /// For an error bubble: resends the user message that got the error.
    private func retryAction(for message: CoachModel.ChatMessage) -> (() -> Void)? {
        guard message.role == .error,
              let index = coach.messages.firstIndex(where: { $0.id == message.id }),
              let question = coach.messages[..<index].last(where: { $0.role == .user }) else { return nil }
        let text = question.text
        return { Task { await send(text) } }
    }

    /// For a data-backed reply: asks the on-device model to say more about it.
    private func sayMoreAction(for message: CoachModel.ChatMessage) -> (() -> Void)? {
        guard message.canSayMore, OnDeviceCoach.availabilityMessage == nil else { return nil }
        return { Task { await coach.sayMore(about: message) } }
    }

    /// Rest mode or a rest day in the weekly plan: no workout card unless the
    /// user asks anyway ("give me a workout anyway", "I want to train"), so the
    /// card never contradicts an answer that says rest.
    private func restingToday(for text: String) -> Bool {
        let resting = settings.isRestMode || metrics.dayGuidance?.isRestDay == true
        return resting && !CoachIntent.insistsOnWorkout(text)
    }

    private func send(_ text: String) async {
        var plan: PlannedWorkout?
        if CoachModel.isTrainingQuestion(text) && !CoachModel.wantsCardio(text) && !restingToday(for: text) {
            let (focus, minutes) = CoachModel.requestedFocusAndMinutes(text)
            let lastPlan = coach.messages.last { $0.plan != nil }?.plan
            let resolvedFocus = focus ?? lastPlan?.focus
                ?? WorkoutPlanner.suggestedFocus(recentExerciseIDs: LiftHistory.recentExerciseIDs(sessions))
            // The same request as the workout builder (`TrainerPlanRequest`): the week's set targets,
            // movements for muscles behind on the week, age, known numbers and the abs finisher.
            let history = LiftHistory.make(from: sessions, unit: gym.profile.unit)
            let left = weeklyPlans.progress(sessions: sessions)?.remaining ?? 2
            let request = TrainerPlanRequest(
                focus: resolvedFocus,
                minutes: minutes ?? lastPlan?.minutes ?? 45,
                prioritySlots: focus == nil ? (muscles.coverage(sessionsLeft: max(1, left), preferred: resolvedFocus)?.prioritySlots ?? []) : [],
                block: weeklyPlans.blockWeek,
                finisherLength: settings.absFinisher,
                exerciseFilter: ExerciseFilter(neverAgain: ExerciseExclusions.shared.ids,
                                               reports: PainLogStore.shared.allReports(checkIns: checkIns, health: []),
                                               today: .now),
                warmUpMinutes: WarmUpRoutine.make(tier: settings.warmUpTier(for: resolvedFocus),
                                                  firstSlots: resolvedFocus.slots, gym: gym.profile).minutes
            )
            let session = request.plan(gym: gym, plans: weeklyPlans, muscles: muscles, metrics: metrics,
                                       settings: settings, sessions: sessions, history: history)
            plan = AbsFinisher.appending(request.finisher(for: session, gym: gym, sessions: sessions, history: history),
                                         to: session)
        }
        await coach.send(text, facts: makeFacts(plan: plan), plan: plan)
    }
}

extension CoachView {
    /// Today's numbers as plain values for `CoachAnswers` (the answers the app
    /// gives without the model) and for the facts an open question gets.
    func makeFacts(plan: PlannedWorkout?) -> CoachFacts {
        var f = CoachFacts()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) ?? .now
        f.goals = settings.goalsSet ? settings.goals : nil
        f.restMode = settings.isRestMode

        f.strain = metrics.strain?.strain
        f.targetStrain = metrics.targetStrain
        f.yesterdayStrain = metrics.yesterdayStrain
        f.cardioLoad = metrics.strain?.cardioLoad
        f.liftingLoad = metrics.strain?.liftingLoad
        f.dayGuidance = metrics.dayGuidance
        f.hrvBelowNormal = metrics.trainEasyToday

        f.recovery = metrics.recovery?.score
        f.recoveryCalibrated = metrics.recovery?.isCalibrated ?? true
        f.recoveryContributors = metrics.recoveryContributors(drinksLastNight: checkIns.evening(on: yesterday)?.drinks, illness: illnessAlert)
        f.hrv = metrics.hrv
        f.hrvChangePercent = metrics.recovery?.hrvChangePercent
        f.restingHeartRate = metrics.restingHeartRate
        f.restingHeartRateChange = metrics.recovery?.restingHeartRateChange

        f.sleepScore = metrics.sleep?.score
        f.sleepHours = metrics.sleep.map { $0.asleep / 3600 }
        f.sleepNeedHours = metrics.sleep.map { $0.need / 3600 }
        f.deepHours = metrics.sleep.map { $0.deep / 3600 }
        f.remHours = metrics.sleep.map { $0.rem / 3600 }
        f.sleepInterruptions = metrics.sleep?.interruptions
        f.sleepDebtHours = metrics.sleepDebt?.hours

        // The same numbers as Today's calorie card; hidden with the Settings switch.
        if !settings.hideCalories {
            f.caloriesEaten = metrics.calories?.eaten ?? metrics.nutritionToday?.calories
            f.calorieTarget = metrics.calorieTarget
            f.caloriesProjectedBurn = metrics.calories?.projected ?? metrics.energy?.projectedTotal
        }
        f.proteinGrams = metrics.nutritionToday?.proteinGrams
        f.proteinTargetGrams = metrics.proteinTarget
        f.carbsGrams = metrics.nutritionToday?.carbsGrams
        f.bodyMassKg = metrics.bodyMassKg
        f.trainedToday = !metrics.activities.isEmpty
        f.caloriesHidden = settings.hideCalories
        if !settings.hideCalories, let summary = metrics.calories {
            f.caloriesBurnedSoFar = summary.burnedSoFar
            f.activeCaloriesSoFar = summary.activeSoFar
        }

        // Readings for the questions the app answers itself (and when the model is off).
        f.steps = metrics.steps
        f.stepGoal = vitals.stat("steps")?.goal
        f.vo2Max = vitals.vo2MaxHistory.max { $0.date < $1.date }?.value
        let unit = settings.weightUnit
        if let mass = metrics.bodyMassKg { f.bodyWeightText = "\(unit.format(mass)) \(unit.rawValue)" }
        if let weekly = metrics.weightTrendWeekly {
            let sign = weekly > 0 ? "+" : ""
            let perWeek = unit.display(weekly).formatted(.number.precision(.fractionLength(1)))
            f.weightTrendText = "\(sign)\(perWeek) \(unit.rawValue) a week"
        }
        f.trainingStyle = gym.style
        f.restTimerSeconds = RestPreferences.global

        if let plan {
            f.plannedSession = CoachFacts.PlannedSession(
                title: plan.title,
                minutes: plan.estimatedMinutes ?? WorkoutPlanner.estimatedMinutes(plan.exercises),
                exerciseCount: plan.exercises.count,
                rationale: plan.rationale,
                targetRPE: plan.targetRPE
            )
        }
        f.gymConfigured = gym.isConfigured
        let finished = sessions.filter { !$0.isActive }
        let cutoff = calendar.date(byAdding: .day, value: -14, to: .now) ?? .now
        f.workoutsLast14Days = finished.filter { $0.startedAt >= cutoff }.count
        if let last = finished.map(\.startedAt).max() {
            f.daysSinceLastWorkout = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: .now)).day
        }
        if let last = finished.max(by: { $0.startedAt < $1.startedAt }) {
            f.lastWorkout = lastWorkoutFact(last)
        }

        var extras = healthSummary.split(separator: "\n").map(String.init)
        if let weather = conditions.coachSummary(place: settings.placeName) { extras.append(weather) }
        if let plan = weeklyPlans.coachSummary(sessions: sessions, extra: metrics.recentLiftingDays) { extras.append(plan) }
        if let notes = checkIns.coachSummary { extras.append(contentsOf: notes.split(separator: "\n").map(String.init)) }
        if gym.isConfigured { extras.append(gym.planner.gymSummary()) }
        f.extraLines = extras
        f.medicationLines = medications.coachSummary
        f.labLines = labs.coachSummary ?? []
        return f
    }
}

extension CoachView {
    /// Today's illness-watch alert, the same one the recovery sheet shows.
    var illnessAlert: IllnessWatch.Alert? {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        return vitals.illnessAlert(metrics: metrics, drinksLastNight: checkIns.evening(on: yesterday)?.drinks,
                                   reportedSymptoms: checkIns.morning()?.isSick ?? false,
                                   daysSinceLastPeriod: checkIns.daysSinceLastPeriod())
    }

    /// The last finished gym session, for "How did my workout go?".
    func lastWorkoutFact(_ session: WorkoutSession) -> CoachFacts.LastWorkout {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: session.startedAt), to: calendar.startOfDay(for: .now)).day ?? 0
        let unit = settings.weightUnit
        let volume = session.totalVolumeKg
        let volumeText: String? = volume > 0
            ? "\(unit.display(volume).formatted(.number.precision(.fractionLength(0)))) \(unit.rawValue)" : nil
        let names = session.orderedExercises.filter { log in log.sets.contains { $0.isCompleted } }.map(\.name)
        return CoachFacts.LastWorkout(
            name: session.name,
            daysAgo: max(0, days),
            minutes: Int((session.duration / 60).rounded()),
            workingSets: session.effortSets.count,
            exerciseNames: names,
            sessionRPE: session.sessionRPE,
            volumeText: volumeText
        )
    }

    /// Everything newer the app knows, in a few lines for the coach.
    var healthSummary: String {
        var lines: [String] = []
        if settings.goalsSet {
            var line = "Goal: \(settings.goals.title)"
            if let target = metrics.calorieTarget { line += ", calorie target \(whole(target)) kcal/day" }
            if let protein = metrics.proteinTarget { line += ", protein \(whole(protein)) g/day" }
            lines.append(line + ".")
        }
        if let maintenance = metrics.maintenance {
            lines.append("Measured maintenance \(whole(maintenance.maintenance)) kcal/day from \(maintenance.loggedDays) days of food logs; weight trend \(maintenance.weeklyChangeKg.formatted(.number.precision(.fractionLength(2)))) kg/week.")
        }
        if let trend = metrics.recovery?.hrvTrend {
            lines.append("7-day HRV \(whole(trend.average)) ms, normal range \(whole(trend.normalRange.lowerBound))-\(whole(trend.normalRange.upperBound)) ms (\(trend.status.rawValue)).\(metrics.trainEasyToday ? " HRV-guided: an easy day suits today." : "")")
        }
        if let consistency = metrics.sleepConsistency { lines.append("Sleep Regularity Index \(consistency)/100 (last week).") }
        if let debt = metrics.sleepDebt {
            lines.append("Sleep debt \(debt.hours.formatted(.number.precision(.fractionLength(1)))) h over 14 nights (need \(settings.sleepNeedHours.formatted()) h)" + (debt.plan.map { "; plan: " + $0 } ?? "") + ".")
        }
        // Cut × sleep debt (`CutAndSleep`, Nedeltcheva 2010) and the 90-day VO₂ max trend (`CardioFitness.trend`).
        if let cut = CutAndSleep.advice(goals: settings.goalsSet ? settings.goals : nil, sleepDebt: metrics.sleepDebt) {
            lines.append("Cutting with high sleep debt: " + cut.message)
        }
        if let trend = CardioFitness.trend(vitals.vo2MaxHistory.map { DayValue(date: $0.date, value: $0.value) }) {
            let fitnessAge = CardioFitness.fitnessAge(vo2Max: trend.latest, age: settings.age, sex: settings.sex)
            lines.append("VO₂ max \(trend.latest.formatted(.number.precision(.fractionLength(1)))) ml/kg/min, 90-day trend \(trend.direction.rawValue); fitness age about \(fitnessAge) ±\(CardioFitness.watchUncertaintyYears) (one measure, FRIEND norms)." + (CardioFitness.nudge(for: trend).map { " " + $0 } ?? ""))
        }
        if settings.isRestMode {
            lines.append("REST MODE is on (the user is sick or resting): no strain target; suggest rest, sleep, fluids and at most easy walking, not workouts.")
        }
        if let metric = metrics.hrvMetric { lines.append("HRV metric: \(metric).") }
        // Heart-rate sources that disagreed today (`HeartRateMerge`): the ear sensor while lifting,
        // or the steadier series, was kept; averaging would have hidden the bad readings.
        if let worst = metrics.todaysDisagreements.max(by: { $0.minutes < $1.minutes }) {
            lines.append("Heart-rate sources disagreed today: \(worst.lowerSource) read about \(whole(abs(worst.meanDifference))) bpm lower than \(worst.higherSource) for \(worst.minutes) min; \(worst.preferredSource) was used for strain.")
        }
        if let water = metrics.nutritionToday?.waterLiters { lines.append("Water today \(water.formatted(.number.precision(.fractionLength(1)))) L.") }
        // Protein per meal and carbs by training day (`NutritionTargets`: Schoenfeld & Aragon 2018; Burke 2011),
        // low energy availability (`EnergyAvailability`: IOC REDs 2023) and the hand-typed body measurements.
        if let spread = NutritionTargets.proteinPerMeal(bodyMassKg: metrics.bodyMassKg, goals: settings.goalsSet ? settings.goals : nil, age: settings.age) {
            let trainingDay = !metrics.activities.isEmpty || weeklyPlans.todayPlan() != nil
            var line = "Protein per meal: about \(whole(spread.grams)) g at each of \(spread.meals) meals."
            if let carbs = NutritionTargets.carbsText(bodyMassKg: metrics.bodyMassKg, trainingDay: trainingDay, goals: settings.goalsSet ? settings.goals : nil) { line += " " + carbs }
            if let availability = metrics.energyAvailability, availability.isLow { line += " Energy availability is low (\(availability.valueText) over 7 days): suggest easing the deficit, not pushing through." }
            lines.append(line)
        }
        if let measured = measurements.coachSummary(heightCm: metrics.heightCm ?? (settings.heightCm > 0 ? settings.heightCm : nil), age: settings.age, sex: settings.sex) {
            lines.append(measured)
        }
        let lowNutrients = metrics.micronutrients.filter { $0.kind != .ok }
        if !lowNutrients.isEmpty {
            lines.append("Vitamins/minerals (7-day avg vs target): " + lowNutrients.map { "\($0.nutrient.name) \(Int($0.percentOfTarget.rounded()))% (\($0.kind.rawValue))" }.joined(separator: ", ") + ".")
        }
        if let alert = illnessAlert {
            lines.append("Illness watch (\(alert.level.label)): " + alert.signals.joined(separator: ", ") + ".")
        }
        // Daylight and apnoea from the newer HealthKit types (HealthKitClient+iOS26; Burns 2023; competitors.md §1g).
        if let daylight = vitals.daylightMinutesToday { lines.append("Time in daylight today \(whole(daylight)) min (2-hour anchor, observational evidence; Apple Watch).") }
        if !vitals.apnoeaNights30.isEmpty { lines.append("Apple Watch flagged possible sleep apnoea on \(vitals.apnoeaNights30.count) of the last 30 nights: suggest talking to a doctor; don't diagnose.") }
        if let deload = muscles.deload { lines.append("Deload suggested: stalled " + deload.stalledLifts.joined(separator: ", ") + ".") }
        let tired = muscles.states.values.filter { $0.status == .fatigued }.map(\.muscle.name)
        if !tired.isEmpty { lines.append("Fatigued muscles: " + tired.sorted().joined(separator: ", ") + ".") }
        lines.append(contentsOf: habitLines)
        return lines.joined(separator: "\n")
    }
}

extension CoachView {
    /// Caffeine, alcohol, heat, weight pace, body age, what moved recovery,
    /// and every Health stat, for the coach.
    var habitLines: [String] {
        var lines: [String] = []
        let calendar = Calendar.current

        // Caffeine cut-off from the usual bedtime (Gardiner et al. 2023).
        let bedtime = CaffeineTiming.usualBedtimeMinutes(metrics.recentBedtimes)
        var caffeine = "Usual bedtime \(CaffeineTiming.clockText(bedtime)); caffeine cut-off \(CaffeineTiming.clockText(CaffeineTiming.cutoffMinutes(bedtimeMinutes: bedtime, mg: 100))) for coffee, \(CaffeineTiming.clockText(CaffeineTiming.cutoffMinutes(bedtimeMinutes: bedtime, mg: 200))) for pre-workout"
        if let evening = checkIns.evening(), let mg = evening.caffeineMg, mg > 0, let minutes = evening.lastCaffeineMinutes {
            let late = CaffeineTiming.isTooLate(minutes: minutes, mg: mg, bedtimeMinutes: bedtime)
            caffeine += "; today \(Int(mg)) mg, last at \(CaffeineTiming.clockText(minutes))\(late ? " (too late for good sleep)" : "")"
        }
        lines.append(caffeine + ".")

        // The user's own alcohol effect, from their nights.
        let alcohol = checkIns.alcoholFindings.map { finding in
            let digits = finding.measure == .sleepScore ? 0 : 1
            let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(digits))
            return "\(finding.measure.rawValue) \(finding.withDrinks.formatted(format)) after drinking vs \(finding.without.formatted(format)) without (\(finding.nightsWith)/\(finding.nightsWithout) nights\(finding.isClear ? ", clear difference" : ", not clear yet"))"
        }
        if !alcohol.isEmpty { lines.append("Their alcohol effect: " + alcohol.joined(separator: "; ") + ".") }

        // Heat.
        if metrics.heatAdjustment > 0 {
            lines.append("Hot day: strain target lowered by \(Int(metrics.heatAdjustment.rounded())) points; trained in the heat on \(conditions.heatTrainingDays) of the last 14 days (acclimation takes about 10-14 hot training days and fades after 2-3 weeks away from the heat).")
        }

        // Weight change speed (Helms et al. 2014).
        if let weekly = metrics.weightTrendWeekly, let mass = metrics.bodyMassKg,
           let message = WeightPace.message(WeightPace.check(weeklyChangeKg: weekly, bodyMassKg: mass, goals: settings.goalsSet ? settings.goals : nil)) {
            lines.append("Weight pace: " + message)
        }

        // Body age with its confidence and biggest factors.
        if let age = vitals.bodyAge {
            let factors = age.factors.prefix(3).map { "\($0.name) \($0.years >= 0 ? "+" : "")\($0.years.formatted(.number.precision(.fractionLength(1)))) y" }
            lines.append("Body age \(age.rangeLabel) vs real age \(age.age) (\(age.confidence.label.lowercased())): " + factors.joined(separator: ", ") + ".")
        }

        // What moved today's recovery.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) ?? .now
        // Illness signs have their own "Illness watch" line, which the prompt
        // leaves out; kept out of this line so it isn't dropped with them.
        let contributors = metrics.recoveryContributors(drinksLastNight: checkIns.evening(on: yesterday)?.drinks, illness: illnessAlert)
            .filter { $0.id != "illness" }
        if !contributors.isEmpty {
            lines.append("What moved recovery: " + contributors.prefix(5).map { "\($0.name) \($0.effect.rawValue) it (\($0.detail))" }.joined(separator: "; ") + ".")
        }

        // Every Health stat with a value (steps vs goal, strength days, blood pressure, sleep, etc.).
        let stats = vitals.stats.compactMap { stat -> String? in
            guard let value = stat.value else { return nil }
            let unit = stat.unit.isEmpty ? "" : " \(stat.unit)"
            return "\(stat.title) \(value)\(unit)" + (stat.status.map { " (\($0))" } ?? "")
        }
        if !stats.isEmpty { lines.append("Health stats: " + stats.joined(separator: "; ") + ".") }
        return lines
    }
}

/// Shown while Apple's on-device model can't answer (Apple Intelligence off,
/// not supported, or still downloading): data answers still work.
private struct ModelStatusBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.recoveryModerate)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Answers from your data still work.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.recoveryModerate.opacity(0.12), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// A horizontal chip row that runs to the screen edges instead of being
    /// cut at the page's 16-pt margin, with its first chip still aligned to
    /// the margin and the chip shadows left unclipped.
    func edgeToEdgeChips() -> some View {
        self
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollClipDisabled()
            .padding(.horizontal, -16)
    }
}

private struct ContextChip: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(Theme.secondaryText)
            Text(value).fontWeight(.semibold).foregroundStyle(Theme.primaryText)
        }
        // The chips scroll sideways, so each keeps its full width instead of truncating.
        .lineLimit(1)
        .fixedSize()
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.card, in: .capsule)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
    }
}

private struct MessageView: View {
    let message: CoachModel.ChatMessage
    let onStart: (PlannedWorkout) -> Void
    /// Resends the question behind an error bubble; nil when there is none.
    var onRetry: (() -> Void)? = nil
    /// Asks the model to say more about a data-backed reply; nil when not offered.
    var onSayMore: (() -> Void)? = nil
    /// The coach avatar scales with Dynamic Type (HIG Typography; ux-audit.md P22).
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize: CGFloat = 32

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 50)
                Text(message.text)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(LinearGradient(colors: [Theme.strain, Theme.lifting], startPoint: .leading, endPoint: .trailing), in: .rect(cornerRadius: 22))
            }
        case .coach:
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkle")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: avatarSize, height: avatarSize)
                    .background(LinearGradient(colors: [Theme.strain, Theme.sleep], startPoint: .bottomLeading, endPoint: .topTrailing), in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 12) {
                    CoachReplyText(text: message.text)
                        .textSelection(.enabled)
                    if let action = message.action, !action.isEmpty {
                        ActionLine(text: action)
                    }
                    if message.source == .data {
                        ReplyFooter(onSayMore: onSayMore)
                    }
                    if let plan = message.plan {
                        PlanCard(plan: plan, onStart: onStart)
                    }
                }
            }
        case .error:
            VStack(alignment: .leading, spacing: 8) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.recoveryLow)
                    .textSelection(.enabled)
                if let onRetry {
                    Button("Try again", systemImage: "arrow.clockwise", action: onRetry)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(Theme.recoveryLow)
                }
            }
            .padding(12)
            .background(Theme.recoveryLow.opacity(0.1), in: .rect(cornerRadius: 14))
        }
    }
}

/// One suggested next step under a reply.
private struct ActionLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.lifting)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next step: \(text)")
    }
}

/// "From your data" caption under a reply the app computed itself, with the
/// optional "Say more" that hands it to the on-device model to explain.
private struct ReplyFooter: View {
    var onSayMore: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Label("From your data", systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            if let onSayMore {
                Button("Say more", systemImage: "text.bubble", action: onSayMore)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(Theme.sleep)
                    .accessibilityHint("Asks the on-device model to explain this answer")
            }
        }
    }
}

private struct PlanCard: View {
    let plan: PlannedWorkout
    let onStart: (PlannedWorkout) -> Void

    @Environment(DailyMetricsModel.self) private var metrics
    /// The exercise number badge scales with Dynamic Type so the number never clips (ux-audit.md P22).
    @ScaledMetric(relativeTo: .headline) private var badgeSize: CGFloat = 32

    var body: some View {
        let minutes = plan.estimatedMinutes ?? WorkoutPlanner.estimatedMinutes(plan.exercises)
        let gain = metrics.strainGain(addedLoad: StrainPlanner().liftingLoad(minutes: Double(minutes), rpe: plan.targetRPE))
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Suggested", color: Theme.lifting)
            HStack(alignment: .firstTextBaseline) {
                Text(plan.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                let time = Text("\(minutes) min · ").foregroundStyle(Theme.secondaryText)
                let strain = Text("≈+\(strainText(gain)) strain").foregroundStyle(Theme.strain)
                Text("\(time)\(strain)")
            }
            .font(.subheadline)
            ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.headline)
                        .foregroundStyle(Theme.lifting)
                        .frame(width: badgeSize, height: badgeSize)
                        .background(Theme.lifting.opacity(0.12), in: .rect(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(exercise.name)
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text(detail(exercise))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            Button {
                onStart(plan)
            } label: {
                Label("Start this workout", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.card)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.ink, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private func detail(_ exercise: PlannedExercise) -> String {
        // The same words as the builder and the live workout (`Prescription`).
        var text = Prescription.sets(exercise.sets, repsLow: exercise.reps.lowerBound, repsHigh: exercise.reps.upperBound,
                                     targetReps: exercise.targetReps, rpe: exercise.rpe)
        if let load = exercise.load {
            text += " · " + Prescription.load(load, unit: plan.unit.rawValue, kind: exercise.loadKind)
        }
        return text
    }
}

/// A coach reply with simple markdown: "#" headings, "- " / "1." lists,
/// paragraphs, and inline bold/italic/code. Model text is never treated as
/// a localization key.
private struct CoachReplyText: View {
    let text: String

    private enum Block: Hashable {
        case heading(String)
        case bullet(marker: String, text: String)
        case paragraph(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty {
                result.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("#") {
                flush()
                result.append(.heading(String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush()
                result.append(.bullet(marker: "•", text: String(line.dropFirst(2))))
            } else if let match = line.firstMatch(of: /^(\d{1,2})[.)]\s+(.*)$/) {
                flush()
                result.append(.bullet(marker: "\(match.1).", text: String(match.2)))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let value):
                    Text(Self.inline(value))
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                        .padding(.top, 2)
                case .bullet(let marker, let value):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker)
                            .foregroundStyle(Theme.secondaryText)
                            .monospacedDigit()
                        Text(Self.inline(value))
                            .foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .paragraph(let value):
                    Text(Self.inline(value))
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Bold, italic, code and links within a line; plain text if it isn't valid markdown.
    static func inline(_ value: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: value, options: options)) ?? AttributedString(value)
    }
}
