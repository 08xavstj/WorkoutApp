import Foundation

/// The words of the workout reminder: a playful line written from the day's
/// own data, or a plain one. Pure rules, so they can be tested: which lines
/// fit today (`situations`), which one to send (`pick`), which line each
/// pending reminder holds (`reconcile`), and what may never be said
/// (`WorkoutBanterGuard`). The lines are in `WorkoutBanterLibrary`. The app
/// (`WorkoutVoice`, `Reminders.scheduleWorkoutReminders`) supplies the facts.
/// Research and the reasons for each choice: docs/research/funny-nudges-2026-11.md.
///
/// What rests on evidence, and what doesn't:
/// - **Rotation.** A reminder template a person has seen recently works less
///   well, and the effect recovers as the memory fades: Yancey & Settles, "A
///   Sleeping, Recovering Bandit Algorithm for Optimizing Recurring
///   Notifications", KDD 2020 (full text read). They model it as a recency
///   penalty that halves every 15 days (a guess they did not fit), and always
///   re-sending the last template cut lesson completions by 0.5% (relative).
///   The effect is real but small. This app has one user and no way to learn
///   which line "works", so it keeps only the part that needs no learning: a
///   line never repeats until its whole group has been used, and never within
///   `recentWindow` reminders when anything else fits (app choice, anchored to
///   their "few weeks to a month").
/// - **Eligibility.** Their templates carry rules about who may get them
///   ("must have a 3+ day streak"); here every line knows which facts it needs
///   and which situation it fits, and is left out when a fact is missing.
/// - **Humour.** Weak evidence. Humour has a small positive effect on
///   persuasion overall (r = .13 over 89 studies, mostly attitudes, not
///   behaviour: Walter et al., Hum Commun Res 2018; abstract read), and no
///   trial has tested funny exercise reminders. The playful voice is the
///   owner's preference, offered with a Plain alternative; it is not presented
///   as science.
/// - **No guilt, no shame, no body talk.** Guilt appeals did nothing in the
///   two health studies of a 26-study meta-analysis (g = −0.01; Peng et al.,
///   Front Psychol 2023, full text read); controlling language raises
///   reactance (Rains, Hum Commun Res 2013; Ma et al. 2026, abstracts only);
///   guilt and body-image motives predict worse long-term exercise adherence
///   than autonomous ones (Teixeira et al., IJBNPA 2012; Ntoumanis et al.,
///   Health Psychol Rev 2021, as cited in docs/research/behaviour-change.md).
///   So the jokes are about the barbell and the app, never the person.
/// - **Safety states are plain.** Low recovery, flagged illness, logged pain,
///   rest mode and rest days get plain, kind wording and no push to train
///   (`Caution`); the app's own rules decide those states. So does a run of
///   low-mood mornings (`Caution.keepPlain`, `MoodCare`): the session stands,
///   the jokes stop, and the line never says why.
public enum WorkoutBanter {
    // MARK: Limits (app choices)

    /// The title says what and when ("Upper A at 18:00"); the same limit as the
    /// coach's messages (`CoachCheckIns.maxTitleCharacters`).
    public static let maxTitleCharacters = 40
    /// A banner shows about four lines of body before iOS cuts it; Apple
    /// publishes no number. 160 characters stays inside that at the default
    /// text size and leaves room for the if-then line shown as the subtitle.
    public static let maxBodyCharacters = 160
    public static let minBodyCharacters = 20
    /// Reminders a line stays out for after it was used, when anything else
    /// fits. Yancey & Settles expected the novelty loss to "mostly decay within
    /// the span of a few weeks to a month" and used a 15-day half-life; 60
    /// reminders is four of those half-lives even with a reminder every day,
    /// and about 15 weeks at four sessions a week.
    public static let recentWindow = 60

    public enum Tone: String, Codable, Sendable, CaseIterable, Identifiable {
        case playful, plain

        public var id: String { rawValue }
        public var label: String { self == .playful ? "Playful" : "Plain" }
    }

