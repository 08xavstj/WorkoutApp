import SwiftUI
import Charts
import AppCore

/// The yearly functional tests on the fitness check page (`FunctionalTest`;
/// docs/research/next-features-2026-11.md, I4): push-ups for everyone, the
/// sitting-rising test from 45 and the one-leg stand from 50. Each row opens
/// the test's page. Cohort studies only, so every page says "linked with,
/// in one cohort".
struct FunctionalTestsCard: View {
    @Environment(UserSettings.self) private var settings
    @State private var store = FunctionalTestStore.shared

    var body: some View {
        let available = FunctionalTest.available(age: settings.age)
        let later = FunctionalTest.allCases.filter { !available.contains($0) }
        VStack(alignment: .leading, spacing: 4) {
            CardLabel(text: "Yearly strength and balance tests", color: Theme.lifting)
            Text("Simple tests that cohort studies have linked with heart health and survival. Once a year shows whether you're holding on to them.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            ForEach(available) { test in
                row(test)
            }
            if !later.isEmpty {
                Text(later.map { "From \($0.minimumAge): \($0.title.lowercasedFirst)" }.joined(separator: ". ") + ".")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func row(_ test: FunctionalTest) -> some View {
        let last = store.history(test).first
        let due = FunctionalTest.isDue(test, results: store.results)
        return NavigationLink {
            FunctionalTestPage(test: test)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(test))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.lifting)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(test.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        if due { Chip(text: last == nil ? "Try it" : "Due", color: Theme.lifting) }
                    }
                    Text(last.map { "\(test.formatted($0.value)) on \($0.date.formatted(.dateTime.month(.abbreviated).day().year()))" } ?? "Not done yet")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
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
        .accessibilityIdentifier("functional-test-\(test.rawValue)")
    }

    private func icon(_ test: FunctionalTest) -> String {
        switch test {
        case .pushUps: "figure.strengthtraining.functional"
        case .sittingRising: "figure.cooldown"
        case .oneLegStand: "figure.stand"
        }
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

/// One functional test: why, how, the safety notes, the result typed in,
/// what it means against the cohort, and the trend.
struct FunctionalTestPage: View {
    let test: FunctionalTest
    @Environment(UserSettings.self) private var settings
    @State private var store = FunctionalTestStore.shared
    @State private var pushUps: Int?
    @State private var sitSupports = 0
    @State private var sitUnsteady = 0
    @State private var riseSupports = 0
    @State private var riseUnsteady = 0
    @State private var held = true
    @State private var pendingDelete: FunctionalTest.Result?

    private var history: [FunctionalTest.Result] { store.history(test) }

    /// The value from what's entered, nil until it's valid.
    private var entered: Double? {
        switch test {
        case .pushUps: pushUps.flatMap { test.validated(Double($0)) }
        case .sittingRising:
            FunctionalTest.sittingRisingScore(sitSupports: sitSupports, sitUnsteady: sitUnsteady,
                                              riseSupports: riseSupports, riseUnsteady: riseUnsteady)
        case .oneLegStand: held ? 1 : 0
        }
    }

    var body: some View {
        FitnessDetailPage(title: test.title) {
            intro
            steps
            safety
            entry
            if let latest = history.first {
                meaning(latest)
            }
            if history.count >= 2, test != .oneLegStand {
                trend
            }
            if !history.isEmpty {
                log
            }
            Text("Not a medical test. A low or falling result is a reason to train for it and to mention it to your doctor, not a diagnosis.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(test.title)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this result?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { store.delete(pendingDelete) }
                pendingDelete = nil
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(introTitle)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(introText)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Chip(text: "Linked with, in one cohort", color: Theme.lifting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.lifting)
    }

    private var introTitle: String {
        switch test {
        case .pushUps: "Upper-body strength in one number"
        case .sittingRising: "Getting down to the floor and back up"
        case .oneLegStand: "Balance, in 10 seconds"
        }
    }

    private var introText: String {
        switch test {
        case .pushUps:
            "In one study of active men, those who could do more than 40 push-ups had far fewer heart problems over 10 years than those who managed fewer than 10. It was one small group of firefighters with few events, so treat it as a sign, not a verdict."
        case .sittingRising:
            "Sitting down on the floor and standing up without help takes strength, flexibility and balance together. In adults aged 46 to 75, lower scores went with higher death rates over about 12 years."
        case .oneLegStand:
            "Balance fades from the mid-50s. In adults aged 51 to 75, not being able to stand on one leg for 10 seconds went with a higher risk of death over about 7 years."
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "How to do it", color: Theme.lifting)
            ForEach(Array(test.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.liftingText)
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

    private var safety: some View {
        Label {
            Text(test.safety)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.shield")
                .foregroundStyle(Theme.recoveryModerate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Your result", color: Theme.lifting)
            switch test {
            case .pushUps:
                HStack {
                    Text("Push-ups")
                    Spacer()
                    TextField("count", value: $pushUps, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        .accessibilityIdentifier("functional-test-count")
                }
            case .sittingRising:
                Stepper("Supports sitting down: \(sitSupports)", value: $sitSupports, in: 0...5)
                Stepper("Wobbles sitting down: \(sitUnsteady)", value: $sitUnsteady, in: 0...10)
                Stepper("Supports getting up: \(riseSupports)", value: $riseSupports, in: 0...5)
                Stepper("Wobbles getting up: \(riseUnsteady)", value: $riseUnsteady, in: 0...10)
            case .oneLegStand:
                Picker("Result", selection: $held) {
                    Text("Held 10 s").tag(true)
                    Text("Couldn't").tag(false)
                }
                .pickerStyle(.segmented)
            }
            if let entered, test != .oneLegStand {
                Text(test.formatted(entered))
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.primaryText)
            }
            Button {
                guard let entered else { return }
                store.add(FunctionalTest.Result(test: test, date: .now, value: entered))
                pushUps = nil
                sitSupports = 0
                sitUnsteady = 0
                riseSupports = 0
                riseUnsteady = 0
            } label: {
                Text("Save this result")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.lifting)
            .disabled(entered == nil)
            .accessibilityIdentifier("functional-test-save")
        }
        .font(.subheadline)
        .foregroundStyle(Theme.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func meaning(_ latest: FunctionalTest.Result) -> some View {
        let reading = FunctionalTest.interpret(test, value: latest.value, age: settings.age, sex: settings.sex)
        return VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "What your last result means", color: Theme.lifting)
            Text(reading.headline)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(reading.detail)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let note = reading.ageNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let change = FunctionalTest.change(test, results: store.results) {
                Text(changeText(change))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func changeText(_ change: Double) -> String {
        let amount = abs(change).formatted(.number.precision(.fractionLength(0...1)))
        let unit = test == .pushUps ? " push-up\(abs(change) == 1 ? "" : "s")" : " point\(abs(change) == 1 ? "" : "s")"
        if change == 0 { return "The same as last time." }
        return "\(change > 0 ? "Up" : "Down") \(amount)\(unit) since last time."
    }

    private var trend: some View {
        let points = history.sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "Trend", color: Theme.lifting)
            Chart(points) { result in
                LineMark(x: .value("Date", result.date), y: .value(test.resultLabel, result.value))
                    .foregroundStyle(Theme.lifting.opacity(0.5))
                PointMark(x: .value("Date", result.date), y: .value(test.resultLabel, result.value))
                    .foregroundStyle(Theme.lifting)
                    .symbolSize(80)
            }
            .chartYScale(domain: test == .sittingRising ? 0...10 : 0...max(10, (points.map(\.value).max() ?? 0) + 5))
            .frame(height: 160)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(test.title) trend: \(points.map { test.formatted($0.value) }.joined(separator: ", "))")
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardLabel(text: "Results", color: Theme.lifting).padding(.bottom, 8)
            ForEach(history) { result in
                HStack {
                    Text(result.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Text(test.formatted(result.value))
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
                    .accessibilityLabel("Delete result from \(result.date.formatted(date: .abbreviated, time: .omitted))")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
