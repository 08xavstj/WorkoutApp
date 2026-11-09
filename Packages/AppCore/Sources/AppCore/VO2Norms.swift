import Foundation

/// Where a VO₂ max sits against other people of your age and sex, from one
/// published table so every VO₂ max number in the app agrees.
///
/// Source: Kaminsky LA, Arena R, Myers J. Reference Standards for
/// Cardiorespiratory Fitness Measured With Cardiopulmonary Exercise Testing:
/// Data From the Fitness Registry and the Importance of Exercise National
/// Database. Mayo Clin Proc 2015;90(11):1515-1523 (FRIEND; 7,783 maximal
/// treadmill tests with measured VO₂ max, US adults aged 20-79 without
/// cardiovascular disease). Table 3, "Men/Women from FRIEND", treadmill.
///
/// - Test mode matters: cycle tests read lower and FRIEND publishes separate
///   cycle standards (Kaminsky et al., Mayo Clin Proc 2017). These treadmill
///   norms suit Apple Watch, which estimates from walking and running.
/// - The FRIEND update (Kaminsky et al., Mayo Clin Proc 2022;97:285-293)
///   reports treadmill values 1.5-4.6 ml/kg/min lower than 2015 (its
///   abstract; the full tables weren't checked for this app). The app
///   keeps the 2015 table for the medians, percentiles and fitness age alike;
///   if it moves to 2022 it must move all of them together.
/// - FRIEND volunteers were referred for or chose a lab test; they are not a
///   random sample of the population.
/// - The category names at the table's cut points are the app's plain-words
///   choice (in the spirit of ACSM's percentile bands), not FRIEND's.
public enum VO2Norms {
    /// The table's percentiles, in order.
    public static let percentiles: [Double] = [5, 10, 25, 50, 75, 90, 95]

    /// FRIEND 2015 Table 3, treadmill, ml/kg/min. Rows are age decades
    /// 20-29, 30-39, 40-49, 50-59, 60-69, 70-79; columns are `percentiles`.
    public static let friendTreadmill: [BiologicalSex: [[Double]]] = [
        .male: [
            [29.0, 32.1, 40.1, 48.0, 55.2, 61.8, 66.3],
            [27.2, 30.2, 35.9, 42.4, 49.2, 56.5, 59.8],
            [24.2, 26.8, 31.9, 37.8, 45.0, 52.1, 55.6],
            [20.9, 22.8, 27.1, 32.6, 39.7, 45.6, 50.7],
            [17.4, 19.8, 23.7, 28.2, 34.5, 40.3, 43.0],
            [16.3, 17.1, 20.4, 24.4, 30.4, 36.6, 39.7],
        ],
        .female: [
            [21.7, 23.9, 30.5, 37.6, 44.7, 51.3, 56.0],
            [19.0, 20.9, 25.3, 30.2, 36.1, 41.4, 45.8],
            [17.0, 18.8, 22.1, 26.7, 32.4, 38.4, 41.7],
            [16.0, 17.3, 19.9, 23.4, 27.6, 32.0, 35.9],
            [13.4, 14.6, 17.2, 20.0, 23.8, 27.0, 29.4],
            [13.1, 13.6, 15.6, 18.3, 20.8, 23.1, 24.1],
        ],
    ]

    /// FRIEND 2015 Table 2, all ages 20-79: mean VO₂ max and number of tests.
    public static let allAgesMean: [BiologicalSex: (mean: Double, tests: Int)] = [
        .male: (37.9, 4611),
        .female: (27.6, 3172),
    ]

    /// "Average adult": the FRIEND all-ages means for men and women pooled by
    /// their number of tests (Table 2): (4611 × 37.9 + 3172 × 27.6) / 7783 ≈
    /// 33.7. Derived by the app from the table, and a mean rather than a
    /// median.
    public static var averageAdult: Double {
        let groups = BiologicalSex.allCases.compactMap { allAgesMean[$0] }
        let tests = groups.reduce(0) { $0 + $1.tests }
        guard tests > 0 else { return 0 }
        return groups.reduce(0.0) { $0 + $1.mean * Double($1.tests) } / Double(tests)
    }

    /// The table column for one percentile, by decade (20s ... 70s).
    static func column(_ index: Int, sex: BiologicalSex) -> [Double] {
        (friendTreadmill[sex] ?? []).map { $0[index] }
    }