    /// The comic register of a line; never the same one two reminders running.
    public enum Register: String, Codable, Sendable, CaseIterable {
        case deadpan, absurd, mockHeroic, selfAware, gymBro, understatement, bureaucratic, natureDoc
        /// Not a joke: the Plain tone and every `Caution` line.
        case plain
    }

    /// What a line is about. A day usually fits several.
    public enum Situation: String, Codable, Sendable, CaseIterable {
        case planned, shortOption, nearRecord, stuckLift, comeback, longBreak, weekStart, weekProgress, lastOfWeek
        case weeksInARow, neglectedMuscle, afterRecord, afterVolume, deload, highRecovery
        case morning, evening, monday, friday, weekend
        /// The reminder after one went unanswered: it says reminders go quiet after it.
        case lastCall
        // Plain and kind only (`Caution`).
        case lowRecovery, illness, pain, restMode, restDay
        /// Plain wording while mood is low (`Facts.keepPlain`); the session still stands.
        case keepPlain

        /// How much of the day's own data the situation carries (app choice):
        /// lines for a specific situation are preferred over general ones.
        var weight: Double {
            switch self {
            case .nearRecord, .stuckLift, .afterRecord, .afterVolume, .comeback, .neglectedMuscle, .weeksInARow, .lastOfWeek: 3
            case .weekProgress, .weekStart, .deload, .highRecovery, .longBreak: 2
            case .morning, .evening, .monday, .friday, .weekend, .shortOption: 1
            default: 0
            }
        }
    }

    public enum RecoveryBand: String, Codable, Sendable { case low, normal, high }

    /// A state in which the reminder is plain and kind and never pushes to
    /// train. Most serious first.
    public enum Caution: String, Codable, Sendable, CaseIterable {
        case restMode, illness, pain, lowRecovery, restDay
        /// A run of low-mood mornings (`MoodCare.keepPlain`): no jokes, and the
        /// line never names the reason (it shows on the Lock Screen).
        case keepPlain

        var situation: Situation {
            switch self {
            case .restMode: .restMode
            case .illness: .illness
            case .pain: .pain
            case .lowRecovery: .lowRecovery
            case .restDay: .restDay
            case .keepPlain: .keepPlain
            }
        }
    }

    // MARK: Facts

    /// A lift worth a line: its last top set, the next step, and whether it
    /// has sat at one weight (`WorkoutBanterFacts.lift`).
    public struct Lift: Codable, Sendable, Equatable {
        public var name: String
        public var lastWeightKg: Double
        public var lastReps: Int
        /// The next weight up that the gym can load, when known.
        public var nextWeightKg: Double?
        /// Whole weeks the top weight has stayed the same with no more reps; nil when it is moving.
        public var weeksAtWeight: Int?
        /// The last top set is within reach of the lift's best (estimated 1RM).
        public var nearBest: Bool

        public init(name: String, lastWeightKg: Double, lastReps: Int, nextWeightKg: Double? = nil,
                    weeksAtWeight: Int? = nil, nearBest: Bool = false) {
            self.name = name
            self.lastWeightKg = lastWeightKg
            self.lastReps = lastReps
            self.nextWeightKg = nextWeightKg
            self.weeksAtWeight = weeksAtWeight
            self.nearBest = nearBest
        }
    }

    public struct Neglected: Codable, Sendable, Equatable {
        /// Lower case, as it reads mid-sentence: "hamstrings", "upper back".
        public var muscle: String
        public var days: Int

        public init(muscle: String, days: Int) {
            self.muscle = muscle
            self.days = days
        }
    }

    /// What stood out in the last session.
    public struct Standout: Codable, Sendable, Equatable {
        /// The lift that set a record, when one did.
        public var recordLift: String?
        /// The session's total weight × reps, when it was the most in the recent sessions.
        public var volumeKg: Double?
        public var daysAgo: Int

