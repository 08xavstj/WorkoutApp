import HealthKit
#if os(iOS)
import AppCore
#endif

// How each cardio activity is saved in Apple Health. Shared by the iPhone app
// (which starts one on the Watch, `WatchSync.startCardioOnWatch`) and the
// Watch app (which records it, `WatchCardioModel`), so the two always agree
// on which configuration means which activity.

extension CardioActivity {
    /// The Apple Health workout type the activity is saved as.
    nonisolated var healthType: HKWorkoutActivityType {
        switch self {
        case .outdoorRun, .treadmill: .running
        case .outdoorWalk: .walking
        case .hiking: .hiking
        case .outdoorCycle, .indoorCycle: .cycling
        case .rower: .rowing
        case .elliptical: .elliptical
        case .stairs: .stairClimbing
        case .hiit: .highIntensityIntervalTraining
        case .squash: .squash
        case .badminton: .badminton
        case .tennis: .tennis
        case .pickleball: .pickleball
        case .tableTennis: .tableTennis
        case .basketball: .basketball
        case .volleyball: .volleyball
        case .indoorSoccer, .outdoorSoccer: .soccer
        case .ultimateFrisbee: .discSports
        case .hockey: .hockey
        case .climbing: .climbing
        case .crossCountrySkiing: .crossCountrySkiing
        case .downhillSkiing: .downhillSkiing
        case .snowboarding: .snowboarding
        case .skating: .skatingSports
        case .other: .other
        }
    }

    nonisolated var locationType: HKWorkoutSessionLocationType {
        switch isOutdoor {
        case .some(true): .outdoor
        case .some(false): .indoor
        case .none: .unknown
        }
    }

    /// The configuration that starts this activity on the Watch.
    nonisolated func workoutConfiguration() -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = healthType
        configuration.locationType = locationType
        return configuration
    }

    /// The activity a configuration stands for: the exact type and place
    /// first (indoor soccer, not soccer outside), else the first with the
    /// type. Nil for a type the cardio mode doesn't record (strength).
    nonisolated static func matching(_ type: HKWorkoutActivityType, location: HKWorkoutSessionLocationType) -> CardioActivity? {
        allCases.first { $0.healthType == type && $0.locationType == location }
            ?? allCases.first { $0.healthType == type }
    }
}
