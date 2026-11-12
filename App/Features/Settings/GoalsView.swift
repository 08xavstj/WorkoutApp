import SwiftUI
import AppCore

/// Weight and training goals. Opens with a suggestion from body composition.
///
/// A sheet from Today's setup card; pushed (`pushed: true`) from Settings and
/// onboarding, so a sheet never opens on a sheet (ux-audit.md 4.1 rule 5).
struct GoalsView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals
    @Environment(\.dismiss) private var dismiss
    @State private var goals = Goals()
    @State private var targetText = ""
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 90
    /// True when pushed onto another NavigationStack.
    var pushed = false

    private var suggestion: Goals {
        let fat = vitals.stat("fat")?.series.last?.value
        let bmi = vitals.stat("bmi")?.series.last?.value
        return GoalPlanner.suggest(bodyFatPercent: fat, bmi: bmi, sex: settings.sex)
    }

    private var suggestionReason: String {
        if let fat = vitals.stat("fat")?.series.last?.value {
            return "Based on your body fat (\(fat.formatted(.number.precision(.fractionLength(0))))%)."
        }
        if let bmi = vitals.stat("bmi")?.series.last?.value {
            return "Based on your BMI (\(bmi.formatted(.number.precision(.fractionLength(1))))). Body fat from a smart scale would be more accurate."
        }
        return "Add body fat or weight and height in Apple Health for a personal suggestion."
    }

    var body: some View {
        SheetNavigationStack(isSheet: !pushed) {
            Form {
                // First time: the suggestion leads. Once goals are saved it moves to the
                // end, and only shows when it differs from the chosen weight goal.
                if !settings.goalsSet {
                    suggestionSection
                }

                Section {
                    Picker("Weight", selection: $goals.weight) {
                        Text("Lose").tag(Goals.Weight.lose)
                        Text("Maintain").tag(Goals.Weight.maintain)
                        Text("Gain").tag(Goals.Weight.gain)
                    }
                    .pickerStyle(.segmented)
                    if goals.weight != .maintain {
                        Picker("Pace", selection: $goals.weeklyRatePercent) {
                            ForEach(rateOptions, id: \.self) { rate in
                                Text(paceLabel(rate)).tag(rate)
                            }
                        }
                        LabeledContent("Target weight") {
                            HStack(spacing: 4) {
                                TextField(settings.weightUnit.rawValue, text: $targetText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: fieldWidth)
                                Text(settings.weightUnit.rawValue).foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                } header: {
                    Text("Body weight")
                } footer: {
                    // The personal maximum and why (`GoalPlanner.maximumWeeklyRate`; docs/research/calories.md).
                    Text(rateLimit.message)
                }

                Section {
                    ForEach(Goals.Focus.allCases, id: \.self) { focus in
                        Toggle(focus.label, isOn: Binding(
                            get: { goals.focuses.contains(focus) },
                            set: { on in
                                if on { goals.focuses.append(focus) } else { goals.focuses.removeAll { $0 == focus } }
                            }
                        ))
                    }
                } header: {
                    Text("Training focus")
                } footer: {
                    Text("Muscle: 6-15 reps, close to failure. Strength: 3-6 reps on big lifts, stopping a little short of failure. Stamina: higher reps plus Zone 2 cardio. Pick more than one if you like.")
                }

                // Long-term lift targets with a projected range (`LiftGoalProjection`).
                LiftGoalsFormSection(goals: $goals.liftGoals)

                if settings.goalsSet, suggestion.weight != goals.weight {
                    suggestionSection
                }

                Section("Your plan") {
                    LabeledContent("Goal", value: goals.title)
                    if let target = calorieTarget {
                        LabeledContent("Calories", value: "\(whole(target).formatted()) kcal/day")
                    }
                    if let protein = proteinPreview {
                        LabeledContent("Protein", value: "\(whole(protein)) g/day")
                    }
                    if let weeks = weeksToTarget {
                        LabeledContent("Time to target", value: "~\(Int(weeks.rounded(.up))) weeks")
                    }
                    LabeledContent("Workouts", value: styleLabel)
                    if let status = metrics.trainingStatus {
                        LabeledContent("Lifting history", value: status.label)
                    }
                    if let weekly = metrics.weightTrendWeekly, let weight = metrics.bodyMassKg,
                       let warning = WeightPace.message(WeightPace.check(weeklyChangeKg: weekly, bodyMassKg: weight, goals: goals)) {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.recoveryModerateText)
                    }
                }
            }
            .navigationTitle("Your goals")
            .navigationBarTitleDisplayMode(.inline)
            // Pushed: Cancel and Save replace Back, so edits are never dropped by a swipe.
            .navigationBarBackButtonHidden(pushed)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(goals.focuses.isEmpty)
                }
            }
            .onAppear {
                goals = settings.goalsSet ? settings.goals : suggestion
                holdRateAtMaximum()
                targetText = goals.targetWeightKg.map { settings.weightUnit.display($0).formatted(.number.precision(.fractionLength(0...1))) } ?? ""
            }
            .onChange(of: goals.weight) { _, _ in
                let options = rateOptions
                if !options.contains(goals.weeklyRatePercent), let first = options.dropFirst().first ?? options.first {
                    goals.weeklyRatePercent = first
                }
            }
        }
    }

    /// "Suggested: Maintain weight" from body composition, and a button to use it.
    private var suggestionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggested: \(suggestion.title)")
                    .font(.headline)
                Text(suggestionReason + " A starting point, not a rule.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Button("Use suggestion") {
                let liftGoals = goals.liftGoals // The suggestion is about body weight; keep the lift goals.
                goals = suggestion
                goals.liftGoals = liftGoals
            }
        }
    }

    /// The fastest weekly rate for this person and the goal being edited.
    private var rateLimit: GoalPlanner.RateLimit {
        metrics.rateLimit(for: goals)
    }

    /// Picker rates, without the ones above the personal maximum.
    private var rateOptions: [Double] {
        GoalPlanner.rateOptions(for: goals.weight, maximum: rateLimit.percent)
    }

    /// A saved rate above the personal maximum drops to the fastest allowed one.
    private func holdRateAtMaximum() {
        let options = rateOptions
        if goals.weight != .maintain, !options.contains(goals.weeklyRatePercent), let fastest = options.last {
            goals.weeklyRatePercent = min(goals.weeklyRatePercent, fastest)
            if !options.contains(goals.weeklyRatePercent), let slowest = options.first {
                goals.weeklyRatePercent = slowest
            }
        }
    }

    private func paceLabel(_ rate: Double) -> String {
        guard let weight = metrics.bodyMassKg else { return "\(rate.formatted())% a week" }
        let perWeek = settings.weightUnit.display(weight * rate / 100)
        return "\(perWeek.formatted(.number.precision(.fractionLength(1)))) \(settings.weightUnit.rawValue)/week (\(rate.formatted())%)"
    }

    private var parsedTarget: Double? {
        Double(targetText.replacingOccurrences(of: ",", with: ".")).map { settings.weightUnit.toKilograms($0) }
    }

    /// Protein for the goals being edited, capped so carbs and fat still fit
    /// the calorie target (`MacroSplit`), as on Today.
    private var proteinPreview: Double? {
        if let split = MacroSplit.make(calorieTarget: calorieTarget, bodyMassKg: metrics.bodyMassKg, bodyFatPercent: metrics.bodyFatPercent,
                                       heightCm: metrics.heightCm, goals: goals, sex: metrics.sex,
                                       trainingStatus: metrics.trainingStatus, minimumProteinPerKg: metrics.medicationProteinPerKg) {
            return split.proteinGrams
        }
        return GoalPlanner.proteinGrams(goals: goals, bodyMassKg: metrics.bodyMassKg, bodyFatPercent: metrics.bodyFatPercent,
                                        heightCm: metrics.heightCm, minimumPerKg: metrics.medicationProteinPerKg)
    }

    private var calorieTarget: Double? {
        guard let base = metrics.maintenance?.maintenance ?? metrics.calories?.projected,
              let weight = metrics.bodyMassKg else { return nil }
        // The same safety minimum as Home (`CalorieSafety`, IOC REDs 2023).
        return max(GoalPlanner.calorieTarget(maintenance: base, bodyMassKg: weight,
                                             goals: GoalPlanner.cappedGoals(goals, limit: rateLimit), sex: settings.sex),
                   metrics.calorieMinimum ?? 0)
    }

    private var weeksToTarget: Double? {
        guard let weight = metrics.bodyMassKg else { return nil }
        var withTarget = GoalPlanner.cappedGoals(goals, limit: rateLimit)
        withTarget.targetWeightKg = parsedTarget
        return GoalPlanner.weeksToTarget(currentKg: weight, goals: withTarget)
    }

    private var styleLabel: String {
        switch GoalPlanner.trainingStyle(goals) {
        case .strength: "Strength (heavy, low reps)"
        case .muscle: "Muscle building"
        case .endurance: "Endurance (higher reps)"
        case .balanced: "Balanced"
        case .strengthAndMuscle: "Strength + muscle"
        }
    }

    private func save() {
        var saved = goals
        saved.targetWeightKg = goals.weight == .maintain ? nil : parsedTarget
        settings.goals = saved
        settings.goalsSet = true
        dismiss()
    }
}