        public init(recordLift: String? = nil, volumeKg: Double? = nil, daysAgo: Int) {
            self.recordLift = recordLift
            self.volumeKg = volumeKg
            self.daysAgo = daysAgo
        }
    }

    /// What the app knows about the day a reminder is for. Everything is
    /// optional: a line that needs a missing fact is simply not used.
    public struct Facts: Codable, Sendable, Equatable {
        /// "Upper A", "Legs".
        public var sessionName: String?
        public var sessionMinutes: Int?
        public var shortMinutes: Int?
        /// Minutes before the session that the reminder arrives.
        public var leadMinutes: Int?
        /// Nothing is planned for the day.
        public var isRestDay = false
        public var daysSinceLastSession: Int?
        public var sessionsDone: Int?
        public var sessionsPlanned: Int?
        /// Weeks in a row the plan was kept (`Consistency.weekKept`). Only ever
        /// shown while it stands; a broken run is never mentioned
        /// (Silverman & Barasch, J Consum Res 2023, via behaviour-change.md).
        public var weeksInARow: Int?
        public var lift: Lift?
        public var neglected: Neglected?
        public var standout: Standout?
        public var recovery: RecoveryBand?
        public var isDeloadWeek = false
        public var illnessFlagged = false
        /// The area pain is logged for ("lower back"), or "" when only the fact is known.
        public var painArea: String?
        public var restMode = false
        /// 0–23, the hour the session starts.
        public var hour: Int?
        /// `Calendar` weekday of the session: 1 = Sunday … 7 = Saturday.
        public var weekday: Int?
        public var unit: LoadUnit = .kg
        /// The last reminder went unanswered: this one says reminders go quiet after it.
        public var lastCall = false
        /// Keep the wording plain and kind: three or more low-mood mornings in
        /// the last week (`MoodCare.keepPlain`). Humour
        /// that misses on a low day is a risk with no evidence of benefit
        /// (Walter et al. 2018 above), so the app's choice is to stop joking.
        public var keepPlain = false

        public init() {}

        /// The safety state that makes the reminder plain, most serious first.
        public var caution: Caution? {
            if restMode { return .restMode }
            if illnessFlagged { return .illness }
            if painArea != nil { return .pain }
            if recovery == .low { return .lowRecovery }
            if isRestDay { return .restDay }
            if keepPlain { return .keepPlain }
            return nil
        }

        /// Sessions still to do this week, when both counts are known.
        public var sessionsLeft: Int? {
            guard let sessionsDone, let sessionsPlanned else { return nil }
            return max(0, sessionsPlanned - sessionsDone)
        }
    }

    // MARK: Thresholds (app choices)

    /// Days off before a line may mention them. Shorter gaps are ordinary rest
    /// between sessions.
    public static let comebackFromDays = 4
    /// From here the number is left out: after a long break the count reads
    /// as a reproach however it is worded, and little fitness is lost in two
    /// to three weeks anyway (Mujika & Padilla, Sports Med 2000, via behaviour-change.md).
    public static let longBreakFromDays = 15
    /// A muscle group is worth a line after a week without a set, and not
    /// after `neglectedMaxDays` (by then it reads as a reproach).
    public static let neglectedFromDays = 7
    public static let neglectedMaxDays = 45
    /// A record or a big session is news for a week.
    public static let standoutMaxDays = 7
    public static let stuckFromWeeks = 2

