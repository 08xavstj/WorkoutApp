import SwiftUI
import AppCore

// The PHQ-9 and GAD-7, offered inside the app (never as a notification) when
// mornings have run low for two weeks, at most every 4 weeks
// (`MoodQuestionnaires`; evidence-audit-2026-11.md, Gaps, item 4). Results
// are a screen, not a diagnosis. Item 9 above zero shows crisis contacts at
// once. Switched off for good in Settings › Data & privacy.

/// The low-mood rule's finding for today (`CoachNudges.lowMoodFinding`).
private func todaysLowMood(_ checkIns: CheckInStore) -> LowMoodRule.Finding? {
    CoachNudges.lowMoodFinding(checkIns: checkIns, now: .now)
}

/// The offer's words, shared by the check-in section and the Mood page card.
private enum MoodScreenCopy {
    static let title = "Two weeks of low mornings"
    static let body = "Two short questionnaires doctors use (PHQ-9 and GAD-7) can show whether it's worth talking to someone. About 3 minutes; the answers stay on your iPhone."
}

/// The offer at the top of the morning check-in, only on the days it applies.
struct MoodScreenOfferSection: View {
    @Environment(CheckInStore.self) private var checkIns
    @State private var store = MoodScreenStore.shared
    @State private var taking = false
    /// "Not now" was tapped (the store's record isn't observed).
    @State private var dismissed = false

    var body: some View {
        // Kept while the questionnaire is open: saving ends the offer, and the sheet must stay for the results.
        if taking || (!dismissed && store.offerDue(lowMood: todaysLowMood(checkIns))) {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(MoodScreenCopy.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(MoodScreenCopy.body)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Answer the questions") { taking = true }
                    .accessibilityIdentifier("mood-screen-take")
                Button("Not now") {
                    store.dismissOffer()
                    dismissed = true
                }
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("mood-screen-not-now")
            }
            .onAppear { store.noteOffered() }
            .sheet(isPresented: $taking) { MoodScreenSheet() }
        }
    }
}

/// Health › Patterns › Mood: the offer when it applies, then past results.
/// Nothing at all until one of them applies.
struct MoodScreenCard: View {
    @Environment(CheckInStore.self) private var checkIns
    @State private var store = MoodScreenStore.shared
    @State private var taking = false

