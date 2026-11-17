import SwiftUI
import AppCore

/// Typing Apple's numbers in for a day, or checking what was read from a
/// screenshot before it is saved.
///
/// From a screenshot, a number is only filled in when the reader found one
/// clear value beside its label (`AppleScoreScreenReader.Result.best`); every
/// other candidate is listed with the label it was next to, to tap or ignore.
/// Nothing is saved until Save. Opened for a day that already has numbers
/// (typed mode), clearing one and saving removes it.
struct AppleScoresEntrySheet: View {
    let entry: AppleScoresEntry

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date.now
    @State private var readiness: Int?
    @State private var sleepText = ""
    @State private var ageText = ""
    @State private var hasLoaded = false

    private var store: AppleScoresStore { .shared }
    private var isFromScreenshot: Bool { entry.reading != nil }

    var body: some View {
        NavigationStack {
            Form {
                if let reading = entry.reading {
                    readSection(reading)
                }
                Section {
                    DatePicker("Day", selection: $day, in: ...store.now, displayedComponents: .date)
                } footer: {
                    if entry.reading?.dayHint == .yesterday {
                        Text("The screenshot says Yesterday, so the day is set to yesterday.")
                    }
                }
                Section {
                    Picker("Readiness", selection: $readiness) {
                        Text("Not set").tag(Int?.none)
                        ForEach(Array(AppleScoreKind.readiness.range), id: \.self) { value in
                            Text("\(value)").tag(Int?.some(value))
                        }
                    }
                    .accessibilityIdentifier("apple-scores-readiness")
                } footer: {
                    Text(readinessFooter)
                }
                Section {
                    TextField("0 to 100", text: $sleepText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Apple's Sleep score")
                        .accessibilityIdentifier("apple-scores-sleep")
                } header: {
                    Text("Sleep score")
                } footer: {
                    Text(footer(.sleepScore, text: sleepText, empty: "Last night's score, from the Sleep app or the Health app."))
                }
                Section {
                    TextField("Years", text: $ageText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Apple's Health Age in years")
                        .accessibilityIdentifier("apple-scores-health-age")
                } header: {
                    Text("Health Age")
                } footer: {
                    Text(footer(.healthAge, text: ageText, empty: "From Health \u{203A} Longevity. Leave it empty on days it hasn't changed."))
                }
            }
            // Opaque at every detent: a part-height sheet is see-through glass by default.
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isFromScreenshot ? "Check the numbers" : "Apple's scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("apple-scores-save")
                }
            }
            .onAppear(perform: load)
            .onChange(of: day) {
                // Typed mode shows the chosen day's saved numbers; a screenshot's stay as read.
                if hasLoaded, !isFromScreenshot { loadSaved() }
            }
        }
        .presentationBackground(Theme.background)
    }

    // MARK: What the screenshot said

    private func readSection(_ reading: AppleScoreScreenReader.Result) -> some View {
        Section {
            ForEach(reading.candidates) { candidate in
                Button {
                    use(candidate)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(candidate.kind.title): \(candidate.summary)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.primaryText)
                            Text(note(candidate))
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        if isUsed(candidate) {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.recoveryHighText)
                                .accessibilityLabel("Filled in")
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Fills this number in below")
            }
        } header: {
            Text("Read from the screenshot")
        } footer: {
            Text("Check each number against your screenshot and correct it below if it's wrong. Tap a line to use it. Nothing is saved until you tap Save.")
        }
    }

    /// The text the number came from, Apple's word beside it, and any doubt.
    private func note(_ candidate: AppleScoreScreenReader.Candidate) -> String {
        var parts = ["Read as \u{201C}\(candidate.valueText)\u{201D}"]
        if let level = candidate.level {
            parts.append("with \u{201C}\(level == "ok" ? "OK" : level.capitalized)\u{201D} beside it")
        }
        var text = parts.joined(separator: ", ") + "."
        if candidate.confidence == .low {
            text += " Not filled in: " + candidate.doubts.map(\.words).joined(separator: " ")
        }
        return text
    }

