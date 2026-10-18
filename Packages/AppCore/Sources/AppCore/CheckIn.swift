import Foundation

// MARK: - Answers

/// Morning check-in. Every answer is optional.
public struct MorningCheckIn: Codable, Sendable, Equatable {
    public enum Symptom: String, Codable, Sendable, CaseIterable {
        case soreThroat = "Sore throat"
        case congestion = "Congestion"
        case fever = "Fever or chills"
        case bodyAches = "Body aches"
    }

    public enum BodyArea: String, Codable, Sendable, CaseIterable {
        case legs = "Legs"
        case glutes = "Glutes"
        case back = "Back"
        case chest = "Chest"
        case shoulders = "Shoulders"
        case arms = "Arms"
        case core = "Core"

        var isLower: Bool { self == .legs || self == .glutes }
    }

    public enum Cycle: String, Codable, Sendable, CaseIterable {
        case period = "On my period"
        case notPeriod = "Not on my period"
        case notTracking = "Don't track"
    }

    /// Start of the morning's day.
    public var day: Date
    public var rested: Int?
    public var soreness: Int?
    public var soreAreas: [BodyArea] = []
    public var mood: Int?
    public var symptoms: [Symptom] = []
    /// 0, 1 or 2 (= 2 or more).
    public var nightWakings: Int?
    public var cycle: Cycle?
    /// Filled in by the app, not asked: a hard workout ended within an hour of falling asleep.
    public var lateHardWorkout: Bool?

    public init(day: Date) {
        self.day = day
    }

    public var isSick: Bool { !symptoms.isEmpty }
}

/// Evening check-in. Every answer is optional.
public struct EveningCheckIn: Codable, Sendable, Equatable {
    public var day: Date
    public var caffeineMg: Double?
    /// Minutes after midnight.
    public var lastCaffeineMinutes: Int?
    public var drinks: Int?
    public var lastDrinkMinutes: Int?
    public var stress: Int?
    public var lastMealMinutes: Int?
    public var nicotine: Bool?
    public var sauna: Bool?
    public var coldPlunge: Bool?

    public init(day: Date) {
        self.day = day
    }

    /// Common sources, mg (USDA FoodData Central / product labels).
    public static let caffeinePresets: [(name: String, mg: Double)] = [
        ("Coffee (8 oz)", 95), ("Espresso shot", 63), ("Energy drink", 120),
        ("Pre-workout", 200), ("Black tea", 47), ("Cola (12 oz)", 34),
    ]
}

// MARK: - Coaching from this morning's answers

public enum CheckInCoaching {
    /// A workout focus that avoids sore muscles, or nil if no change is needed.
    public static func focus(for morning: MorningCheckIn) -> WorkoutFocus? {
        guard (morning.soreness ?? 0) >= 5, !morning.soreAreas.isEmpty else { return nil }
        let lowerSore = morning.soreAreas.contains { $0.isLower }
        let upperSore = morning.soreAreas.contains { !$0.isLower && $0 != .core }
        switch (lowerSore, upperSore) {
        case (true, false): return .upper
        case (false, true): return .lower
        default: return nil
        }
    }

    /// One line of advice from this morning's answers, most important first.
    public static func advice(for morning: MorningCheckIn) -> String? {
        if morning.symptoms.contains(.fever) || morning.symptoms.contains(.bodyAches) {
            return "Fever or body aches: rest today. Training hard while sick slows recovery."
        }
        if morning.isSick {
            return "Feeling unwell: keep any training light and short."
        }
        if let focus = focus(for: morning) {
            let areas = morning.soreAreas.map(\.rawValue).joined(separator: ", ").lowercased()
            return "Sore \(areas): a \(focus.title.lowercased()) session works the fresh muscles."
        }
        if (morning.soreness ?? 0) >= 7 {
            return "Very sore all over: go lighter or do easy cardio."
        }
        if let rested = morning.rested, rested <= 2 {
            return "You don't feel rested: keep effort moderate even if recovery looks fine."
        }
        return nil
    }
}

// MARK: - What affects you

/// One morning with the check-ins that lead into it and what the watch measured.
public struct CheckInDay: Sendable, Equatable {
    public var morning: Date
    /// The evening before this morning.
    public var evening: EveningCheckIn?
    public var checkIn: MorningCheckIn?
    public var hrv: Double?
    public var restingHeartRate: Double?
    public var sleepScore: Double?

    public init(morning: Date, evening: EveningCheckIn?, checkIn: MorningCheckIn?, hrv: Double?, restingHeartRate: Double?, sleepScore: Double?) {
        self.morning = morning
        self.evening = evening
        self.checkIn = checkIn
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
        self.sleepScore = sleepScore
    }
}

