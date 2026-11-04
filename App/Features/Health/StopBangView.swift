import SwiftUI
import AppCore

/// The STOP-Bang sleep apnoea screen: eight yes/no questions, a score and a
/// risk band (Chung et al., Chest 2016). A screen, never a diagnosis.
///
/// A sheet from the Breathing page; pushed (`pushed: true`) from Body
/// measurements, which can itself be a sheet, so it's never a sheet on a
/// sheet (ux-audit.md 4.1 rule 5).
struct StopBangView: View {
    @Environment(BodyMeasurementsStore.self) private var store
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var answers: [String: Bool] = [:]
    @State private var saved = false
    /// True when pushed onto another NavigationStack.
    var pushed = false

    private var score: Int { StopBang.score(answers) }
    private var risk: StopBang.Risk { StopBang.risk(score: score) }

    var body: some View {
        SheetNavigationStack(isSheet: !pushed) {
            Form {
                Section {
                    ForEach(StopBang.questions) { question in
                        Toggle(isOn: binding(question.id)) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(question.letter)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Theme.oxygen, in: .circle)
                                    .accessibilityHidden(true)
                                Text(question.text)
                                    .font(.subheadline)
                            }
                        }
                        .tint(Theme.oxygen)
                    }
                } header: {
                    Text("Over the last few months")
                } footer: {
                    Text("Age, sex and BMI are filled in from your profile when known. Measure your neck with a tape just under the Adam's apple.")
                }
                Section {
                    HStack {
                        Text("Score")
                        Spacer()
                        Text("\(score) of 8")
                            .font(.headline)
                            .monospacedDigit()
                        Chip(text: risk.rawValue, color: StopBangSummaryCard.color(for: risk))
                    }
                    Text(StopBang.advice(risk))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Result")
                } footer: {
                    Text("0-2 low, 3-4 intermediate, 5-8 high (Chung et al., Chest 2016). At 3 or more the screen finds about 85-95% of moderate-to-severe apnoea but also flags many people without it, so it rules out better than it rules in. An Apple Watch sleep-apnoea notification catches about two thirds of cases; no notification doesn't mean no apnoea. Only a sleep study can diagnose it.")
                }
            }
            .navigationTitle("Sleep apnoea screen")
            .navigationBarTitleDisplayMode(.inline)
            // Pushed: Cancel and Save replace Back, so answers are never dropped by a swipe.
            .navigationBarBackButtonHidden(pushed)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.saveStopBang(answers: answers)
                        dismiss()
                    }
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(get: { answers[id] ?? false }, set: { answers[id] = $0 })
    }

    /// Last year's answers, then the profile's for age, sex and BMI.
    private func prefill() {
        guard answers.isEmpty else { return }
        var filled = store.stopBang?.answers ?? [:]
        let profile = StopBang.profileAnswers(age: settings.age, sex: settings.sex, bmi: bmi)
        for (key, value) in profile where filled[key] == nil || store.stopBang == nil {
            filled[key] = value
        }
        answers = filled
    }

    private var bmi: Double? {
        let heightCm = metrics.heightCm ?? (settings.heightCm > 0 ? settings.heightCm : nil)
        guard let weight = metrics.bodyMassKg, let heightCm, heightCm > 100 else { return nil }
        let meters = heightCm / 100
        return weight / (meters * meters)
    }
}
