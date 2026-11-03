import Foundation

/// Grip strength, typed in twice a year from a hand dynamometer (dominant
/// hand, best of three squeezes, in kg).
///
/// - Why: in the PURE study (139,691 adults, 17 countries) each 5 kg less grip
///   went with about 16% more deaths from any cause and 17% more from heart
///   disease, a stronger link than systolic blood pressure (Leong et al.,
///   Lancet 2015). It's a marker; whether raising it changes risk isn't known.
/// - Cut-offs: "probable sarcopenia" under 27 kg for men and 16 kg for women
///   (Cruz-Jentoft et al., EWGSOP2, Age Ageing 2019).
/// - Age bands: rounded from the Jamar reference values pooled by Bohannon et
///   al. (Physiotherapy 2006; 12 sources, 3,317 adults), which put a man in
///   his 20s-40s at about 45-55 kg. The UK life-course norms (Dodds et al.,
///   PLoS One 2014) peak a few kg lower in the 30s; they weren't in the
///   research report and are cited from memory, so the bands read as "about".
///   The spread (about ±1 standard deviation) is an app rounding of the same
///   tables, not a published cut-off.
public enum GripStrength {
    public enum Hand: String, Codable, Sendable, CaseIterable, Identifiable {
        case left, right
        public var id: String { rawValue }
        public var label: String { self == .left ? "Left" : "Right" }
    }

    /// EWGSOP2 probable-sarcopenia cut-off (Cruz-Jentoft et al. 2019).
    public static func sarcopeniaCutoffKg(sex: BiologicalSex) -> Double {
        sex == .male ? 27 : 16
    }

    public struct Band: Sendable, Equatable {
        /// Typical value for the age band (dominant hand, kg).
        public var mean: Double
        /// About one standard deviation.
        public var spread: Double
        public var low: Double { mean - spread }
        public var high: Double { mean + spread }
    }

    /// The age-band reference (Bohannon 2006, rounded; see the type comment).
    public static func band(age: Int, sex: BiologicalSex) -> Band {
        let decade = min(80, max(20, (age / 10) * 10))
        switch (sex, decade) {
        case (.male, 20): return Band(mean: 50, spread: 9)
        case (.male, 30): return Band(mean: 52, spread: 9)
        case (.male, 40): return Band(mean: 50, spread: 9)
        case (.male, 50): return Band(mean: 46, spread: 8)
        case (.male, 60): return Band(mean: 41, spread: 8)
        case (.male, 70): return Band(mean: 35, spread: 7)
        case (.male, _): return Band(mean: 29, spread: 6)
        case (_, 20): return Band(mean: 31, spread: 6)
        case (_, 30): return Band(mean: 32, spread: 6)
        case (_, 40): return Band(mean: 30, spread: 6)
        case (_, 50): return Band(mean: 28, spread: 5)
        case (_, 60): return Band(mean: 25, spread: 5)
        case (_, 70): return Band(mean: 22, spread: 5)
        case (_, _): return Band(mean: 18, spread: 4)
        }
    }

    public enum Reading: String, Sendable, Equatable {
        /// Under the EWGSOP2 cut-off.
        case belowCutoff = "Below the sarcopenia line"
        /// Under the age band (more than about 1 SD below its mean).
        case belowAverage = "Below average for your age"
        case average = "About average for your age"
        case aboveAverage = "Above average for your age"
    }

    public static func reading(kg: Double, age: Int, sex: BiologicalSex) -> Reading {
        if kg < sarcopeniaCutoffKg(sex: sex) { return .belowCutoff }
        let band = band(age: age, sex: sex)
        if kg < band.low { return .belowAverage }
        if kg > band.high { return .aboveAverage }
        return .average
    }

    /// What the reading means, in plain words. Never a diagnosis.
    public static func advice(_ reading: Reading, age: Int, sex: BiologicalSex) -> String {
        let band = band(age: age, sex: sex)
        let typical = "People your age and sex typically squeeze about \(Int(band.low))-\(Int(band.high)) kg."
        switch reading {
        case .belowCutoff:
            return "Under \(Int(sarcopeniaCutoffKg(sex: sex))) kg is the line the European sarcopenia consensus uses for probable low muscle strength. One squeeze on a cheap dynamometer can be off, so repeat it rested; if it stays there, mention it to a doctor. Heavy pulling (rows, deadlifts, carries) raises it. \(typical)"
        case .belowAverage:
            return "\(typical) Below that band isn't a diagnosis, but grip tracks whole-body strength, and in large studies each 5 kg less went with about 16% more deaths. Rows, deadlifts and loaded carries are the lever."
        case .average:
            return "\(typical) Aim above the middle of the band: grip is a free by-product of pulling and carrying, and higher is better across the whole range."
        case .aboveAverage:
            return "\(typical) You're above it. Keep it: in large studies, every 5 kg of grip went with about 16% fewer deaths."
        }
    }

    // MARK: Cadence

    /// Twice a year is enough: grip changes slowly, and the point is to
    /// confirm strength is kept through a cut or a long block
    /// (docs/research/health-metrics.md, section 2).
    public static let intervalDays = 182

    public static func nextDue(lastMeasured: Date?, calendar: Calendar = .current) -> Date? {
        guard let lastMeasured else { return nil }
        return calendar.date(byAdding: .day, value: intervalDays, to: calendar.startOfDay(for: lastMeasured))
    }

    public static func isDue(lastMeasured: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let due = nextDue(lastMeasured: lastMeasured, calendar: calendar) else { return true }
        return calendar.startOfDay(for: now) >= due
    }
}
