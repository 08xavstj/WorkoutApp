import Foundation

/// When a dose joins the Lock Screen doses card and the Today screen's
/// "Up next" list. The dose's own reminder still fires at the time set on it.
///
/// The hours are the user's preference, not research: a card that showed
/// from midnight sat on the Lock Screen all night, and creatine kept it there
/// all day. Creatine timing makes little difference (Kreider et al., J Int Soc
/// Sports Nutr 2017;14:18, position stand), so showing it later costs nothing.
public enum DoseCard {
    /// Medications show from 06:00 (app's choice, the owner's request).
    public static let medicationsFromHour = 6
    /// Creatine and other supplements show from 12:00 (app's choice, the owner's request).
    public static let supplementsFromHour = 12
    /// A dose joins the card this long before its own time, never earlier
    /// (and never before the floor hours above). App's choice, not research:
    /// an evening dose on the card from 06:00 made the card sit there all day.
    public static let leadMinutes = 120

    /// Ingredient words that make a name a medicine even when a supplement
    /// word is in it too ("Acetaminophen/Caffeine", "Aspirin + caffeine"):
    /// common pain-relief combinations that `MedicationKnowledge` has no class
    /// for. App's choice, a short list so a real medicine is never held to noon.
    static let medicineWords: Set<String> = [
        "acetaminophen", "paracetamol", "aspirin", "butalbital", "ergotamine", "codeine", "orphenadrine",
        "excedrin", "fioricet", "cafergot",
    ]

    /// Every word of every supplement name and alias ("creatine", "fish", "oil"…).
    private static let supplementWords: Set<String> = Set(
        SupplementKnowledge.entries.flatMap(\.names).flatMap { $0.split(separator: " ").map(String.init) }
    )

    /// True for creatine and the other supplements in the research table
    /// (`SupplementKnowledge`), matched on whole words. Anything else counts
    /// as a medication, so an unrecognised name is never held back to noon;
    /// so does a name with a real drug in it as well ("Sertraline, magnesium",
    /// "Acetaminophen/Caffeine"), whatever supplement word it also carries.
    public static func isSupplement(_ name: String) -> Bool {
        guard SupplementKnowledge.match(name) != nil else { return false }
        let words = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if words.contains(where: medicineWords.contains) { return false }
        // A drug `MedicationKnowledge` knows in the rest of the name. The supplement
        // words are left out first: creatine and melatonin are in both tables, and
        // "Testosterone booster" is the herbal product, not the hormone.
        let rest = words.filter { !supplementWords.contains($0) }.joined(separator: " ")
        return MedicationKnowledge.match(rest) == nil
    }

    /// The first moment on `day` a dose of this kind may show (06:00 or noon),
    /// whatever its own time.
    public static func showFrom(name: String, day: Date, calendar: Calendar = .current) -> Date {
        let hour = isSupplement(name) ? supplementsFromHour : medicationsFromHour
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start)
            ?? start.addingTimeInterval(TimeInterval(hour * 3600))
    }

    /// The first moment on `day` the dose due at `minutes` after midnight
    /// shows: `leadMinutes` before its time, but never before the floor hour
    /// for its kind (`showFrom(name:day:calendar:)`).
    public static func showFrom(name: String, day: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        let floor = showFrom(name: name, day: day, calendar: calendar)
        let start = calendar.startOfDay(for: day)
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        // By hour and minute, so it's right on the days clocks change.
        let doseTime = calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: start)
            ?? start.addingTimeInterval(TimeInterval(clamped * 60))
        return max(floor, doseTime.addingTimeInterval(-TimeInterval(leadMinutes * 60)))
    }

    /// What the app last did with a day's Lock Screen card, kept so a card
    /// the user swiped away isn't put straight back.
    public struct CardLog: Codable, Sendable, Equatable {
        /// The card's day ("2026-11-16").
        public var day: String
        /// Ids of the untaken doses the card has shown.
        public var offered: [String]
        /// The app ended it itself (everything on it was taken, or it was switched off).
        public var endedByApp: Bool

        public init(day: String, offered: [String], endedByApp: Bool = false) {
            self.day = day
            self.offered = offered
            self.endedByApp = endedByApp
        }
    }

    /// Whether a new card may start when none is showing. Not when today's
    /// card went without the app ending it (the user swiped it away, or iOS
    /// took it down after its hours) and every dose still to take was already
    /// on it: only a dose that has joined since brings the card back.
    public static func mayStart(remaining: [String], dayKey: String, last: CardLog?) -> Bool {
        guard !remaining.isEmpty else { return false }
        guard let last, last.day == dayKey, !last.endedByApp else { return true }
        return !Set(remaining).isSubset(of: last.offered)
    }

    /// Whether a dose of this kind may show at `now` (the floor hours only).
    public static func shows(name: String, day: Date, at now: Date, calendar: Calendar = .current) -> Bool {
        showFrom(name: name, day: day, calendar: calendar) <= now
    }

    /// Whether the dose due at `minutes` after midnight shows at `now`.
    public static func shows(name: String, day: Date, minutes: Int, at now: Date, calendar: Calendar = .current) -> Bool {
        showFrom(name: name, day: day, minutes: minutes, calendar: calendar) <= now
    }
}
