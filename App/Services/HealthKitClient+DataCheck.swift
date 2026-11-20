import Foundation
import HealthKit
import AppCore

/// One measure in the Health data check (Settings › Health data check).
nonisolated struct HealthDataCheckItem: Sendable, Identifiable {
    enum Group: String, CaseIterable, Sendable {
        case heart = "Heart"
        case breathing = "Breathing and blood oxygen"
        case sleep = "Sleep and temperature"
        case activity = "Activity and fitness"
        case alerts = "Watch notifications"
    }

    let id: String
    /// The name in Tensile.
    let title: String
    /// The name the Health app uses, for the access switch.
    let healthName: String
    let group: Group
    let cadence: HealthDataCheck.Cadence
    /// The newest reading in the last `HealthDataCheck.windowDays` days.
    let newest: Date?
    /// "14.6 /min"; nil for notifications and sleep.
    let newestValue: String?
    /// Days with a reading in the last 14.
    let daysWithData: Int
    /// Where the readings came from in the window ("Alex's Apple Watch").
    let sources: [String]

    func status(now: Date) -> HealthDataCheck.Status {
        HealthDataCheck.status(newest: newest, cadence: cadence, now: now)
    }
}

nonisolated extension HealthKitClient {
    /// What the check looks at: what Apple Watch (Series 12, watchOS 27)
    /// writes and Tensile reads (docs/research/apple-watch-series-12-metrics-2026-11.md).
    private struct CheckSpec: Sendable {
        let id: String
        let title: String
        let healthName: String
        let group: HealthDataCheckItem.Group
        let cadence: HealthDataCheck.Cadence
        let type: HKSampleType
        /// Unit and digits for the newest value; nil for categories.
        let unit: HKUnit?
        let unitLabel: String
        let digits: Int
        /// Shown as a percentage (blood oxygen is stored as a fraction).
        var percent = false
    }

    private static var checkSpecs: [CheckSpec] {
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        let vo2 = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        var specs: [CheckSpec] = [
            CheckSpec(id: "heartRate", title: "Heart rate", healthName: "Heart Rate", group: .heart, cadence: .continuous,
                      type: HKQuantityType(.heartRate), unit: perMinute, unitLabel: "bpm", digits: 0),
            CheckSpec(id: "restingHeartRate", title: "Resting heart rate", healthName: "Resting Heart Rate", group: .heart, cadence: .nightly,
                      type: HKQuantityType(.restingHeartRate), unit: perMinute, unitLabel: "bpm", digits: 0),
            CheckSpec(id: "hrvSDNN", title: "HRV (SDNN)", healthName: "Heart Rate Variability", group: .heart, cadence: .nightly,
                      type: HKQuantityType(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli), unitLabel: "ms", digits: 0),
        ]
        if let rmssd = recoveryHRVType {
            specs.append(CheckSpec(id: "hrvRMSSD", title: "HRV (RMSSD, iOS 27)", healthName: "Heart Rate Variability", group: .heart,
                                   cadence: .nightly, type: rmssd, unit: .secondUnit(with: .milli), unitLabel: "ms", digits: 0))
        }
        specs += [
            CheckSpec(id: "walkingHeartRate", title: "Walking heart rate", healthName: "Walking Heart Rate Average", group: .heart,
                      cadence: .nightly, type: HKQuantityType(.walkingHeartRateAverage), unit: perMinute, unitLabel: "bpm", digits: 0),

            CheckSpec(id: "respiratoryRate", title: "Breathing rate", healthName: "Respiratory Rate", group: .breathing, cadence: .nightly,
                      type: HKQuantityType(.respiratoryRate), unit: perMinute, unitLabel: "/min", digits: 1),
            CheckSpec(id: "oxygenSaturation", title: "Blood oxygen", healthName: "Blood Oxygen", group: .breathing, cadence: .occasional,
                      type: HKQuantityType(.oxygenSaturation), unit: .percent(), unitLabel: "%", digits: 0, percent: true),
            CheckSpec(id: "breathingDisturbances", title: "Breathing disturbances", healthName: "Breathing Disturbances", group: .breathing,
                      cadence: .nightly, type: HKQuantityType(.appleSleepingBreathingDisturbances), unit: .count(), unitLabel: "", digits: 1),

            CheckSpec(id: "sleep", title: "Sleep", healthName: "Sleep", group: .sleep, cadence: .nightly,
                      type: HKCategoryType(.sleepAnalysis), unit: nil, unitLabel: "", digits: 0),
            CheckSpec(id: "wristTemperature", title: "Wrist temperature", healthName: "Wrist Temperature", group: .sleep, cadence: .nightly,
                      type: HKQuantityType(.appleSleepingWristTemperature), unit: .degreeCelsius(), unitLabel: "°C", digits: 2),

            CheckSpec(id: "steps", title: "Steps", healthName: "Steps", group: .activity, cadence: .continuous,
                      type: HKQuantityType(.stepCount), unit: .count(), unitLabel: "steps", digits: 0),
            CheckSpec(id: "activeEnergy", title: "Active energy", healthName: "Active Energy", group: .activity, cadence: .continuous,
                      type: HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), unitLabel: "kcal", digits: 0),
            CheckSpec(id: "exerciseMinutes", title: "Exercise minutes", healthName: "Exercise Minutes", group: .activity, cadence: .occasional,
                      type: HKQuantityType(.appleExerciseTime), unit: .minute(), unitLabel: "min", digits: 0),
            CheckSpec(id: "vo2Max", title: "VO₂ max", healthName: "Cardio Fitness", group: .activity, cadence: .occasional,
                      type: HKQuantityType(.vo2Max), unit: vo2, unitLabel: "mL/kg/min", digits: 1),
            CheckSpec(id: "walkingSpeed", title: "Walking speed", healthName: "Walking Speed", group: .activity, cadence: .occasional,
                      type: HKQuantityType(.walkingSpeed), unit: HKUnit.meter().unitDivided(by: .second()), unitLabel: "m/s", digits: 2),
            CheckSpec(id: "daylight", title: "Time in daylight", healthName: "Time in Daylight", group: .activity, cadence: .occasional,
                      type: HKQuantityType(.timeInDaylight), unit: .minute(), unitLabel: "min", digits: 0),

            CheckSpec(id: "highHeartRate", title: "High heart rate", healthName: "High Heart Rate Notifications", group: .alerts,
                      cadence: .alert, type: HKCategoryType(.highHeartRateEvent), unit: nil, unitLabel: "", digits: 0),
            CheckSpec(id: "lowHeartRate", title: "Low heart rate", healthName: "Low Heart Rate Notifications", group: .alerts,
                      cadence: .alert, type: HKCategoryType(.lowHeartRateEvent), unit: nil, unitLabel: "", digits: 0),
            CheckSpec(id: "irregularRhythm", title: "Irregular rhythm", healthName: "Irregular Rhythm Notifications", group: .alerts,
                      cadence: .alert, type: HKCategoryType(.irregularHeartRhythmEvent), unit: nil, unitLabel: "", digits: 0),
            CheckSpec(id: "sleepApnea", title: "Sleep apnoea", healthName: "Sleep Apnea Notifications", group: .alerts,
                      cadence: .alert, type: HKCategoryType(.sleepApneaEvent), unit: nil, unitLabel: "", digits: 0),
        ]
        if let hypertension = hypertensionReadTypes.first as? HKSampleType {
            specs.append(CheckSpec(id: "hypertension", title: "Hypertension", healthName: "Hypertension Notifications", group: .alerts,
                                   cadence: .alert, type: hypertension, unit: nil, unitLabel: "", digits: 0))
        }
        return specs
    }

    /// Each measure's newest reading, days with data and sources, read
    /// one measure at a time (a 5-second heart-rate series is large).
    @concurrent
    func dataCheck(now: Date = .now) async -> [HealthDataCheckItem] {
        if let demo = DemoHealth.active { return demoDataCheck(demo, now: now) }
        guard isAvailable else { return [] }
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -HealthDataCheck.windowDays, to: now) ?? now
        let fortnightStart = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now)) ?? now
        var items: [HealthDataCheckItem] = []
        for spec in Self.checkSpecs {
            let window = HKQuery.predicateForSamples(withStart: windowStart, end: now)
            let newestDescriptor = HKSampleQueryDescriptor(
                predicates: [.sample(type: spec.type, predicate: window)],
                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
                limit: 1
            )
            let newest = (try? await newestDescriptor.result(for: store))?.first
            var value: String?
            if let quantity = newest as? HKQuantitySample, let unit = spec.unit {
                var number = quantity.quantity.doubleValue(for: unit)
                if spec.percent { number *= 100 }
                let text = number.formatted(.number.precision(.fractionLength(spec.digits)))
                value = spec.unitLabel.isEmpty ? text : (spec.unitLabel == "%" || spec.unitLabel.hasPrefix("°") ? text + spec.unitLabel : "\(text) \(spec.unitLabel)")
            }
            let sourceDescriptor = HKSourceQueryDescriptor(predicate: .sample(type: spec.type, predicate: window))
            let sources = ((try? await sourceDescriptor.result(for: store)) ?? []).map(\.name).sorted()
            let days = newest == nil ? 0 : await daysWithData(spec.type, from: fortnightStart, to: now, calendar: calendar)
            items.append(HealthDataCheckItem(
                id: spec.id, title: spec.title, healthName: spec.healthName, group: spec.group, cadence: spec.cadence,
                newest: newest?.endDate, newestValue: value, daysWithData: days, sources: sources
            ))
        }
        return items
    }

    /// Days from `start` to `end` with at least one reading.
    private func daysWithData(_ type: HKSampleType, from start: Date, to end: Date, calendar: Calendar) async -> Int {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        if let quantityType = type as? HKQuantityType {
            let options: HKStatisticsOptions = quantityType.aggregationStyle == .cumulative ? .cumulativeSum : .discreteAverage
            let descriptor = HKStatisticsCollectionQueryDescriptor(
                predicate: .quantitySample(type: quantityType, predicate: predicate),
                options: options,
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            guard let collection = try? await descriptor.result(for: store) else { return 0 }
            return collection.statistics().filter { $0.sumQuantity() != nil || $0.averageQuantity() != nil }.count
        }
        let descriptor = HKSampleQueryDescriptor(predicates: [.sample(type: type, predicate: predicate)],
                                                 sortDescriptors: [], limit: 5000)
        let samples = (try? await descriptor.result(for: store)) ?? []
        return Set(samples.map { calendar.startOfDay(for: $0.endDate) }).count
    }

    /// The screenshot tour's made-up check: everything arriving, no notifications.
    private func demoDataCheck(_ demo: DemoHealth, now: Date) -> [HealthDataCheckItem] {
        let lastNight = Calendar.current.startOfDay(for: now).addingTimeInterval(3 * 3600)
        return Self.checkSpecs.map { spec in
            let isAlert = spec.cadence == .alert
            let newest: Date? = isAlert ? nil : (spec.cadence == .nightly ? lastNight : now.addingTimeInterval(-1800))
            let value: String? = switch spec.id {
            case "respiratoryRate": "14.6 /min"
            case "heartRate": "64 bpm"
            case "restingHeartRate": "54 bpm"
            case "hrvSDNN", "hrvRMSSD": "48 ms"
            case "oxygenSaturation": "97%"
            default: nil
            }
            return HealthDataCheckItem(id: spec.id, title: spec.title, healthName: spec.healthName, group: spec.group,
                                       cadence: spec.cadence, newest: newest, newestValue: value,
                                       daysWithData: isAlert ? 0 : 14, sources: isAlert ? [] : ["Apple Watch"])
        }
    }
}
