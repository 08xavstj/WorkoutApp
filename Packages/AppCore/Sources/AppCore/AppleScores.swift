import Foundation

/// Apple's own numbers that the app keeps beside its own: the Readiness score
/// from the Apple Watch Series 12 / Ultra 4, the Sleep score (watchOS 26 and
/// later) and the Health app's Health Age (iOS 27.3).
///
/// Apple gives apps no way to read any of them (checked 17 Nov 2026; see
/// docs/research/apple-scores-2026-11.md), so the owner brings them in: from a
/// screenshot, by typing, or from a Shortcut. Apple hasn't published how any
/// of the three is calculated beyond a list of inputs, so the app only stores
/// and compares them. It never mixes them into its own scores.
public enum AppleScoreKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case readiness
    case sleepScore
    case healthAge

    public var id: String { rawValue }

    /// Apple's name for the number.
    public var title: String {
        switch self {
        case .readiness: "Readiness"
        case .sleepScore: "Sleep score"
        case .healthAge: "Health Age"
        }
    }

    /// The values the number can take.
    ///
    /// - Readiness: 0–10 in whole numbers. Apple's bands are whole-number
    ///   ranges (0–1, 2–4, 5–7, 8–10), so no half steps (Apple Support 128112,
    ///   "Understand your readiness score on Apple Watch").
    /// - Sleep score: 0–100 (Apple Watch User Guide, "Track your sleep").
    /// - Health Age: Apple publishes no limits; 10–120 is the app's range for
    ///   catching typos, the same one the first hand-typed version used.
    public var range: ClosedRange<Int> {
        switch self {
        case .readiness: 0...10
        case .sleepScore: 0...100
        case .healthAge: 10...120
        }
    }

    /// Readiness and the Sleep score belong to one day; Health Age moves
    /// slowly, so its latest value stands until it is replaced.
    public var isDaily: Bool { self != .healthAge }

    /// The app's own number that sits beside it.
    public var appTitle: String {
        switch self {
        case .readiness: "Recovery"
        case .sleepScore: "Sleep score"
        case .healthAge: "Body age"
        }
    }

    /// Whether the two numbers are on the same scale, so a plain difference
    /// means something (Readiness is 0–10 against a 1–99 recovery score).
    public var sharesScaleWithApp: Bool { self != .readiness }

    public func accepts(_ value: Int) -> Bool { range.contains(value) }

    /// Apple's word for a value, when Apple has published the bands.
    public func levelLabel(for value: Int) -> String? {
        switch self {
        case .readiness: AppleReadinessLevel(score: value)?.label
        case .sleepScore: AppleSleepScoreLevel(score: value)?.label
        case .healthAge: nil
        }
    }
}

/// Apple's four Readiness recommendations and their score ranges
/// (Apple Support 128112, read 17 Nov 2026).
public enum AppleReadinessLevel: String, Sendable, CaseIterable {
    case recover
    case paceYourself
    case ready
    case goForIt

    public var label: String {
        switch self {
        case .recover: "Recover"
        case .paceYourself: "Pace Yourself"
        case .ready: "Ready"
        case .goForIt: "Go For It"
        }
    }

    public var range: ClosedRange<Int> {
        switch self {
        case .recover: 0...1
        case .paceYourself: 2...4
        case .ready: 5...7
        case .goForIt: 8...10
        }
    }

    public init?(score: Int) {
        guard let level = Self.allCases.first(where: { $0.range.contains(score) }) else { return nil }
        self = level
    }
}

/// Apple's five Sleep score levels (Apple Watch User Guide, "Track your sleep
/// with Apple Watch", read 17 Nov 2026; the bands changed once, in watchOS 26.2).
public enum AppleSleepScoreLevel: String, Sendable, CaseIterable {
    case veryLow
    case low
    case ok
    case high
    case veryHigh

    public var label: String {
        switch self {
        case .veryLow: "Very Low"
        case .low: "Low"
        case .ok: "OK"
        case .high: "High"
        case .veryHigh: "Very High"
        }
    }

