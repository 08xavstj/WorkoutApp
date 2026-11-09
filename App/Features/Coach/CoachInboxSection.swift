import SwiftUI
import AppCore

/// The coach's own messages (morning, after a workout, evening) at the top
/// of the Coach tab, as coach bubbles with their follow-up question, so a
/// notification can turn into a conversation. Shows the last day and a half;
/// seeing them here counts as opening them (`CoachInbox.markSeen`).
struct CoachInboxSection: View {
    /// Sends a question to the chat (CoachView's `send`).
    let ask: (String) -> Void

    @State private var inbox = CoachInbox.shared

    /// How far back the tab shows (app choice: today's and last night's messages).
    private static let showHours: Double = 36

    private var recent: [CoachInbox.Entry] {
        let now = Date.now
        let cutoff = now.addingTimeInterval(-Self.showHours * 3600)
        return Array(inbox.delivered(now: now).filter { $0.deliverAt >= cutoff }.suffix(3))
    }

    var body: some View {
        let entries = recent
        VStack(alignment: .leading, spacing: 16) {
            ForEach(entries) { entry in
                CoachNudgeBubble(entry: entry, ask: ask)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: entries.map(\.id)) {
            inbox.markSeen(entries.filter { !$0.opened }.map(\.id))
        }
        .task(id: inbox.pendingQuestion) {
            guard let question = inbox.pendingQuestion else { return }
            inbox.pendingQuestion = nil
            ask(question)
        }
    }
}

private struct CoachNudgeBubble: View {
    let entry: CoachInbox.Entry
    let ask: (String) -> Void
    /// Same avatar as the chat's coach replies, scaling with Dynamic Type.
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize: CGFloat = 32

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: avatarSize, height: avatarSize)
                .background(LinearGradient(colors: [Theme.strain, Theme.sleep], startPoint: .bottomLeading, endPoint: .topTrailing), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                header
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(entry.body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let question = entry.question {
                    Button {
                        ask(question)
                    } label: {
                        Label(question, systemImage: "arrow.turn.down.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .background(Theme.card, in: .capsule)
                            .overlay(Capsule().strokeBorder(Theme.separator))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Asks the coach")
                }
            }
        }
    }

    /// "Morning · 7:15 AM · from your data"
    private var header: some View {
        let time = entry.deliverAt.formatted(date: .omitted, time: .shortened)
        let source = entry.reworded ? "worded on this iPhone" : "from your data"
        return Text("\(entry.kind.label) · \(time) · \(source)")
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
    }
}
