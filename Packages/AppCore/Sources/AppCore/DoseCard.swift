import Foundation

/// When a dose joins the Lock Screen doses card and the Today screen's
/// "Up next" list. The dose's own reminder still fires at the time set on it.
///
/// The two hours are the user's preference, not research: a card that showed
/// from midnight sat on the Lock Screen all night, and creatine kept it there
/// all day. Creatine timing makes little difference (Kreider et al., J Int Soc
/// Sports Nutr 2017;14:18, position stand), so showing it later costs nothing.
public enum DoseCard {
    /// Medications show from 06:00.
    public static let medicationsFromHour = 6
    /// Creatine and other supplements show from 12:00.
    public static let supplementsFromHour = 12

    /// True for creatine and the other supplements in the research table
    /// (`SupplementKnowledge`), matched on whole words. Anything else counts
    /// as a medication, so an unrecognised name is never held back to noon.
    public static func isSupplement(_ name: String) -> Bool {
        SupplementKnowledge.match(name) != nil
    }

    /// The first moment on `day` the dose shows.
    public static func showFrom(name: String, day: Date, calendar: Calendar = .current) -> Date {
        let hour = isSupplement(name) ? supplementsFromHour : medicationsFromHour
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start)
            ?? start.addingTimeInterval(TimeInterval(hour * 3600))
    }

    /// Whether the dose shows at `now`.
    public static func shows(name: String, day: Date, at now: Date, calendar: Calendar = .current) -> Bool {
        showFrom(name: name, day: day, calendar: calendar) <= now
    }
}