    /// The situations a day fits, for choosing lines. A caution state or the
    /// last call stands alone.
    public static func situations(for facts: Facts) -> Set<Situation> {
        // Keeping plain still lets the last call say that reminders go quiet (in plain words).
        if let caution = facts.caution, !(caution == .keepPlain && facts.lastCall) { return [caution.situation] }
        if facts.lastCall { return [.lastCall] }
        var result: Set<Situation> = [.planned]
        if facts.shortMinutes != nil { result.insert(.shortOption) }
        if let lift = facts.lift, !facts.isDeloadWeek {
            // A deload week is for lighter loads: no line asks for a record then.
            if let weeks = lift.weeksAtWeight, weeks >= stuckFromWeeks {
                result.insert(.stuckLift)
            } else if lift.nearBest, lift.nextWeightKg != nil {
                result.insert(.nearRecord)
            }
        }
        if let days = facts.daysSinceLastSession {
            if days >= longBreakFromDays {
                result.insert(.longBreak)
            } else if days >= comebackFromDays {
                result.insert(.comeback)
            }
        }
        if let done = facts.sessionsDone, let planned = facts.sessionsPlanned, planned >= 2, done < planned {
            if done == 0 {
                result.insert(.weekStart)
            } else if planned - done == 1 {
                result.insert(.lastOfWeek)
            } else {
                result.insert(.weekProgress)
            }
        }
        if let weeks = facts.weeksInARow, weeks >= 2 { result.insert(.weeksInARow) }
        if let neglected = facts.neglected, (neglectedFromDays...neglectedMaxDays).contains(neglected.days) {
            result.insert(.neglectedMuscle)
        }
        if let standout = facts.standout, standout.daysAgo <= standoutMaxDays {
            if standout.recordLift != nil {
                result.insert(.afterRecord)
            } else if standout.volumeKg != nil {
                result.insert(.afterVolume)
            }
        }
        if facts.isDeloadWeek { result.insert(.deload) }
        if facts.recovery == .high, !facts.isDeloadWeek { result.insert(.highRecovery) }
        if let hour = facts.hour {
            if hour < 10 { result.insert(.morning) }
            if hour >= 18 { result.insert(.evening) }
        }
        switch facts.weekday {
        case 2: result.insert(.monday)
        case 6: result.insert(.friday)
        case 1, 7: result.insert(.weekend)
        default: break
        }
        return result
    }

    // MARK: Slots

    /// A place in a line that a fact fills: "{session} in {lead} minutes."
    public enum Slot: String, CaseIterable, Sendable {
        case session, minutes, short, lead, days, done, planned, left, weeks
        /// The lift's name in lower case, and as logged.
        case lift, Lift
        /// "82.5 kg × 5", "82.5 kg", "5", "85 kg".
        case last, lastWeight, lastReps, next
        case stuckWeeks, muscle, muscleDays, standoutLift, volume, weekday, pain
    }

    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// The text a slot shows, or nil when the fact is missing.
    public static func value(of slot: Slot, in facts: Facts) -> String? {
        switch slot {
        case .session: return clean(facts.sessionName)
        case .minutes: return facts.sessionMinutes.flatMap { $0 > 1 ? String($0) : nil }
        case .short: return facts.shortMinutes.flatMap { $0 > 1 ? String($0) : nil }
        case .lead: return facts.leadMinutes.flatMap { $0 > 1 ? String($0) : nil }
        case .days: return facts.daysSinceLastSession.flatMap { $0 > 1 ? String($0) : nil }
        case .done: return facts.sessionsDone.map(String.init)
        case .planned: return facts.sessionsPlanned.flatMap { $0 > 1 ? String($0) : nil }
        case .left: return facts.sessionsLeft.flatMap { $0 > 1 ? String($0) : nil }
        case .weeks: return facts.weeksInARow.flatMap { $0 > 1 ? String($0) : nil }
        case .lift: return clean(facts.lift?.name)?.lowercased()
        case .Lift: return clean(facts.lift?.name)
        case .last:
            guard let lift = facts.lift, lift.lastReps > 0, lift.lastWeightKg > 0 else { return nil }
            return "\(weightText(lift.lastWeightKg, unit: facts.unit)) × \(lift.lastReps)"
        case .lastWeight:
            guard let lift = facts.lift, lift.lastWeightKg > 0 else { return nil }
            return weightText(lift.lastWeightKg, unit: facts.unit)
        case .lastReps: return facts.lift.flatMap { $0.lastReps > 1 ? String($0.lastReps) : nil }
        case .next:
            guard let lift = facts.lift, let next = lift.nextWeightKg, next > lift.lastWeightKg else { return nil }
            return weightText(next, unit: facts.unit)
        case .stuckWeeks: return facts.lift?.weeksAtWeight.flatMap { $0 > 1 ? String($0) : nil }
        case .muscle: return clean(facts.neglected?.muscle)?.lowercased()
        case .muscleDays: return facts.neglected.flatMap { $0.days > 1 ? String($0.days) : nil }
        case .standoutLift: return clean(facts.standout?.recordLift)?.lowercased()
        case .volume:
            guard let kg = facts.standout?.volumeKg, kg > 0 else { return nil }
            return "\(grouped(Int(facts.unit.fromKilograms(kg).rounded()))) \(facts.unit.rawValue)"
        case .weekday:
            guard let weekday = facts.weekday, (1...7).contains(weekday) else { return nil }
            return weekdayNames[weekday - 1]
        case .pain: return clean(facts.painArea)?.lowercased()
        }
    }

