import Foundation

/// The zone scheme from the app's own types (`HeartRateProfile`,
/// `HeartRateSample`). Kept apart from `HeartRateZoneScheme.swift`, which the
/// Watch app compiles without the rest of AppCore.
extension HeartRateZoneScheme {
    /// The scheme the user asked for and the one in use. They differ when
    /// Apple Health has no zones to give (iOS 26, or none set up) or the typed
    /// limits are missing or invalid: Tensile's zones stand in.
    public struct Resolution: Sendable, Equatable {
        public var requested: Kind
        public var scheme: HeartRateZoneScheme

        public init(requested: Kind, scheme: HeartRateZoneScheme) {
            self.requested = requested
            self.scheme = scheme
        }

        /// True when the requested scheme couldn't be built and Tensile's is shown.
        public var fellBack: Bool { scheme.kind != requested }
    }

    /// Tensile's zones for a profile: the zones `HeartRateProfile.zone` gives.
    public static func tensile(profile: HeartRateProfile) -> HeartRateZoneScheme {
        reserve(resting: profile.restingHeartRate, maximum: profile.maxHeartRate)
    }

    /// Builds the chosen scheme, falling back to Tensile's when it can't be built.
    /// - Parameters:
    ///   - appleFloor: zone 1's lower limit from Apple Health, if it has one.
    ///   - appleBoundaries: where Health's zones 2-5 start; nil when Health gave none.
    ///   - customStarts: where the typed zones 1-5 start.
    public static func resolve(
        kind: Kind,
        profile: HeartRateProfile,
        appleFloor: Double? = nil,
        appleBoundaries: [Double]? = nil,
        customStarts: [Double]? = nil
    ) -> Resolution {
        let fallback = tensile(profile: profile)
        // One easy band whatever the zones: it is defined on reserve, not on a zone number.
        let easy = fallback.easyBand
        let scheme: HeartRateZoneScheme? = switch kind {
        case .reserve: fallback
        case .percentOfMax: percentOfMax(maximum: profile.maxHeartRate, resting: profile.restingHeartRate)
        case .appleHealth: appleBoundaries.flatMap { appleHealth(floor: appleFloor, boundaries: $0, easyBand: easy) }
        case .custom: customStarts.flatMap { custom(starts: $0, easyBand: easy) }
        }
        return Resolution(requested: kind, scheme: scheme ?? fallback)
    }

    /// Minutes in zones 1-5 from heart-rate samples (`zoneMinutes(_:)`). For
    /// Tensile's scheme this equals `StrainCalculator.dailyStrain(...).zoneMinutes`.
    public func minutes(_ heartRate: [HeartRateSample]) -> [Double] {
        zoneMinutes(heartRate.map { (date: $0.date, bpm: $0.bpm) })
    }
}
