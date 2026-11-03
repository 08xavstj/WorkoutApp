import Foundation
import HealthKit
import AppCore

nonisolated extension HealthKitClient {
    /// Calories burned inside workouts, summed per day for the last `days`
    /// days (today included), from each workout's own energy total. Days with
    /// no workout are left out. This is the "exercise energy" in energy
    /// availability (`EnergyAvailability`); everyday movement isn't counted,
    /// as the IOC definition intends. Workouts without an energy total (some
    /// logged sessions) count as zero, which makes the estimate err high.
    @concurrent
    func workoutEnergyPerDay(days: Int) async throws -> [DatedValue] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let energyType = HKQuantityType(.activeEnergyBurned)
        do {
            var byDay: [Date: Double] = [:]
            for workout in try await descriptor.result(for: store) {
                let kcal = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                byDay[calendar.startOfDay(for: workout.startDate), default: 0] += kcal
            }
            return byDay.keys.sorted().map { DatedValue(date: $0, value: byDay[$0] ?? 0) }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }
}
