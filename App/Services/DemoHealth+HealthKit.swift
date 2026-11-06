import Foundation
import HealthKit
import AppCore

/// HealthKit identifiers → demo metrics, for the demo-mode branches in
/// `HealthKitClient` (`DemoHealth`). Anything not listed has no demo data.
nonisolated extension DemoHealth {
    static func metric(_ identifier: HKQuantityTypeIdentifier) -> Metric? {
        switch identifier {
        case .restingHeartRate: .restingHeartRate
        case .heartRateVariabilitySDNN: .hrv
        case .walkingHeartRateAverage: .walkingHeartRate
        case .heartRateRecoveryOneMinute: .heartRateRecovery
        case .oxygenSaturation: .oxygenSaturation
        case .respiratoryRate: .respiratoryRate
        case .appleSleepingWristTemperature: .wristTemperature
        case .appleSleepingBreathingDisturbances: .breathingDisturbances
        case .vo2Max: .vo2Max
        case .stepCount: .steps
        case .distanceWalkingRunning: .distanceKm
        case .flightsClimbed: .flights
        case .activeEnergyBurned: .activeEnergy
        case .basalEnergyBurned: .basalEnergy
        case .timeInDaylight: .daylightMinutes
        case .appleExerciseTime: .exerciseMinutes
        case .bodyMass: .bodyMass
        case .bodyFatPercentage: .bodyFat
        case .bodyMassIndex: .bmi
        case .leanBodyMass: .leanMass
        case .height: .height
        case .bloodPressureSystolic: .systolic
        case .bloodPressureDiastolic: .diastolic
        case .dietaryEnergyConsumed: .dietaryEnergy
        case .dietaryProtein: .protein
        case .dietaryCarbohydrates: .carbs
        case .dietaryFatTotal: .fat
        case .dietaryFiber: .fiber
        case .dietaryWater: .water
        case .dietaryCaffeine: .caffeine
        case .numberOfAlcoholicBeverages: .alcoholicDrinks
        case .dietaryVitaminC: .vitaminC
        case .dietaryVitaminD: .vitaminD
        case .dietaryZinc: .zinc
        case .dietaryIron: .iron
        case .dietaryMagnesium: .magnesium
        case .dietaryPotassium: .potassium
        case .dietarySodium: .sodium
        case .dietaryCalcium: .calcium
        case .dietaryVitaminB12: .vitaminB12
        case .dietaryFolate: .folate
        case .dietaryVitaminA: .vitaminA
        case .dietarySelenium: .selenium
        default: nil
        }
    }
}
