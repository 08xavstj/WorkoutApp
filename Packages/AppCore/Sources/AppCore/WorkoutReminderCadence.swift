import Foundation

/// When workout reminders go quiet and when they come back, as pure rules
/// on top of `WorkoutReminderRules` (the log of what went out and what was answered).
///
/// - After one reminder goes unanswered, the next one is the **last call**:
///   it says, once and kindly, that reminders go quiet after it, and it is
///   the only one left pending, so the quiet starts by itself even if the
///   app is never opened again.
/// - After two in a row (`WorkoutReminderRules.ignoredBeforePause`) they are
///   **quiet**, counted from when the last one went out.
/// - They come back when you train or confirm a weekly plan, at once and in
///   full; or when you open the app once the quiet has lasted `quietDays`,
///   **one at a time** until one is answered. The first quiet lasts a day, so
///   the next time you open the app they are back, as the last call said.
///   One more unanswered then, with no second last call, and the next quiet
///   is longer (3, 7, then 14 days).
///
/// Why: repeated prompts stop working (HeartSteps: the effect of a suggestion
/// fell about 2% a day and was gone by day 28, and people said the
/// suggestions "became boring after 2–4 weeks": Klasnja et al., Ann Behav Med
/// 2019, full text read), and a reminder nobody answers is noise. The numbers
/// (two, the quiet lengths) are app choices; no trial tested them.
public enum WorkoutReminderCadence {
    public struct State: Codable, Sendable, Equatable {
        /// When the current quiet began; nil while reminders are on.
        public var quietSince: Date?
        /// Quiet spells in a row with no answered reminder between them.
        public var quietSpells = 0
        /// Back from a quiet spell by opening the app, at this time: one
        /// reminder at a time until one is answered. Nil otherwise.
        public var oneAtATimeSince: Date?

        public init() {}
    }

    public enum Stage: String, Sendable, Equatable {
        case normal, lastCall, oneAtATime, quiet
        /// The one reminder the last call or one-at-a-time stage allows went
        /// out today and hasn't been answered yet: nothing more is scheduled
        /// until it is, or until tomorrow settles it.
        case waiting

        /// Reminders kept pending at this stage.
        public var maxPending: Int {
            switch self {
            case .normal: 7
            case .lastCall, .oneAtATime: 1
            case .quiet, .waiting: 0
            }
        }
    }

    public struct Decision: Sendable, Equatable {
        public var state: State
        public var stage: Stage
        /// Start the log again (what went unanswered before the quiet no longer counts).
        public var clearLog: Bool
    }

    /// Days a quiet spell lasts before opening the app ends it (app choice).
    public static func quietDays(spell: Int) -> Int {
        switch spell {
        case ...1: 1
        case 2: 3
        case 3: 7
        default: 14
        }
    }

    /// - Parameters:
    ///   - log: day key → when that day's reminder fires (`WorkoutReminderRules`).
    ///   - tapped: day keys whose reminder was tapped or excused (rest mode).
    ///   - trained: day keys with training.
    ///   - dayKey: turns a date into a day key ("2027-01-10").
    public static func evaluate(_ state: State, log: [String: Date], tapped: Set<String>, trained: Set<String>, now: Date,
                                calendar: Calendar = .current, dayKey: (Date) -> String) -> Decision {
        var next = state
        let todayKey = dayKey(now)
        if next.quietSince == nil {
            if let since = next.oneAtATimeSince {
                // The log was started again when the quiet ended, so any tap in it is an answer since then.
                let sinceKey = dayKey(since)
                if trained.contains(where: { $0 >= sinceKey }) || log.keys.contains(where: { tapped.contains($0) }) {
                    next = State()
                }
            }
            // Training answers every reminder up to that day; later ones are answered by a tap (or rest mode).
            let latestTrained = trained.max()
            let open = log.filter { entry in latestTrained.map { entry.key > $0 } ?? true }
            let sentToday = (open[todayKey].map { $0 <= now }) ?? false
            // Today's reminder tapped: the row of unanswered ones is over.
            let ignored = sentToday && tapped.contains(todayKey)
                ? 0 : WorkoutReminderRules.ignoredInARow(log: open, answered: tapped, todayKey: todayKey, now: now)
            guard ignored >= (next.oneAtATimeSince != nil ? 1 : WorkoutReminderRules.ignoredBeforePause) else {
                let stage: Stage = next.oneAtATimeSince != nil ? .oneAtATime : (ignored >= 1 ? .lastCall : .normal)
                // The single reminder these stages allow is already out today, unanswered so far.
                if stage != .normal, sentToday { return Decision(state: next, stage: .waiting, clearLog: false) }
                return Decision(state: next, stage: stage, clearLog: false)
            }
            // Quiet since the last unanswered reminder went out.
            next.quietSince = open.filter { $0.key < todayKey && $0.value <= now }.values.max() ?? now
            next.quietSpells += 1
            next.oneAtATimeSince = nil
        }
        let since = next.quietSince ?? now
        let sinceKey = dayKey(since)
        if trained.contains(where: { $0 > sinceKey }) {
            return Decision(state: State(), stage: .normal, clearLog: true)
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: since), to: calendar.startOfDay(for: now)).day ?? 0
        guard days >= quietDays(spell: next.quietSpells) else {
            return Decision(state: next, stage: .quiet, clearLog: false)
        }
        next.quietSince = nil
        next.oneAtATimeSince = now
        return Decision(state: next, stage: .oneAtATime, clearLog: true)
    }
}
