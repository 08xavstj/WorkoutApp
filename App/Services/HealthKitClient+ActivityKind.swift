import AppCore
import HealthKit

nonisolated extension HealthKitClient {
    /// The calendar's kind for a Health workout: Tensile's own activity when
    /// it saved one, else from HealthKit's activity type.
    static func activityKind(for type: HKWorkoutActivityType, tensile: CardioActivity?) -> ActivityKind {
        if let tensile { return ActivityKind.of(tensile) }
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: return .lifting
        case .running: return .run
        case .walking, .hiking: return .walk
        case .cycling, .handCycling: return .ride
        case .swimming, .swimBikeRun: return .swim
        case .rowing, .elliptical, .stairClimbing, .stairs, .stepTraining, .highIntensityIntervalTraining,
             .mixedCardio, .crossTraining, .jumpRope, .kickboxing, .boxing, .cardioDance, .socialDance:
            return .otherCardio
        case .soccer, .basketball, .tennis, .hockey, .squash, .badminton, .pickleball, .tableTennis, .volleyball,
             .discSports, .climbing, .americanFootball, .australianFootball, .baseball, .softball, .cricket,
             .handball, .lacrosse, .rugby, .racquetball, .golf, .martialArts, .wrestling, .fencing:
            return .sport
        case .crossCountrySkiing, .downhillSkiing, .snowboarding, .skatingSports, .snowSports: return .snow
        default: return .other
        }
    }
}
