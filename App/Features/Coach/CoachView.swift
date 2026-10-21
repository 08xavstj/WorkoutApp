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
    @Environment(ProgressPhotosModel.self) private var progressPhotos
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var draft = ""
    @State private var showingGym = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        header
                        contextChips
                        if coach.messages.isEmpty {
                            emptyState
                        }
                        ForEach(coach.messages) { message in
                            MessageView(message: message) { plan in
                                launcher.start(plan, in: modelContext)
                            }
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
            .toolbarVisibility(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { inputBar }
            .sheet(isPresented: $showingGym) { MyGymView() }
            .task(id: coach.pendingQuestion) {
                if let question = coach.pendingQuestion {
                    coach.pendingQuestion = nil
                    await send(question)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label {
                    Text("Coach")
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(LinearGradient(colors: [Theme.strain, Theme.sleep], startPoint: .bottomLeading, endPoint: .topTrailing))
                }
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.primaryText)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                Menu {
                    Button("New conversation", systemImage: "square.and.pencil") { coach.newConversation() }
                    Button("My Gym", systemImage: "dumbbell") { showingGym = true }
                } label: {
                    GlassIcon(systemName: "line.3.horizontal")
                }
                .accessibilityLabel("Coach options")
            }
            Text("Knows today's data and your gym · \(settings.coachMode == .onDevice ? "on-device" : "Claude")")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.top, 8)
    }

    private var contextChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if let recovery = metrics.recovery {
                    ContextChip(color: Theme.recoveryColor(for: recovery.score), label: "Recovery", value: "\(recovery.score)%")
                }
                if let strain = metrics.strain {
                    let target = metrics.targetStrain.map { " / \(whole($0.lowerBound))–\(whole($0.upperBound))%" } ?? ""
                    ContextChip(color: Theme.strain, label: "Strain", value: "\(strainText(strain.strain))\(target)")
                }
                if let protein = metrics.nutritionToday?.proteinGrams {
                    ContextChip(color: Theme.nutrition, label: "Protein", value: "\(whole(protein)) g")
                }
                // Same number as Home's calorie card: today's target minus food eaten.
                if let target = metrics.calorieTarget, let eaten = metrics.calories?.eaten {
                    let left = target - eaten
                    ContextChip(color: Theme.lifting, label: left >= 0 ? "Left" : "Over", value: "\(whole(abs(left))) kcal")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about training, recovery, sleep or food.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text(gym.isConfigured
                 ? "Workouts are built from \(gym.profile.name) and rounded to the weights you can load."
                 : "Set up My Gym (menu, top right) so workouts use your equipment and weight jumps.")
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
                ForEach(CoachModel.followUps, id: \.self) { text in
                    Button {
                        Task { await send(text) }
                    } label: {
                        Text(text)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Theme.card, in: .capsule)
                            .overlay(Capsule().strokeBorder(Theme.separator))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
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
                    .frame(width: 40, height: 40)
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

    private func send(_ text: String) async {
        var plan: PlannedWorkout?
        if CoachModel.isTrainingQuestion(text) && !CoachModel.wantsCardio(text) {
            let (focus, minutes) = CoachModel.requestedFocusAndMinutes(text)
            let lastPlan = coach.messages.last { $0.plan != nil }?.plan
            let resolvedFocus = focus ?? lastPlan?.focus
                ?? WorkoutPlanner.suggestedFocus(recentExerciseIDs: LiftHistory.recentExerciseIDs(sessions))
            plan = gym.planner.plan(
                focus: resolvedFocus,
                minutes: minutes ?? lastPlan?.minutes ?? 45,
                recovery: metrics.recoveryForTraining,
                history: LiftHistory.make(from: sessions, unit: gym.profile.unit)
            )
        }
        var snapshot = CoachSnapshot.make(
            metrics: metrics, sessions: sessions, unit: settings.weightUnit,
            gymSummary: gym.isConfigured ? gym.planner.gymSummary() : nil, plan: plan
        )
        snapshot.medications = medications.coachSummary
        snapshot.labs = labs.coachSummary
        snapshot.checkIns = checkIns.coachSummary
        snapshot.name = settings.name.isEmpty ? nil : settings.name
        snapshot.weather = conditions.coachSummary(place: settings.placeName)
        snapshot.health = healthSummary
        await coach.send(text, snapshot: snapshot, settings: settings, plan: plan)
    }
}

extension CoachView {
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
            lines.append("7-day HRV \(whole(trend.average)) ms, normal range \(whole(trend.normalRange.lowerBound))-\(whole(trend.normalRange.upperBound)) ms (\(trend.status.rawValue)).\(metrics.trainEasyToday ? " HRV-guided: today should be easy." : "")")
        }
        if let consistency = metrics.sleepConsistency { lines.append("Sleep Regularity Index \(consistency)/100 (last week).") }
        if let debt = metrics.sleepDebt {
            lines.append("Sleep debt \(debt.hours.formatted(.number.precision(.fractionLength(1)))) h over 14 nights (need \(settings.sleepNeedHours.formatted()) h)" + (debt.plan.map { "; plan: " + $0 } ?? "") + ".")
        }
        if settings.isRestMode {
            lines.append("REST MODE is on (the user is sick or resting): no strain target; suggest rest, sleep, fluids and at most easy walking, not workouts.")
        }
        if let metric = metrics.hrvMetric { lines.append("HRV metric: \(metric).") }
        if let water = metrics.nutritionToday?.waterLiters { lines.append("Water today \(water.formatted(.number.precision(.fractionLength(1)))) L.") }
        let lowNutrients = metrics.micronutrients.filter { $0.kind != .ok }
        if !lowNutrients.isEmpty {
            lines.append("Vitamins/minerals (7-day avg vs target): " + lowNutrients.map { "\($0.nutrient.name) \(Int($0.percentOfTarget.rounded()))% (\($0.kind.rawValue))" }.joined(separator: ", ") + ".")
        }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        if let alert = vitals.illnessAlert(metrics: metrics, drinksLastNight: checkIns.evening(on: yesterday)?.drinks, reportedSymptoms: checkIns.morning()?.isSick ?? false) {
            lines.append("Illness watch (\(alert.level.label)): " + alert.signals.joined(separator: ", ") + ".")
        }
        if let deload = muscles.deload { lines.append("Deload suggested: stalled " + deload.stalledLifts.joined(separator: ", ") + ".") }
        let tired = muscles.states.values.filter { $0.status == .fatigued }.map(\.muscle.name)
        if !tired.isEmpty { lines.append("Fatigued muscles: " + tired.sorted().joined(separator: ", ") + ".") }
        lines.append(contentsOf: habitLines)
        if let analysis = progressPhotos.latestAnalysis {
            lines.append("Latest progress-photo analysis (\(analysis.date.formatted(date: .abbreviated, time: .omitted))): " + String(analysis.text.prefix(700)))
        }
        return lines.joined(separator: "\n")
    }
}

