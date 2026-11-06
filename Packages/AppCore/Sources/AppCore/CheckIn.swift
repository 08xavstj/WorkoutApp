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
    /// Optional words for the mood, as `MoodFeeling` raw values (Apple label names).
    public var feelings: [String]?
    /// Optional "what's affecting it", as `MoodAssociation` raw values (Apple association names).
    public var associations: [String]?
    /// "Something hurts?": area, 0-10 and worse after training (`PainGuard`).
    /// Optional so check-ins saved before it existed still decode.
    public var pains: [PainReport]?

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
    /// Drinks logged one by one (type, amount, strength). When present,
    /// `drinks` and `lastDrinkMinutes` are worked out from these.
    public var alcohol: [AlcoholEntry]?
    /// How the evening feels, 1-5 (optional; `stress` stands in for it when missing).
    public var mood: Int?
    /// Optional words for the mood, as `MoodFeeling` raw values (Apple label names).
    public var feelings: [String]?
    /// Optional "what's affecting it", as `MoodAssociation` raw values (Apple association names).
    public var associations: [String]?

    public init(day: Date) {
        self.day = day
    }

    /// Valence for the evening's State of Mind entry: the mood when given,
    /// else the stress scale turned around (`MoodScale.valence(stress:)`).
    public var eveningValence: Double? {
        if let mood { return MoodScale.valence(mood: mood) }
        if let stress { return MoodScale.valence(stress: stress) }
        return nil
    }

    /// Standard drinks from the itemised log, or nil if nothing was itemised.
    public var standardDrinks: Double? {
        guard let alcohol, !alcohol.isEmpty else { return nil }
        return alcohol.reduce(0) { $0 + $1.standardDrinks }
    }

    /// Keeps the simple drink count and last-drink time in step with the
    /// itemised log, so the rest of the app (recovery, illness watch,
    /// patterns, coach) keeps working off `drinks`.
    public mutating func syncDrinksFromAlcohol() {
        guard let alcohol else { return }
        if alcohol.isEmpty {
            drinks = 0
            lastDrinkMinutes = nil
            self.alcohol = nil
            return
        }
        let total = alcohol.reduce(0) { $0 + $1.standardDrinks }
        // Any drink counts as at least one, so a small glass isn't recorded as none.
        drinks = max(1, Int(total.rounded()))
        lastDrinkMinutes = alcohol.compactMap(\.minutes).max()
    }

    /// Common sources, mg (USDA FoodData Central / product labels).
    public static let caffeinePresets: [(name: String, mg: Double)] = [
        ("Coffee (8 oz)", 95), ("Espresso shot", 63), ("Energy drink", 120),
        ("Pre-workout", 200), ("Black tea", 47), ("Cola (12 oz)", 34),
    ]
}

// MARK: - Alcohol

