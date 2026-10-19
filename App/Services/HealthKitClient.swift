import Foundation
import HealthKit
import AppCore

/// All HealthKit reads and writes. Every method runs off the main actor and
/// returns plain AppCore values, so no HealthKit objects cross actors.
// HKHealthStore is documented as thread-safe, hence @unchecked.
nonisolated final class HealthKitClient: @unchecked Sendable {
    let store = HKHealthStore()
    /// Beat-to-beat RMSSD for finished nights, so they're read only once.
    private let rmssdCache = RMSSDCache()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            // Beat-to-beat timings (Apple Watch), to compute RMSSD like Garmin does.
            HKSeriesType.heartbeat(),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.bodyMass),
            HKQuantityType(.height),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.vo2Max),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.stepCount),
            // Everything else a Garmin (via Garmin Connect), a scale or a food app may write.
            HKQuantityType(.walkingHeartRateAverage),
            HKQuantityType(.heartRateRecoveryOneMinute),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.bodyTemperature),
            HKQuantityType(.appleSleepingWristTemperature),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.flightsClimbed),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.bodyMassIndex),
            HKQuantityType(.leanBodyMass),
            HKQuantityType(.bloodPressureSystolic),
            HKQuantityType(.bloodPressureDiastolic),
            HKCategoryType(.mindfulSession),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal),
            HKQuantityType(.dietaryFiber),
            HKQuantityType(.dietaryWater),
            HKQuantityType(.dietaryCaffeine),
            HKQuantityType(.numberOfAlcoholicBeverages),
            // Vitamins and minerals (Cronometer writes these).
            HKQuantityType(.dietaryVitaminC),
            HKQuantityType(.dietaryVitaminD),
            HKQuantityType(.dietaryZinc),
            HKQuantityType(.dietaryIron),
            HKQuantityType(.dietaryMagnesium),
            HKQuantityType(.dietaryPotassium),
            HKQuantityType(.dietarySodium),
            HKQuantityType(.dietaryCalcium),
            HKQuantityType(.dietaryVitaminB12),
            HKQuantityType(.dietaryFolate),
            HKQuantityType(.dietaryVitaminA),
            HKQuantityType(.dietarySelenium),
            HKObjectType.workoutType(),
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex)
        ]
    }

    private var shareTypes: Set<HKSampleType> {
        // Heart rate and energy are written by the live workout session (AirPods Pro 3 / chest strap).
        [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
         // Home blood pressure readings you type in.
         HKQuantityType(.bloodPressureSystolic), HKQuantityType(.bloodPressureDiastolic)]
    }

    @concurrent
    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    /// Shows the Health permission sheet again only when there are types the
    /// user hasn't been asked about yet (e.g. after an update adds new stats).
    @concurrent
    func requestAuthorizationIfNeeded() async {
        guard isAvailable,
              let status = try? await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes),
              status == .shouldRequest else { return }
        try? await store.requestAuthorization(toShare: shareTypes, read: readTypes)
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

    /// Raw heart rate in a window, grouped by where it came from
    /// (e.g. "AirPods Pro" via this app vs. "Garmin Connect").
    @concurrent
    func heartRateBySource(from start: Date, to end: Date) async throws -> [HeartRateSource] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        var groups: [String: [HeartRateSample]] = [:]
        var order: [String] = []
        for sample in try await descriptor.result(for: store) {
            let source = sample.sourceRevision.source.name
            let device = sample.device?.name
            let label = device.map { "\($0) (\(source))" } ?? source
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(HeartRateSample(date: sample.startDate, bpm: sample.quantity.doubleValue(for: unit)))
        }
        return order.map { HeartRateSource(name: $0, samples: groups[$0] ?? []) }
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

    /// Overnight HRV as RMSSD (ms) computed from Apple Watch beat-to-beat
    /// recordings taken during each night's main sleep, keyed by the morning.
    /// Empty for watches that don't share beat-to-beat data (e.g. Garmin).
    @concurrent
    func nightlyRMSSD(nights allNights: [SleepNight]) async -> [Date: Double] {
        let today = Calendar.current.startOfDay(for: .now)
        var known = rmssdCache.values(for: allNights.map(\.date))
        // Only nights not read before (today's is always re-read: the watch syncs late).
        let nights = allNights.filter { known[$0.date] == nil || $0.date >= today }
        guard let first = nights.map(\.bedtime).min(), let last = nights.map(\.wake).max() else {
            return known.compactMapValues { $0 }
        }
        let predicate = HKQuery.predicateForSamples(withStart: first, end: last)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.heartbeat(), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await descriptor.result(for: store) else { return known.compactMapValues { $0 } }
        var valuesByNight: [Date: [Double]] = [:]
        for case let series as HKHeartbeatSeriesSample in samples {
            guard let night = nights.first(where: { series.startDate >= $0.bedtime && series.endDate <= $0.wake }) else { continue }
            guard let beats = try? await heartbeats(series), let value = BeatToBeat.rmssd(beats, minimumSeconds: 50) else { continue }
            valuesByNight[night.date, default: []].append(value)
        }
        // Apple records about a minute at a time; RMSSD needs ~3 minutes of
        // clean beats, so a night needs several recordings.
        for night in nights {
            let values = valuesByNight[night.date] ?? []
            let value: Double? = values.count >= 3 ? values.sorted()[values.count / 2] : nil
            known[night.date] = .some(value)
            if night.date < today { rmssdCache.store(value, for: night.date) }
        }
        return known.compactMapValues { $0 }
    }

    /// The beats in one heartbeat series.
    private func heartbeats(_ series: HKHeartbeatSeriesSample) async throws -> [BeatToBeat.Beat] {
        let collector = BeatCollector()
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKHeartbeatSeriesQuery(heartbeatSeries: series) { _, time, precededByGap, done, error in
                if let error {
                    collector.finish { continuation.resume(throwing: error) }
                    return
                }
                collector.append(BeatToBeat.Beat(time: time, precededByGap: precededByGap))
                if done {
                    collector.finish { continuation.resume(returning: collector.beats) }
                }
            }
            store.execute(query)
        }
    }

    func sleepNights(nights: Int = 7) async throws -> [SleepConsistency.Night] {
        try await sleepHistory(nights: nights).map { SleepConsistency.Night(bedtime: $0.bedtime, wake: $0.wake) }
    }

    /// Average daily vitamins and minerals over the last `days` days, counting
    /// only days with food logged (800+ kcal).
    @concurrent
    func nutrientAverages(days: Int = 7) async throws -> (averages: [Micronutrients.Nutrient: Double], daysLogged: Int) {
        let today = Calendar.current.startOfDay(for: .now)
        let energy = try await dailySeries(.dietaryEnergyConsumed, unit: .kilocalorie(), days: days + 1, cumulative: true)
        let loggedDays = Set(energy.filter { $0.date < today && $0.value >= 800 }.map(\.date))
        guard !loggedDays.isEmpty else { return ([:], 0) }
        let milligram = HKUnit.gramUnit(with: .milli)
        let microgram = HKUnit.gramUnit(with: .micro)
        let types: [(Micronutrients.Nutrient, HKQuantityTypeIdentifier, HKUnit)] = [
            (.vitaminC, .dietaryVitaminC, milligram), (.vitaminD, .dietaryVitaminD, microgram),
            (.zinc, .dietaryZinc, milligram), (.iron, .dietaryIron, milligram),
            (.magnesium, .dietaryMagnesium, milligram), (.potassium, .dietaryPotassium, milligram),
            (.sodium, .dietarySodium, milligram), (.calcium, .dietaryCalcium, milligram),
            (.vitaminB12, .dietaryVitaminB12, microgram), (.folate, .dietaryFolate, microgram),
            (.vitaminA, .dietaryVitaminA, microgram), (.selenium, .dietarySelenium, microgram),
            (.fiber, .dietaryFiber, .gram()),
        ]
        var averages: [Micronutrients.Nutrient: Double] = [:]
        for (nutrient, identifier, unit) in types {
            let series = (try? await dailySeries(identifier, unit: unit, days: days + 1, cumulative: true)) ?? []
            let logged = series.filter { loggedDays.contains($0.date) }
            // Nothing at all usually means the food app doesn't export this nutrient.
            guard !logged.isEmpty else { continue }
            averages[nutrient] = logged.map(\.value).reduce(0, +) / Double(loggedDays.count)
        }
        return (averages, loggedDays.count)
    }

    /// Average hours asleep over the last `nights` nights (overlapping
    /// samples from different sources are merged, not double counted).
    @concurrent
    func averageSleepHours(nights: Int = 7) async throws -> Double? {
        let totals = try await sleepHistory(nights: nights).map(\.hoursAsleep)
        guard !totals.isEmpty else { return nil }
        return totals.reduce(0, +) / Double(totals.count)
    }

    /// One entry per night (dated by the morning it ended): hours asleep in the
    /// main sleep, with overlapping samples from different sources merged, plus
    /// when it started and ended. Nights under 2 hours are left out.
    @concurrent
    func sleepHistory(nights: Int) async throws -> [SleepNight] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -nights, to: today)?.addingTimeInterval(-6 * 3600) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]
        var byNight: [Date: [DateInterval]] = [:]
        for sample in try await descriptor.result(for: store) where asleepValues.contains(sample.value) {
            let night = calendar.startOfDay(for: sample.startDate.addingTimeInterval(6 * 3600))
            byNight[night, default: []].append(DateInterval(start: sample.startDate, end: max(sample.startDate, sample.endDate)))
        }
        return byNight.keys.sorted().compactMap { night in
            // Only the main sleep counts: an afternoon nap or an evening doze
            // more than 90 minutes from it is a separate session.
            guard let main = SleepSessions.main(byNight[night] ?? []) else { return nil }
            let hours = main.asleep / 3600
            guard hours >= 2 else { return nil }
            return SleepNight(date: night, hoursAsleep: hours, bedtime: main.start, wake: main.end, intervals: main.intervals)
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
    func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, since: Date? = nil) async throws -> Double? {
        let predicate = since.map { HKQuery.predicateForSamples(withStart: $0, end: nil) }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
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
                distanceKm: distance,
                uuid: workout.uuid
            )
        }
    }

    /// Start and end of every workout in a range, from any app (used for
    /// heart-rate recovery and to leave workouts out of the stress estimate).
    @concurrent
    func workoutIntervals(from start: Date, to end: Date) async throws -> [DateInterval] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).map {
            DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate))
        }
    }

    /// Total mindful minutes per day (breathing or meditation sessions).
    @concurrent
    func mindfulMinutes(days: Int) async throws -> [DatedValue] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.mindfulSession), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        var byDay: [Date: Double] = [:]
        for sample in try await descriptor.result(for: store) {
            byDay[calendar.startOfDay(for: sample.startDate), default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 60
        }
        return byDay.keys.sorted().map { DatedValue(date: $0, value: byDay[$0] ?? 0) }
    }

    /// Step count in a range, split into steps inside and outside the given
    /// windows. Uses statistics so steps counted by both the iPhone and the
    /// watch aren't added twice (Health picks one source per moment).
    @concurrent
    func steps(from start: Date, to end: Date, excluding windows: [DateInterval]) async throws -> (total: Double, outside: Double) {
        let total = try await dailySum(.stepCount, unit: .count(), start: start, end: end) ?? 0
        // Merge overlapping windows (a logged session and the watch's own
        // workout often cover the same time) so their steps aren't subtracted twice.
        var merged: [DateInterval] = []
        for window in windows.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, window.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, window.end))
            } else {
                merged.append(window)
            }
        }
        var inside = 0.0
        for window in merged {
            let from = max(window.start, start)
            let to = min(window.end, end)
            guard to > from else { continue }
            inside += try await dailySum(.stepCount, unit: .count(), start: from, end: to) ?? 0
        }
        return (total, max(0, total - inside))
    }

    /// Average resting calories a day over recent complete days, as written by
    /// the watch (Garmin Connect writes resting energy). Nil if there's too little.
    @concurrent
    func restingEnergyPerDay(days: Int = 7) async throws -> Double? {
        let series = try await dailySeries(.basalEnergyBurned, unit: .kilocalorie(), days: days + 1, cumulative: true)
        let today = Calendar.current.startOfDay(for: .now)
        let full = series.filter { $0.date < today && $0.value > 800 }.map(\.value)
        guard full.count >= 2 else { return nil }
        return full.reduce(0, +) / Double(full.count)
    }

    /// What the watch has written for today so far: resting and active calories.
    @concurrent
    func deviceEnergy(from start: Date, to end: Date) async throws -> (resting: Double?, active: Double?) {
        async let resting = dailySum(.basalEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let active = dailySum(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        return try await (resting, active)
    }

    /// Calls `onChange` whenever new steps, energy, heart rate, breathing or
    /// sleep data lands in Apple Health (e.g. after Garmin Connect syncs).
    /// Lets HealthKit wake the app when new data arrives (e.g. a Garmin sync),
    /// so scores and the widget update without opening the app.
    func enableBackgroundDelivery() {
        let types: [HKObjectType] = [
            HKQuantityType(.heartRate), HKQuantityType(.restingHeartRate), HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.stepCount)
        ]
        for type in types {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    func observeChanges(_ onChange: @escaping @Sendable () -> Void) {
        let types: [HKSampleType] = [
            HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate), HKQuantityType(.respiratoryRate), HKQuantityType(.oxygenSaturation),
            HKQuantityType(.heartRateVariabilitySDNN), HKCategoryType(.sleepAnalysis),
            HKQuantityType(.dietaryEnergyConsumed)
        ]
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                if error == nil { onChange() }
                completion()
            }
            store.execute(query)
        }
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

/// One night's sleep, dated by the morning it ended.
nonisolated struct SleepNight: Sendable, Identifiable, Equatable {
    var date: Date
    var hoursAsleep: Double
    var bedtime: Date
    var wake: Date
    /// The main sleep's asleep intervals (for the Sleep Regularity Index).
    var intervals: [DateInterval] = []
    var id: Date { date }
}

extension Array where Element == SleepNight {
    /// Sleep Regularity Index (0-100) over these nights, if there are enough.
    nonisolated var regularityScore: Int? {
        guard let first = self.map(\.date).min() else { return nil }
        // Noon before the first morning, through noon today.
        let start = first.addingTimeInterval(-12 * 3600)
        let days = Int((Date.now.timeIntervalSince(start) / 86_400).rounded(.down))
        return SleepRegularity.score(asleep: flatMap(\.intervals), start: start, days: days)
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
    /// HealthKit's ID, so two sources recording the same time stay distinct.
    var uuid = UUID()
    var id: UUID { uuid }
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

nonisolated struct HeartRateSource: Sendable, Identifiable {
    var name: String
    var samples: [HeartRateSample]
    var id: String { name }
}

// MARK: - Timed samples (caffeine, protein per meal)

extension HealthKitClient {
    /// Individual samples with their times (not daily totals), e.g. each
    /// caffeine or protein entry a food app wrote. Values in `unit`.
    @concurrent
    func timedSamples(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> [DatedValue] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).map {
            DatedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
        }
    }
}

/// Collects beats from an HKHeartbeatSeriesQuery, whose handler runs on a
/// HealthKit queue, and makes sure the continuation resumes only once.
nonisolated private final class BeatCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BeatToBeat.Beat] = []
    private var finished = false

    var beats: [BeatToBeat.Beat] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func append(_ beat: BeatToBeat.Beat) {
        lock.lock(); defer { lock.unlock() }
        storage.append(beat)
    }

    func finish(_ resume: () -> Void) {
        lock.lock()
        let first = !finished
        finished = true
        lock.unlock()
        if first { resume() }
    }
}

/// Remembers each finished night's RMSSD (or that there was none).
nonisolated private final class RMSSDCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Date: Double?] = [:]

    /// Known nights only; a stored nil means "read, no beat-to-beat data".
    func values(for nights: [Date]) -> [Date: Double?] {
        lock.lock(); defer { lock.unlock() }
        var result: [Date: Double?] = [:]
        for night in nights {
            if let value = storage[night] { result[night] = value }
        }
        return result
    }

    func store(_ value: Double?, for night: Date) {
        lock.lock(); defer { lock.unlock() }
        storage[night] = .some(value)
    }
}
