import Foundation
import Observation
import AppCore

/// The messages the coach sent first (`CoachNudges`): morning, after a
/// workout and evening. Each shows in the Coach tab once its time has come,
/// so the conversation can carry on there, and whether it was opened drives
/// the back-off (`CoachCheckIns.backOff`). Kept for 30 days as JSON in
/// UserDefaults, like `WarmUpStore` and `SupersetRegistry`; nothing leaves the
/// iPhone.
@Observable
final class CoachInbox {
    nonisolated struct Entry: Codable, Sendable, Identifiable, Equatable {
        /// The notification identifier: "coach|morning|2027-01-11".
        var id: String
        var kind: CoachCheckIns.Kind
        var title: String
        /// The words shown: the app's own, or the on-device model's rewording of them.
        var body: String
        var link: String
        var question: String?
        /// When it is (or was) due; it shows in the Coach tab from then.
        var deliverAt: Date
        /// Sent as a notification, not only to the Coach tab.
        var notified: Bool
        /// Tapped, answered with a notification button, or seen in the Coach tab.
        var opened: Bool
        /// The rule-based message's key (`CoachCheckIns.Message.key`), for "nothing new".
        var key: String
        /// The body is the on-device model's rewording.
        var reworded: Bool

        var sent: CoachCheckIns.Sent {
            CoachCheckIns.Sent(kind: kind, deliverAt: deliverAt, notified: notified, opened: opened, key: key)
        }
    }

    static let shared = CoachInbox()

    private static let storageKey = "coachInbox"
    static let keepDays = 30

    private(set) var entries: [Entry]
    /// A question from a "workoutapp://coach?q=…" link, asked once the Coach tab shows (`CoachInboxSection`).
    var pendingQuestion: String?

    init() {
        entries = Self.load()
    }

    /// For `AppRouter.open`: keeps the link's question ("q") for the Coach tab.
    func open(_ url: URL) {
        let question = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "q" }?.value
        if let question, !question.isEmpty { pendingQuestion = question }
    }

    /// Everything as `CoachCheckIns` reads it.
    var history: [CoachCheckIns.Sent] { entries.map(\.sent) }

    /// Messages whose time has come, oldest first.
    func delivered(now: Date = .now) -> [Entry] {
        entries.filter { $0.deliverAt <= now }.sorted { $0.deliverAt < $1.deliverAt }
    }

    /// Messages of `kind` not yet due (at most one, normally).
    func pending(_ kind: CoachCheckIns.Kind, now: Date = .now) -> [Entry] {
        entries.filter { $0.kind == kind && $0.deliverAt > now }
    }

    func entry(id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Adds `entry`, replacing any message of the same kind that isn't due yet.
    func replacePending(with entry: Entry, now: Date = .now) {
        var updated = entries.filter { !($0.kind == entry.kind && $0.deliverAt > now) && $0.id != entry.id }
        updated.append(entry)
        save(updated, now: now)
    }

    /// Drops the messages of `kind` that aren't due yet (turned off, or nothing to say any more).
    func removePending(_ kind: CoachCheckIns.Kind, now: Date = .now) {
        let updated = entries.filter { !($0.kind == kind && $0.deliverAt > now) }
        if updated != entries { save(updated, now: now) }
    }

    func markOpened(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), !entries[index].opened else { return }
        var updated = entries
        updated[index].opened = true
        save(updated)
    }

    /// The Coach tab showed these: seen counts as opened, so reading the
    /// coach in the app never counts as ignoring it.
    func markSeen(_ ids: [String]) {
        var updated = entries
        var changed = false
        for index in updated.indices where ids.contains(updated[index].id) && !updated[index].opened {
            updated[index].opened = true
            changed = true
        }
        if changed { save(updated) }
    }

    // MARK: Storage

    private func save(_ updated: [Entry], now: Date = .now) {
        let cutoff = now.addingTimeInterval(-TimeInterval(Self.keepDays) * 86_400)
        let kept = updated.filter { $0.deliverAt >= cutoff }.sorted { $0.deliverAt < $1.deliverAt }
        entries = kept
        if let data = try? JSONEncoder().encode(kept) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return decoded
    }
}