    /// The cut points (one per `percentiles`) for an age, interpolated
    /// between decade midpoints 25, 35, ... 75 and held flat outside them,
    /// exactly as `Biomarkers.medianVO2Max` does, so the 50th equals it.
    public static func cutPoints(age: Int, sex: BiologicalSex) -> [Double] {
        let rows = friendTreadmill[sex] ?? []
        guard let first = rows.first else { return [] }
        let position = min(Double(rows.count - 1), max(0, (Double(age) - 25) / 10))
        let lower = Int(position.rounded(.down))
        let upper = min(rows.count - 1, lower + 1)
        let fraction = position - Double(lower)
        return first.indices.map { column in
            rows[lower][column] + (rows[upper][column] - rows[lower][column]) * fraction
        }
    }

    /// The median (50th percentile) for an age.
    public static func median(age: Int, sex: BiologicalSex) -> Double {
        cutPoints(age: age, sex: sex)[3]
    }

    /// The 90th percentile for an age: the start of the top 10%.
    public static func topTenPercent(age: Int, sex: BiologicalSex) -> Double {
        cutPoints(age: age, sex: sex)[5]
    }

    // MARK: Percentile and category

    /// Approximate percentile: straight lines between the table's cut points,
    /// held at 5 below the 5th and 95 above the 95th (the table says nothing
    /// beyond them; see `Standing.isBelowTable` / `isAboveTable`).
    public static func percentile(vo2: Double, age: Int, sex: BiologicalSex) -> Double {
        let cuts = cutPoints(age: age, sex: sex)
        guard let first = cuts.first, let last = cuts.last else { return 50 }
        if vo2 <= first { return percentiles[0] }
        if vo2 >= last { return percentiles[percentiles.count - 1] }
        for index in 0..<(cuts.count - 1) where vo2 < cuts[index + 1] {
            let span = cuts[index + 1] - cuts[index]
            let fraction = span > 0 ? (vo2 - cuts[index]) / span : 0
            return percentiles[index] + (percentiles[index + 1] - percentiles[index]) * fraction
        }
        return percentiles[percentiles.count - 1]
    }

    /// Bands at the table's 10th, 25th, 50th, 75th and 90th percentiles.
    public enum Category: Int, Sendable, CaseIterable, Comparable {
        /// Under the 10th percentile.
        case low
        /// 10th-25th.
        case belowAverage
        /// 25th-50th.
        case average
        /// 50th-75th.
        case good
        /// 75th-90th.
        case excellent
        /// 90th and up.
        case topTen

        public var name: String {
            switch self {
            case .low: "Low"
            case .belowAverage: "Below average"
            case .average: "Average"
            case .good: "Good"
            case .excellent: "Excellent"
            case .topTen: "Top 10%"
            }
        }

        /// Under the 25th percentile: worth a caution colour.
        public var isBelowAverage: Bool { self < .average }

        /// The percentile the band starts at (0 for `low`).
        public var lowerPercentile: Double {
            switch self {
            case .low: 0
            case .belowAverage: 10
            case .average: 25
            case .good: 50
            case .excellent: 75
            case .topTen: 90
            }
        }

        public static func < (lhs: Category, rhs: Category) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public static func category(vo2: Double, age: Int, sex: BiologicalSex) -> Category {
        let cuts = cutPoints(age: age, sex: sex)
        guard cuts.count == percentiles.count else { return .average }
        // cuts[1] = 10th, [2] = 25th, [3] = 50th, [4] = 75th, [5] = 90th.
        switch vo2 {
        case ..<cuts[1]: return .low
        case ..<cuts[2]: return .belowAverage
        case ..<cuts[3]: return .average
        case ..<cuts[4]: return .good
        case ..<cuts[5]: return .excellent
        default: return .topTen
        }
    }

    /// One band on the scale bar, in ml/kg/min.
    public struct Segment: Sendable, Equatable {
        public var category: Category
        public var range: ClosedRange<Double>
    }