extension CoachView {
    /// Caffeine, alcohol, heat, weight pace, body age, what moved recovery,
    /// and every Biology stat, for the coach.
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
            lines.append("Hot day: strain target lowered by \(Int(metrics.heatAdjustment.rounded())) points; trained in the heat on \(conditions.heatTrainingDays) of the last 14 days (acclimation takes about 10-14).")
        }

        // Weight change speed (Helms et al. 2014).
        if let weekly = metrics.weightTrendWeekly, let mass = metrics.bodyMassKg,
           let message = WeightPace.message(WeightPace.check(weeklyChangeKg: weekly, bodyMassKg: mass, goals: settings.goalsSet ? settings.goals : nil)) {
            lines.append("Weight pace: " + message)
        }

        // Body age with its confidence and biggest factors.
        if let age = vitals.bodyAge {
            let factors = age.factors.prefix(3).map { "\($0.name) \($0.years >= 0 ? "+" : "")\($0.years.formatted(.number.precision(.fractionLength(1)))) y" }
            lines.append("Body age \(age.bodyAge.formatted(.number.precision(.fractionLength(1)))) vs real age \(age.age) (\(age.confidence.label.lowercased())): " + factors.joined(separator: ", ") + ".")
        }

        // What moved today's recovery.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) ?? .now
        let contributors = metrics.recoveryContributors(drinksLastNight: checkIns.evening(on: yesterday)?.drinks, illness: nil)
        if !contributors.isEmpty {
            lines.append("What moved recovery: " + contributors.prefix(5).map { "\($0.name) \($0.effect.rawValue) it (\($0.detail))" }.joined(separator: "; ") + ".")
        }

        // Every Biology stat with a value (steps vs goal, strength days, blood pressure, sleep, etc.).
        let stats = vitals.stats.compactMap { stat -> String? in
            guard let value = stat.value else { return nil }
            let unit = stat.unit.isEmpty ? "" : " \(stat.unit)"
            return "\(stat.title) \(value)\(unit)" + (stat.status.map { " (\($0))" } ?? "")
        }
        if !stats.isEmpty { lines.append("Biology stats: " + stats.joined(separator: "; ") + ".") }
        return lines
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
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.card, in: .capsule)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
    }
}

private struct MessageView: View {
    let message: CoachModel.ChatMessage
    let onStart: (PlannedWorkout) -> Void

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
                    .frame(width: 32, height: 32)
                    .background(LinearGradient(colors: [Theme.strain, Theme.sleep], startPoint: .bottomLeading, endPoint: .topTrailing), in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 12) {
                    CoachReplyText(text: message.text)
                        .textSelection(.enabled)
                    if let plan = message.plan {
                        PlanCard(plan: plan, onStart: onStart)
                    }
                }
            }
        case .error:
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(Theme.recoveryLow)
                .padding(12)
                .background(Theme.recoveryLow.opacity(0.1), in: .rect(cornerRadius: 14))
        }
    }
}

private struct PlanCard: View {
    let plan: PlannedWorkout
    let onStart: (PlannedWorkout) -> Void

    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        let minutes = WorkoutPlanner.estimatedMinutes(plan.exercises)
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
                        .frame(width: 32, height: 32)
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
        var text = "\(exercise.sets) × \(exercise.reps.lowerBound)–\(exercise.reps.upperBound) @ RPE \(exercise.rpe.formatted())"
        if let load = exercise.load {
            text += " · \(load.formatted(.number.precision(.fractionLength(0...2)))) \(plan.unit.rawValue)"
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
