import Foundation

/// Relative strength (best estimated 1RM ÷ body mass) for the three big
/// lifts against age-and-sex bands, framed as a health marker next to
/// VO₂ max, not a leaderboard.
///
/// Muscular strength predicts all-cause mortality (García-Hermoso et al.,
/// Arch Phys Med Rehabil 2018, meta-analysis of about 2 million people);
/// in PURE, grip strength beat systolic blood pressure as a predictor
/// (Leong et al., Lancet 2015). That evidence is for strength in general,
/// not for any lift or ratio. The bands here are an app choice adapted from
/// commonly published, crowd-sourced strength-standards tables (not
/// re-verified; docs/research/competitors.md item 10), so they're labelled as such.
public enum StrengthForHealth {
    public enum Lift: String, CaseIterable, Sendable, Equatable, Identifiable {
        case bench, squat, deadlift

        public var id: String { rawValue }

        public var name: String {
            switch self {
            case .bench: "Bench press"
            case .squat: "Squat"
            case .deadlift: "Deadlift"
            }
        }
    }

    public enum Band: Int, Sendable, Equatable, Comparable, CaseIterable {
        case startingOut, building, good, strong, veryStrong

        public var label: String {
            switch self {
            case .startingOut: "Starting out"
            case .building: "Building"
            case .good: "Good"
            case .strong: "Strong"
            case .veryStrong: "Very strong"
            }
        }

        public static func < (lhs: Band, rhs: Band) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Result: Sendable, Equatable, Identifiable {
        public var lift: Lift
        public var estimatedOneRepMaxKg: Double
        /// e1RM ÷ body mass.
        public var ratio: Double
        public var band: Band
        /// Ratio needed for the next band, nil at the top.
        public var nextThreshold: Double?

        public var id: Lift { lift }
    }

    public static let evidenceNote = "An app choice: bands adapted from strength-standards tables; the health link is for strength in general (García-Hermoso 2018; Leong 2015)."

    /// The band most people can reach with a couple of years of consistent
    /// training; the "keep 2+ strength days and reach this" target for
    /// health and stamina goals (competitors.md item 10 goal tailoring).
    public static let healthTargetBand = Band.good

    /// Cut points (ratio of body mass) between the five bands at age 40 or
    /// under, from the lowest band up: the ratio that enters Building, Good,
    /// Strong and Very strong. Adapted (rounded) from the novice /
    /// intermediate / advanced / elite rows of published strength-standards
    /// tables for an 80 kg man and a 60 kg woman (crowd-sourced; app choice).
    static func baseThresholds(lift: Lift, sex: BiologicalSex) -> [Double] {
        switch (lift, sex) {
        case (.bench, .male): [0.6, 1.0, 1.5, 1.9]
        case (.squat, .male): [0.9, 1.25, 1.75, 2.25]
        case (.deadlift, .male): [1.0, 1.5, 2.0, 2.5]
        case (.bench, .female): [0.4, 0.7, 1.0, 1.25]
        case (.squat, .female): [0.6, 1.0, 1.5, 2.0]
        case (.deadlift, .female): [0.75, 1.25, 1.75, 2.25]
        }
    }

    /// Thresholds ease by 1% a year after 40, down to 70% at 70 and beyond
    /// (app choice, mirroring the age coefficients in standards tables;
    /// strength in population studies falls roughly 1-1.5% a year after 40).
    public static func ageFactor(_ age: Int) -> Double {
        guard age > 40 else { return 1 }
        return max(0.7, 1 - 0.01 * Double(age - 40))
    }

    /// The cut points for this person: four numbers, lowest first.
    public static func thresholds(lift: Lift, sex: BiologicalSex, age: Int) -> [Double] {
        let factor = ageFactor(age)
        return baseThresholds(lift: lift, sex: sex).map { $0 * factor }
    }

    public static func band(ratio: Double, lift: Lift, sex: BiologicalSex, age: Int) -> Band {
        let cuts = thresholds(lift: lift, sex: sex, age: age)
        let index = cuts.filter { ratio >= $0 }.count
        return Band(rawValue: index) ?? .veryStrong
    }