    var body: some View {
        let offer = store.offerDue(lowMood: todaysLowMood(checkIns))
        let history = store.history
        if offer || !history.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CardLabel(text: "Mood questionnaires", color: Theme.sleep)
                if offer {
                    Text(MoodScreenCopy.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(MoodScreenCopy.body)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .onAppear { store.noteOffered() }
                }
                ForEach(history.prefix(6)) { result in
                    HStack {
                        Text(result.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Text("\(result.kind.title) \(result.score) · \(result.severity.label.lowercased())")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.primaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
                Button {
                    taking = true
                } label: {
                    Text(offer ? "Answer the questions" : "Answer them again")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("mood-screen-card-take")
                Text("Screens, not a diagnosis. Over the last 2 weeks, so answering more often than every few weeks adds little.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .accessibilityIdentifier("mood-screen-card")
            .sheet(isPresented: $taking) { MoodScreenSheet() }
        }
    }
}

/// The questionnaires, one after the other (the GAD-7 under 65 only:
/// USPSTF 2023), then the results in plain words.
struct MoodScreenSheet: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.healthClient) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var answers: [MoodQuestionnaires.Kind: [Int?]] = [:]
    @State private var saved: [MoodQuestionnaires.Result]?

    private var kinds: [MoodQuestionnaires.Kind] { MoodQuestionnaires.kinds(age: settings.age) }

    private func binding(_ kind: MoodQuestionnaires.Kind, _ index: Int) -> Binding<Int?> {
        Binding(
            get: {
                guard let list = answers[kind], list.indices.contains(index) else { return nil }
                return list[index]
            },
            set: { value in
                var list = answers[kind] ?? Array(repeating: nil, count: kind.items.count)
                list[index] = value
                answers[kind] = list
            }
        )
    }

    private var selfHarmAnswered: Bool {
        guard let list = answers[.phq9], list.indices.contains(MoodQuestionnaires.selfHarmItem),
              let value = list[MoodQuestionnaires.selfHarmItem] else { return false }
        return value > 0
    }

    private var complete: Bool {
        kinds.allSatisfy { kind in
            let list = answers[kind] ?? []
            return list.count == kind.items.count && list.allSatisfy { $0 != nil }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let saved {
                    MoodScreenResults(results: saved)
                } else {
                    ForEach(kinds) { kind in
                        Section {
                            ForEach(kind.items.indices, id: \.self) { index in
                                MoodScreenItem(number: index + 1, text: kind.items[index], answer: binding(kind, index))
                                    .accessibilityIdentifier("mood-screen-\(kind.rawValue)-\(index + 1)")
                                // PHQ-9 item 9 above zero: the crisis contacts straight away.
                                if kind == .phq9, index == MoodQuestionnaires.selfHarmItem, selfHarmAnswered {
                                    MoodScreenCrisisText()
                                }
                            }
                        } header: {
                            Text("\(kind.title): \(kind.about)")
                        } footer: {
                            Text(kind.stem)
                        }
                    }
                    Section {
                        Text("A screen, not a diagnosis. Your answers stay on this iPhone; if you allow it, the scores are also saved to Apple Health.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .navigationTitle(saved == nil ? "Mood questionnaires" : "Your results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if saved == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: save)
                            .disabled(!complete)
                            .accessibilityIdentifier("mood-screen-done")
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(saved == nil && !answers.isEmpty)
        }
    }

    private func save() {
        let now = Date.now
        let results = kinds.map { kind in
            MoodQuestionnaires.Result(kind: kind, date: now, answers: (answers[kind] ?? []).map { $0 ?? 0 })
        }
        MoodScreenStore.shared.add(results)
        if let health {
            Task {
                for result in results { try? await health.saveMoodScreen(result) }
            }
        }
        saved = results
    }
}

/// One item: its words and the four answers.
private struct MoodScreenItem: View {
    let number: Int
    let text: String
    @Binding var answer: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(number). \(text)")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(MoodQuestionnaires.answers.indices, id: \.self) { value in
                Button {
                    answer = value
                } label: {
                    HStack {
                        Image(systemName: answer == value ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(answer == value ? Theme.sleep : Theme.secondaryText)
                        Text(MoodQuestionnaires.answers[value])
                            .font(.subheadline)
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                    }
                    .frame(minHeight: 36)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(answer == value ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// Crisis contacts, shown at once when PHQ-9 item 9 is above zero.
private struct MoodScreenCrisisText: View {
    var body: some View {
        Label {
            Text(MoodQuestionnaires.crisisText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "phone.fill")
                .foregroundStyle(Theme.recoveryModerateText)
        }
        .accessibilityIdentifier("mood-screen-crisis")
    }
}

/// Each score in plain words, one calm doctor line when moderate or higher,
/// and the crisis contacts again when item 9 was above zero.
private struct MoodScreenResults: View {
    let results: [MoodQuestionnaires.Result]

    var body: some View {
        if results.contains(where: \.selfHarmAnswered) {
            Section {
                MoodScreenCrisisText()
            }
        }
        ForEach(results) { result in
            Section(result.kind.title) {
                Text(result.summary.replacingOccurrences(of: "\(result.kind.title): ", with: ""))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.primaryText)
                Text(result.meaning)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Section {
            if results.contains(where: \.suggestsDoctor) {
                Text("A GP or family doctor is a good first step; you can show them these answers.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
            }
            Text("Questionnaires by Kroenke, Spitzer and Williams (PHQ-9, 2001) and Spitzer and colleagues (GAD-7, 2006); 10 or more is the usual point where a doctor looks further. US guidance recommends these screens for adults (USPSTF 2023).")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// Settings › Data & privacy: switch the offer off for good (or back on).
struct MoodScreenSettingsSection: View {
    @State private var store = MoodScreenStore.shared

    var body: some View {
        Section {
            Toggle("Offer mood questionnaires", isOn: Binding(get: { !store.turnedOff }, set: { store.setTurnedOff(!$0) }))
                .accessibilityIdentifier("settings-mood-screens")
        } header: {
            Text("Mood")
        } footer: {
            Text("After two weeks of mostly low mornings, the check-in offers the PHQ-9 and GAD-7, at most every 4 weeks. Off means they're never offered. Answers stay on this iPhone.")
        }
    }
}
