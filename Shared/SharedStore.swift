import Foundation
import AppCore

/// Data shared between the app, its widget and Live Activity, stored in the
/// App Group so all three can read and write it.
nonisolated enum SharedStore {
    static let appGroup = "group.com.lontraindustries.workoutapp"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Decodes, or reports data that is there but won't decode (kept under
    /// "<key>.corrupt"), so a save never wipes data that only failed to read.
    static func loadChecked<T: Decodable>(_ type: T.Type, key: String) -> (value: T?, unreadable: Bool) {
        guard let data = defaults.data(forKey: key) else { return (nil, false) }
        if let value = try? JSONDecoder().decode(type, from: data) { return (value, false) }
        defaults.set(data, forKey: key + ".corrupt")
        return (nil, true)
    }

    /// Saves, keeping the previous value under "<key>.bak".
    static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        if let old = defaults.data(forKey: key), old != data { defaults.set(old, forKey: key + ".bak") }
        defaults.set(data, forKey: key)
    }
}

/// What the Home Screen widget shows.
nonisolated struct WidgetSnapshot: Codable, Sendable, Equatable {
    var updated: Date
    var hrv: Double?
    /// The morning the HRV belongs to.
    var hrvDate: Date?
    var recovery: Int?
    var strain: Double?
    /// The user types or measures HRV in the app (recent readings), so the widget
    /// may ask for one; nil (older snapshots) counts as yes. Watch users aren't asked.
    var logsHRV: Bool? = nil

    static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot? { SharedStore.load(WidgetSnapshot.self, key: key) }
    func save() { SharedStore.save(self, key: Self.key) }

    var hrvIsFromToday: Bool {
        hrvDate.map { Calendar.current.isDateInToday($0) } ?? false
    }
}

/// A medication the user takes, with its reminder times and the days it's due.
nonisolated struct Medication: Codable, Sendable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var dose: String = ""
    /// Reminder times as minutes after midnight. Empty = no reminders (as needed).
    var times: [Int] = []
    var startDate: Date = .now
    var notes: String = ""
    var isActive = true
    /// Which days it's due (weekly injections, every N days). Optional so
    /// medications saved before schedules existed still decode; nil = daily.
    var schedule: MedicationSchedule? = nil

    /// The schedule in use: daily unless one was set.
    var plan: MedicationSchedule { schedule ?? .daily }

    /// True when a dose is due on `day` (on or after the start date).
    func isDue(on day: Date, calendar: Calendar = .current) -> Bool {
        isActive && calendar.startOfDay(for: startDate) <= calendar.startOfDay(for: day) && plan.includes(day, calendar: calendar)
    }
}

/// One scheduled dose on one day.
nonisolated struct Dose: Codable, Sendable, Hashable, Identifiable {
    var medicationID: UUID
    var name: String
    var dose: String
    /// Start of the day.
    var day: Date
    /// Minutes after midnight.
    var minutes: Int

    /// Stable key, e.g. "UUID|2026-10-18|480".
    var id: String {
        "\(medicationID.uuidString)|\(Self.dayKey(day))|\(minutes)"
    }

    /// The clock time on that day. Set by hour and minute (not seconds after
    /// midnight) so it's right on the days clocks change.
    var time: Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
            ?? day.addingTimeInterval(TimeInterval(minutes * 60))
    }

    static func dayKey(_ day: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: day)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

/// Medications and the log of doses taken.
nonisolated enum MedicationStore {
    private static let medsKey = "medications"
    private static let takenKey = "dosesTaken"

    static func medications() -> [Medication] {
        SharedStore.load([Medication].self, key: medsKey) ?? []
    }

    static func save(_ medications: [Medication]) {
        guard !SharedStore.loadChecked([Medication].self, key: medsKey).unreadable else { return }
        SharedStore.save(medications, key: medsKey)
    }

    /// Dose key → when it was taken.
    static func takenLog() -> [String: Date] {
        SharedStore.load([String: Date].self, key: takenKey) ?? [:]
    }

    static func isTaken(_ doseID: String) -> Bool {
        takenLog()[doseID] != nil
    }

    static func markTaken(_ doseID: String, at date: Date = .now) {
        guard !SharedStore.loadChecked([String: Date].self, key: takenKey).unreadable else { return }
        var log = takenLog()
        log[doseID] = date
        // Keep 60 days of history.
        let cutoff = Date.now.addingTimeInterval(-60 * 86_400)
        log = log.filter { $0.value > cutoff }
        SharedStore.save(log, key: takenKey)
    }

    static func unmark(_ doseID: String) {
        guard !SharedStore.loadChecked([String: Date].self, key: takenKey).unreadable else { return }
        var log = takenLog()
        log[doseID] = nil
        SharedStore.save(log, key: takenKey)
    }

    /// Scheduled doses for a day, in time order: only medications due that
    /// day (`Medication.schedule`), so a weekly injection appears once a week.
    static func doses(on day: Date, calendar: Calendar = .current) -> [Dose] {
        let start = calendar.startOfDay(for: day)
        return medications()
            .filter { $0.isDue(on: start, calendar: calendar) }
            .flatMap { med in
                med.times.map { Dose(medicationID: med.id, name: med.name, dose: med.dose, day: start, minutes: $0) }
            }
            .sorted { $0.minutes < $1.minutes }
    }
}
