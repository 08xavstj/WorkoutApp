import Foundation
import HealthKit
import AppCore

/// What Apple Health said about the person's heart-rate zones.
nonisolated enum HealthZoneReading: Sendable, Equatable {
    /// iOS 26, or an app built with the iOS 26 SDK: Health has no zones to ask for.
    case unsupported
    /// iOS 27, and Health has no zones for this person.
    case none
    /// The read threw. Zones read earlier stay in use.
    case failed
    /// Where zones 2 and up start, in bpm; zone 1's lower limit when Health
    /// gives one; and whether the person typed them (else Health worked them out).
    case zones(floor: Double?, boundaries: [Double], setByUser: Bool)
}

nonisolated extension HealthKitClient {
    /// The heart-rate zones Apple Health holds: the ones typed in the Watch
    /// app (Workout › Heart Rate Zones), else the ones Health works out.
    ///
    /// iOS 27 only: `HKHealthStore.preferredWorkoutZoneConfiguration(for:)`
    /// (developer.apple.com/documentation/healthkit/hkhealthstore/preferredworkoutzoneconfiguration(for:)).
    /// A configuration is built from "the upper boundaries of each zone … The
    /// first zone has no lower bound, and the last zone has no upper bound"
    /// (`HKWorkoutZoneConfiguration.init(quantityType:zoneBoundaries:)`), so
    /// zone 1 normally has no floor here. Apple doesn't publish the
    /// percentages behind the zones it works out; its user guide says only
    /// that they are "a percentage of your maximum heart rate" (Apple Watch
    /// User Guide, "View Heart Rate Zones", watchOS 27).
    @concurrent
    func preferredHeartRateZones() async -> HealthZoneReading {
        if DemoHealth.active != nil { return DemoHealth.heartRateZones }
        guard isAvailable else { return .unsupported }
        #if compiler(>=6.4)
        if #available(iOS 27, watchOS 27, *) {
            let configuration: HKWorkoutZoneConfiguration?
            do {
                configuration = try await store.preferredWorkoutZoneConfiguration(for: HKQuantityType(.heartRate))
            } catch {
                return .failed
            }
            guard let configuration else { return .none }
            let unit = HKUnit.count().unitDivided(by: .minute())
            let zones = configuration.zones.sorted { $0.index < $1.index }
            guard zones.count >= 2 else { return .none }
            var boundaries: [Double] = []
            // Each zone starts where it says, or where the one below ends.
            for (lower, upper) in zip(zones, zones.dropFirst()) {
                guard let edge = upper.minimum ?? lower.maximum, edge.is(compatibleWith: unit) else { return .none }
                boundaries.append(edge.doubleValue(for: unit))
            }
            var floor: Double?
            if let minimum = zones[0].minimum, minimum.is(compatibleWith: unit) {
                floor = minimum.doubleValue(for: unit)
            }
            return .zones(floor: floor, boundaries: boundaries, setByUser: configuration.source == .user)
        }
        #endif
        return .unsupported
    }
}

nonisolated extension DemoHealth {
    /// Demo mode's "Apple Health" zones: made-up limits for the demo's
    /// 34-year-old (60, 70, 80 and 90% of a 52-to-184 reserve), so the
    /// option has something to show in the screenshot tour.
    static var heartRateZones: HealthZoneReading {
        .zones(floor: nil, boundaries: [131, 144, 158, 171], setByUser: false)
    }
}