/// One drink: what it was, how much, and how strong.
///
/// A US standard drink is 14 g of pure alcohol (NIAAA), e.g. 12 oz of 5% beer,
/// 5 oz of 12% wine or 1.5 oz of 40% spirits. Grams = millilitres × ABV ×
/// 0.789 g/mL (the density of ethanol).
public struct AlcoholEntry: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case beer, lightBeer, strongBeer, wine, sparkling, spirits, cocktail, cider, seltzer, sake

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .beer: "Beer"
            case .lightBeer: "Light beer"
            case .strongBeer: "IPA / strong beer"
            case .wine: "Wine"
            case .sparkling: "Champagne / prosecco"
            case .spirits: "Spirits (shot)"
            case .cocktail: "Cocktail / mixed drink"
            case .cider: "Cider"
            case .seltzer: "Hard seltzer"
            case .sake: "Sake"
            }
        }

        /// Typical strength, % alcohol by volume.
        public var typicalABV: Double {
            switch self {
            case .beer: 5
            case .lightBeer: 4.2
            case .strongBeer: 7
            case .wine: 12
            case .sparkling: 12
            case .spirits: 40
            case .cocktail: 13
            case .cider: 5
            case .seltzer: 5
            case .sake: 15
            }
        }

        /// Common serving sizes, in millilitres.
        public var servings: [(name: String, millilitres: Double)] {
            switch self {
            case .beer, .lightBeer, .strongBeer, .cider:
                [("Can or bottle (12 oz)", 355), ("Pint (16 oz)", 473), ("Imperial pint", 568), ("Tallboy (24 oz)", 710)]
            case .wine:
                [("Glass (5 oz)", 148), ("Large glass (8 oz)", 237), ("Bottle", 750)]
            case .sparkling:
                [("Flute (5 oz)", 148), ("Bottle", 750)]
            case .spirits:
                [("Shot (1.5 oz)", 44), ("Double (3 oz)", 89)]
            case .cocktail:
                [("Cocktail (6 oz)", 180), ("Large (10 oz)", 300)]
            case .seltzer:
                [("Can (12 oz)", 355), ("Tall can (19 oz)", 562)]
            case .sake:
                [("Glass (6 oz)", 180), ("Small carafe (10 oz)", 300)]
            }
        }
    }

    public static let gramsPerStandardDrink = 14.0
    static let ethanolDensity = 0.789

    public var id: UUID
    public var kind: Kind
    public var millilitres: Double
    /// % alcohol by volume.
    public var abv: Double
    /// When it was finished, minutes after midnight (can be over 24 h for after midnight).
    public var minutes: Int?

    public init(id: UUID = UUID(), kind: Kind, millilitres: Double, abv: Double? = nil, minutes: Int? = nil) {
        self.id = id
        self.kind = kind
        self.millilitres = millilitres
        self.abv = abv ?? kind.typicalABV
        self.minutes = minutes
    }

    public var gramsOfAlcohol: Double {
        max(0, millilitres) * max(0, abv) / 100 * Self.ethanolDensity
    }

    public var standardDrinks: Double {
        gramsOfAlcohol / Self.gramsPerStandardDrink
    }
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
    /// This morning's mood valence (−1...1), from Health's daily mood or the
    /// check-in's 1-5 mood (`MoodScale`). The outcome the day before acts on.
    public var moodValence: Double?
    /// Did the day before have a workout (any app, 10 min or more)?
    public var trainedYesterday: Bool?
    /// The day before's strain (0-100) and what your training days usually reach.
    public var strainYesterday: Double?
    public var usualTrainingStrain: Double?
    /// Hours of sleep debt over the 14 nights up to and including this night (`SleepDebt`).
    public var sleepDebtHours: Double?
    /// Mindful minutes logged the day before (Mindfulness app, breathing, Calm...).
    public var mindfulMinutes: Double?

    public init(morning: Date, evening: EveningCheckIn?, checkIn: MorningCheckIn?, hrv: Double?, restingHeartRate: Double?, sleepScore: Double?,
                waterLiters: Double? = nil, bedtimeMinutes: Int? = nil,
                moodValence: Double? = nil, trainedYesterday: Bool? = nil, strainYesterday: Double? = nil,
                usualTrainingStrain: Double? = nil, sleepDebtHours: Double? = nil, mindfulMinutes: Double? = nil) {
        self.morning = morning
        self.evening = evening
        self.checkIn = checkIn
        self.hrv = hrv
        self.restingHeartRate = restingHeartRate
        self.sleepScore = sleepScore
        self.waterLiters = waterLiters
        self.bedtimeMinutes = bedtimeMinutes
        self.moodValence = moodValence
        self.trainedYesterday = trainedYesterday
        self.strainYesterday = strainYesterday
        self.usualTrainingStrain = usualTrainingStrain
        self.sleepDebtHours = sleepDebtHours
        self.mindfulMinutes = mindfulMinutes
    }

    /// Associations named in the evening before or this morning ("work", "family"...).
    var moodAssociations: Set<String> {
        Set((evening?.associations ?? []) + (checkIn?.associations ?? []))
    }

    /// A mood (or its chips) was answered in the evening before or this morning.
    var hasMoodAnswer: Bool {
        checkIn?.mood != nil || checkIn?.associations != nil || evening?.mood != nil || evening?.associations != nil
    }
}