    public var range: ClosedRange<Int> {
        switch self {
        case .veryLow: 0...40
        case .low: 41...60
        case .ok: 61...80
        case .high: 81...95
        case .veryHigh: 96...100
        }
    }

    public init?(score: Int) {
        guard let level = Self.allCases.first(where: { $0.range.contains(score) }) else { return nil }
        self = level
    }
}

/// Apple's numbers by day, with the app's own number for the same day kept
/// beside each, so the two can be compared later without recomputing old days.
///
/// Days are keyed "2026-11-17" in the owner's calendar. One reading per kind
/// per day: Readiness changes through the day, and the last one entered wins.
public struct AppleScoreLog: Codable, Sendable, Equatable {
    /// How a reading got in.
    public enum Source: String, Codable, Sendable {
        case typed
        case screenshot
        case shortcut
        /// The Health Age typed into the first version of the card.
        case migrated
    }

    public struct Reading: Codable, Sendable, Equatable {
        public var value: Int
        public var recordedAt: Date
        public var source: Source

        public init(value: Int, recordedAt: Date, source: Source) {
            self.value = value
            self.recordedAt = recordedAt
            self.source = source
        }
    }

    public struct Day: Codable, Sendable, Equatable {
        public var readiness: Reading?
        public var sleepScore: Reading?
        public var healthAge: Reading?
        /// The app's own numbers for the same day (recovery 1–99, sleep score
        /// 0–100, body age in years), saved when they were known.
        public var appRecovery: Int?
        public var appSleepScore: Int?
        public var appBodyAge: Int?

        public init() {}

        public subscript(kind: AppleScoreKind) -> Reading? {
            get {
                switch kind {
                case .readiness: readiness
                case .sleepScore: sleepScore
                case .healthAge: healthAge
                }
            }
            set {
                switch kind {
                case .readiness: readiness = newValue
                case .sleepScore: sleepScore = newValue
                case .healthAge: healthAge = newValue
                }
            }
        }

        public func appValue(_ kind: AppleScoreKind) -> Int? {
            switch kind {
            case .readiness: appRecovery
            case .sleepScore: appSleepScore
            case .healthAge: appBodyAge
            }
        }

        mutating func setAppValue(_ kind: AppleScoreKind, _ value: Int?) {
            switch kind {
            case .readiness: appRecovery = value
            case .sleepScore: appSleepScore = value
            case .healthAge: appBodyAge = value
            }
        }

        /// No Apple reading left on this day.
        public var isEmpty: Bool { readiness == nil && sleepScore == nil && healthAge == nil }
    }

    /// One row of history: Apple's reading and the app's number, if known.
    public struct Entry: Sendable, Equatable, Identifiable {
        public var day: String
        public var reading: Reading
        public var appValue: Int?
        public var id: String { day }
    }

    /// Days kept (a little over two years; the file stays a few kilobytes).
    public static let keptDays = 800

    public private(set) var days: [String: Day]

    public init(days: [String: Day] = [:]) {
        self.days = days
    }

    // MARK: Day keys

    /// "2026-11-17" for the calendar day `date` falls on.
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return key(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    static func key(year: Int, month: Int, day: Int) -> String {
        func padded(_ value: Int, _ width: Int) -> String {
            let text = String(max(0, value))
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return padded(year, 4) + "-" + padded(month, 2) + "-" + padded(day, 2)
    }

    static func parts(of key: String) -> (year: Int, month: Int, day: Int)? {
        let pieces = key.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3, (1...12).contains(pieces[1]), (1...31).contains(pieces[2]) else { return nil }
        return (pieces[0], pieces[1], pieces[2])
    }

    /// Noon on the key's day, for showing the date.
    public static func date(forKey key: String, calendar: Calendar = .current) -> Date? {
        guard let parts = parts(of: key) else { return nil }
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12))
    }

