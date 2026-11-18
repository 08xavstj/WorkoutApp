import SwiftUI
import Charts
import AppCore

/// One row in the cardio fitness card: the quarterly fitness check
/// (`FitnessCheck`; evidence-audit-2026-11.md, Gaps, item 5). Apple Watch
/// reads VO₂ max only on outdoor walks and runs, about 6 ml/kg/min low on
/// average with 13% typical error (Lambe 2025, `VO2Source.appleWatchAccuracy`),
/// so a lifter gets few, rough readings. A standard
/// walking test done the same way every 3 months gives a steadier line.
/// A row, never a notification.
struct FitnessCheckRow: View {
    @State private var store = FitnessCheckStore.shared

    var body: some View {
        let history = store.history
        NavigationLink {
            FitnessCheckPage()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.oxygen)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Fitness check")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        if FitnessCheck.isDue(history) {
                            Chip(text: history.isEmpty ? "Try it" : "Due", color: Theme.oxygen)
                        }
                    }
                    Text(detail(history))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows a walking test that measures VO₂ max")
        .accessibilityIdentifier("fitness-check-row")
    }

    private func detail(_ history: [FitnessCheck.Result]) -> String {
        guard let last = history.first else {
            return "A 15-minute walking test every 3 months gives a steadier VO₂ max than the watch alone."
        }
        let value = "≈\(Int(last.vo2Max.rounded())) on \(last.date.formatted(.dateTime.month(.abbreviated).day()))"
        if FitnessCheck.isDue(history) { return "Last \(value). Time for the next one." }
        let next = FitnessCheck.nextDue(history).map { " · next in " + $0.formatted(.dateTime.month(.wide)) } ?? ""
        return "Last \(value)\(next)"
    }
}

/// Fitness › Cardio fitness › Fitness check: the test step by step, the
/// result typed in, and every check on the VO₂ max trend next to the watch's
/// readings.
struct FitnessCheckPage: View {
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals
    @Environment(GymStore.self) private var gym
    @State private var store = FitnessCheckStore.shared
    @State private var test: FitnessCheck.Test = .mileWalk
    @State private var minutes: Int?
    @State private var seconds: Int?
    @State private var heartRate: Int?
    @State private var speed: Double?
    @State private var speedInMph = false
    @State private var pendingDelete: FitnessCheck.Result?

    private var suggested: [FitnessCheck.Test] {
        FitnessCheck.suggested(age: settings.age, hasTreadmill: gym.profile.cardioMachines?.contains(.treadmill) == true)
    }

    private var weightKg: Double? {
        metrics.bodyMassKg ?? (settings.weightKg > 0 ? settings.weightKg : nil)
    }

    /// The estimate from what's typed so far; nil until it's complete and plausible.
    private var estimate: Double? {
        guard let heartRate else { return nil }
        switch test {
        case .mileWalk:
            guard let minutes, let weightKg else { return nil }
            let time = Double(minutes) + Double(seconds ?? 0) / 60
            return FitnessCheck.mileWalk(minutes: time, heartRate: Double(heartRate), age: settings.age, sex: settings.sex, weightKg: weightKg)
        case .treadmillWalk:
            guard let speed else { return nil }
            let mph = speedInMph ? speed : speed / FitnessCheck.kmhPerMph
            return FitnessCheck.treadmillWalk(speedMph: mph, heartRate: Double(heartRate), age: settings.age, sex: settings.sex)
        }
    }

