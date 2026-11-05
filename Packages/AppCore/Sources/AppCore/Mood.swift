import Foundation

// MARK: - Mood (State of Mind)

/// Plain-word feelings the check-ins offer. Raw values are the names of
/// Apple's `HKStateOfMind.Label` cases (iOS 18+), so they round-trip to
/// Health without a lookup table in the app; the app maps them in
/// `HealthKitClient+Mood`. Kept to a handful so the chip row stays short.
public enum MoodFeeling: String, Codable, Sendable, CaseIterable, Identifiable {
    case calm, content, happy, grateful, stressed, anxious, drained, irritated, sad

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .calm: "Calm"
        case .content: "Content"
        case .happy: "Happy"
        case .grateful: "Grateful"
        case .stressed: "Stressed"
        case .anxious: "Anxious"
        case .drained: "Drained"
        case .irritated: "Irritated"
        case .sad: "Sad"
        }
    }

    /// Pleasant feelings read as a good sign in the mood list.
    public var isPleasant: Bool {
        switch self {
        case .calm, .content, .happy, .grateful: true
        case .stressed, .anxious, .drained, .irritated, .sad: false
        }
    }
}

/// What the mood is about. Raw values are the names of Apple's
/// `HKStateOfMind.Association` cases (community, currentEvents, dating,
/// education, family, fitness, friends, health, hobbies, identity, money,
/// partner, selfCare, spirituality, tasks, travel, weather, work). Sleep is
/// not one of Apple's associations; a short night shows up through the
/// sleep-debt factor instead. The check-ins offer the ones that fit a
/// training app plus the everyday ones; the rest can still arrive from Health.
public enum MoodAssociation: String, Codable, Sendable, CaseIterable, Identifiable {
    case work, family, friends, partner, money, health, fitness, selfCare, tasks, weather

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .work: "Work"
        case .family: "Family"
        case .friends: "Friends"
        case .partner: "Partner"
        case .money: "Money"
        case .health: "Health"
        case .fitness: "Training"
        case .selfCare: "Self-care"
        case .tasks: "To-dos"
        case .weather: "Weather"
        }
    }

    /// For the patterns engine: "a day with work on your mind".
    public var factorName: String { "a day with \(title.lowercased()) on your mind" }
}

/// The 1-5 check-in scales as State of Mind valence (−1...1).
public enum MoodScale {
    /// Mood 1 → −0.8, 3 → 0, 5 → +0.8 (app mapping; Apple's slider is
    /// continuous, so the ends are left for "very unpleasant/pleasant").
    public static func valence(mood: Int) -> Double {
        Double(max(1, min(5, mood)) - 3) * 0.4
    }

    /// Stress 1 (calm) → +0.8, 3 → 0, 5 (very high) → −0.8. Used for the
    /// evening's momentary emotion when no mood was given.
    public static func valence(stress: Int) -> Double {
        -valence(mood: stress)
    }

    /// Valence as a 0-100 number for the patterns engine, whose percent
    /// changes need positive values (`CheckInInsights`).
    public static func score(valence: Double) -> Double {
        (max(-1, min(1, valence)) + 1) * 50
    }

    /// Plain word for a valence, matching the check-in's scale labels.
    public static func word(valence: Double) -> String {
        switch valence {
        case ..<(-0.6): "Low"
        case ..<(-0.2): "Meh"
        case ..<0.2: "OK"
        case ..<0.6: "Good"
        default: "Great"
        }
    }

    /// Readable names for Apple's label and association raw names
    /// ("selfCare" → "Self-care", "currentEvents" → "Current events").
    public static func readable(_ name: String) -> String {
        if let feeling = MoodFeeling(rawValue: name) { return feeling.title }
        if let association = MoodAssociation(rawValue: name) { return association.title }
        var words = ""
        for character in name {
            if character.isUppercase { words += " " + character.lowercased() } else { words.append(character) }
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

/// One State of Mind entry, from Health (any app) or from a check-in.
public struct MoodSample: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        /// How the whole day felt.
        case daily
        /// How you felt at that moment.
        case momentary
    }

    public var date: Date
    /// −1 (very unpleasant) ... 1 (very pleasant).
    public var valence: Double
    public var kind: Kind
    /// Apple label names ("happy", "drained"); see `MoodFeeling`.
    public var labels: [String]
    /// Apple association names ("work", "fitness"); see `MoodAssociation`.
    public var associations: [String]
    /// True when this came from one of Tensile's own check-ins.
    public var fromThisApp: Bool

    public var id: String { "\(date.timeIntervalSinceReferenceDate)|\(kind.rawValue)|\(valence)" }

    public init(date: Date, valence: Double, kind: Kind, labels: [String] = [], associations: [String] = [], fromThisApp: Bool = false) {
        self.date = date
        self.valence = valence
        self.kind = kind
        self.labels = labels
        self.associations = associations
        self.fromThisApp = fromThisApp
    }
}

/// Merges moods from Health with the app's check-ins, one list per day.
public enum MoodHistory {
    /// Health's entries from other apps come first; the app's own check-ins
    /// fill days Health has nothing for. (The app also writes its check-ins
    /// to Health, so `health` must already leave out this app's samples, or
    /// pass them flagged `fromThisApp` and they're dropped here.)
    public static func merge(health: [MoodSample], checkIns: [MoodSample], calendar: Calendar = .current) -> [MoodSample] {
        let others = health.filter { !$0.fromThisApp }
        let daysCovered = Set(others.map { calendar.startOfDay(for: $0.date) })
        let filler = checkIns.filter { !daysCovered.contains(calendar.startOfDay(for: $0.date)) }
        return (others + filler).sorted { $0.date < $1.date }
    }

    /// Average valence per day: the daily mood when there is one, else the
    /// average of that day's momentary emotions. Oldest first.
    public static func dailyValence(_ samples: [MoodSample], calendar: Calendar = .current) -> [(day: Date, valence: Double)] {
        var byDay: [Date: [MoodSample]] = [:]
        for sample in samples {
            byDay[calendar.startOfDay(for: sample.date), default: []].append(sample)
        }
        return byDay.keys.sorted().compactMap { day in
            guard let entries = byDay[day], !entries.isEmpty else { return nil }
            let daily = entries.filter { $0.kind == .daily }
            let used = daily.isEmpty ? entries : daily
            return (day: day, valence: used.map(\.valence).reduce(0, +) / Double(used.count))
        }
    }

    /// Mean valence over the days in `dailyValence`, nil with no data.
    public static func averageValence(_ samples: [MoodSample], calendar: Calendar = .current) -> Double? {
        let days = dailyValence(samples, calendar: calendar)
        guard !days.isEmpty else { return nil }
        return days.map(\.valence).reduce(0, +) / Double(days.count)
    }
}