    /// Days since 1 Jan 1970 for a key, so gaps between entries can be
    /// counted without a calendar (civil-date arithmetic, proleptic Gregorian).
    public static func ordinal(forKey key: String) -> Int? {
        guard let parts = parts(of: key) else { return nil }
        let year = parts.month <= 2 ? parts.year - 1 : parts.year
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400
        let shiftedMonth = (parts.month + 9) % 12
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + parts.day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    // MARK: Changing

    /// Saves a reading; false (and nothing saved) when the value is outside
    /// the kind's range.
    @discardableResult
    public mutating func record(_ kind: AppleScoreKind, value: Int, day: String, at recordedAt: Date, source: Source) -> Bool {
        guard kind.accepts(value), Self.parts(of: day) != nil else { return false }
        var entry = days[day] ?? Day()
        entry[kind] = Reading(value: value, recordedAt: recordedAt, source: source)
        days[day] = entry
        trim()
        return true
    }

    public mutating func remove(_ kind: AppleScoreKind, day: String) {
        guard var entry = days[day] else { return }
        entry[kind] = nil
        entry.setAppValue(kind, nil)
        days[day] = entry.isEmpty ? nil : entry
    }

    /// Keeps the app's own number beside Apple's for `day`. Only on a day that
    /// has that Apple reading; true when something changed.
    @discardableResult
    public mutating func setAppValue(_ kind: AppleScoreKind, _ value: Int?, day: String) -> Bool {
        guard var entry = days[day], entry[kind] != nil, entry.appValue(kind) != value else { return false }
        entry.setAppValue(kind, value)
        days[day] = entry
        return true
    }

    private mutating func trim() {
        guard days.count > Self.keptDays else { return }
        for old in days.keys.sorted().prefix(days.count - Self.keptDays) { days[old] = nil }
    }

    // MARK: Reading

    public func reading(_ kind: AppleScoreKind, day: String) -> Reading? {
        days[day]?[kind]
    }

    /// Every day with this kind, oldest first.
    public func entries(_ kind: AppleScoreKind) -> [Entry] {
        days.keys.sorted().compactMap { day in
            guard let entry = days[day], let reading = entry[kind] else { return nil }
            return Entry(day: day, reading: reading, appValue: entry.appValue(kind))
        }
    }

    public func latest(_ kind: AppleScoreKind) -> Entry? {
        entries(kind).last
    }

    /// The days that have both numbers, oldest first, for `ScoreAgreement`.
    public func pairs(_ kind: AppleScoreKind) -> [ScoreAgreement.Pair] {
        entries(kind).compactMap { entry in
            guard let app = entry.appValue, let ordinal = Self.ordinal(forKey: entry.day) else { return nil }
            return ScoreAgreement.Pair(day: ordinal, apple: Double(entry.reading.value), app: Double(app))
        }
    }

    public var isEmpty: Bool { days.isEmpty }

    // MARK: Coach

    /// One line for the on-device coach: the latest of each number with its
    /// day, or nil when there is none. Worded so that it survives
    /// `CoachPromptVocabulary` (which renames the app's recovery score to
    /// "Readiness score"): every value says "Apple's" and gives its scale.
    public func coachLine(today: String) -> String? {
        var parts: [String] = []
        for kind in AppleScoreKind.allCases {
            guard let entry = latest(kind) else { continue }
            let when = Self.relativeDay(entry.day, today: today)
            switch kind {
            case .readiness:
                let level = kind.levelLabel(for: entry.reading.value).map { " (\"\($0)\")" } ?? ""
                parts.append("Apple's Readiness \(entry.reading.value) out of 10\(level), \(when)")
            case .sleepScore:
                parts.append("Apple's Sleep score \(entry.reading.value) out of 100, \(when)")
            case .healthAge:
                parts.append("Apple's Health Age \(entry.reading.value) years, \(when)")
            }
        }
        guard !parts.isEmpty else { return nil }
        return "Apple Watch's own numbers, entered by the user (Apple works them out differently from this log's scores, so they needn't match and neither is the more correct one): "
            + parts.joined(separator: "; ") + "."
    }

    /// "today", "yesterday", "3 days ago" or "on 2026-11-02".
    static func relativeDay(_ day: String, today: String) -> String {
        guard let then = ordinal(forKey: day), let now = ordinal(forKey: today) else { return "on \(day)" }
        switch now - then {
        case 0: return "today"
        case 1: return "yesterday"
        case 2...13: return "\(now - then) days ago"
        default: return "on \(day)"
        }
    }
}
