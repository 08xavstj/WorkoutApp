import Foundation

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

    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
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

    static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot? { SharedStore.load(WidgetSnapshot.self, key: key) }
    func save() { SharedStore.save(self, key: Self.key) }

    var hrvIsFromToday: Bool {
        hrvDate.map { Calendar.current.isDateInToday($0) } ?? false
    }
}

/// A medication the user takes, with daily reminder times.
nonisolated struct Medication: Codable, Sendable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var dose: String = ""
    /// Reminder times as minutes after midnight. Empty = no reminders (as needed).
    var times: [Int] = []
    var startDate: Date = .now
    var notes: String = ""
    var isActive = true
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

    var time: Date { day.addingTimeInterval(TimeInterval(minutes * 60)) }

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
        var log = takenLog()
        log[doseID] = date
        // Keep 60 days of history.
        let cutoff = Date.now.addingTimeInterval(-60 * 86_400)
        log = log.filter { $0.value > cutoff }
        SharedStore.save(log, key: takenKey)
    }

    static func unmark(_ doseID: String) {
        var log = takenLog()
        log[doseID] = nil
        SharedStore.save(log, key: takenKey)
    }

    /// Scheduled doses for a day, in time order.
    static func doses(on day: Date, calendar: Calendar = .current) -> [Dose] {
        let start = calendar.startOfDay(for: day)
        return medications()
            .filter { $0.isActive && calendar.startOfDay(for: $0.startDate) <= start }
            .flatMap { med in
                med.times.map { Dose(medicationID: med.id, name: med.name, dose: med.dose, day: start, minutes: $0) }
            }
            .sorted { $0.minutes < $1.minutes }
    }
}
