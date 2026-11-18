import Foundation
import HealthKit
import AppCore

// MARK: - Apple's heart events, walking speed, mindful minutes, waist
//
// docs/research/next-features-2026-11.md: W5 (Apple's high, low and
// irregular-rhythm notifications, one line in the heart section), §4a row 7
// (walking speed, tracked and graded from 60), W11 (mindful minutes from
// Apple's Mindfulness app as a "What affects you" factor; no session of our
// own) and I10 (waist written to and read from Health).
nonisolated extension HealthKitClient {
    /// Added to `readTypes` with one line there.
    static var heartEventAndMobilityReadTypes: Set<HKObjectType> {
        [
            HKCategoryType(.highHeartRateEvent),
            HKCategoryType(.lowHeartRateEvent),
            HKCategoryType(.irregularHeartRhythmEvent),
            HKQuantityType(.walkingSpeed),
            HKCategoryType(.mindfulSession),
            HKQuantityType(.waistCircumference),
        ]
    }

    /// Added to `shareTypes` with one line there: the waist you type in.
    /// HealthKit has no hip type that the app knows of, so hip stays on the
    /// iPhone only.
    static var bodyMeasurementShareTypes: Set<HKSampleType> {
        [HKQuantityType(.waistCircumference)]
    }

    // MARK: Heart events

    /// Apple Watch's high, low and irregular-rhythm notifications in the last
    /// `HeartEvents.windowDays` days (each sample is one notification).
    @concurrent
    func heartEventCounts() async throws -> HeartEvents.Counts {
        if let demo = DemoHealth.active { return demo.heartEventCounts }
        guard isAvailable else { return HeartEvents.Counts(high: 0, low: 0, irregular: 0) }
        let start = Date.now.addingTimeInterval(-Double(HeartEvents.windowDays) * 86_400)
        async let high = eventDates(.highHeartRateEvent, since: start)
        async let low = eventDates(.lowHeartRateEvent, since: start)
        async let irregular = eventDates(.irregularHeartRhythmEvent, since: start)
        return HeartEvents.counts(high: try await high, low: try await low, irregular: try await irregular)
    }

    @concurrent
    private func eventDates(_ identifier: HKCategoryTypeIdentifier, since start: Date) async throws -> [Date] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            return try await descriptor.result(for: store).map(\.startDate)
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    // MARK: Walking speed

    /// The iPhone's walking speed, one average per day in m/s, oldest first.
    @concurrent
    func walkingSpeed(days: Int) async throws -> [DatedValue] {
        if let demo = DemoHealth.active { return demo.walkingSpeedSeries(days: days) }
        guard isAvailable else { return [] }
        return try await dailySeries(.walkingSpeed, unit: HKUnit.meter().unitDivided(by: .second()), days: days, cumulative: false)
    }

    // MARK: Mindful minutes

    /// Minutes of mindful sessions per day (start of day), from any app,
    /// for the last `days` days. Sessions are counted on the day they start.
    @concurrent
    func mindfulMinutesByDay(days: Int) async throws -> [Date: Double] {
        if let demo = DemoHealth.active { return demo.mindfulMinutesByDay(days: days) }
        guard isAvailable else { return [:] }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now)) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.mindfulSession), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples: [HKCategorySample]
        do {
            samples = try await descriptor.result(for: store)
        } catch let error as HKError where error.code == .errorNoData {
            return [:]
        }
        var minutes: [Date: Double] = [:]
        for sample in samples {
            let length = max(0, sample.endDate.timeIntervalSince(sample.startDate)) / 60
            minutes[calendar.startOfDay(for: sample.startDate), default: 0] += min(length, 180)
        }
        return minutes
    }

    // MARK: Waist

    /// Saves a typed waist to Health (centimetres), tagged so it isn't read back as another app's.
    @concurrent
    func saveWaist(centimeters: Double, date: Date) async throws {
        if DemoHealth.active != nil { return }
        guard isAvailable else { return }
        let sample = HKQuantitySample(
            type: HKQuantityType(.waistCircumference),
            quantity: HKQuantity(unit: .meterUnit(with: .centi), doubleValue: centimeters),
            start: date, end: date,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        try await store.save(sample)
    }

    /// Waist readings other apps or the Health app saved, oldest first, in
    /// cm (this app's own are left out: they're already in the store).
    @concurrent
    func healthWaistReadings(days: Int = 730) async throws -> [WaistReadings.Reading] {
        if let demo = DemoHealth.active { return demo.healthWaistReadings }
        guard isAvailable else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.waistCircumference), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples: [HKQuantitySample]
        do {
            samples = try await descriptor.result(for: store)
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
        let own = HKSource.default().bundleIdentifier
        return samples
            .filter { $0.sourceRevision.source.bundleIdentifier != own }
            .map { WaistReadings.Reading(date: $0.startDate, centimeters: $0.quantity.doubleValue(for: .meterUnit(with: .centi)), fromHealth: true) }
    }
}
