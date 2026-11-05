import Foundation
import HealthKit
import AppCore

/// Samples the app writes to Apple Health beyond workouts and blood pressure:
/// paced-breathing sessions (mindful minutes), the morning mood (state of
/// mind) and the session RPE as a workout effort score (docs/research/competitors.md item 7).
nonisolated extension HealthKitClient {
    /// Metadata key on dietary samples an earlier version of the app wrote as
    /// AI meal estimates. The app no longer writes them, but `estimateOnlyDays`
    /// still finds the old ones so `EstimatedIntake` can down-weight those days.
    static let estimateMetadataKey = "TensileEstimate"

    // MARK: Mindful minutes

    /// Saves a breathing session as a mindful-minutes sample.
    @concurrent
    func saveMindfulSession(start: Date, end: Date) async throws {
        let sample = HKCategorySample(
            type: HKCategoryType(.mindfulSession),
            value: HKCategoryValue.notApplicable.rawValue,
            start: start, end: max(end, start.addingTimeInterval(1)),
            metadata: ["TensileBreathingPace": "\(Int(PacedBreathing.breathsPerMinute.rounded())) breaths/min"]
        )
        try await store.save(sample)
    }

    // MARK: State of mind (iOS 18)

    /// Writes the 1-5 check-in mood as a daily-mood state of mind, so the
    /// Health app's mental-wellbeing view sees it (competitors.md §1g).
    /// Valence runs −1...1; 1 → −0.8, 3 → 0, 5 → +0.8 (app mapping).
    @concurrent
    func saveStateOfMind(mood: Int, date: Date) async throws {
        let clamped = max(1, min(5, mood))
        let valence = Double(clamped - 3) * 0.4
        let label: HKStateOfMind.Label = switch clamped {
        case 1: .sad
        case 2: .discouraged
        case 3: .indifferent
        case 4: .content
        default: .happy
        }
        let sample = HKStateOfMind(date: date, kind: .dailyMood, valence: valence, labels: [label], associations: [])
        try await store.save(sample)
    }

    // MARK: Workout effort score (iOS 18)

    /// Writes the session RPE (1-10) as a workout effort score, related to
    /// the HKWorkout the app saved for the same session when one is found
    /// (so Apple's Training Load counts lifting; competitors.md §1g), else as
    /// a standalone sample over the session's time with the RPE in metadata.
    @concurrent
    func saveWorkoutEffort(score: Int, start: Date, end: Date) async throws {
        let clamped = Double(max(1, min(10, score)))
        let sample = HKQuantitySample(
            type: HKQuantityType(.workoutEffortScore),
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: clamped),
            start: start, end: max(end, start.addingTimeInterval(1)),
            metadata: ["TensileSessionRPE": clamped]
        )
        try await store.save(sample)
        guard let workout = try await ownWorkout(start: start, end: end) else { return }
        // Linking can fail (e.g. the workout was saved by another builder); the sample stands on its own then.
        _ = try? await store.relateWorkoutEffortSample(sample, with: workout, activity: nil)
    }

    /// The workout this app saved closest to `start`, within a minute.
    private func ownWorkout(start: Date, end: Date) async throws -> HKWorkout? {
        let predicate = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-60), end: end.addingTimeInterval(60))
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let ownBundle = Bundle.main.bundleIdentifier
        return try await descriptor.result(for: store)
            .filter { $0.sourceRevision.source.bundleIdentifier == ownBundle }
            .min { abs($0.startDate.timeIntervalSince(start)) < abs($1.startDate.timeIntervalSince(start)) }
    }

    // MARK: Estimated meals from earlier versions

    /// Days in the last `days` (today included) whose calorie entries were
    /// all this app's old AI estimates: no Cronometer or other source logged anything.
    @concurrent
    func estimateOnlyDays(days: Int) async throws -> Set<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.dietaryEnergyConsumed), predicate: predicate)],
            sortDescriptors: []
        )
        var estimateDays = Set<Date>()
        var otherDays = Set<Date>()
        do {
            for sample in try await descriptor.result(for: store) {
                let day = calendar.startOfDay(for: sample.startDate)
                if (sample.metadata?[Self.estimateMetadataKey] as? Bool) == true {
                    estimateDays.insert(day)
                } else {
                    otherDays.insert(day)
                }
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
        return estimateDays.subtracting(otherDays)
    }
}
