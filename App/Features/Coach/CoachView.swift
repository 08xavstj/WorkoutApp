import SwiftUI
import SwiftData

/// Chat with the AI coach about your recovery, sleep and training.
struct CoachView: View {
    @Environment(CoachModel.self) private var coach
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if coach.messages.isEmpty {
                            emptyState
                        }
                        ForEach(coach.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if coach.isThinking {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Thinking…").foregroundStyle(Theme.secondaryText)
                            }
                            .id("thinking")
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: coach.messages.count) {
                    guard let lastID = coach.messages.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
            .background(Theme.background)
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(settings.coachMode == .onDevice ? "On-device" : "Claude")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.cardRaised, in: .capsule)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        coach.newConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New conversation")
                    .disabled(coach.messages.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                inputBar
            }
            .task(id: coach.pendingQuestion) {
                if let question = coach.pendingQuestion {
                    coach.pendingQuestion = nil
                    await send(question)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(Theme.strain)
            Text("Ask about your recovery, sleep or training.")
                .font(.title3.weight(.semibold))
            Text("The coach sees today's scores and your last two weeks of workouts.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            ForEach(CoachModel.suggestions, id: \.self) { suggestion in
                Button {
                    Task { await send(suggestion) }
                } label: {
                    Text(suggestion)
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.card, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 40)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message your coach", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.card, in: .rect(cornerRadius: 20))
                .onSubmit { Task { await sendDraft() } }
            Button {
                Task { await sendDraft() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coach.isThinking)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Theme.background)
    }

    private func sendDraft() async {
        let text = draft
        draft = ""
        await send(text)
    }

    private func send(_ text: String) async {
        let snapshot = CoachSnapshot.make(metrics: metrics, sessions: sessions, unit: settings.weightUnit)
        await coach.send(text, snapshot: snapshot, settings: settings)
    }
}

private struct MessageBubble: View {
    let message: CoachModel.ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(LocalizedStringKey(message.text))
                .textSelection(.enabled)
                .padding(12)
                .background(background, in: .rect(cornerRadius: 16))
                .foregroundStyle(message.role == .error ? Theme.recoveryLow : .white)
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var background: Color {
        switch message.role {
        case .user: Theme.strain.opacity(0.35)
        case .coach: Theme.card
        case .error: Theme.recoveryLow.opacity(0.12)
        }
    }
}
