import AppCore
import Foundation
import FoundationModels
import UserNotifications
import os

/// Turns planned reminders into notification content, off the main actor
/// (called from `Reminders.scheduleWorkoutReminders`).
nonisolated enum WorkoutVoiceWriter {
    /// A workout reminder about to be scheduled.
    struct Planned: Sendable {
        var key: String
        var fire: Date
        var slot: Reminders.PlannedSlot
        /// Nil when the caller gave no facts: the reminder keeps its old plain wording.
        var facts: WorkoutBanter.Facts?
        var isToday: Bool
    }

    private static let log = Logger(subsystem: "com.lontraindustries.workoutapp", category: "workout-voice")

    /// Each reminder's line, by day key. With nothing planned, the saved
    /// pending lines are cleared (and the ones that went out join the history).
    static func lines(for planned: [Planned], voice: WorkoutVoiceContext?, now: Date) -> [String: WorkoutBanter.Assigned] {
        guard let voice else { return [:] }
        let requests = planned.compactMap { item in
            item.facts.map { WorkoutBanter.DayRequest(dayKey: item.key, fire: item.fire, facts: $0, isToday: item.isToday) }
        }
        // A model's line stays pending only while fresh lines are on and the model is there.
        let freshLines = voice.freshLines && WorkoutVoiceModel.isAvailable
        return WorkoutVoiceStore.shared.reconcile(requests, tone: voice.tone, freshLines: freshLines, now: now)
    }

    /// The notification: what and when in the title, the line in the body,
    /// and the if-then line you wrote under the title.
    static func content(for item: Planned, line: WorkoutBanter.Assigned?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "\(item.slot.name) at \(item.slot.start.formatted(date: .omitted, time: .shortened))"
        let ifThen = item.slot.ifThen?.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = ifThen?.isEmpty == false ? ifThen : nil
        if let line, let facts = item.facts {
            // Keeping plain (`Caution.keepPlain`) isn't a no-push day: the session and your if-then line stand.
            let mustBeSaid = facts.noPush || facts.lastCall
            if line.tone == .plain, !mustBeSaid, let plan {
                // Plain, with a plan of your own: your words are the reminder, as before.
                content.body = plan
            } else {
                content.body = line.pick.text
                // Your if-then line stays in view, except on a day when the reminder must not push.
                if let plan, !facts.noPush { content.subtitle = plan }
            }
        } else {
            content.body = plan ?? "Your planned session in \(Reminders.workoutLeadMinutes) minutes. The short version counts too."
        }
        content.sound = .default
        content.userInfo = ["link": "workoutapp://plan"]
        return content
    }

    /// The soonest pending reminder gets at least this long before it fires
    /// for the model to write its line (app choice).
    static let minimumLeadSeconds: TimeInterval = 5 * 60

    /// Asks the on-device model for a fresh line for the soonest reminder
    /// that may have one (`WorkoutBanter.wantsGenerated`), in the background:
    /// scheduling never waits for it, and the library line stays unless the
    /// model's line passes every check (`WorkoutBanterGuard.acceptGenerated`).
    /// At most one request at a time and one per reminder and set of facts.
    static func freshen(_ planned: [Planned], lines: [String: WorkoutBanter.Assigned], voice: WorkoutVoiceContext?, now: Date) {
        guard let voice, voice.freshLines, voice.tone == .playful else { return }
        let candidates = planned.sorted { $0.fire < $1.fire }.filter { item in
            guard let facts = item.facts, let line = lines[item.key] else { return false }
            return item.fire.timeIntervalSince(now) > minimumLeadSeconds && WorkoutBanter.wantsGenerated(line, facts: facts)
        }
        guard let item = candidates.first, let facts = item.facts, let askedFor = lines[item.key], WorkoutVoiceModel.isAvailable else { return }
        guard WorkoutVoiceStore.shared.startAsking() else { return }
        Task.detached(priority: .utility) {
            let history = WorkoutVoiceStore.shared.history()
            let examples = WorkoutBanterPrompt.examples(facts: facts, history: history)
            let prompt = WorkoutBanterPrompt.prompt(facts: facts, examples: examples)
            let candidate = await WorkoutVoiceModel.line(prompt: prompt)
            // Not a near-copy of the examples it was shown or of anything sent lately.
            let recent = examples + history.recentTexts(WorkoutBanter.recentWindow)
            let accepted = candidate.flatMap { WorkoutBanterGuard.acceptGenerated($0, facts: facts, recent: recent) }
            // Only onto the line it was written for, and only while still true for today's facts.
            let stored = WorkoutVoiceStore.shared.finishAsking(dayKey: item.key, facts: facts, accepted: accepted, askedFor: askedFor)
            log.notice("fresh line for \(item.key, privacy: .public): \(accepted == nil ? "kept the library line" : "accepted", privacy: .public)")
            guard accepted != nil, let stored, stored.isGenerated, stored.pick.text == accepted else { return }
            await replacePending(item, line: stored)
        }
    }

    /// Puts the new line on the reminder if it is still waiting to go out, at
    /// the time the stored pending reminder has now (a reschedule while the
    /// model was writing may have moved it).
    private static func replacePending(_ item: Planned, line: WorkoutBanter.Assigned) async {
        let center = UNUserNotificationCenter.current()
        let identifier = Reminders.workoutIdentifier(forDayKey: item.key)
        var item = item
        if line.fire != item.fire {
            item.fire = line.fire
            item.slot.start = line.fire.addingTimeInterval(TimeInterval(Reminders.workoutLeadMinutes * 60))
        }
        guard item.fire > .now, await center.pendingNotificationRequests().map(\.identifier).contains(identifier) else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fire)
        // The same identifier: iOS replaces the pending request.
        let request = UNNotificationRequest(identifier: identifier, content: content(for: item, line: line),
                                            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        try? await center.add(request)
    }
}

// MARK: - On-device model

/// One short line from Apple's on-device model (FoundationModels). The
/// prompt holds training-log facts only (`WorkoutBanterPrompt`), the session
/// and its reply never leave this function, and only a `String` comes out,
/// to be checked by `WorkoutBanterGuard.acceptGenerated` before any use.
nonisolated enum WorkoutVoiceModel {
    /// The longest the model gets (app choice); the library line is already scheduled by then.
    static let timeoutSeconds = 20
    /// Livelier than the coach's answers (0.2–0.3): variety is the point here, and every line is checked.
    static let temperature = 0.9
    /// A line is under 160 characters; this leaves room and stops a ramble.
    static let maximumResponseTokens = 80

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    @concurrent nonisolated static func line(prompt: String) async -> String? {
        guard isAvailable else { return nil }
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: WorkoutBanterPrompt.instructions)
                let options = GenerationOptions(temperature: temperature, maximumResponseTokens: maximumResponseTokens)
                do {
                    return try await session.respond(to: prompt, options: options).content
                } catch {
                    // Unavailable, declined or cancelled: the library line stays.
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