public enum CheckInInsights {
    public enum Outcome: String, Sendable, CaseIterable {
        case hrv = "HRV"
        case restingHeartRate = "Resting heart rate"
        case sleepScore = "Sleep score"

        /// Higher is better for HRV and sleep, lower for resting heart rate.
        var higherIsBetter: Bool { self != .restingHeartRate }

        func value(_ day: CheckInDay) -> Double? {
            switch self {
            case .hrv: day.hrv
            case .restingHeartRate: day.restingHeartRate
            case .sleepScore: day.sleepScore
            }
        }
    }

    /// A yes/no condition about the evening before (or the morning itself).
    public struct Factor: Sendable {
        public var id: String
        public var name: String
        var test: @Sendable (CheckInDay) -> Bool?

        public init(id: String, name: String, test: @escaping @Sendable (CheckInDay) -> Bool?) {
            self.id = id
            self.name = name
            self.test = test
        }
    }

    public struct Insight: Sendable, Equatable, Identifiable {
        public var factor: String
        public var outcome: Outcome
        /// Percent difference on days with the factor vs without.
        public var percentChange: Double
        public var daysWith: Int
        public var daysWithout: Int
        public var isGood: Bool
        public var id: String { factor + outcome.rawValue }

        public var sentence: String {
            let direction = percentChange >= 0 ? "higher" : "lower"
            return "\(outcome.rawValue) is \(Int(abs(percentChange).rounded()))% \(direction) after \(factor.lowercased())"
        }
    }

    public static let factors: [Factor] = [
        Factor(id: "drinks2", name: "2+ drinks") { $0.evening?.drinks.map { $0 >= 2 } },
        Factor(id: "anyAlcohol", name: "Any alcohol") { $0.evening?.drinks.map { $0 >= 1 } },
        Factor(id: "caffeine300", name: "300 mg+ caffeine") { $0.evening?.caffeineMg.map { $0 >= 300 } },
        Factor(id: "lateCaffeine", name: "Caffeine after 2 pm") { day in
            guard let evening = day.evening else { return nil }
            if (evening.caffeineMg ?? 0) == 0 { return false }
            return evening.lastCaffeineMinutes.map { $0 >= 14 * 60 }
        },
        Factor(id: "lateMeal", name: "Eating after 9 pm") { $0.evening?.lastMealMinutes.map { $0 >= 21 * 60 } },
        Factor(id: "stress", name: "A stressful day (4-5)") { $0.evening?.stress.map { $0 >= 4 } },
        Factor(id: "nicotine", name: "Nicotine") { $0.evening?.nicotine },
        Factor(id: "sauna", name: "Sauna") { $0.evening?.sauna },
        Factor(id: "cold", name: "Cold plunge") { $0.evening?.coldPlunge },
        Factor(id: "lateWorkout", name: "A hard workout within an hour of bed") { $0.checkIn?.lateHardWorkout },
        Factor(id: "sick", name: "Feeling sick") { $0.checkIn.map(\.isSick) },
    ]

    /// Factors whose days differ by at least `minimumPercent`, with at least
    /// `minimumDays` days on each side. Biggest effects first.
    public static func analyze(_ days: [CheckInDay], minimumDays: Int = 3, minimumPercent: Double = 5) -> [Insight] {
        var insights: [Insight] = []
        for factor in factors {
            for outcome in Outcome.allCases {
                var with: [Double] = []
                var without: [Double] = []
                for day in days {
                    guard let present = factor.test(day), let value = outcome.value(day) else { continue }
                    if present { with.append(value) } else { without.append(value) }
                }
                guard with.count >= minimumDays, without.count >= minimumDays else { continue }
                let meanWith = with.reduce(0, +) / Double(with.count)
                let meanWithout = without.reduce(0, +) / Double(without.count)
                guard meanWithout > 0 else { continue }
                let change = (meanWith / meanWithout - 1) * 100
                guard abs(change) >= minimumPercent else { continue }
                insights.append(Insight(
                    factor: factor.name, outcome: outcome, percentChange: change,
                    daysWith: with.count, daysWithout: without.count,
                    isGood: (change > 0) == outcome.higherIsBetter
                ))
            }
        }
        return insights.sorted { abs($0.percentChange) > abs($1.percentChange) }
    }

    /// Days of check-ins still needed before patterns are shown.
    public static func daysUntilReady(_ days: [CheckInDay], target: Int = 14) -> Int {
        max(0, target - days.filter { $0.evening != nil || $0.checkIn != nil }.count)
    }
}
