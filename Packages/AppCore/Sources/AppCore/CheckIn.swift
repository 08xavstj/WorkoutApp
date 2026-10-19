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
    /// Litres of water logged the day before this morning.
    public var waterLiters: Double?
    /// When you fell asleep that night, minutes after the evening's midnight
    /// (over 1440 after midnight, e.g. 1500 = 1:00 am). Nil if unknown.
    public var bedtimeMinutes: Int?

    public init(morning: Date, evening: EveningCheckIn?, checkIn: MorningCheckIn?, hrv: Double?, restingHeartRate: Double?, sleepScore: Double?,
                waterLiters: Double? = nil, bedtimeMinutes: Int? = nil) {
        self.morning = morning
        self.evening = evening
        self.checkIn = checkIn
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
        self.sleepScore = sleepScore
        self.waterLiters = waterLiters
        self.bedtimeMinutes = bedtimeMinutes
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
        // Gardiner et al., Sleep Med Rev 2023: a coffee within ~8.8 h of bed costs sleep.
        Factor(id: "lateCaffeine", name: "Caffeine within 9 h of bed") { day in
            guard let evening = day.evening else { return nil }
            let mg = evening.caffeineMg ?? 0
            if mg == 0 { return false }
            let bedtime = day.bedtimeMinutes ?? CaffeineTiming.defaultBedtimeMinutes
            return evening.lastCaffeineMinutes.map { CaffeineTiming.isTooLate(minutes: $0, mg: mg, bedtimeMinutes: bedtime) }
        },
        Factor(id: "lateMeal", name: "Eating after 9 pm") { $0.evening?.lastMealMinutes.map { $0 >= 21 * 60 } },
        Factor(id: "stress", name: "A stressful day (4-5)") { $0.evening?.stress.map { $0 >= 4 } },
        Factor(id: "nicotine", name: "Nicotine") { $0.evening?.nicotine },
        Factor(id: "sauna", name: "Sauna") { $0.evening?.sauna },
        Factor(id: "cold", name: "Cold plunge") { $0.evening?.coldPlunge },
        Factor(id: "lateWorkout", name: "A hard workout within an hour of bed") { $0.checkIn?.lateHardWorkout },
        Factor(id: "sick", name: "Feeling sick") { $0.checkIn.map(\.isSick) },
        Factor(id: "lowWater", name: "Under 2 L of water") { $0.waterLiters.map { $0 < 2 } },
    ]

    /// Factors that really seem to change an outcome for you.
    ///
    /// A pattern is shown only when:
    /// - there are at least `minimumDays` days with and without the factor;
    /// - the difference is bigger than your normal day-to-day swing (half a
    ///   standard deviation, the "smallest worthwhile change" used for HRV
    ///   monitoring; Plews et al., Sports Med 2013);
    /// - a Welch t-test says it's unlikely to be chance, after correcting for
    ///   testing many factor/outcome pairs at once (Benjamini-Hochberg false
    ///   discovery rate, `falseDiscoveryRate`).
    /// Alcohol's effect on overnight HRV is well documented and usually shows
    /// up (Pietilä et al., JMIR Ment Health 2018).
    public static func analyze(_ days: [CheckInDay], minimumDays: Int = 7, falseDiscoveryRate: Double = 0.1) -> [Insight] {
        struct Candidate {
            var insight: Insight
            var p: Double
        }
        var candidates: [Candidate] = []
        var testsRun = 0
        for factor in factors {
            for outcome in Outcome.allCases {
                var with: [Double] = []
                var without: [Double] = []
                for day in days {
                    guard let present = factor.test(day), let value = outcome.value(day) else { continue }
                    if present { with.append(value) } else { without.append(value) }
                }
                guard with.count >= minimumDays, without.count >= minimumDays else { continue }
                testsRun += 1
                let (meanWith, varWith) = meanVariance(with)
                let (meanWithout, varWithout) = meanVariance(without)
                guard meanWithout > 0 else { continue }
                let pooledVariance: Double = (varWith + varWithout) / 2
                let pooledSD = sqrt(pooledVariance)
                let difference = meanWith - meanWithout
                // Bigger than a normal day-to-day swing.
                guard abs(difference) >= 0.5 * pooledSD, abs(difference) > 0 else { continue }
                let p = welchPValue(meanA: meanWith, varA: varWith, nA: with.count,
                                    meanB: meanWithout, varB: varWithout, nB: without.count)
                let change = (meanWith / meanWithout - 1) * 100
                candidates.append(Candidate(insight: Insight(
                    factor: factor.name, outcome: outcome, percentChange: change,
                    daysWith: with.count, daysWithout: without.count,
                    isGood: (change > 0) == outcome.higherIsBetter
                ), p: p))
            }
        }
        // Benjamini-Hochberg: keep the k smallest p-values where p(k) <= k/m * q.
        let m = Double(max(testsRun, 1))
        let sorted = candidates.sorted { $0.p < $1.p }
        var keep = 0
        for (index, candidate) in sorted.enumerated() where candidate.p <= Double(index + 1) / m * falseDiscoveryRate {
            keep = index + 1
        }
        return sorted.prefix(keep).map(\.insight).sorted { abs($0.percentChange) > abs($1.percentChange) }
    }

    static func meanVariance(_ values: [Double]) -> (Double, Double) {
        let mean = values.reduce(0, +) / Double(values.count)
        guard values.count > 1 else { return (mean, 0) }
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count - 1)
        return (mean, variance)
    }

    /// Two-sided p-value of Welch's t-test.
    static func welchPValue(meanA: Double, varA: Double, nA: Int, meanB: Double, varB: Double, nB: Int) -> Double {
        let a = varA / Double(nA)
        let b = varB / Double(nB)
        let se = sqrt(a + b)
        guard se > 0 else { return meanA == meanB ? 1 : 0 }
        let t = abs(meanA - meanB) / se
        let partA: Double = (a * a) / Double(nA - 1)
        let partB: Double = (b * b) / Double(nB - 1)
        let dfDenominator: Double = partA + partB
        let sum: Double = a + b
        let df: Double = dfDenominator > 0 ? sum * sum / dfDenominator : Double(nA + nB - 2)
        // P(|T| > t) = I_x(df/2, 1/2) with x = df / (df + t²).
        return regularizedIncompleteBeta(x: df / (df + t * t), a: df / 2, b: 0.5)
    }

    /// I_x(a, b) via its continued fraction (modified Lentz method).
    static func regularizedIncompleteBeta(x: Double, a: Double, b: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        // Use the symmetry I_x(a,b) = 1 - I_{1-x}(b,a) where the fraction converges faster.
        if x > (a + 1) / (a + b + 2) {
            return 1 - regularizedIncompleteBeta(x: 1 - x, a: b, b: a)
        }
        let logGammas: Double = lgamma(a + b) - lgamma(a) - lgamma(b)
        let logPowers: Double = a * log(x) + b * log(1 - x)
        let logFront = logGammas + logPowers
        let front = exp(logFront) / a
        let tiny = 1e-300
        var f = 1.0, c = 1.0, d = 0.0
        for i in 0...300 {
            let m = Double(i / 2)
            let numerator: Double
            if i == 0 {
                numerator = 1
            } else if i % 2 == 0 {
                let top: Double = m * (b - m) * x
                let bottom: Double = (a + 2 * m - 1) * (a + 2 * m)
                numerator = top / bottom
            } else {
                let top: Double = (a + m) * (a + b + m) * x
                let bottom: Double = (a + 2 * m) * (a + 2 * m + 1)
                numerator = -top / bottom
            }
            d = 1 + numerator * d
            if abs(d) < tiny { d = tiny }
            d = 1 / d
            c = 1 + numerator / c
            if abs(c) < tiny { c = tiny }
            let step = c * d
            f *= step
            if abs(1 - step) < 1e-10 { break }
        }
        return min(1, max(0, front * (f - 1)))
    }

    /// Days of check-ins still needed before patterns are shown.
    public static func daysUntilReady(_ days: [CheckInDay], target: Int = 14) -> Int {
        max(0, target - days.filter { $0.evening != nil || $0.checkIn != nil }.count)
    }
}
