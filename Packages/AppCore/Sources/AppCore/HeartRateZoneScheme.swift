import Foundation

/// A heart-rate range in beats per minute: from `lower` up to, not including, `upper`.
public nonisolated struct HeartRateBand: Codable, Sendable, Equatable {
    public nonisolated enum Side: Sendable, Equatable {
        case below, inside, above
    }

    /// `upper` for a band with no top (the highest zone). A plain large number,
    /// so the band still encodes as JSON (infinity doesn't).
    public static let noUpperLimit = 1000.0

    public var lower: Double
    public var upper: Double

    public init(lower: Double, upper: Double) {
        self.lower = lower
        self.upper = upper
    }

    public func contains(_ bpm: Double) -> Bool { bpm >= lower && bpm < upper }

    public func side(of bpm: Double) -> Side {
        if bpm < lower { return .below }
        return bpm < upper ? .inside : .above
    }

    /// "108–133", "under 133" (no floor) or "171+" (no top), in whole beats.
    public var text: String {
        let low = Int(lower.rounded())
        let high = Int(upper.rounded())
        if upper >= Self.noUpperLimit { return "\(low)+" }
        if lower <= 0 { return "under \(high)" }
        return "\(low)–\(high)"
    }
}

/// How heart rate is cut into five zones for display and for the Watch's
/// cardio mode (docs/research/workout-zones-2026-11.md). Three ways to choose
/// the limits (`Kind.choices`):
///
/// - `reserve`: Tensile's own, by heart-rate reserve. The default, and what
///   `HeartRateProfile.zone` and day strain have always used.
/// - `appleHealth`: the limits Apple Health holds (read on iOS/watchOS 27).
/// - `custom`: limits the user typed, e.g. from a lab or threshold test.
///
/// Percent of maximum was a fourth option until 17 Nov 2026. The evidence
/// audit dropped it: it added a second scale on which the same heart rate
/// lands about a zone higher, and fixed percentages match individual
/// thresholds poorly whichever base they use (Iannetta 2020, below). The
/// `percentOfMax` case stays only so a saved choice or a scheme the Watch
/// stored still decodes; it is used as Tensile's (`Kind.inUse`).
///
/// Day strain does not read this type: `StrainCalculator` weights every
/// minute by its fraction of heart-rate reserve (Banister's TRIMP), whatever
/// scheme is shown.
///
/// No fixed-percentage scheme puts everyone in the same physiological state:
/// in 100 adults the lactate threshold sat anywhere from 60 to 90% of maximum
/// heart rate (Iannetta D, et al. A critical evaluation of current methods
/// for exercise prescription in women and men. Med Sci Sports Exerc
/// 2020;52(2):466-473). The zones are labels for effort, not measurements.
///
/// This file needs only Foundation, so the Watch app compiles it on its own
/// (project.yml, `TensileWatch: sources:`).
public nonisolated struct HeartRateZoneScheme: Codable, Sendable, Equatable {
    public nonisolated enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        /// `percentOfMax` is retired (see the type comment): it decodes, is never offered, and stands for `reserve`.
        case reserve, percentOfMax, appleHealth, custom

        public var id: String { rawValue }

        /// The options offered in Settings.
        public static let choices: [Kind] = [.reserve, .appleHealth, .custom]

        /// The option used for this choice: a retired percent-of-max choice falls back to Tensile's.
        public var inUse: Kind { self == .percentOfMax ? .reserve : self }

        /// Short name, for pickers and captions.
        public var title: String {
            switch self {
            case .reserve: "Tensile"
            case .percentOfMax: "Percent of max"
            case .appleHealth: "Apple Health"
            case .custom: "Custom"
            }
        }

        /// One plain sentence on what the option does.
        public var explanation: String {
            switch self {
            case .reserve:
                "Five zones from 50% to 100% of the gap between your resting and maximum heart rate. Day strain uses the same scale."
            case .percentOfMax:
                "No longer offered: Tensile's zones are used instead."
            case .appleHealth:
                "The zones set in Apple Health, so Tensile matches Apple's Workout and Fitness apps."
            case .custom:
                "Your own limits, for example from a lab or threshold test."
            }
        }
    }

    /// Resting and maximum heart rate behind a `reserve` scheme. Kept so the
    /// zone for a heart rate is worked out with exactly the arithmetic of
    /// `HeartRateProfile.zone`, including at the limits.
    public nonisolated struct ReserveBasis: Codable, Sendable, Equatable {
        public var resting: Double
        public var maximum: Double

        public init(resting: Double, maximum: Double) {
            self.resting = resting
            self.maximum = maximum
        }
    }

    /// Which of the four ways these limits came from.
    public var kind: Kind
    /// Where zone 1 starts, in bpm; nil when zone 1 has no floor (Apple
    /// Health's first zone has none: everything under zone 2 is zone 1).
    public var floor: Double?
    /// Where zones 2, 3, 4 and 5 start, in bpm, ascending.
    public var boundaries: [Double]
    /// Set for `reserve` schemes only (see `ReserveBasis`).
    public var reserveBasis: ReserveBasis?
    /// The "Easy" target for cardio (`easyBand(resting:maximum:)`).
    public var easyBand: HeartRateBand

    public init(kind: Kind, floor: Double?, boundaries: [Double], reserveBasis: ReserveBasis? = nil, easyBand: HeartRateBand) {
        self.kind = kind
        self.floor = floor
        self.boundaries = boundaries
        self.reserveBasis = reserveBasis
        self.easyBand = easyBand
    }

    // MARK: Limits and where they come from

    /// Zones 1-5 start at these fractions of heart-rate reserve
    /// (resting + fraction × (maximum − resting); Karvonen MJ, Kentala E,
    /// Mustala O. The effects of training on heart rate: a longitudinal study.
    /// Ann Med Exp Biol Fenn 1957;35:307-315). The 10-point steps are Edwards'
    /// five zones from 50% of maximum (Edwards S. The Heart Rate Monitor Book.
    /// Polar Electro, 1993; as described in Borresen J, Lambert MI. Sports Med
    /// 2009;39(9):779-795; neither re-verified) moved onto reserve, which tracks
    /// oxygen-uptake reserve better than percent of maximum does (Swain DP,
    /// Leutholtz BC. Heart rate reserve is equivalent to %VO2 reserve, not to
    /// %VO2max. Med Sci Sports Exerc 1997;29:410-414). The same numbers as
    /// `HeartRateProfile.zone`; putting the steps on reserve is the app's choice.
    public static let reserveFractions = [0.5, 0.6, 0.7, 0.8, 0.9]

    /// "Easy" as a fraction of heart-rate reserve: 40% up to 60%, ACSM's
    /// moderate intensity (40-59% of reserve; vigorous starts at 60%. Garber
    /// CE, et al. ACSM position stand: quantity and quality of exercise for
    /// developing and maintaining cardiorespiratory, musculoskeletal, and
    /// neuromotor fitness in apparently healthy adults. Med Sci Sports Exerc
    /// 2011;43(7):1334-1359; the two bands were confirmed from papers quoting
    /// the stand, not from its own table). It is the band `EasyCardio` plans
    /// for, and for most people it is close to "zone 2" on a percent-of-max
    /// watch (60-70% of maximum), not to zone 2 on a reserve scale. It stands
    /// in for "below the first threshold", which only a lab test finds
    /// (Iannetta 2020, in the type comment): if you can't talk in full
    /// sentences you are above easy, whatever the number says (Reed JL, Pipe
    /// AL. The talk test: a useful tool for prescribing and monitoring
    /// exercise intensity. Curr Opin Cardiol 2014;29(5):475-480).
    public static let easyReserveLower = 0.40
    public static let easyReserveUpper = 0.60

    /// Resting heart rate assumed when none is known (the Watch on its own,
    /// before the phone has sent its zones): a typical adult value, so the
    /// Watch can stay on Tensile's reserve scale. The app's choice; the phone's
    /// measured resting rate replaces it at the next sync.
    public static let standInResting = 60.0

    /// The easy band from resting and maximum heart rate (40-60% of reserve).
    public static func easyBand(resting: Double, maximum: Double) -> HeartRateBand {
        let reserve = max(0, maximum - resting)
        return HeartRateBand(lower: resting + easyReserveLower * reserve, upper: resting + easyReserveUpper * reserve)
    }

    /// Maximum heart rate from age: 208 − 0.7 × age (Tanaka H, Monahan KD,
    /// Seals DR. Age-predicted maximal heart rate revisited. J Am Coll Cardiol
    /// 2001;37:153-156), the formula `HeartRateProfile.maxHeartRate` uses.
    /// Off by about 10 bpm (1 SD) for one person.
    public static func estimatedMaximum(age: Int) -> Double {
        208 - 0.7 * Double(age)
    }

    // MARK: Building a scheme

    /// Tensile's zones, by heart-rate reserve.
    public static func reserve(resting: Double, maximum: Double) -> HeartRateZoneScheme {
        let reserve = maximum - resting
        let edges = reserveFractions.map { resting + $0 * reserve }
        return HeartRateZoneScheme(
            kind: .reserve, floor: edges[0], boundaries: Array(edges.dropFirst()),
            reserveBasis: ReserveBasis(resting: resting, maximum: maximum),
            easyBand: easyBand(resting: resting, maximum: maximum)
        )
    }

    /// Tensile's zones from age alone, for a Watch that has heard nothing from
    /// the phone and has no zones in Health: the maximum from age and the
    /// stand-in resting rate. It was percent of maximum until the option was
    /// dropped (evidence audit, 17 Nov 2026), so the Watch never shows a
    /// second scale.
    public static func ageEstimate(age: Int) -> HeartRateZoneScheme {
        reserve(resting: standInResting, maximum: estimatedMaximum(age: age))
    }

    /// Apple Health's zones. `boundaries` are where zones 2-5 start; `floor` is
    /// zone 1's lower limit when Health gives one. Nil unless there are exactly
    /// four usable boundaries (five zones, which is what the app draws).
    public static func appleHealth(floor: Double?, boundaries: [Double], easyBand: HeartRateBand) -> HeartRateZoneScheme? {
        guard boundaries.count == zoneCount - 1, let valid = validated(boundaries) else { return nil }
        let usableFloor = floor.flatMap { $0 > 0 && $0 < valid[0] ? $0 : nil }
        return HeartRateZoneScheme(kind: .appleHealth, floor: usableFloor, boundaries: valid, easyBand: easyBand)
    }

    /// Typed limits: where each of zones 1-5 starts, in bpm. Nil unless there
    /// are five, rising by at least 1 bpm each, inside `plausibleRange`.
    public static func custom(starts: [Double], easyBand: HeartRateBand) -> HeartRateZoneScheme? {
        guard starts.count == zoneCount, let valid = validated(starts) else { return nil }
        return HeartRateZoneScheme(kind: .custom, floor: valid[0], boundaries: Array(valid.dropFirst()), easyBand: easyBand)
    }

    /// The app draws five zones.
    public static let zoneCount = 5

    /// Heart rates a limit may take, in bpm. The app's choice, wide enough for
    /// any adult: no one's zone limit sits below a slow resting rate or above
    /// the highest maximum heart rates on record.
    public static let plausibleRange = 40.0...230.0

    /// The limits if they rise by at least 1 bpm and sit inside `plausibleRange`.
    public static func validated(_ limits: [Double]) -> [Double]? {
        guard !limits.isEmpty, limits.allSatisfy({ $0.isFinite && plausibleRange.contains($0) }) else { return nil }
        for (lower, upper) in zip(limits, limits.dropFirst()) where upper - lower < 1 { return nil }
        return limits
    }

    // MARK: Reading a heart rate

    /// Zone 1-5 for a heart rate, or nil below zone 1. A heart rate exactly on
    /// a limit belongs to the zone that starts there.
    public func zone(for bpm: Double) -> Int? {
        if let reserveBasis { return Self.reserveZone(bpm, basis: reserveBasis) }
        if let floor, bpm < floor { return nil }
        var zone = 1
        for edge in boundaries where bpm >= edge { zone += 1 }
        return zone
    }

    /// `HeartRateProfile.zone`, step for step, so a `reserve` scheme never
    /// disagrees with strain's zone minutes by a rounding error at a limit.
    private static func reserveZone(_ bpm: Double, basis: ReserveBasis) -> Int? {
        let reserve = basis.maximum - basis.resting
        guard reserve > 0 else { return nil }
        let fraction = min(1, max(0, (bpm - basis.resting) / reserve))
        return reserveZone(fraction: fraction)
    }

    /// Zone 1-5 for a fraction of heart-rate reserve (zone 1 from 50%, one
    /// zone per 10%), with a little slack so a heart rate exactly on a limit
    /// lands in the zone that starts there: 133 bpm at a limit of 133.0 came
    /// out as 0.59999… of reserve and fell a zone short. `HeartRateProfile`
    /// (strain) uses this too, so the two never disagree. Foundation only:
    /// this file is also compiled into the Watch app.
    public static func reserveZone(fraction: Double) -> Int? {
        let slack = 1e-9
        guard fraction >= 0.5 - slack else { return nil }
        return min(5, max(1, Int((fraction - 0.5) / 0.1 + slack) + 1))
    }

    /// The bpm range of zone 1-5 (`zone` outside that gives nil). Zone 1 starts
    /// at 0 when there is no floor; the top zone ends at `HeartRateBand.noUpperLimit`.
    public func band(forZone zone: Int) -> HeartRateBand? {
        guard zone >= 1, zone <= boundaries.count + 1 else { return nil }
        let lower = zone == 1 ? (floor ?? 0) : boundaries[zone - 2]
        let upper = zone <= boundaries.count ? boundaries[zone - 1] : HeartRateBand.noUpperLimit
        return HeartRateBand(lower: lower, upper: upper)
    }

    /// "120–133", "under 133" or "171+" for zone 1-5.
    public func rangeText(forZone zone: Int) -> String {
        band(forZone: zone)?.text ?? "–"
    }

    // MARK: Minutes in each zone

    /// Gaps between readings longer than this count for nothing, and one
    /// reading stands for at most `maxMinutesPerSample`: the same handling as
    /// `StrainCalculator.maxSampleGap` and `.maxMinutesPerSample` (a test
    /// holds the two pairs equal).
    public static let maxSampleGap: TimeInterval = 10 * 60
    public static let maxMinutesPerSample = 2.0

    /// Minutes in zones 1-5 (index 0 = zone 1) from heart-rate readings: each
    /// reading stands for the time to the next one, as in
    /// `StrainCalculator.dailyStrain`.
    public func zoneMinutes(_ readings: [(date: Date, bpm: Double)]) -> [Double] {
        let sorted = readings.sorted { $0.date < $1.date }
        var minutes = Array(repeating: 0.0, count: boundaries.count + 1)
        for (current, next) in zip(sorted, sorted.dropFirst()) {
            let gap = next.date.timeIntervalSince(current.date)
            guard gap > 0, gap <= Self.maxSampleGap else { continue }
            guard let zone = zone(for: current.bpm), zone <= minutes.count else { continue }
            minutes[zone - 1] += min(gap / 60, Self.maxMinutesPerSample)
        }
        return minutes
    }
}
