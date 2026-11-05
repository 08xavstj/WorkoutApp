import Foundation

/// Weekly headphone (or environmental) sound exposure against the WHO/ITU
/// safe-listening budget.
///
/// WHO-ITU H.870 "Guidelines for safe listening devices/systems" (2019,
/// revised 2022) and WHO "Safe listening devices and systems: a WHO-ITU
/// standard" (2019) set a weekly sound allowance of 80 dB(A) for 40 hours
/// for adults (75 dB(A) for 40 hours for children and sensitive users), with
/// the equal-energy rule: every +3 dB halves the allowed time. The allowance
/// is carried over from occupational hearing-conservation limits (ISO 1999
/// / NIOSH 1998: 85 dB(A) for 8 h a day, 3 dB exchange rate) with a 5 dB
/// margin, so it is a safety guideline rather than a measured threshold of
/// harm; the UI says so. See docs/research/watch-features.md §1.6.
public enum HearingExposure {
    /// The WHO/ITU weekly allowance for adults: 80 dB(A) for 40 hours
    /// (WHO-ITU H.870, 2019; WHO 2019).
    public static let referenceLevel: Double = 80
    public static let referenceHours: Double = 40
    /// The stricter allowance for children and sensitive users (WHO-ITU H.870).
    public static let sensitiveReferenceLevel: Double = 75
    /// Equal-energy rule: time halves for every 3 dB (ISO 1999; NIOSH 1998).
    public static let exchangeRateDecibels: Double = 3

    /// One exposure sample: an A-weighted equivalent continuous level over
    /// some hours (HealthKit's `headphoneAudioExposure` samples are exactly
    /// this; a sample's level is its Leq over its own duration).
    public struct Sample: Sendable, Equatable {
        public var start: Date
        /// dB(A) SPL, equivalent continuous level over `hours`.
        public var level: Double
        public var hours: Double

        public init(start: Date, level: Double, hours: Double) {
            self.start = start
            self.level = level
            self.hours = hours
        }
    }

    public struct Result: Sendable, Equatable {
        /// Hours of listening in the window.
        public var hours: Double
        /// Energy-weighted average level, dB(A), over the listening hours (nil
        /// when there was no listening).
        public var equivalentLevel: Double?
        /// Share of the weekly budget used, 1.0 = the full allowance.
        public var budgetFraction: Double
        /// Share of the budget used per day (start of day → fraction).
        public var dailyFractions: [Date: Double]

        public var percentOfBudget: Int { Int((budgetFraction * 100).rounded()) }
        public var isOverBudget: Bool { budgetFraction >= 1 }
    }

    /// Hours allowed per week at a steady `level`, from the equal-energy
    /// rule: 40 h at 80 dB(A), 20 h at 83, 10 h at 86, 5 h at 89, about
    /// 1 h 15 min at 95 (WHO-ITU H.870 table).
    public static func allowedHours(at level: Double, referenceLevel: Double = referenceLevel) -> Double {
        referenceHours / pow(2, (level - referenceLevel) / exchangeRateDecibels)
    }

    /// Sound energy relative to the reference level per hour of listening:
    /// 1 at the reference level, 2 at +3 dB, 10 at +10 dB.
    static func relativeEnergy(_ level: Double, referenceLevel: Double) -> Double {
        pow(10, (level - referenceLevel) / 10)
    }

    /// Sums the samples (normally the last 7 days) into the weekly dose.
    public static func weekly(
        _ samples: [Sample],
        referenceLevel: Double = referenceLevel,
        calendar: Calendar = .current
    ) -> Result {
        var hours = 0.0
        var energyHours = 0.0
        var daily: [Date: Double] = [:]
        for sample in samples where sample.hours > 0 && sample.level.isFinite {
            let energy = relativeEnergy(sample.level, referenceLevel: referenceLevel) * sample.hours
            hours += sample.hours
            energyHours += energy
            daily[calendar.startOfDay(for: sample.start), default: 0] += energy / referenceHours
        }
        let level: Double? = hours > 0 ? referenceLevel + 10 * log10(energyHours / hours) : nil
        return Result(
            hours: hours,
            equivalentLevel: level,
            budgetFraction: energyHours / referenceHours,
            dailyFractions: daily
        )
    }

    /// Short wording for the stat; `nil` when there is nothing to say.
    public static func nudge(for result: Result) -> String? {
        guard result.hours > 0 else { return nil }
        if result.budgetFraction >= 1 {
            return "Over the weekly safe-listening budget. Turning the volume down 3 dB doubles the time you can listen safely."
        }
        if result.budgetFraction >= 0.75 {
            return "Close to the weekly budget. A notch quieter during long sessions keeps you under it."
        }
        return nil
    }
}