    var body: some View {
        FitnessDetailPage(title: "Fitness check") {
            intro
            if suggested.count > 1 {
                Picker("Test", selection: $test) {
                    ForEach(suggested) { Text($0 == .mileWalk ? "Outdoor walk" : "Treadmill").tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("fitness-check-test")
            }
            steps
            entry
            if !store.results.isEmpty || !vitals.vo2MaxHistory.isEmpty {
                trend
            }
            if !store.results.isEmpty {
                history
            }
            Text("Each test is an estimate, about ±5 ml/kg/min against a lab test; its value is doing the same test the same way each time. Not a medical test. Stop if you feel chest pain, faintness or unusual breathlessness.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Fitness check")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !suggested.contains(test), let first = suggested.first { test = first }
        }
        .confirmationDialog("Delete this check?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { store.delete(pendingDelete) }
                pendingDelete = nil
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A steadier VO₂ max, every 3 months")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("Apple Watch reads VO₂ max only on outdoor walks, runs and hikes. \(VO2Source.appleWatchAccuracy) A standard walking test, done the same way each time, shows whether your fitness is really moving.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !test.validAges.contains(settings.age) {
                Text("This test was built on people aged \(test.validAges.lowerBound)-\(test.validAges.upperBound), so at \(settings.age) the number is rougher; the trend still helps.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.oxygen)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: test.title, color: Theme.oxygen)
            ForEach(Array(test.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.oxygen)
                        .frame(width: 18, alignment: .leading)
                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Text(test.citation)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Your result", color: Theme.oxygen)
            if test == .mileWalk {
                HStack {
                    Text("Time")
                    Spacer()
                    TextField("min", value: $minutes, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                        .accessibilityIdentifier("fitness-check-minutes")
                    Text(":")
                    TextField("sec", value: $seconds, format: .number)
                        .keyboardType(.numberPad)
                        .frame(width: 44)
                        .accessibilityIdentifier("fitness-check-seconds")
                }
                if weightKg == nil {
                    Text("Add your weight in Settings › Profile: the walk test needs it.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                HStack {
                    Text("Speed")
                    Spacer()
                    TextField(speedInMph ? "2.0-4.5" : "3.2-7.2", value: $speed, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        .accessibilityIdentifier("fitness-check-speed")
                    Picker("Unit", selection: $speedInMph) {
                        Text("km/h").tag(false)
                        Text("mph").tag(true)
                    }
                    .labelsHidden()
                }
            }
            HStack {
                Text("Heart rate at the end")
                Spacer()
                TextField("bpm", value: $heartRate, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .accessibilityIdentifier("fitness-check-heart-rate")
            }
            if let estimate {
                Text("≈ \(Int(estimate.rounded())) ml/kg/min")
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.primaryText)
            }
            Button {
                guard let estimate else { return }
                store.add(FitnessCheck.Result(test: test, date: .now, vo2Max: estimate))
                minutes = nil
                seconds = nil
                heartRate = nil
                speed = nil
            } label: {
                Text("Save this check")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.oxygen)
            .disabled(estimate == nil)
            .accessibilityIdentifier("fitness-check-save")
        }
        .font(.subheadline)
        .foregroundStyle(Theme.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// The watch's readings as a line, the checks as larger points, on one chart.
    private var trend: some View {
        let watch = vitals.vo2MaxHistory
        let checks = store.results
        return VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "VO₂ max trend", color: Theme.oxygen)
            Chart {
                ForEach(watch, id: \.date) { reading in
                    LineMark(x: .value("Date", reading.date), y: .value("VO₂ max", reading.value), series: .value("Source", "Watch"))
                        .foregroundStyle(Theme.oxygen.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                ForEach(checks) { check in
                    PointMark(x: .value("Date", check.date), y: .value("VO₂ max", check.vo2Max))
                        .foregroundStyle(Theme.strain)
                        .symbolSize(90)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
            HStack(spacing: 14) {
                legend(color: Theme.oxygen.opacity(0.45), text: "Apple Watch")
                legend(color: Theme.strain, text: "Fitness checks")
            }
            if let change = FitnessCheck.change(checks) {
                Text("Since the last check with the same test: \(change >= 0 ? "+" : "−")\(abs(change).formatted(.number.precision(.fractionLength(1)))) ml/kg/min. Small changes can be the test's own wobble.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("VO₂ max trend: \(watch.count) watch readings and \(checks.count) fitness checks")
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardLabel(text: "Checks", color: Theme.oxygen).padding(.bottom, 8)
            ForEach(store.history) { result in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(Theme.primaryText)
                        Text(result.test == .mileWalk ? "Outdoor walk" : "Treadmill")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Text("≈ \(Int(result.vo2Max.rounded()))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                    Button {
                        pendingDelete = result
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete check from \(result.date.formatted(date: .abbreviated, time: .omitted))")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
