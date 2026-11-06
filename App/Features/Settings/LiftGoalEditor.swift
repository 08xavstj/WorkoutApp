import SwiftUI
import SwiftData
import AppCore

/// Goals › Lift goals: the saved targets, each pushing the editor, plus
/// "Add a lift goal". Edits are kept with the rest of Goals on Save.
struct LiftGoalsFormSection: View {
    @Binding var goals: [LiftGoal]
    @Environment(UserSettings.self) private var settings

    var body: some View {
        Section {
            ForEach(goals) { goal in
                NavigationLink {
                    LiftGoalEditor(goal: goal) { updated in
                        if let index = goals.firstIndex(where: { $0.id == updated.id }) {
                            goals[index] = updated
                        }
                    }
                } label: {
                    Text(LiftGoalHistory.title(goal, unit: settings.weightUnit))
                }
            }
            .onDelete { goals.remove(atOffsets: $0) }
            NavigationLink("Add a lift goal") {
                LiftGoalEditor(goal: nil) { goals.append($0) }
            }
        } header: {
            Text("Lift goals")
        } footer: {
            // McEwan 2016 (goal setting, d ≈ 0.55); Swann 2021 (out-of-reach specific goals can backfire).
            Text("A target for a lift's estimated 1RM. Fitness › Strength shows where your last 12 weeks are heading. Goals help most when they feel reachable, so treat it as a direction rather than a test (McEwan 2016; Swann 2021).")
        }
    }
}

/// Pick a lift (your logged lifts first, then the main barbell lifts), a
/// target weight or body-weight multiple, and an optional date.
struct LiftGoalEditor: View {
    private let original: LiftGoal?
    private let onSave: (LiftGoal) -> Void

    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var exerciseID = ""
    @State private var byBodyweight = false
    @State private var valueText = ""
    @State private var hasDate = false
    @State private var date = Date.now.addingTimeInterval(16 * 7 * 86_400)
    @State private var loaded = false
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 90

    init(goal: LiftGoal?, onSave: @escaping (LiftGoal) -> Void) {
        self.original = goal
        self.onSave = onSave
    }

    struct LiftOption: Hashable, Identifiable {
        var id: String
        var name: String
    }

    /// The main barbell lifts, offered even before they're logged.
    static let mainLifts: [LiftOption] = [
        LiftOption(id: "Barbell_Bench_Press_-_Medium_Grip", name: "Bench press"),
        LiftOption(id: "Barbell_Squat", name: "Squat"),
        LiftOption(id: "Barbell_Deadlift", name: "Deadlift"),
        LiftOption(id: "Standing_Military_Press", name: "Overhead press"),
    ]

    /// Logged lifts, most often done first, then the main lifts not yet logged.
    private var options: [LiftOption] {
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        for session in sessions where !session.isActive {
            for exercise in session.exercises where exercise.sets.contains(where: { $0.isCompleted && !$0.isWarmup && $0.weightKg > 0 }) {
                counts[exercise.exerciseID, default: 0] += 1
                if names[exercise.exerciseID] == nil { names[exercise.exerciseID] = exercise.name }
            }
        }
        var result = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { LiftOption(id: $0.key, name: names[$0.key] ?? $0.key) }
        for lift in Self.mainLifts where !result.contains(where: { $0.id == lift.id }) {
            result.append(lift)
        }
        if let original, !result.contains(where: { $0.id == original.exerciseID }) {
            result.insert(LiftOption(id: original.exerciseID, name: original.name), at: 0)
        }
        return result
    }

    private var parsedValue: Double? {
        guard let value = Double(valueText.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        // A body-weight multiple outside 0.25–5 is almost certainly a typo.
        if byBodyweight { return (0.25...5).contains(value) ? value : nil }
        return value
    }

    private var bodyMassKg: Double { metrics.bodyMassKg ?? settings.weightKg }

    var body: some View {
        Form {
            Section {
                Picker("Lift", selection: $exerciseID) {
                    ForEach(options) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                LiftGoalLatestRow(exerciseID: exerciseID, sessions: sessions, unit: settings.weightUnit)
            }
            Section {
                Picker("Target", selection: $byBodyweight) {
                    Text("Weight").tag(false)
                    Text("× body weight").tag(true)
                }
                .pickerStyle(.segmented)
                LabeledContent(byBodyweight ? "Multiple" : "Estimated 1RM") {
                    HStack(spacing: 4) {
                        TextField(byBodyweight ? "1.5" : settings.weightUnit.rawValue, text: $valueText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: fieldWidth)
                        Text(byBodyweight ? "×" : settings.weightUnit.rawValue)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                if byBodyweight, let multiple = parsedValue {
                    LabeledContent("Today", value: LiftGoalHistory.weightText(multiple * bodyMassKg, unit: settings.weightUnit))
                }
            } footer: {
                Text("Estimated 1RM: the most you could lift once, worked out from your sets of 10 reps or fewer.")
            }
            Section {
                Toggle("By a date", isOn: $hasDate)
                if hasDate {
                    DatePicker("Date", selection: $date, in: Date.now..., displayedComponents: .date)
                }
            } footer: {
                Text("Optional. The projection looks at most 6 months ahead; a later date still works as a direction.")
            }
        }
        .navigationTitle(original == nil ? "New lift goal" : "Lift goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { save() }
                    .disabled(parsedValue == nil || exerciseID.isEmpty)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let original else {
            exerciseID = options.first?.id ?? ""
            return
        }
        exerciseID = original.exerciseID
        if let multiple = original.bodyweightMultiple {
            byBodyweight = true
            valueText = multiple.formatted(.number.precision(.fractionLength(0...2)))
        } else if let target = original.targetKg {
            valueText = settings.weightUnit.display(target).formatted(.number.precision(.fractionLength(0...1)))
        }
        if let targetDate = original.targetDate {
            hasDate = true
            date = targetDate
        }
    }

    private func save() {
        guard let value = parsedValue else { return }
        let name = options.first(where: { $0.id == exerciseID })?.name ?? original?.name ?? exerciseID
        let goal = LiftGoal(
            id: original?.id ?? UUID(),
            exerciseID: exerciseID,
            name: name,
            targetKg: byBodyweight ? nil : settings.weightUnit.toKilograms(value),
            bodyweightMultiple: byBodyweight ? value : nil,
            targetDate: hasDate ? Calendar.current.startOfDay(for: date) : nil
        )
        onSave(goal)
        dismiss()
    }
}

/// The lift's latest estimated 1RM, so the target can be set from where you are.
private struct LiftGoalLatestRow: View {
    let exerciseID: String
    let sessions: [WorkoutSession]
    let unit: WeightUnit

    var body: some View {
        if let latest = LiftGoalHistory.samples(exerciseID: exerciseID, sessions: sessions).last {
            LabeledContent("Latest e1RM", value: LiftGoalHistory.weightText(latest.kg, unit: unit))
        } else {
            Text("Not logged yet; the projection starts after a few sessions.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
