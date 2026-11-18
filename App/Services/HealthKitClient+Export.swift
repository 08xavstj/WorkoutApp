import AppCore
import Foundation
import HealthKit

nonisolated extension HealthKitClient {
    /// Every cardio workout and sport in Apple Health (strength left out: the
    /// sets file covers logged lifting), oldest first, for the cardio CSV.
    /// Average and maximum heart rate are the workout's own statistics.
    @concurrent
    func cardioExportRows(since start: Date = .distantPast) async throws -> [CardioExportRow] {
        if let demo = DemoHealth.active { return demo.cardioExportRows() }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let strengthTypes: [HKWorkoutActivityType] = [.traditionalStrengthTraining, .functionalStrengthTraining]
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return try await descriptor.result(for: store).compactMap { workout in
            guard !strengthTypes.contains(workout.workoutActivityType) else { return nil }
            let distance = Self.workoutDistanceTypes.lazy
                .compactMap { workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }
                .first { $0 > 0 }
            let heart = workout.statistics(for: HKQuantityType(.heartRate))
            let activity = (workout.metadata?[Self.watchCardioMetadataKey] as? String).flatMap(CardioActivity.init(rawValue:))
            return CardioExportRow(
                start: workout.startDate,
                type: activity?.title ?? Self.name(for: workout.workoutActivityType),
                source: workout.device?.name ?? workout.sourceRevision.source.name,
                durationSeconds: workout.duration,
                distanceMeters: distance,
                averageBpm: heart?.averageQuantity()?.doubleValue(for: bpm),
                maximumBpm: heart?.maximumQuantity()?.doubleValue(for: bpm),
                elevationGainMeters: (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter())
            )
        }
    }
}

nonisolated extension DemoHealth {
    /// The demo's runs and rides, with heart rate from its made-up day.
    func cardioExportRows() -> [CardioExportRow] {
        cardio.filter { $0.end <= now }.sorted { $0.start < $1.start }.map { workout in
            let readings = heartRate(from: workout.start, to: workout.end).map(\.bpm)
            return CardioExportRow(
                start: workout.start, type: workout.name, source: "Apple Watch",
                durationSeconds: workout.end.timeIntervalSince(workout.start),
                distanceMeters: workout.km.map { $0 * 1000 },
                averageBpm: readings.isEmpty ? nil : readings.reduce(0, +) / Double(readings.count),
                maximumBpm: readings.max()
            )
        }
    }
}
