import Foundation

/// When to remind about a measurement that is due (a monthly waist, a
/// 6-monthly grip test, a 3-6-monthly home blood pressure week).
///
/// Reminders were rebuilt on every launch, and an overdue one always moved to
/// "tomorrow morning", so an overdue measurement nagged every day. Now: one
/// reminder when it falls due (or the next morning, if that has passed), and
/// if it is still not done, the next one only a full interval later. Repeated
/// prompts that aren't acted on lose their effect and get notifications
/// turned off (alert fatigue: Ancker et al., BMC Med Inform Decis Mak 2017);
/// the one-then-a-full-interval rule itself is the app's choice.
public enum OverdueReminder {
    /// The day the next reminder should fire on, or nil to keep none.
    /// - Parameters:
    ///   - due: when the measurement falls due.
    ///   - lastNag: the fire date of the last reminder scheduled for an
    ///     overdue measurement, if any (stored by the app).
    ///   - intervalDays: the measurement's own cadence.
    /// - Returns: the start of the day to remind on (the app picks the time).
    public static func nextDay(due: Date, lastNag: Date?, intervalDays: Int, now: Date = .now,
                               calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)
        guard let lastNag, lastNag >= dueDay else {
            // Not reminded since it fell due: on the due day, or today if that has passed.
            return max(dueDay, today)
        }
        let nagDay = calendar.startOfDay(for: lastNag)
        // Still waiting to fire: keep it where it is.
        if lastNag > now { return nagDay }
        // Fired and still not done: wait a whole interval.
        let next = calendar.date(byAdding: .day, value: max(1, intervalDays), to: nagDay) ?? nagDay
        return max(next, today)
    }
}