    /// The bands for an age across `scale`, low to high.
    public static func segments(age: Int, sex: BiologicalSex, scale: ClosedRange<Double>) -> [Segment] {
        let cuts = cutPoints(age: age, sex: sex)
        guard cuts.count == percentiles.count else { return [] }
        let edges = [scale.lowerBound, cuts[1], cuts[2], cuts[3], cuts[4], cuts[5], scale.upperBound]
        return Category.allCases.enumerated().compactMap { index, category in
            let low = max(scale.lowerBound, edges[index])
            let high = min(scale.upperBound, edges[index + 1])
            return high > low ? Segment(category: category, range: low...high) : nil
        }
    }

    /// The bar's span: the table's 5th to 95th for your age, widened to fit
    /// `values` (yours and the reference marks), with 2 to spare, in steps of 5.
    public static func scale(age: Int, sex: BiologicalSex, including values: [Double] = []) -> ClosedRange<Double> {
        let cuts = cutPoints(age: age, sex: sex)
        let all = cuts + values.filter { $0.isFinite && $0 > 0 }
        let low = max(0, ((all.min() ?? 20) - 2) / 5).rounded(.down) * 5
        let high = (((all.max() ?? 65) + 2) / 5).rounded(.up) * 5
        return low...max(high, low + 10)
    }

    // MARK: Standing in words

    public struct Standing: Sendable, Equatable {
        public var vo2: Double
        public var percentile: Double
        public var category: Category
        public var isBelowTable: Bool
        public var isAboveTable: Bool
        public var sex: BiologicalSex
        /// The age the table was read at; FRIEND covers 20-79, so younger and
        /// older ages are read against the nearest decade (`cutPoints`).
        public var age: Int = 40

        /// "About the 60th percentile for men your age", "Above the 95th
        /// percentile for women your age". Rounded to 5: it's interpolated.
        /// Outside the table's 20-79 it names the decade used instead of "your age".
        public var percentileText: String {
            let group = sex == .male ? "men" : "women"
            let who = VO2Norms.peerText(age: age)
            if isBelowTable { return "Below the 5th percentile for \(group) \(who)" }
            if isAboveTable { return "Above the 95th percentile for \(group) \(who)" }
            let rounded = Int(min(95, max(5, (percentile / 5).rounded() * 5)))
            return "About the \(VO2Norms.ordinal(rounded)) percentile for \(group) \(who)"
        }
    }

    /// Ages the FRIEND table covers (Kaminsky et al. 2015: adults 20-79).
    public static let coveredAges = 20...79

    /// "your age", or the nearest decade the table has when you're outside it
    /// (the norms are clamped there, not extrapolated).
    public static func peerText(age: Int) -> String {
        if age < coveredAges.lowerBound { return "in their 20s (the norms start at 20)" }
        if age > coveredAges.upperBound { return "in their 70s (the norms stop at 79)" }
        return "your age"
    }

    public static func standing(vo2: Double, age: Int, sex: BiologicalSex) -> Standing {
        let cuts = cutPoints(age: age, sex: sex)
        return Standing(
            vo2: vo2,
            percentile: percentile(vo2: vo2, age: age, sex: sex),
            category: category(vo2: vo2, age: age, sex: sex),
            isBelowTable: vo2 < (cuts.first ?? 0),
            isAboveTable: vo2 > (cuts.last ?? .infinity),
            sex: sex,
            age: age
        )
    }

    /// 1st, 2nd, 3rd, 4th, 11th, 12th, 13th, 21st ...
    public static func ordinal(_ value: Int) -> String {
        let tens = value % 100
        if (11...13).contains(tens) { return "\(value)th" }
        switch value % 10 {
        case 1: return "\(value)st"
        case 2: return "\(value)nd"
        case 3: return "\(value)rd"
        default: return "\(value)th"
        }
    }

    // MARK: Reference marks

    public struct Reference: Sendable, Equatable, Identifiable {
        public enum Kind: String, Sendable, Equatable {
            case sameSex, otherSex, adult, topTen
        }

        public var kind: Kind
        public var value: Double
        /// Short, for a tick under the bar: "Avg man", "Avg adult", "Top 10%".
        public var shortLabel: String
        /// For the list: "Typical man your age".
        public var label: String
        public var id: String { kind.rawValue }
    }

