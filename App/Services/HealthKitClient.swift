import Foundation
import HealthKit
import AppCore

/// All HealthKit reads and writes. Every method runs off the main actor and
/// returns plain AppCore values, so no HealthKit objects cross actors.
// HKHealthStore is documented as thread-safe, hence @unchecked.
nonisolated final class HealthKitClient: @unchecked Sendable {
    let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.bodyMass),
            HKQuantityType(.height),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.vo2Max),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),
            HKQuantityType(.dietaryFiber),
            HKQuantityType(.dietaryWater),
            HKObjectType.workoutType(),
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex)
        ]
    }

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType()]
    }

    @concurrent
    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    /// Age and sex from the Health profile, if the user allowed it.
    func profileCharacteristics() -> (age: Int?, sex: BiologicalSex?) {
        var age: Int?
        if let birthday = try? store.dateOfBirthComponents(),
           let date = Calendar.current.date(from: birthday) {
            age = Calendar.current.dateComponents([.year], from: date, to: .now).year
        }
        var sex: BiologicalSex?
        switch (try? store.biologicalSex())?.biologicalSex {
        case .some(.female): sex = .female
        case .some(.male): sex = .male
        default: sex = nil
        }
        return (age, sex)
    }

    // MARK: - Heart rate

    @concurrent
    func heartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        return try await descriptor.result(for: store).map {
            HeartRateSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit))
        }
    }

    /// Heart rate averaged per minute: at most 1,440 values a day, however often
    /// the watch records. Much lighter than raw samples for multi-day ranges.
    @concurrent
    func heartRatePerMinute(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.heartRate), predicate: predicate),
            options: .discreteAverage,
            anchorDate: Calendar.current.startOfDay(for: start),
            intervalComponents: DateComponents(minute: 1)
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        do {
            return try await descriptor.result(for: store).statistics().compactMap { statistics in
                statistics.averageQuantity().map { HeartRateSample(date: statistics.startDate, bpm: $0.doubleValue(for: unit)) }
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    // MARK: - Nightly vitals

    /// Overnight HRV and daily resting heart rate for each of the last `days` nights.
    ///
    /// HRV for "night D" averages samples from 6 pm on D-1 to noon on D, so it
    /// reflects sleep rather than daytime stress. Returned newest first.
    @concurrent
    func nightlyVitals(days: Int, endingOn day: Date) async throws -> [DailyVitals] {
        let calendar = Calendar.current
        let lastNight = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: lastNight),
              let start = calendar.date(byAdding: .day, value: -days, to: lastNight)?.addingTimeInterval(-6 * 3600)
        else { return [] }

        // HRV samples, bucketed into nights.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let hrvDescriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRateVariabilitySDNN), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let ms = HKUnit.secondUnit(with: .milli)
        var hrvByNight: [Date: [Double]] = [:]
        for sample in try await hrvDescriptor.result(for: store) {
            // Shift by 6 h so 6 pm-midnight counts toward the next morning.
            let shifted = sample.startDate.addingTimeInterval(6 * 3600)
            guard calendar.component(.hour, from: shifted) < 18 else { continue } // drop noon-6 pm
            hrvByNight[calendar.startOfDay(for: shifted), default: []].append(sample.quantity.doubleValue(for: ms))
        }

        // Resting heart rate, one value per day.
        let rhrDescriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.restingHeartRate), predicate: predicate),
            options: .discreteAverage,
            anchorDate: lastNight,
            intervalComponents: DateComponents(day: 1)
        )
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var rhrByDay: [Date: Double] = [:]
        for statistics in try await rhrDescriptor.result(for: store).statistics() {
            if let average = statistics.averageQuantity() {
                rhrByDay[calendar.startOfDay(for: statistics.startDate)] = average.doubleValue(for: bpm)
            }
        }

        let nights = Set(hrvByNight.keys).union(rhrByDay.keys)
        return nights.sorted(by: >).map { night in
            let hrv = hrvByNight[night].map { $0.reduce(0, +) / Double($0.count) }
            return DailyVitals(date: night, hrvMilliseconds: hrv, restingHeartRate: rhrByDay[night])
        }
    }

    // MARK: - Sleep

    /// Sleep samples for the night ending on the morning of `day` (6 pm the day before to 2 pm).
    @concurrent
    func sleepSamples(forNightEnding day: Date) async throws -> [SleepSample] {
        let calendar = Calendar.current
        let morning = calendar.startOfDay(for: day)
        let start = morning.addingTimeInterval(-6 * 3600)
        let end = morning.addingTimeInterval(14 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).compactMap { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            let stage: SleepStage
            switch value {
            case .inBed: stage = .inBed
            case .awake: stage = .awake
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            case .asleepUnspecified: stage = .unspecified
            @unknown default: return nil
            }
            return SleepSample(stage: stage, start: sample.startDate, end: sample.endDate)
        }
    }

    // MARK: - Nutrition (Cronometer and other food loggers write these to Health)

    /// Totals for one calendar day. Values are nil when nothing of that type was logged.
    @concurrent
    func nutrition(on day: Date) async throws -> NutritionDay {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)

        async let calories = dailySum(.dietaryEnergyConsumed, unit: .kilocalorie(), start: start, end: end)
        async let protein = dailySum(.dietaryProtein, unit: .gram(), start: start, end: end)
        async let carbs = dailySum(.dietaryCarbohydrates, unit: .gram(), start: start, end: end)
        async let fat = dailySum(.dietaryFatTotal, unit: .gram(), start: start, end: end)
        async let fiber = dailySum(.dietaryFiber, unit: .gram(), start: start, end: end)
        async let water = dailySum(.dietaryWater, unit: .liter(), start: start, end: end)

        return try await NutritionDay(
            date: start,
            calories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            fiberGrams: fiber,
            waterLiters: water
        )
    }

    /// Most recent body weight in kilograms.
    @concurrent
    func latestBodyMassKg() async throws -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        return try await descriptor.result(for: store).first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    @concurrent
    private func dailySum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async throws -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate),
            options: .cumulativeSum
        )
        do {
            return try await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: unit)
        } catch let error as HKError where error.code == .errorNoData {
            return nil
        }
    }

    // MARK: - Body measurements and series

    /// Most recent value of a quantity (height, body fat, VO2 max...).
    @concurrent
    func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        return try await descriptor.result(for: store).first?.quantity.doubleValue(for: unit)
    }

    /// One value per day for the last `days` days (average, or total when `cumulative`).
    /// Days without data are left out.
    @concurrent
    func dailySeries(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int, cumulative: Bool) async throws -> [DatedValue] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: today),
              let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate),
            options: cumulative ? .cumulativeSum : .discreteAverage,
            anchorDate: today,
            intervalComponents: DateComponents(day: 1)
        )
        do {
            return try await descriptor.result(for: store).statistics().compactMap { statistics in
                let quantity = cumulative ? statistics.sumQuantity() : statistics.averageQuantity()
                guard let quantity else { return nil }
                return DatedValue(date: statistics.startDate, value: quantity.doubleValue(for: unit))
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    /// Average breathing rate during the night ending on the morning of `day`.
    @concurrent
    func overnightRespiratoryRate(forNightEnding day: Date) async throws -> Double? {
        let morning = Calendar.current.startOfDay(for: day)
        let predicate = HKQuery.predicateForSamples(withStart: morning.addingTimeInterval(-6 * 3600), end: morning.addingTimeInterval(12 * 3600))
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.respiratoryRate), predicate: predicate)],
            sortDescriptors: []
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        let values = try await descriptor.result(for: store).map { $0.quantity.doubleValue(for: unit) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Workouts recorded by other apps (Garmin Connect, Strava...) in a time range.
    @concurrent
    func externalWorkouts(from start: Date, to end: Date) async throws -> [ExternalWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let ownBundle = Bundle.main.bundleIdentifier
        let strengthTypes: [HKWorkoutActivityType] = [.traditionalStrengthTraining, .functionalStrengthTraining]
        return try await descriptor.result(for: store).compactMap { workout in
            guard workout.sourceRevision.source.bundleIdentifier != ownBundle else { return nil }
            let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo))
            return ExternalWorkout(
                name: Self.name(for: workout.workoutActivityType),
                isStrength: strengthTypes.contains(workout.workoutActivityType),
                start: workout.startDate,
                end: workout.endDate,
                distanceKm: distance
            )
        }
    }

    /// Step count today, split into steps inside and outside the given windows.
    @concurrent
    func steps(from start: Date, to end: Date, excluding windows: [DateInterval]) async throws -> (total: Double, outside: Double) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.stepCount), predicate: predicate)],
            sortDescriptors: []
        )
        var total = 0.0
        var outside = 0.0
        for sample in try await descriptor.result(for: store) {
            let count = sample.quantity.doubleValue(for: .count())
            total += count
            let middle = sample.startDate.addingTimeInterval(sample.endDate.timeIntervalSince(sample.startDate) / 2)
            if !windows.contains(where: { $0.contains(middle) }) {
                outside += count
            }
        }
        return (total, outside)
    }

    private static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: "Walk"
        case .running: "Run"
        case .cycling: "Ride"
        case .hiking: "Hike"
        case .swimming: "Swim"
        case .rowing: "Row"
        case .elliptical: "Elliptical"
        case .yoga: "Yoga"
        case .highIntensityIntervalTraining: "HIIT"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength"
        case .stairClimbing: "Stairs"
        case .soccer: "Soccer"
        case .basketball: "Basketball"
        case .tennis: "Tennis"
        case .hockey: "Hockey"
        default: "Workout"
        }
    }

    // MARK: - Writing workouts

    /// Saves a finished gym session to Apple Health as Traditional Strength Training.
    @concurrent
    func saveStrengthWorkout(start: Date, end: Date) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }
}

nonisolated struct DatedValue: Sendable, Identifiable, Equatable {
    var date: Date
    var value: Double
    var id: Date { date }
}

nonisolated struct ExternalWorkout: Sendable, Identifiable, Equatable {
    var name: String
    var isStrength: Bool
    var start: Date
    var end: Date
    var distanceKm: Double?
    var id: Date { start }
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}
