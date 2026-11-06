import Foundation
import AppCore

/// Supplements marked as taken in the app (`MedicationStore`), as nutrient
/// amounts for the vitamins page (`Micronutrients.supplementAverages`).
nonisolated enum SupplementNutrients {
    /// Days averaged, the same window as the food log.
    static let days = 7

    /// Doses taken in the last `days` days, today included.
    static func takenDoses(now: Date = .now, calendar: Calendar = .current) -> [Micronutrients.SupplementDose] {
        let taken = MedicationStore.takenLog()
        var doses: [Micronutrients.SupplementDose] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            for dose in MedicationStore.doses(on: day, calendar: calendar) where taken[dose.id] != nil {
                doses.append(Micronutrients.SupplementDose(name: dose.name, dose: dose.dose))
            }
        }
        return doses
    }

    /// Daily average per nutrient from taken doses.
    static func dailyAverages(now: Date = .now) -> [Micronutrients.Nutrient: Double] {
        Micronutrients.supplementAverages(takenDoses(now: now), days: days)
    }

    /// Active supplements for a nutrient, e.g. "Vitamin D 2000 IU".
    static func listed(for nutrient: Micronutrients.Nutrient, in medications: [Medication]) -> [Medication] {
        medications.filter { $0.isActive && Micronutrients.supplementNutrient(name: $0.name) == nutrient }
    }
}
