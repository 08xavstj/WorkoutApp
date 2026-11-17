import Foundation
import AppCore

/// Supplements marked as taken in the app (`MedicationStore`), as nutrient
/// amounts for the vitamins page (`Micronutrients.supplementAverages`).
nonisolated enum SupplementNutrients {
    /// Days averaged, the same window as the food log.
    static let days = 7

    /// Doses taken in the last `days` days, today included. Counted by
    /// medication and day, not by the exact reminder time: a dose's id carries
    /// its time, so editing the time would otherwise drop the days before it.
    static func takenDoses(now: Date = .now, calendar: Calendar = .current) -> [Micronutrients.SupplementDose] {
        let takenIDs = MedicationStore.takenLog().keys
        let medications = MedicationStore.medications()
        var doses: [Micronutrients.SupplementDose] = []
        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let day = calendar.startOfDay(for: date)
            for medication in medications where medication.isDue(on: day, calendar: calendar) {
                let prefix = Dose.dayPrefix(medicationID: medication.id, day: day)
                let count = takenIDs.filter { $0.hasPrefix(prefix) }.count
                for _ in 0..<count {
                    doses.append(Micronutrients.SupplementDose(name: medication.name, dose: medication.dose))
                }
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
