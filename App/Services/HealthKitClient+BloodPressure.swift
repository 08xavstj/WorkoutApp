import Foundation
import HealthKit
import AppCore

/// One blood pressure reading from Apple Health (a cuff reading you typed in
/// here, or one a cuff's app saved).
nonisolated struct BloodPressureReading: Sendable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var systolic: Double
    var diastolic: Double
    var source: String
    var arm: String?

    var asCore: HomeBloodPressure.Reading {
        HomeBloodPressure.Reading(date: date, systolic: systolic, diastolic: diastolic)
    }
}

nonisolated extension HealthKitClient {
    static let armMetadataKey = "WorkoutAppArm"

    /// Saves a cuff reading as a blood pressure correlation (and the pulse,
    /// if given, as a resting heart-rate sample).
    @concurrent
    func saveBloodPressure(systolic: Double, diastolic: Double, pulse: Double?, date: Date, arm: String) async throws {
        let mmHg = HKUnit.millimeterOfMercury()
        let metadata: [String: Any] = [Self.armMetadataKey: arm]
        let systolicSample = HKQuantitySample(
            type: HKQuantityType(.bloodPressureSystolic),
            quantity: HKQuantity(unit: mmHg, doubleValue: systolic),
            start: date, end: date, metadata: metadata
        )
        let diastolicSample = HKQuantitySample(
            type: HKQuantityType(.bloodPressureDiastolic),
            quantity: HKQuantity(unit: mmHg, doubleValue: diastolic),
            start: date, end: date, metadata: metadata
        )
        let correlation = HKCorrelation(
            type: HKCorrelationType(.bloodPressure),
            start: date, end: date,
            objects: [systolicSample, diastolicSample],
            metadata: metadata
        )
        try await store.save(correlation)
        if let pulse, pulse > 20 {
            let heartRate = HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: pulse),
                start: date, end: date,
                metadata: [HKMetadataKeyHeartRateMotionContext: HKHeartRateMotionContext.sedentary.rawValue]
            )
            try await store.save(heartRate)
        }
    }

    /// Blood pressure readings from the last `days` days, newest first.
    @concurrent
    func bloodPressureReadings(days: Int) async throws -> [BloodPressureReading] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: HKCorrelationType(.bloodPressure), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let mmHg = HKUnit.millimeterOfMercury()
        let systolicType = HKQuantityType(.bloodPressureSystolic)
        let diastolicType = HKQuantityType(.bloodPressureDiastolic)
        do {
            return try await descriptor.result(for: store).compactMap { correlation in
                guard let systolic = correlation.objects(for: systolicType).first as? HKQuantitySample,
                      let diastolic = correlation.objects(for: diastolicType).first as? HKQuantitySample else { return nil }
                return BloodPressureReading(
                    id: correlation.uuid,
                    date: correlation.startDate,
                    systolic: systolic.quantity.doubleValue(for: mmHg),
                    diastolic: diastolic.quantity.doubleValue(for: mmHg),
                    source: correlation.sourceRevision.source.name,
                    arm: correlation.metadata?[Self.armMetadataKey] as? String
                )
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }
}