    /// Trimmed, on one line, without braces; nil when empty.
    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// "82.5 kg", "185 lb": the owner's unit, at most one decimal.
    public static func weightText(_ kilograms: Double, unit: LoadUnit) -> String {
        "\(decimal(unit.fromKilograms(kilograms))) \(unit.rawValue)"
    }

    /// One decimal at most, none when it is zero: 82.5, 100.
    static func decimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        return tenths % 10 == 0 ? String(tenths / 10) : "\(tenths / 10).\(abs(tenths % 10))"
    }

    /// 6240 → "6,240".
    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return value < 0 ? "-" + result : result
    }

    // MARK: Lines

    public struct Line: Sendable, Equatable, Identifiable {
        /// Stable, so the history survives edits to the library: "pl07".
        public let id: String
        public let situation: Situation
        public let register: Register
        /// The words, with `{slot}` places.
        public let template: String
        public let slots: [Slot]

        public init(_ id: String, _ situation: Situation, _ register: Register, _ template: String) {
            self.id = id
            self.situation = situation
            self.register = register
            self.template = template
            self.slots = WorkoutBanter.slotNames(in: template).compactMap(Slot.init(rawValue:))
        }

        /// The line with every slot filled, or nil when a fact is missing.
        public func render(_ facts: Facts) -> String? {
            var text = template
            for slot in slots {
                guard let value = WorkoutBanter.value(of: slot, in: facts) else { return nil }
                text = text.replacingOccurrences(of: "{\(slot.rawValue)}", with: value)
            }
            return text.contains("{") || text.contains("}") ? nil : text
        }

        /// How much it prefers to be picked: more of the day's data, more weight.
        var weight: Double { 1 + Double(Set(slots).count) + 2 * situation.weight }
    }

    /// Every `{name}` in a template, in order, known or not.
    public static func slotNames(in template: String) -> [String] {
        template.matches(of: /\{([A-Za-z]+)\}/).map { String($0.output.1) }
    }

    /// The first two words, lower case, with slots as "{}": two lines that
    /// open the same way aren't sent on consecutive days.
    public static func opening(of text: String) -> String {
        let normalised = text.replacing(/\{[A-Za-z]+\}/, with: "{}").lowercased()
        return normalised.split(whereSeparator: { $0 == " " }).prefix(2)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;!?…")) }
            .joined(separator: " ")
    }

    static let motifs = ["barbell", "dumbbell", "kettlebell", "plates", "rack", "bench", "chalk", "playlist", "chart",
                         "notification", "app", "bro", "committee", "prophecy", "hero"]

    /// The thing a joke leans on (the barbell, the plates, the app…), so the
    /// same prop doesn't carry two reminders running.
    public static func motif(of text: String) -> String? {
        let words = Set(CoachIntent.words(text))
        return motifs.first { words.contains($0) || words.contains($0 + "s") }
    }

    // MARK: History

    public struct History: Codable, Sendable, Equatable {
        public struct Entry: Codable, Sendable, Equatable {
            public var dayKey: String
            /// A library line's id, or "gen|…" for a line the on-device model wrote.
            public var lineID: String
            public var situation: String
            public var register: String
            public var opening: String
            public var motif: String?
            public var text: String

            public init(dayKey: String, lineID: String, situation: String, register: String, opening: String,
                        motif: String?, text: String) {
                self.dayKey = dayKey
                self.lineID = lineID
                self.situation = situation
                self.register = register
                self.opening = opening
                self.motif = motif
                self.text = text
            }

            public var isGenerated: Bool { lineID.hasPrefix(WorkoutBanter.generatedPrefix) }
        }

        /// Reminders that went out, oldest first.
        public var entries: [Entry] = []
        /// Per situation, the lines used since its group was last used up.
        public var cycles: [String: [String]] = [:]

        /// Entries kept: more than a year of daily reminders (app choice).
        public static let kept = 400

        public init() {}

        public mutating func record(_ entry: Entry) {
            entries.append(entry)
            if entries.count > Self.kept { entries.removeFirst(entries.count - Self.kept) }
            guard !entry.isGenerated else { return }
            var cycle = cycles[entry.situation] ?? []
            // Used again: its group was used up, so a new round starts with it.
            if cycle.contains(entry.lineID) { cycle = [] }
            cycle.append(entry.lineID)
            cycles[entry.situation] = cycle
        }

        /// The texts of the newest reminders, newest last.
        public func recentTexts(_ count: Int) -> [String] { entries.suffix(count).map(\.text) }
    }

    static let generatedPrefix = "gen|"

    // MARK: Picking

    public struct Pick: Codable, Sendable, Equatable {
        public var lineID: String
        public var situation: String
        public var register: String
        public var text: String

        public init(lineID: String, situation: String, register: String, text: String) {
            self.lineID = lineID
            self.situation = situation
            self.register = register
            self.text = text
        }

        func entry(dayKey: String) -> History.Entry {
            History.Entry(dayKey: dayKey, lineID: lineID, situation: situation, register: register,
                          opening: WorkoutBanter.opening(of: text), motif: WorkoutBanter.motif(of: text), text: text)
        }
    }

    /// The line sent when nothing in the library fits (it always does; this
    /// is the floor): the words the reminder had before it had a voice.
    public static let fallbackText = "Your planned session is coming up. The short version counts too."

    /// The lines that could be sent for these facts in this tone, rendered.
    public static func eligible(facts: Facts, tone: Tone, library: [Line] = WorkoutBanterLibrary.all) -> [(line: Line, text: String)] {
        let fitting = situations(for: facts)
        // Caution lines are plain whatever the tone.
        let plainOnly = tone == .plain || facts.caution != nil
        return library.compactMap { line in
            guard fitting.contains(line.situation), (line.register == .plain) == plainOnly,
                  let text = line.render(facts), (minBodyCharacters...maxBodyCharacters).contains(text.count) else { return nil }
            return (line, text)
        }
    }

    /// The line for a day. The same facts, history and seed always give the
    /// same line.
    ///
    /// In order: only lines whose facts are present; within a situation no
    /// line again until all of its eligible lines have been used; nothing
    /// used in the last `recentWindow` reminders; never the line or the words
    /// just sent; then, while anything is left, not the last register, not
    /// the last opening, not the last prop, not the last situation. Among
    /// what remains, lines that use more of the day's data are likelier.
    public static func pick(facts: Facts, tone: Tone, history: History, seed: UInt64,
                            library: [Line] = WorkoutBanterLibrary.all) -> Pick {
        let all = eligible(facts: facts, tone: tone, library: library)
        guard !all.isEmpty else {
            return Pick(lineID: "fallback", situation: Situation.planned.rawValue, register: Register.plain.rawValue, text: fallbackText)
        }
        // Per situation: what this round hasn't used; a used-up group starts again.
        var pool: [(line: Line, text: String)] = []
        for (_, group) in Dictionary(grouping: all, by: { $0.line.situation }) {
            let used = Set(history.cycles[group[0].line.situation.rawValue] ?? [])
            let unused = group.filter { !used.contains($0.line.id) }
            pool += unused.isEmpty ? group : unused
        }
        pool.sort { $0.line.id < $1.line.id }

        func narrow(_ keep: ((line: Line, text: String)) -> Bool) {
            let kept = pool.filter(keep)
            if !kept.isEmpty { pool = kept }
        }
        let recentIDs = Set(history.entries.suffix(recentWindow).map(\.lineID))
        let recentTexts = Set(history.entries.suffix(recentWindow).map(\.text))
        narrow { !recentIDs.contains($0.line.id) && !recentTexts.contains($0.text) }
        if let last = history.entries.last {
            narrow { $0.line.id != last.lineID && $0.text != last.text }
            narrow { $0.line.register.rawValue != last.register }
            narrow { opening(of: $0.text) != last.opening }
            if let motif = last.motif { narrow { WorkoutBanter.motif(of: $0.text) != motif } }
            narrow { $0.line.situation.rawValue != last.situation }
        }

        var generator = SplitMix64(seed: seed)
        let total = pool.reduce(0) { $0 + $1.line.weight }
        var roll = generator.unit() * total
        var chosen = pool[pool.count - 1]
        for candidate in pool {
            roll -= candidate.line.weight
            if roll < 0 {
                chosen = candidate
                break
            }
        }
        return Pick(lineID: chosen.line.id, situation: chosen.line.situation.rawValue,
                    register: chosen.line.register.rawValue, text: chosen.text)
    }

    /// A seed from a day key ("2027-01-11"), the same on every launch
    /// (`Hashable` is not: Swift seeds it per process).
    public static func seed(for key: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// A small fixed random number generator (SplitMix64), so picks can be replayed.
    struct SplitMix64 {
        var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state = state &+ 0x9e37_79b9_7f4a_7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
            z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
            return z ^ (z >> 31)
        }

        /// In 0..<1.
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }

    // MARK: Pending reminders

    /// The line a pending reminder holds.
    public struct Assigned: Codable, Sendable, Equatable {
        public var dayKey: String
        public var fire: Date
        public var pick: Pick
        public var tone: Tone
        /// Written before its own day, from what was known then; rewritten
        /// once on the day, when the day's own data is in.
        public var ahead: Bool
        /// The facts the on-device model was last asked about (`promptSignature`), so it is asked once.
        public var modelAsked: String?

        public init(dayKey: String, fire: Date, pick: Pick, tone: Tone, ahead: Bool, modelAsked: String? = nil) {
            self.dayKey = dayKey
            self.fire = fire
            self.pick = pick
            self.tone = tone
            self.ahead = ahead
            self.modelAsked = modelAsked
        }

        public var isGenerated: Bool { pick.lineID.hasPrefix(WorkoutBanter.generatedPrefix) }
    }

    /// What is saved: the reminders that went out and the lines the pending ones hold.
    public struct Store: Codable, Sendable, Equatable {
        public var history = History()
        public var pending: [Assigned] = []

        public init() {}
    }

    /// A reminder about to be scheduled.
    public struct DayRequest: Sendable, Equatable {
        public var dayKey: String
        public var fire: Date
        public var facts: Facts
        /// The reminder is for today, so `facts` holds the day's own data.
        public var isToday: Bool

        public init(dayKey: String, fire: Date, facts: Facts, isToday: Bool) {
            self.dayKey = dayKey
            self.fire = fire
            self.facts = facts
            self.isToday = isToday
        }
    }

    /// Gives every reminder being scheduled its line, changing as little as
    /// possible, and returns what to save.
    ///
    /// - A pending reminder whose time has passed went out: it joins the history.
    /// - A pending reminder that is no longer wanted (trained already, plan
    ///   changed, switched off) never went out: its line is forgotten, not used up.
    /// - A reminder that already holds a line keeps it while the line is still
    ///   true: same tone, still fits the day, same words when filled in again.
    ///   One written ahead is rewritten once on its own day.
    /// - A new line is picked as if the earlier pending reminders had already
    ///   gone out, so the week ahead doesn't repeat itself.
    public static func reconcile(_ store: Store, requests: [DayRequest], tone: Tone, now: Date,
                                 library: [Line] = WorkoutBanterLibrary.all) -> Store {
        var result = Store()
        result.history = store.history
        let delivered = store.pending.filter { $0.fire <= now }.sorted { $0.fire < $1.fire }
        for assigned in delivered where !result.history.entries.contains(where: { $0.dayKey == assigned.dayKey }) {
            result.history.record(assigned.pick.entry(dayKey: assigned.dayKey))
        }
        var ahead = result.history
        for request in requests.sorted(by: { $0.fire < $1.fire }) where request.fire > now {
            let existing = store.pending.first { $0.dayKey == request.dayKey && $0.fire > now }
            var assigned: Assigned
            if let existing, stillTrue(existing, facts: request.facts, tone: tone, library: library),
               !(existing.ahead && request.isToday) {
                assigned = existing
                assigned.fire = request.fire
            } else {
                let chosen = pick(facts: request.facts, tone: tone, history: ahead, seed: seed(for: request.dayKey), library: library)
                assigned = Assigned(dayKey: request.dayKey, fire: request.fire, pick: chosen, tone: tone, ahead: !request.isToday)
            }
            ahead.record(assigned.pick.entry(dayKey: request.dayKey))
            result.pending.append(assigned)
        }
        return result
    }

    /// Whether a pending line can stay: same tone, its situation still fits,
    /// and it reads the same with today's facts (a model's line: the facts it
    /// was written from are unchanged and it still passes every check).
    static func stillTrue(_ assigned: Assigned, facts: Facts, tone: Tone, library: [Line]) -> Bool {
        guard assigned.tone == tone else { return false }
        if assigned.isGenerated {
            return tone == .playful && facts.caution == nil && !facts.lastCall
                && assigned.modelAsked == WorkoutBanterPrompt.signature(facts)
                && WorkoutBanterGuard.problems(in: assigned.pick.text, facts: facts).isEmpty
        }
        guard let line = library.first(where: { $0.id == assigned.pick.lineID }) else { return false }
        return eligible(facts: facts, tone: tone, library: [line]).first?.text == assigned.pick.text
    }

    // MARK: On-device variation

    /// Share of playful reminders the on-device model may write, when it is
    /// there and switched on (app choice): the hand-written lines are the ones
    /// that were read and tested, so they stay at least half of what is seen.
    public static let generatedEvery = 2

    /// Whether to ask the on-device model for this reminder's line: playful, no
    /// caution state, not the last call, not asked yet for these facts, and
    /// this day's turn (`generatedEvery`).
    public static func wantsGenerated(_ assigned: Assigned, facts: Facts) -> Bool {
        guard assigned.tone == .playful, facts.caution == nil, !facts.lastCall, !assigned.isGenerated,
              assigned.modelAsked != WorkoutBanterPrompt.signature(facts) else { return false }
        return seed(for: assigned.dayKey) % UInt64(generatedEvery) == 0
    }

    /// Notes that the model was asked for `dayKey`'s reminder and, when its
    /// line passed every check (`WorkoutBanterGuard.acceptGenerated`), puts
    /// that line in. The library line it replaces was never sent, so it isn't used up.
    public static func applyGenerated(_ store: Store, dayKey: String, facts: Facts, accepted: String?) -> Store {
        var result = store
        guard let index = result.pending.firstIndex(where: { $0.dayKey == dayKey }) else { return store }
        result.pending[index].modelAsked = WorkoutBanterPrompt.signature(facts)
        guard let accepted else { return result }
        let old = result.pending[index].pick
        result.pending[index].pick = Pick(lineID: generatedPrefix + dayKey, situation: old.situation,
                                          register: "generated", text: accepted)
        return result
    }
}
