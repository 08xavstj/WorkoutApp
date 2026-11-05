import Foundation
import HealthKit
import AppCore

/// Sound exposure from Apple Health (docs/research/watch-features.md §1.6):
/// `headphoneAudioExposure` (iPhone and Apple Watch, iOS 13+) and
/// `environmentalAudioExposure` (Apple Watch). Each sample is an A-weighted
/// equivalent continuous level over its own duration
/// (`HKQuantityAggregationStyle.discreteEquivalentContinuousLevel`), so the
/// weekly dose is the energy-weighted sum in `HearingExposure`.
nonisolated extension HealthKitClient {
    /// Headphone sound over the last 7 days against the WHO/ITU weekly
    /// budget (80 dB(A) for 40 h; `HearingExposure`). Nil when Health has no
    /// headphone levels in the week.
    @concurrent
    func weeklyHeadphoneExposure() async throws -> HearingExposure.Result? {
        let samples = try await audioExposureSamples(.headphoneAudioExposure, days: 7)
        guard !samples.isEmpty else { return nil }
        return HearingExposure.weekly(samples)
    }

    /// Raw dB(A) samples of one exposure type from the last `days` days, in
    /// time order. Hours are each sample's own duration.
    @concurrent
    func audioExposureSamples(_ identifier: HKQuantityTypeIdentifier, days: Int) async throws -> [HearingExposure.Sample] {
        guard isAvailable else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let unit = HKUnit.decibelAWeightedSoundPressureLevel()
        do {
            return try await descriptor.result(for: store).map { sample in
                HearingExposure.Sample(
                    start: sample.startDate,
                    level: sample.quantity.doubleValue(for: unit),
                    hours: sample.endDate.timeIntervalSince(sample.startDate) / 3600
                )
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }
}
