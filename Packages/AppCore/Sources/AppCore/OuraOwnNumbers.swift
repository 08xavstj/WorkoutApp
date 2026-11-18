import Foundation

// "Oura's own numbers": Oura's proprietary scores and estimates, shown as
// Oura reports them, on the owner's explicit request (18 Nov 2026) and
// against the evidence review (docs/research/oura-ring-2026-11.md §5-6):
// none of these numbers has published validation of the number itself.
// They are display-only: no Tensile score, baseline, coach answer or
// recommendation reads them. Keep it that way.

extension Oura {
    /// Extra permissions the panel needs on top of `scopes`: `spo2` for the
    /// breathing disturbance index, and `heart_health` for cardiovascular age
    /// and Cardio Capacity (VO₂ max). That `heart_health` covers those two is
    /// an inference from the scope's description (Oura API spec 1.43;
    /// docs/research/oura-ring-2026-11.md §3.2); if Oura refuses the scope,
    /// sign-in is retried without it.
    public static let ownNumbersScopes = ["spo2", "heart_health"]

    /// The permissions to ask for: `scopes`, plus the panel's when it is on.
    public static func requestedScopes(ownNumbers: Bool, heartHealth: Bool = true) -> String {
        guard ownNumbers else { return scopes }
        let extra = ownNumbersScopes.filter { heartHealth || $0 != "heart_health" }
        return ([scopes] + extra).joined(separator: " ")
    }

    /// One day's Readiness or Sleep score (`daily_readiness`, `daily_sleep`).
    public struct DailyScore: Codable, Sendable, Equatable {
        public var day: String
        public var score: Int?
        public init(day: String, score: Int?) { self.day = day; self.score = score }
    }

    /// One day's stress summary (`daily_stress`): seconds in Oura's "high
    /// stress" and "high recovery" states, and its word for the day.
    public struct DailyStress: Codable, Sendable, Equatable {
        public var day: String
        public var stressHigh: Double?
        public var recoveryHigh: Double?
        public var daySummary: String?

        enum CodingKeys: String, CodingKey {
            case day
            case stressHigh = "stress_high"
            case recoveryHigh = "recovery_high"
            case daySummary = "day_summary"
        }

        public init(day: String, stressHigh: Double?, recoveryHigh: Double?, daySummary: String?) {
            self.day = day
            self.stressHigh = stressHigh
            self.recoveryHigh = recoveryHigh
            self.daySummary = daySummary
        }
    }

    /// One day's resilience level (`daily_resilience`): limited … exceptional.
    public struct DailyResilience: Codable, Sendable, Equatable {
        public var day: String
        public var level: String?
        public init(day: String, level: String?) { self.day = day; self.level = level }
    }

    /// Oura's predicted vascular age in years (`daily_cardiovascular_age`).
    public struct CardiovascularAge: Codable, Sendable, Equatable {
        public var day: String
        public var vascularAge: Int?

        enum CodingKeys: String, CodingKey {
            case day
            case vascularAge = "vascular_age"
        }

        public init(day: String, vascularAge: Int?) { self.day = day; self.vascularAge = vascularAge }
    }

    /// Cardio Capacity, Oura's VO₂ max estimate in ml/kg/min (`vO2_max`).
    public struct VO2Max: Codable, Sendable, Equatable {
        public var day: String
        public var vo2Max: Double?

        enum CodingKeys: String, CodingKey {
            case day
            case vo2Max = "vo2_max"
        }

        public init(day: String, vo2Max: Double?) { self.day = day; self.vo2Max = vo2Max }
    }

    /// The breathing disturbance index from `daily_spo2` (0-100).
    public struct DailySpO2: Codable, Sendable, Equatable {
        public var day: String
        public var breathingDisturbanceIndex: Double?

        enum CodingKeys: String, CodingKey {
            case day
            case breathingDisturbanceIndex = "breathing_disturbance_index"
        }

        public init(day: String, breathingDisturbanceIndex: Double?) {
            self.day = day
            self.breathingDisturbanceIndex = breathingDisturbanceIndex
        }
    }
}

