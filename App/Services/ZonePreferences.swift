import Foundation
import AppCore

/// Settings › Training › Heart-rate zones: which zone scheme the app shows
/// (`HeartRateZoneScheme`), the limits typed for "Custom", and Apple Health's
/// zones as last read. Kept in UserDefaults; screens ask `resolution(profile:)`.
///
/// Day strain never reads this: it stays on heart-rate reserve
/// (`StrainCalculator`), whatever is chosen here.
nonisolated enum ZonePreferences {
    /// `HeartRateZoneScheme.Kind.rawValue`; missing means Tensile's zones.
    static let kindKey = "heartZoneKind"
    /// Five numbers: where the typed zones 1-5 start, in bpm.
    static let customKey = "heartZoneCustomStarts"
    private static let appleKey = "heartZoneAppleZones"

    /// Apple Health's zones, kept so a screen can draw them without waiting for Health.
    nonisolated struct AppleZones: Codable, Sendable, Equatable {
        var floor: Double?
        var boundaries: [Double]
        /// True when the person typed them in Apple's settings.
        var setByUser: Bool
    }

    static var kind: HeartRateZoneScheme.Kind {
        get { UserDefaults.standard.string(forKey: kindKey).flatMap(HeartRateZoneScheme.Kind.init(rawValue:)) ?? .reserve }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: kindKey) }
    }

    static var customStarts: [Double]? {
        get { UserDefaults.standard.array(forKey: customKey) as? [Double] }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: customKey)
            } else {
                UserDefaults.standard.removeObject(forKey: customKey)
            }
        }
    }

    static var appleZones: AppleZones? {
        get {
            UserDefaults.standard.data(forKey: appleKey).flatMap { try? JSONDecoder().decode(AppleZones.self, from: $0) }
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: appleKey)
            } else {
                UserDefaults.standard.removeObject(forKey: appleKey)
            }
        }
    }

    /// The scheme in use for `profile`: the chosen one, or Tensile's when the
    /// chosen one can't be built (`HeartRateZoneScheme.resolve`).
    static func resolution(profile: HeartRateProfile) -> HeartRateZoneScheme.Resolution {
        let apple = appleZones
        return HeartRateZoneScheme.resolve(
            kind: kind, profile: profile,
            appleFloor: apple?.floor, appleBoundaries: apple?.boundaries, customStarts: customStarts
        )
    }

    /// Asks Apple Health for its zones and keeps the answer. Skipped (nil)
    /// unless Apple Health's zones are chosen or `force` is set.
    @discardableResult
    static func refreshAppleZones(health: HealthKitClient?, force: Bool = false) async -> HealthZoneReading? {
        guard let health, force || kind == .appleHealth else { return nil }
        let reading = await health.preferredHeartRateZones()
        switch reading {
        case let .zones(floor, boundaries, setByUser):
            appleZones = AppleZones(floor: floor, boundaries: boundaries, setByUser: setByUser)
        case .none, .unsupported:
            appleZones = nil
        case .failed:
            break
        }
        return reading
    }

    /// The scheme in use after checking Apple Health again when its zones are
    /// the chosen ones (they change as Health's resting and maximum heart rate do).
    static func current(profile: HeartRateProfile, health: HealthKitClient?) async -> HeartRateZoneScheme.Resolution {
        await refreshAppleZones(health: health)
        return resolution(profile: profile)
    }
}