    /// Typical (median) man and woman your age, the average adult (all ages,
    /// derived), and where the top 10% of your age and sex starts.
    public static func references(age: Int, sex: BiologicalSex) -> [Reference] {
        let other: BiologicalSex = sex == .male ? .female : .male
        func noun(_ s: BiologicalSex) -> String { s == .male ? "man" : "woman" }
        return [
            Reference(kind: .sameSex, value: median(age: age, sex: sex),
                      shortLabel: "Avg \(noun(sex))", label: "Typical \(noun(sex)) your age"),
            Reference(kind: .otherSex, value: median(age: age, sex: other),
                      shortLabel: "Avg \(noun(other))", label: "Typical \(noun(other)) your age"),
            Reference(kind: .adult, value: averageAdult,
                      shortLabel: "Avg adult", label: "Average adult, all ages"),
            Reference(kind: .topTen, value: topTenPercent(age: age, sex: sex),
                      shortLabel: "Top 10%", label: "Top 10% of \(sex == .male ? "men" : "women") your age"),
        ]
    }

    // MARK: Tips

    public struct Tip: Sendable, Equatable, Identifiable {
        public var text: String
        /// The study behind it, for an evidence disclosure.
        public var evidence: String
        public var id: String { text }
    }

    /// 3-4 short tips for raising VO₂ max, by where you stand and your goals.
    /// - Parameters:
    ///   - category: from the watch reading, or an estimate when there's none.
    ///   - lifts: strength or muscle is a goal (adds the "cardio won't cost
    ///     muscle" tip).
    ///   - losingWeight: a fat-loss goal (adds the per-kilogram tip).
    public static func tips(category: Category, lifts: Bool, losingWeight: Bool) -> [Tip] {
        var tips: [Tip] = []
        if category < .good {
            // Below the median: volume first, then one harder session.
            tips.append(Tip(
                text: "Start with 2 easy 30-minute sessions a week (bike, rower or incline walk). Less-trained people gain about 5 ml/kg/min in 2–3 months.",
                evidence: "Steady cardio raised VO₂ max by 4.9 ml/kg/min and intervals by 5.5 against no exercise, across 28 trials (Milanović, Sporiš & Weston, Sports Med 2015)."))
            tips.append(Tip(
                text: "Once that feels easy, make one session 4 × 4 minutes hard (90–95% of max heart rate) with 3 minutes easy between.",
                evidence: "4 × 4-minute intervals at 90–95% of max heart rate, 3 times a week for 8 weeks, raised VO₂ max 7.2%, more than steady running (Helgerud et al., Med Sci Sports Exerc 2007). Intervals of 2+ minutes did best in 53 trials (Wen et al., J Sci Med Sport 2019)."))
        } else {
            // At or above the median: intervals are the lever.
            tips.append(Tip(
                text: "Do 1–2 sessions a week of 4 × 4 minutes hard (90–95% of max heart rate), 3 minutes easy between.",
                evidence: "Intervals beat steady cardio by about 1.2 ml/kg/min (Milanović, Sporiš & Weston, Sports Med 2015); 4 × 4 at 90–95% of max heart rate raised VO₂ max 7.2% in 8 weeks (Helgerud et al., Med Sci Sports Exerc 2007)."))
            tips.append(Tip(
                text: category == .topTen
                    ? "You're in the top 10%. Gains get smaller from here; easy cardio plus one hard session a week holds it."
                    : "Keep 150+ minutes of moderate cardio a week as the base; the hard sessions count double.",
                evidence: "WHO: 150–300 minutes moderate or 75–150 vigorous a week (Bull et al., Br J Sports Med 2020)."))
        }
        if lifts {
            tips.append(Tip(
                text: "Cardio won't cost you muscle. Cycling or rowing is kindest to leg days; keep hard cardio a few hours from heavy lifting.",
                evidence: "Across 43 studies, adding cardio didn't blunt muscle growth or max strength; explosive strength suffered most when both were in one session (Schumann et al., Sports Med 2022). Running, not cycling, went with smaller muscle-fibre gains (Lundberg et al., Sports Med 2022)."))
        }
        if losingWeight {
            tips.append(Tip(
                text: "Losing fat raises the number too: it's per kilogram, so 5% less body weight reads about 5% higher at the same fitness.",
                evidence: "VO₂ max in ml/kg/min is litres of oxygen a minute divided by body weight (arithmetic, not a study)."))
        }
        return Array(tips.prefix(4))
    }
}