    private func isUsed(_ candidate: AppleScoreScreenReader.Candidate) -> Bool {
        switch candidate.kind {
        case .readiness: readiness == candidate.value
        case .sleepScore: Int(sleepText) == candidate.value
        case .healthAge: Int(ageText) == candidate.value
        }
    }

    private func use(_ candidate: AppleScoreScreenReader.Candidate) {
        switch candidate.kind {
        case .readiness: readiness = candidate.value
        case .sleepScore: sleepText = String(candidate.value)
        case .healthAge: ageText = String(candidate.value)
        }
    }

    // MARK: Fields

    private var readinessFooter: String {
        guard let readiness, let level = AppleScoreKind.readiness.levelLabel(for: readiness) else {
            return "0 to 10, as the Readiness app shows it. It changes through the day; the last one you save is kept."
        }
        return "Apple calls \(readiness) \u{201C}\(level)\u{201D}."
    }

    /// What a typed field holds.
    private enum Typed {
        case empty
        case value(Int)
        /// Not a whole number in the kind's range.
        case invalid
    }

    private func typed(_ kind: AppleScoreKind, _ text: String) -> Typed {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .empty }
        guard let value = Int(trimmed), kind.accepts(value) else { return .invalid }
        return .value(value)
    }

    private func footer(_ kind: AppleScoreKind, text: String, empty: String) -> String {
        switch typed(kind, text) {
        case .invalid:
            return "A whole number from \(kind.range.lowerBound) to \(kind.range.upperBound)."
        case .empty:
            return empty
        case .value(let value):
            return kind.levelLabel(for: value).map { "Apple calls \(value) \u{201C}\($0)\u{201D}." } ?? empty
        }
    }

    /// The numbers to save, or nil while a field is invalid.
    private var values: [AppleScoreKind: Int]? {
        var result: [AppleScoreKind: Int] = [:]
        if let readiness { result[.readiness] = readiness }
        let fields: [(AppleScoreKind, String)] = [(.sleepScore, sleepText), (.healthAge, ageText)]
        for (kind, text) in fields {
            switch typed(kind, text) {
            case .invalid: return nil
            case .empty: break
            case .value(let value): result[kind] = value
            }
        }
        return result
    }

    /// Saved numbers for the day that were cleared here (typed mode only).
    private func cleared(_ values: [AppleScoreKind: Int]) -> [AppleScoreKind] {
        guard !isFromScreenshot else { return [] }
        return AppleScoreKind.allCases.filter { values[$0] == nil && store.reading($0, on: day) != nil }
    }

    private var canSave: Bool {
        guard let values else { return false }
        return !values.isEmpty || !cleared(values).isEmpty
    }

    // MARK: Loading and saving

    private func load() {
        guard !hasLoaded else { return }
        day = entry.day
        if let reading = entry.reading {
            readiness = reading.best(.readiness)?.value
            sleepText = reading.best(.sleepScore).map { String($0.value) } ?? ""
            ageText = reading.best(.healthAge).map { String($0.value) } ?? ""
        } else {
            loadSaved()
        }
        hasLoaded = true
    }

    private func loadSaved() {
        readiness = store.reading(.readiness, on: day)?.value
        sleepText = store.reading(.sleepScore, on: day).map { String($0.value) } ?? ""
        ageText = store.reading(.healthAge, on: day).map { String($0.value) } ?? ""
    }

    private func save() {
        guard let values else { return }
        for kind in cleared(values) {
            store.remove(kind, day: AppleScoresStore.key(day))
        }
        store.save(values, on: day, source: isFromScreenshot ? .screenshot : .typed)
        store.keepAppValues(recovery: metrics.recovery?.score, recoveryIsFromYesterday: metrics.recoveryIsFromYesterday,
                            bodyAge: vitals.bodyAge?.years)
        dismiss()
    }
}
