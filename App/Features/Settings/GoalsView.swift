import SwiftUI
import AppCore

/// Weight and training goals. Opens with a suggestion from body composition.
struct GoalsView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals
    @Environment(\.dismiss) private var dismiss
    @State private var goals = Goals()
    @State private var targetText = ""

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
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Suggested: \(suggestion.title)")
                            .font(.headline)
                        Text(suggestionReason)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Button("Use suggestion") { goals = suggestion }
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
                            ForEach(GoalPlanner.rateOptions(for: goals.weight), id: \.self) { rate in
                                Text(paceLabel(rate)).tag(rate)
                            }
                        }
                        LabeledContent("Target weight") {
                            TextField(settings.weightUnit.rawValue, text: $targetText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text(settings.weightUnit.rawValue).foregroundStyle(Theme.secondaryText)
                        }
                    }
                } header: {
                    Text("Body weight")
                } footer: {
                    Text(goals.weight == .lose
                         ? "0.5-1% of body weight a week keeps the most muscle; faster loss costs more muscle."
                         : (goals.weight == .gain ? "0.25-0.5% a week; bigger surpluses mostly add fat." : "Calories match what you burn."))
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
                    Text("Muscle: 6-15 reps, close to failure. Strength: 3-6 reps on big lifts, 2-3 left in the tank. Stamina: higher reps plus Zone 2 cardio. Pick more than one if you like.")
                }

                Section("Your plan") {
                    LabeledContent("Goal", value: goals.title)
                    if let target = calorieTarget {
                        LabeledContent("Calories", value: "\(whole(target).formatted()) kcal/day")
                    }
                    if let weight = metrics.bodyMassKg {
                        LabeledContent("Protein", value: "\(whole(weight * GoalPlanner.proteinPerKg(goals))) g/day")
                    }
                    if let weeks = weeksToTarget {
                        LabeledContent("Time to target", value: "~\(Int(weeks.rounded(.up))) weeks")
                    }
                    LabeledContent("Workouts", value: styleLabel)
                }
            }
            .navigationTitle("Your goals")
            .navigationBarTitleDisplayMode(.inline)
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
                targetText = goals.targetWeightKg.map { settings.weightUnit.display($0).formatted(.number.precision(.fractionLength(0...1))) } ?? ""
            }
            .onChange(of: goals.weight) { _, weight in
                let options = GoalPlanner.rateOptions(for: weight)
                if !options.contains(goals.weeklyRatePercent), let first = options.dropFirst().first ?? options.first {
                    goals.weeklyRatePercent = first
                }
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

    private var calorieTarget: Double? {
        guard let base = metrics.maintenance?.maintenance ?? metrics.calories?.projected,
              let weight = metrics.bodyMassKg else { return nil }
        return GoalPlanner.calorieTarget(maintenance: base, bodyMassKg: weight, goals: goals, sex: settings.sex)
    }

    private var weeksToTarget: Double? {
        guard let weight = metrics.bodyMassKg else { return nil }
        var withTarget = goals
        withTarget.targetWeightKg = parsedTarget
        return GoalPlanner.weeksToTarget(currentKg: weight, goals: withTarget)
    }

    private var styleLabel: String {
        switch GoalPlanner.trainingStyle(goals) {
        case .strength: "Strength (heavy, low reps)"
        case .muscle: "Muscle building"
        case .endurance: "Endurance (higher reps)"
        case .balanced: "Balanced"
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
