import Foundation

/// Which days a medication is taken: every day, on chosen weekdays (weekly
/// injections such as semaglutide or tirzepatide), or every N days from a
/// start day. The reminder times (`Medication.times`) apply on each of
/// those days.
///
/// Codable with every field optional on decode, so a stored schedule never
/// fails to load after a field is added. Medications saved before schedules
/// existed have none and stay daily.
public struct MedicationSchedule: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case daily
        /// On the weekdays in `weekdays` (one weekday = once a week).
        case weekdays
        /// Every `intervalDays` days, counting from `anchor`.
        case interval
    }

    public var kind: Kind
    /// `Calendar` weekday numbers: 1 = Sunday … 7 = Saturday.
    public var weekdays: Set<Int>
    /// Days between doses for `.interval` (2 = every other day).
    public var intervalDays: Int
    /// The first dose day for `.interval`.
    public var anchor: Date

    public init(kind: Kind = .daily, weekdays: Set<Int> = [], intervalDays: Int = 2, anchor: Date = Date()) {
        self.kind = kind
        self.weekdays = weekdays.filter { (1...7).contains($0) }
        self.intervalDays = max(1, intervalDays)
        self.anchor = anchor
    }

    public static let daily = MedicationSchedule()

    /// Once a week on `weekday` (1 = Sunday … 7 = Saturday).
    public static func weekly(on weekday: Int) -> MedicationSchedule {
        MedicationSchedule(kind: .weekdays, weekdays: [weekday])
    }

    /// Once a week on the weekday of `day`.
    public static func weekly(onWeekdayOf day: Date, calendar: Calendar = .current) -> MedicationSchedule {
        weekly(on: calendar.component(.weekday, from: day))
    }

    public static func every(_ days: Int, from anchor: Date) -> MedicationSchedule {
        MedicationSchedule(kind: .interval, intervalDays: days, anchor: anchor)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, weekdays, intervalDays, anchor
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = (try? container.decodeIfPresent(Kind.self, forKey: .kind)) ?? .daily
        let weekdays = (try? container.decodeIfPresent(Set<Int>.self, forKey: .weekdays)) ?? []
        let interval = (try? container.decodeIfPresent(Int.self, forKey: .intervalDays)) ?? 2
        let anchor = (try? container.decodeIfPresent(Date.self, forKey: .anchor)) ?? Date()
        self.init(kind: kind, weekdays: weekdays, intervalDays: interval, anchor: anchor)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(weekdays.sorted(), forKey: .weekdays)
        try container.encode(intervalDays, forKey: .intervalDays)
        try container.encode(anchor, forKey: .anchor)
    }

    /// True when a dose is due on `day`. Days are counted as calendar days,
    /// not 24-hour blocks, so daylight-saving changes don't shift them.
    /// A weekday schedule with no weekdays chosen never falls due.
    public func includes(_ day: Date, calendar: Calendar = .current) -> Bool {
        switch kind {
        case .daily:
            return true
        case .weekdays:
            return weekdays.contains(calendar.component(.weekday, from: day))
        case .interval:
            guard intervalDays > 1 else { return true }
            let start = calendar.startOfDay(for: anchor)
            let target = calendar.startOfDay(for: day)
            guard let days = calendar.dateComponents([.day], from: start, to: target).day, days >= 0 else { return false }
            return days % intervalDays == 0
        }
    }

    /// The first day on or after `day` with a dose, looking up to a year ahead.
    public func nextDay(onOrAfter day: Date, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: day)
        for offset in 0..<366 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if includes(candidate, calendar: calendar) { return candidate }
        }
        return nil
    }

    /// Less often than daily: weekly injections, every other day…
    public var isLessThanDaily: Bool {
        switch kind {
        case .daily: false
        case .weekdays: weekdays.count < 7
        case .interval: intervalDays > 1
        }
    }

    /// Once a week on a single weekday.
    public var isWeekly: Bool { kind == .weekdays && weekdays.count == 1 }

    /// "Every day", "Weekly on Monday", "Mon, Wed, Fri", "Every 3 days".
    public func summary(calendar: Calendar = .current) -> String {
        switch kind {
        case .daily:
            return "Every day"
        case .weekdays:
            let days = Self.ordered(weekdays, calendar: calendar)
            if days.isEmpty { return "No days chosen" }
            if days.count == 7 { return "Every day" }
            if days.count == 1, let only = days.first {
                return "Weekly on " + Self.weekdayName(only, calendar: calendar)
            }
            return days.map { Self.weekdayName($0, calendar: calendar, short: true) }.joined(separator: ", ")
        case .interval:
            return intervalDays <= 1 ? "Every day" : (intervalDays == 2 ? "Every other day" : "Every \(intervalDays) days")
        }
    }

    /// Weekday numbers in the calendar's week order (Monday first where the week starts on Monday).
    public static func ordered(_ weekdays: Set<Int>, calendar: Calendar = .current) -> [Int] {
        let first = calendar.firstWeekday
        return weekdays.filter { (1...7).contains($0) }.sorted { ($0 - first + 7) % 7 < ($1 - first + 7) % 7 }
    }

    /// All seven weekday numbers in the calendar's week order.
    public static func weekOrder(calendar: Calendar = .current) -> [Int] {
        ordered(Set(1...7), calendar: calendar)
    }

    public static func weekdayName(_ weekday: Int, calendar: Calendar = .current, short: Bool = false) -> String {
        let names = short ? calendar.shortWeekdaySymbols : calendar.weekdaySymbols
        guard (1...names.count).contains(weekday) else { return "" }
        return names[weekday - 1]
    }
}

extension MedicationKnowledge {
    /// The schedule a medication is usually taken on, when that isn't daily,
    /// from its FDA prescribing information: semaglutide injection (Ozempic,
    /// Wegovy), tirzepatide (Mounjaro, Zepbound) and dulaglutide (Trulicity)
    /// are injected once a week, any time of day (Ozempic PI 2025; Wegovy PI
    /// 2025; Mounjaro PI 2025; Zepbound PI 2025; Trulicity PI 2024). Oral
    /// semaglutide (Rybelsus, the Wegovy pill) and liraglutide (Victoza,
    /// Saxenda) are daily, so they return nil. A suggestion for the editor
    /// only: the user's own schedule always wins.
    public static func usualSchedule(for medicationName: String) -> MedicationSchedule.Kind? {
        let words = medicationName.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let oral: Set<String> = ["pill", "pills", "tablet", "tablets", "oral", "rybelsus"]
        guard words.allSatisfy({ !oral.contains($0) }) else { return nil }
        let weekly: Set<String> = ["semaglutide", "ozempic", "wegovy", "tirzepatide", "mounjaro", "zepbound",
                                   "dulaglutide", "trulicity"]
        return words.contains(where: weekly.contains) ? .weekdays : nil
    }
}
