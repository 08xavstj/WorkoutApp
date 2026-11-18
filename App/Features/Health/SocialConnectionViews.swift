import SwiftUI
import AppCore

// The optional social connection check (I6; `SocialConnectionCheck`): three
// questions from the UCLA Loneliness Scale every 3 months, off by default
// (Settings › Notifications › Mood). Results are shown gently with one
// follow-up line and where to find help; no diagnosis. Stored with the mood
// screens (`MoodScreenStore`), on this iPhone only.

/// Health › Patterns › Mood: the check when it's due, else the last answer.
/// Nothing while the check is switched off.
struct SocialConnectionCard: View {
    @State private var store = MoodScreenStore.shared
    @State private var taking = false

    var body: some View {
        if store.socialCheckOn {
            let due = store.socialCheckDue
            VStack(alignment: .leading, spacing: 10) {
                CardLabel(text: "Social connection", color: Theme.sleep)
                if let last = store.socialHistory.first {
                    HStack {
                        Text(last.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Text("\(last.score) of 9")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.primaryText)
                    }
                    .accessibilityElement(children: .combine)
                    Text(last.meaning)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if !due, let next = SocialConnectionCheck.nextDue(lastTaken: last.date) {
                        Text("Asked again around \(next.formatted(.dateTime.month(.wide).day())).")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else {
                    Text("Three short questions about feeling connected, every 3 months. About 30 seconds; the answers stay on your iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if due {
                    Button {
                        taking = true
                    } label: {
                        Text("Answer the three questions")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("social-check-take")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .accessibilityIdentifier("social-check-card")
            .sheet(isPresented: $taking) { SocialConnectionSheet() }
        }
    }
}

/// The three items, then the result in plain words.
struct SocialConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var answers: [Int?] = Array(repeating: nil, count: SocialConnectionCheck.items.count)
    @State private var saved: SocialConnectionCheck.Result?

    private var complete: Bool { answers.allSatisfy { $0 != nil } }

    var body: some View {
        NavigationStack {
            Form {
                if let saved {
                    Section("Your answers") {
                        Text("\(saved.score) of 9")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.primaryText)
                        Text(saved.meaning)
                            .font(.subheadline)
                            .foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(SocialConnectionCheck.resourceLine)
                            .font(.subheadline)
                            .foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Section {
                        Text(SocialConnectionCheck.sourceLine)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else {
                    Section {
                        ForEach(SocialConnectionCheck.items.indices, id: \.self) { index in
                            SocialConnectionItem(number: index + 1, text: SocialConnectionCheck.items[index], answer: $answers[index])
                                .accessibilityIdentifier("social-check-\(index + 1)")
                        }
                    } footer: {
                        Text("Lately, how often have you felt this way? A check-in for you, not a diagnosis. Answers stay on this iPhone.")
                    }
                }
            }
            .navigationTitle(saved == nil ? "Social connection" : "Your result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if saved == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: save)
                            .disabled(!complete)
                            .accessibilityIdentifier("social-check-done")
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
    }

    private func save() {
        // Answers are 1-3 ("Hardly ever" ... "Often").
        let result = SocialConnectionCheck.Result(date: .now, answers: answers.map { ($0 ?? 0) + 1 })
        MoodScreenStore.shared.addSocial(result)
        saved = result
    }
}

/// One item and its three answers.
private struct SocialConnectionItem: View {
    let number: Int
    let text: String
    @Binding var answer: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(number). \(text)")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(SocialConnectionCheck.answers.indices, id: \.self) { value in
                Button {
                    answer = value
                } label: {
                    HStack {
                        Image(systemName: answer == value ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(answer == value ? Theme.sleep : Theme.secondaryText)
                        Text(SocialConnectionCheck.answers[value])
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
