import Foundation
import AppCore

/// PHQ-9 and GAD-7 results (`MoodQuestionnaires`) and when they were last
/// offered. The results stay on the iPhone in a small JSON file (and, if the
/// person allows it, in Apple Health's scored assessments); nothing is sent
/// anywhere. "Don't offer these" in Settings switches the offer off for good.
@Observable
final class MoodScreenStore {
    static let shared = MoodScreenStore()

    /// Every completed questionnaire, oldest first.
    private(set) var results: [MoodQuestionnaires.Result] = []
    /// Settings › Check-ins › "Mood questionnaires" off: never offered.
    private(set) var turnedOff: Bool
    @ObservationIgnored private var canSave = false
    @ObservationIgnored private let file = SafeJSONFile.appSupport("mood-screens.json")

    static let turnedOffKey = "moodScreens.turnedOff"
    private static let lastOfferedKey = "moodScreens.lastOffered"
    private static let dismissedKey = "moodScreens.dismissed"

    private init() {
        turnedOff = UserDefaults.standard.bool(forKey: Self.turnedOffKey)
        reload()
    }

    func reloadIfUnavailable() {
        if !canSave { reload() }
    }

    /// Newest first.
    var history: [MoodQuestionnaires.Result] { results.sorted { $0.date > $1.date } }

    /// Whether to show the offer today (`MoodQuestionnaires.offerDue`).
    func offerDue(lowMood: LowMoodRule.Finding?, now: Date = .now) -> Bool {
        let defaults = UserDefaults.standard
        // "Not now" hides it for the rest of the day; the 4 weeks run from the offer.
        if let dismissed = defaults.object(forKey: Self.dismissedKey) as? Date, Calendar.current.isDate(dismissed, inSameDayAs: now) { return false }
        let lastOffered = defaults.object(forKey: Self.lastOfferedKey) as? Date
        return MoodQuestionnaires.offerDue(lowMood: lowMood, lastOffered: lastOffered, lastTaken: results.map(\.date).max(),
                                           turnedOff: turnedOff, now: now)
    }

    /// The offer was on screen: it stays up for the rest of today, then waits 4 weeks.
    func noteOffered(now: Date = .now) {
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: Self.lastOfferedKey) as? Date, Calendar.current.isDate(last, inSameDayAs: now) { return }
        defaults.set(now, forKey: Self.lastOfferedKey)
    }

    /// "Not now": gone today, and not back for 4 weeks.
    func dismissOffer(now: Date = .now) {
        noteOffered(now: now)
        UserDefaults.standard.set(now, forKey: Self.dismissedKey)
    }

    func setTurnedOff(_ off: Bool) {
        turnedOff = off
        UserDefaults.standard.set(off, forKey: Self.turnedOffKey)
    }

    func add(_ new: [MoodQuestionnaires.Result]) {
        reloadIfUnavailable()
        results.append(contentsOf: new.filter(\.isComplete))
        save()
    }

    func delete(_ result: MoodQuestionnaires.Result) {
        reloadIfUnavailable()
        results.removeAll { $0.id == result.id }
        save()
    }

    private func reload() {
        // Demo mode starts empty and saves nothing, so the screenshot tour is the same each run.
        if DemoMode.isOn {
            canSave = false
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = file.loadLogged([MoodQuestionnaires.Result].self, decoder: decoder)
        canSave = loaded.state.canSave
        if canSave { results = loaded.value ?? [] }
    }

    private func save() {
        guard !DemoMode.isOn else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        file.saveLogged(results, canSave: canSave, encoder: encoder)
    }
}
