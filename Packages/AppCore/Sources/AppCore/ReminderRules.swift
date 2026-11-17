import Foundation

/// Small, pure rules behind the app's local notifications (`Reminders` in the
/// app), kept here so they can be tested. The aim of every one is fewer
/// prompts: the effect of repeated prompts decays with habituation (Klasnja
/// et al., Ann Behav Med 2019), and Apple's Human Interface Guidelines ask
/// apps not to send several notifications for the same thing.
public enum ReminderRules {
    // MARK: Weigh-in line on the morning reminder

    /// Days between two morning reminders that carry the weigh-in line
    /// (app's choice: at most once a week).
    public static let weighInLineEveryDays = 7

    /// Whether a morning reminder may carry the weigh-in line.
    /// - Parameters:
    ///   - lastCarried: the day whose morning reminder last carried it.
    ///   - morningMinutes: when the morning reminder fires, minutes after midnight.
    /// While that reminder hasn't fired yet the line stays on it (true, so a
    /// reschedule doesn't drop it); once it has fired, not again for
    /// `weighInLineEveryDays` days.
    public static func weighInLineDue(lastCarried: Date?, morningMinutes: Int, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastCarried else { return true }
        let lastDay = calendar.startOfDay(for: lastCarried)
        let fire = calendar.date(bySettingHour: morningMinutes / 60, minute: morningMinutes % 60, second: 0, of: lastDay)
            ?? lastDay.addingTimeInterval(TimeInterval(morningMinutes * 60))
        if fire > now { return true }
        let days = calendar.dateComponents([.day], from: lastDay, to: calendar.startOfDay(for: now)).day ?? 0
        return days >= weighInLineEveryDays
    }

    // MARK: Monday weekly review

    /// The next Monday review reminders, soonest first: Mondays at `minutes`
    /// after midnight that are still ahead, leaving out a Monday on which the
    /// review was already opened before the reminder's time (a reminder for
    /// something just done is noise).
    public static func weeklyReviewFireDates(now: Date, minutes: Int, lastOpened: Date?, count: Int = 2,
                                             calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0..<(7 * (count + 1)) where result.count < count {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  calendar.component(.weekday, from: day) == 2, // Monday
                  let fire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
                  fire > now else { continue }
            if let lastOpened, lastOpened >= day, lastOpened <= fire { continue }
            result.append(fire)
        }
        return result
    }
}

/// The workout reminders' "pause after two ignored in a row" log, as pure
/// rules. The log maps a day key ("2027-01-10", sortable) to the time that
/// day's reminder fires.
public enum WorkoutReminderRules {
    /// Ignored reminders in a row before they pause: each prompt spends attention
    /// and repeated ones habituate (Klasnja et al., Ann Behav Med 2019). Two is the app's choice.
    public static let ignoredBeforePause = 2
    /// Entries kept (app's choice; only the newest few matter).
    public static let keptEntries = 30

    /// The log after a reschedule. Reminders that have fired stay (they may
    /// still count as ignored, today's included); ones that hadn't fired were
    /// just removed from the pending queue, so they leave the log: a reminder
    /// that never went out (reminders turned off, rest mode, a changed plan)
    /// is never counted as ignored. `scheduled` is what is pending now.
    public static func logAfterReschedule(_ log: [String: Date], scheduled: [String: Date], now: Date) -> [String: Date] {
        var result = log.filter { $0.value <= now }
        for (key, fire) in scheduled { result[key] = fire }
        guard result.count > keptEntries else { return result }
        let newest = result.keys.sorted().suffix(keptEntries)
        return result.filter { newest.contains($0.key) }
    }

    /// How many of the most recent delivered reminders, on days before
    /// `todayKey`, went unanswered in a row. `answered` holds the day keys
    /// that were tapped, trained on, or excused (rest mode).
    public static func ignoredInARow(log: [String: Date], answered: Set<String>, todayKey: String, now: Date) -> Int {
        var ignored = 0
        for key in log.keys.sorted().reversed() where key < todayKey {
            guard let fire = log[key], fire <= now else { continue }
            if answered.contains(key) { break }
            ignored += 1
        }
        return ignored
    }
}