    /// Which big lift an exercise name is, or nil for variations whose
    /// standards differ (incline, dumbbell, Romanian, hack squat...).
    public static func lift(forExerciseName name: String) -> Lift? {
        let lower = name.lowercased()
        let excluded = ["dumbbell", "band", "chain", "smith", "machine", "cable", "kettlebell", "single", "one arm", "one-arm"]
        guard !excluded.contains(where: { lower.contains($0) }) else { return nil }
        if lower.contains("bench press") {
            let variations = ["incline", "decline", "close-grip", "close grip", "guillotine", "reverse", "wide", "floor", "board", "pin", "spoto"]
            return variations.contains(where: { lower.contains($0) }) ? nil : .bench
        }
        if lower.contains("deadlift") {
            let variations = ["romanian", "stiff", "straight", "deficit", "rack", "snatch", "clean", "axle", "car", "trap", "hex", "sumo", "jefferson", "suitcase", "block", "pause", "paused"]
            return variations.contains(where: { lower.contains($0) }) ? nil : .deadlift
        }
        if lower.contains("squat") {
            let variations = ["hack", "split", "front", "box", "bodyweight", "goblet", "jump", "zercher", "overhead", "sissy", "pistol", "bulgarian", "to a bench", "side", "belt", "safety", "pause", "paused", "wall", "chair", "air", "sumo", "jefferson"]
            guard lower.contains("barbell") || lower == "squat" || lower.contains("back squat") || lower.contains("powerlifting") else { return nil }
            return variations.contains(where: { lower.contains($0) }) ? nil : .squat
        }
        return nil
    }

    /// Best e1RM per big lift from exercise history (any exercise whose
    /// name maps to the lift), as ratios of body mass with their bands.
    public static func assess(lifts: [(name: String, estimatedOneRepMaxKg: Double)], bodyMassKg: Double, sex: BiologicalSex, age: Int) -> [Result] {
        guard bodyMassKg > 0 else { return [] }
        var best: [Lift: Double] = [:]
        for entry in lifts where entry.estimatedOneRepMaxKg > 0 {
            guard let lift = lift(forExerciseName: entry.name) else { continue }
            best[lift] = max(best[lift] ?? 0, entry.estimatedOneRepMaxKg)
        }
        return Lift.allCases.compactMap { lift in
            guard let e1RM = best[lift] else { return nil }
            let ratio = e1RM / bodyMassKg
            let band = band(ratio: ratio, lift: lift, sex: sex, age: age)
            let cuts = thresholds(lift: lift, sex: sex, age: age)
            let next = band.rawValue < cuts.count ? cuts[band.rawValue] : nil
            return Result(lift: lift, estimatedOneRepMaxKg: e1RM, ratio: ratio, band: band, nextThreshold: next)
        }
    }

    /// One line for the card and the coach: health and stamina goals see
    /// the "good" band as the target; strength and muscle goals see the next band.
    public static func summary(_ results: [Result], goals: Goals?) -> String {
        guard !results.isEmpty else { return "Log bench press, squat or deadlift sets and your relative strength shows here." }
        let strengthFocused = goals.map { $0.focuses.contains(.strength) || $0.focuses.contains(.muscle) } ?? false
        let lowest = results.min { $0.band < $1.band } ?? results[0]
        if strengthFocused {
            guard let next = lowest.nextThreshold else { return "Every lift is in the top band." }
            return "\(lowest.lift.name) is the next one up: \(lowest.band.label) now, \(Band(rawValue: lowest.band.rawValue + 1)?.label ?? "") from \(next.formatted(.number.precision(.fractionLength(2)))) × body weight."
        }
        let below = results.filter { $0.band < healthTargetBand }
        if below.isEmpty { return "All your big lifts are at \"\(healthTargetBand.label)\" or above. Keeping 2+ strength days a week holds the health benefit." }
        return "\(below.map(\.lift.name).joined(separator: ", ")) below \"\(healthTargetBand.label)\". For health, 2+ strength days a week and reaching that band is plenty."
    }
}
