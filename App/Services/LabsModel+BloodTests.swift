import Foundation
import UserNotifications
import AppCore

/// "Know your numbers": the blood tests due for heart and metabolic risk
/// (`BloodTestSchedule`; docs/research/evidence-audit-2026-11.md, Gaps, item 2),
/// from the results in Labs and any test dates typed in without results.
extension LabsModel {
    static let testedOnKey = "labs.testedOn"

    /// Each check that applies at this age, with its due date.
    func bloodTestSchedule(age: Int, now: Date = .now) -> [BloodTestSchedule.Due] {
        let catalogued = results.compactMap { result -> BloodTestSchedule.Result? in
            guard let id = result.markerID else { return nil }
            return BloodTestSchedule.Result(markerID: id, value: result.value, unit: result.unit, date: result.date, status: result.status)
        }
        var typed: [BloodTestSchedule.Check: Date] = [:]
        for (key, date) in testedOn {
            if let check = BloodTestSchedule.Check(rawValue: key) { typed[check] = date }
        }
        return BloodTestSchedule.schedule(results: catalogued, testedOn: typed, age: age, now: now)
    }

    /// The newest typed-in date for one check, if any.
    func typedTestDate(_ check: BloodTestSchedule.Check) -> Date? {
        testedOn[check.rawValue]
    }
}

/// One reminder per blood test when it falls due, only after the person
/// switches it on in Labs (off by default: the owner dislikes nagging, and
/// these are a doctor's-visit task, not a daily one). Same rule as the
/// measurement reminders: one on the due day, then, while still not done,
/// one more after `BloodTestSchedule.reminderRepeatDays` (`OverdueReminder`).
nonisolated extension Reminders {
    static let bloodTestRemindersKey = "bloodTestRemindersOn"
    static var bloodTestRemindersOn: Bool {
        UserDefaults.standard.bool(forKey: bloodTestRemindersKey)
    }

    static func bloodTestIdentifier(_ check: BloodTestSchedule.Check) -> String { "measure|lab|" + check.rawValue }

    /// Replaces the pending blood-test reminders from `schedule`. Nothing while
    /// switched off; a check without a due date (Lp(a) done) has none.
    static func scheduleBloodTestReminders(_ schedule: [BloodTestSchedule.Due]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: BloodTestSchedule.Check.allCases.map(bloodTestIdentifier))
        guard bloodTestRemindersOn else {
            // A reminder that was only waiting never went out: forget it, so
            // switching back on reminds when due (as `measurementRemindersChanged`).
            for check in BloodTestSchedule.Check.allCases {
                let key = lastReminderKey(bloodTestIdentifier(check))
                if let fire = UserDefaults.standard.object(forKey: key) as? Date, fire > .now {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            return
        }
        guard await notificationsAllowed() else { return }
        let calendar = Calendar.current
        for due in schedule {
            guard let dueDate = due.dueDate else { continue }
            let identifier = bloodTestIdentifier(due.check)
            guard let fire = overdueFireDate(identifier: identifier, due: dueDate,
                                             intervalDays: BloodTestSchedule.reminderRepeatDays, calendar: calendar) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(due.check.title) is due"
            content.body = due.check == .lipids && due.askForApoB
                ? "Worth asking your doctor for one at your next visit, with ApoB. Add the results in Labs."
                : "Worth asking your doctor for one at your next visit. Add the results in Labs."
            content.sound = .default
            await add(content, identifier: identifier, at: fire, center: center, calendar: calendar)
            noteReminder(identifier, firesAt: fire)
        }
    }
}