public enum CheckInInsights {
    public enum Outcome: String, Sendable, CaseIterable {
        case hrv = "HRV"
        case restingHeartRate = "Resting heart rate"
        case sleepScore = "Sleep score"
        /// Next-morning mood as a 0-100 score (`MoodScale.score`). Sleep loss
        /// reliably lowers positive affect (Palmer et al., Psychol Bull 2024:
        /// 154 experiments, n 5,717) and exercise lowers depressive symptoms
        /// (Heissel et al., Br J Sports Med 2023; Singh et al., Br J Sports Med
        /// 2023 umbrella review), so the levers the app already tracks are the
        /// ones mood should move with.
        case mood = "Mood"

        /// Higher is better for HRV, sleep and mood, lower for resting heart rate.
        var higherIsBetter: Bool { self != .restingHeartRate }

        func value(_ day: CheckInDay) -> Double? {
            switch self {
            case .hrv: day.hrv
            case .restingHeartRate: day.restingHeartRate
            case .sleepScore: day.sleepScore
            case .mood: day.moodValence.map(MoodScale.score(valence:))
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

    public static let factors: [Factor] = habitFactors + associationFactors

    static let habitFactors: [Factor] = [
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
        // Exercise and mood: Heissel et al., Br J Sports Med 2023 (RCTs in
        // depression, moderate-to-large effect); Singh et al., Br J Sports Med
        // 2023 (umbrella review). A rest day is the same test with the sign
        // flipped, so it isn't listed twice.
        Factor(id: "training", name: "A training day") { $0.trainedYesterday },
        // "Harder than usual": strain at or above what your training days
        // usually reach (`StrainCalculator.usualTrainingStrain`). App-made cut.
        Factor(id: "highStrain", name: "A harder day than usual") { day in
            guard let strain = day.strainYesterday, let usual = day.usualTrainingStrain, usual > 0 else { return nil }
            return strain >= usual
        },
        // Sleep loss lowers positive affect and raises anxiety (Palmer et al.,
        // Psychol Bull 2024, 154 experiments). 3 h is `SleepDebt`'s "moderate" line.
        Factor(id: "sleepDebt", name: "3 h+ of sleep debt") { $0.sleepDebtHours.map { $0 >= 3 } },
        // Mindfulness programmes: anxiety ES 0.38, depression 0.30 at 8 weeks
        // (Goyal et al., JAMA Intern Med 2014, 47 RCTs). Those were daily
        // practice over weeks; 10 minutes in a day is the app's own cut, so
        // the evidence for a one-day effect is weak.
        Factor(id: "mindful10", name: "10+ mindful minutes") { $0.mindfulMinutes.map { $0 >= 10 } },
    ]

    /// What the mood was about, from the check-ins' "What's affecting it?"
    /// chips. Nil on days with no mood answer at all, so days before the
    /// chips existed don't read as "without".
    static let associationFactors: [Factor] = MoodAssociation.allCases.map { association in
        Factor(id: "assoc." + association.rawValue, name: association.factorName) { day in
            guard day.hasMoodAnswer else { return nil }
            return day.moodAssociations.contains(association.rawValue)
        }
    }

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

    /// Indices of the p-values kept by Benjamini-Hochberg at `rate`: the k
    /// smallest where p(k) <= k/m * rate. Infinite p-values count towards m
    /// (they were tested) but are never kept.
    static func benjaminiHochberg(_ pValues: [Double], rate: Double) -> Set<Int> {
        let m = Double(max(pValues.count, 1))
        let order = pValues.indices.sorted { pValues[$0] < pValues[$1] }
        var keep = 0
        for (rank, index) in order.enumerated() where pValues[index].isFinite && pValues[index] <= Double(rank + 1) / m * rate {
            keep = rank + 1
        }
        return Set(order.prefix(keep))
    }

    /// The check-in patterns plus the alcohol card's clear findings, so the
    /// list never says "no clear patterns" while the alcohol card shows one.
    /// Alcohol is tested on its own (a well-documented, pre-stated effect:
    /// Pietilä et al., JMIR Ment Health 2018) with the same rule, so it can
    /// qualify there before it survives the wider many-factor correction.
    public static func merged(_ insights: [Insight], alcohol: [AlcoholEffect.Finding]) -> [Insight] {
        var result = insights
        for finding in alcohol where finding.isClear && finding.without > 0 {
            let outcome: Outcome = switch finding.measure {
            case .restingHeartRate: .restingHeartRate
            case .hrv: .hrv
            case .sleepScore: .sleepScore
            }
            let alreadyShown = result.contains { $0.outcome == outcome && ($0.factor == "Any alcohol" || $0.factor == "2+ drinks") }
            guard !alreadyShown else { continue }
            let change = (finding.withDrinks / finding.without - 1) * 100
            result.append(Insight(
                factor: "Any alcohol", outcome: outcome, percentChange: change,
                daysWith: finding.nightsWith, daysWithout: finding.nightsWithout,
                isGood: (change > 0) == outcome.higherIsBetter
            ))
        }
        return result.sorted { abs($0.percentChange) > abs($1.percentChange) }
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

    /// How close a habit is to being tested: days with it and without it
    /// (with a morning outcome to compare), against `analyze`'s 7 each way.
    public struct FactorProgress: Sendable, Equatable, Identifiable {
        public var name: String
        public var daysWith: Int
        public var daysWithout: Int
        public var needed: Int
        public var id: String { name }
        public var isReady: Bool { daysWith >= needed && daysWithout >= needed }
        /// The short side: "4/7 days" (with the habit) or "5/7 days without".
        public var text: String {
            daysWith < needed
                ? "\(daysWith)/\(needed) days"
                : "\(min(daysWithout, needed))/\(needed) days without"
        }
    }

    /// Factor names that are about alcohol (the check-in factors and the
    /// alcohol card's findings in `merged`).
    public static let alcoholFactors: Set<String> = ["Any alcohol", "2+ drinks"]

    /// The progress items not already answered by a pattern, so the list
    /// never says "Any alcohol 4/7 days" under "HRV 6% lower after any
    /// alcohol". While an alcohol pattern is shown, "2+ drinks" is dropped
    /// too: it's the same habit, measured more strictly.
    public static func uncovered(_ progress: [FactorProgress], by insights: [Insight]) -> [FactorProgress] {
        let shown = Set(insights.map(\.factor))
        let alcoholShown = !shown.isDisjoint(with: alcoholFactors)
        return progress.filter { item in
            !shown.contains(item.name) && !(alcoholShown && alcoholFactors.contains(item.name))
        }
    }

    /// The habits (not mood chips) that have been seen at least once and are
    /// still short of 7 days each way, closest first.
    public static func progress(_ days: [CheckInDay], minimumDays: Int = 7) -> [FactorProgress] {
        habitFactors.compactMap { factor -> FactorProgress? in
            var with = 0
            var without = 0
            for day in days {
                guard let present = factor.test(day),
                      Outcome.allCases.contains(where: { $0.value(day) != nil }) else { continue }
                if present { with += 1 } else { without += 1 }
            }
            let item = FactorProgress(name: factor.name, daysWith: with, daysWithout: without, needed: minimumDays)
            return with > 0 && !item.isReady ? item : nil
        }
        .sorted { min($0.daysWith, $0.daysWithout) > min($1.daysWith, $1.daysWithout) }
    }
}