/// Everything the panel shows, as downloaded.
public nonisolated struct OuraOwnNumbers: Codable, Sendable, Equatable {
    public var readiness: [Oura.DailyScore] = []
    public var sleep: [Oura.DailyScore] = []
    public var stress: [Oura.DailyStress] = []
    public var resilience: [Oura.DailyResilience] = []
    public var cardiovascularAge: [Oura.CardiovascularAge] = []
    public var vo2Max: [Oura.VO2Max] = []
    public var spo2: [Oura.DailySpO2] = []

    public init() {}

    /// Decodes a file from an older version with fewer lists.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        readiness = try c.decodeIfPresent([Oura.DailyScore].self, forKey: .readiness) ?? []
        sleep = try c.decodeIfPresent([Oura.DailyScore].self, forKey: .sleep) ?? []
        stress = try c.decodeIfPresent([Oura.DailyStress].self, forKey: .stress) ?? []
        resilience = try c.decodeIfPresent([Oura.DailyResilience].self, forKey: .resilience) ?? []
        cardiovascularAge = try c.decodeIfPresent([Oura.CardiovascularAge].self, forKey: .cardiovascularAge) ?? []
        vo2Max = try c.decodeIfPresent([Oura.VO2Max].self, forKey: .vo2Max) ?? []
        spo2 = try c.decodeIfPresent([Oura.DailySpO2].self, forKey: .spo2) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case readiness, sleep, stress, resilience, cardiovascularAge, vo2Max, spo2
    }

    public var isEmpty: Bool {
        readiness.isEmpty && sleep.isEmpty && stress.isEmpty && resilience.isEmpty
            && cardiovascularAge.isEmpty && vo2Max.isEmpty && spo2.isEmpty
    }

    /// Adds newly downloaded days: a day already held is replaced, and days
    /// before `cutoffDay` ("yyyy-MM-dd") are dropped.
    public mutating func merge(_ new: OuraOwnNumbers, cutoffDay: String) {
        func merged<T>(_ old: [T], _ fresh: [T], day: (T) -> String) -> [T] {
            var byDay: [String: T] = [:]
            for item in old + fresh { byDay[day(item)] = item }
            return byDay.values.filter { day($0) >= cutoffDay }.sorted { day($0) < day($1) }
        }
        readiness = merged(readiness, new.readiness, day: \.day)
        sleep = merged(sleep, new.sleep, day: \.day)
        stress = merged(stress, new.stress, day: \.day)
        resilience = merged(resilience, new.resilience, day: \.day)
        cardiovascularAge = merged(cardiovascularAge, new.cardiovascularAge, day: \.day)
        vo2Max = merged(vo2Max, new.vo2Max, day: \.day)
        spo2 = merged(spo2, new.spo2, day: \.day)
    }

    // MARK: The panel's rows

    /// One row: Oura's latest value, the day it is for, and the last week's
    /// values for a small trend (oldest first; nil where a day has none).
    public struct Row: Sendable, Equatable, Identifiable {
        public var id: Metric
        public var value: String
        public var day: String
        public var recent: [Double]
    }

    public enum Metric: String, Sendable, CaseIterable, Identifiable {
        case readiness, sleep, stress, resilience, cardiovascularAge, vo2Max, breathingDisturbance

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .readiness: "Readiness score"
            case .sleep: "Sleep score"
            case .stress: "Stress"
            case .resilience: "Resilience"
            case .cardiovascularAge: "Cardiovascular age"
            case .vo2Max: "Cardio Capacity (VO₂ max)"
            case .breathingDisturbance: "Breathing disturbance index"
            }
        }

        /// What the evidence review found, in one line (oura-ring-2026-11.md §5).
        public var evidence: String {
            switch self {
            case .readiness, .sleep:
                "Oura's formula; its weights aren't published and the score hasn't been validated."
            case .stress:
                "Checked only in Oura's internal studies; methods not published."
            case .resilience:
                "Built from three inputs with unpublished weights; not validated."
            case .cardiovascularAge:
                "Predicts calendar age to about 6-7 years; not compared with a clinical stiffness test or with health outcomes."
            case .vo2Max:
                "No published validation; Oura says it is less accurate than a lab test. Apple Watch's VO₂ max is the one with a published accuracy check."
            case .breathingDisturbance:
                "Compared only with Oura's own review of oxygen dips; no sleep-lab study yet. Your Watch's breathing disturbances are FDA-cleared."
            }
        }
    }

    /// The rows that have data, in `Metric` order.
    public func rows(age: Int? = nil) -> [Row] {
        var rows: [Row] = []
        func add<T>(_ metric: Metric, _ items: [T], day: (T) -> String, number: (T) -> Double?, text: (T) -> String?) {
            let known = items.filter { text($0) != nil }
            guard let latest = known.last, let shown = text(latest) else { return }
            let recent = known.suffix(7).compactMap(number)
            rows.append(Row(id: metric, value: shown, day: day(latest), recent: recent))
        }
        add(.readiness, readiness, day: \.day, number: { $0.score.map(Double.init) }, text: { $0.score.map(String.init) })
        add(.sleep, sleep, day: \.day, number: { $0.score.map(Double.init) }, text: { $0.score.map(String.init) })
        add(.stress, stress, day: \.day, number: { $0.stressHigh.map { $0 / 60 } }, text: Self.stressText)
        add(.resilience, resilience, day: \.day, number: { Self.resilienceRank($0.level) }, text: { $0.level.map(Self.capitalized) })
        add(.cardiovascularAge, cardiovascularAge, day: \.day, number: { $0.vascularAge.map(Double.init) }, text: { item in
            item.vascularAge.map { years in
                guard let age else { return "\(years) years" }
                let gap = years - age
                return gap == 0 ? "\(years) years (your age)" : "\(years) years (\(gap > 0 ? "+" : "")\(gap) vs your age)"
            }
        })
        add(.vo2Max, vo2Max, day: \.day, number: \.vo2Max, text: { $0.vo2Max.map { String(format: "%.1f ml/kg/min", $0) } })
        add(.breathingDisturbance, spo2, day: \.day, number: \.breathingDisturbanceIndex,
            text: { $0.breathingDisturbanceIndex.map { "\(Int($0.rounded()))" } })
        return rows
    }

    /// "Restored · 42 min high stress" from a day's summary.
    static func stressText(_ item: Oura.DailyStress) -> String? {
        var parts: [String] = []
        if let summary = item.daySummary, !summary.isEmpty { parts.append(capitalized(summary)) }
        if let high = item.stressHigh { parts.append("\(Int((high / 60).rounded())) min high stress") }
        if let recovery = item.recoveryHigh { parts.append("\(Int((recovery / 60).rounded())) min high recovery") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Oura's levels in order, for the trend (limited = 1 … exceptional = 5).
    static func resilienceRank(_ level: String?) -> Double? {
        guard let level else { return nil }
        let order = ["limited", "adequate", "solid", "strong", "exceptional"]
        return order.firstIndex(of: level.lowercased()).map { Double($0 + 1) }
    }

    static func capitalized(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: " ").prefix(1).uppercased() + text.replacingOccurrences(of: "_", with: " ").dropFirst()
    }
}
