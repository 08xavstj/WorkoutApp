import Foundation
import HealthKit
import AppCore

/// Sleep and workouts around a run of days: what `DaytimeVitals.day` needs to
/// tell awake from asleep and rest from exercise.
nonisolated struct DaytimeContext: Sendable {
    /// Every stretch to treat as asleep: main sleeps from bedtime to waking, and naps.
    var sleep: [DateInterval]
    /// Workouts from any app, and the sessions logged in this one.
    var workouts: [DateInterval]
}

/// Reads for the daytime vitals view (`DaytimeVitals`, `DaytimeVitalsModel`).
///
/// An Apple Watch Series 12 writes heart rate every five seconds (about
/// 17,000 readings a day) and HRV as often as every five minutes (about 288),
/// and the usual range looks back four weeks. So: heart rate, exercise
/// minutes and steps are read as HealthKit statistics per minute (at most
/// 1,440 values a day, however often the watch records); HRV and blood oxygen
/// as sample queries with a limit; a week at a time; and a finished day is
/// reduced once and kept (`DaytimeDayCache`).
nonisolated extension HealthKitClient {
    /// Finished days, reduced (shared by every client: one file). Demo mode keeps its made-up days in a file of its own.
    private static let daytimeCache = DaytimeDayCache(fileName: DemoMode.isOn ? "daytime-days-demo.json" : "daytime-days.json")

    /// The most HRV or blood-oxygen readings read per day (app's choice, for
    /// speed: twice what a Series 12 writes at one every five minutes).
    private static let maximumReadingsPerDay = 600
    /// Days read from Apple Health in one go (app's choice).
    private static let daysPerRead = 7

    // MARK: Context

    /// Sleep and workouts from a little before `start` to `end`. `logged` are
    /// the sessions logged in this app, in case one was not saved to Health.
    /// Reads that fail leave their part empty; nothing here throws.
    @concurrent
    func daytimeContext(from start: Date, to end: Date, logged: [DateInterval]) async -> DaytimeContext {
        let nights = (Calendar.current.dateComponents([.day], from: start, to: .now).day ?? 0) + 2
        // A workout that ended late the evening before still blocks the first
        // minutes of the day (`DaytimeVitals.workoutRecoveryMinutes`).
        let lead = start.addingTimeInterval(-12 * 3600)
        async let mainSleeps = sleepHistory(nights: nights)
        async let everySleep = asleepIntervals(from: lead, to: end)
        async let recorded = workoutIntervals(from: lead, to: end)
        var sleep = ((try? await mainSleeps) ?? []).map { DateInterval(start: $0.bedtime, end: max($0.bedtime, $0.wake)) }
        sleep += (try? await everySleep) ?? []
        let workouts = ((try? await recorded) ?? []) + logged
        return DaytimeContext(sleep: sleep, workouts: workouts)
    }

    /// Every stretch any device recorded as asleep, merged. The main sleeps
    /// come from `sleepHistory`; this adds naps, which that leaves out, so a
    /// nap's low heart rate is not read as daytime rest. Every source counts
    /// here, whatever the sleep-source setting: for this purpose a nap seen by
    /// either the watch or the ring is a nap.
    @concurrent
    func asleepIntervals(from start: Date, to end: Date) async throws -> [DateInterval] {
        if DemoHealth.active != nil { return [] } // demo mode: no naps; `sleepHistory` has the nights
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]
        let intervals = try await descriptor.result(for: store)
            .filter { asleepValues.contains($0.value) }
            .map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
        return DaytimeVitals.clipped(intervals, from: start, to: end)
    }

    // MARK: Readings

    /// Steps in each minute that had any, from HealthKit's statistics (so the
    /// iPhone's and the watch's steps aren't added twice). A sample longer
    /// than a minute is spread over its minutes.
    @concurrent
    func stepsPerMinute(from start: Date, to end: Date) async throws -> [DaytimeVitals.StepMinute] {
        if let demo = DemoHealth.active { return demo.stepsPerMinute(from: start, to: end) }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
            options: .cumulativeSum,
            anchorDate: Calendar.current.startOfDay(for: start),
            intervalComponents: DateComponents(minute: 1)
        )
        do {
            return try await descriptor.result(for: store).statistics().compactMap { statistics in
                guard let steps = statistics.sumQuantity()?.doubleValue(for: .count()), steps >= 1 else { return nil }
                return DaytimeVitals.StepMinute(start: statistics.startDate, steps: steps)
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    /// Apple Health's SDNN readings in a range, asleep and awake, oldest first.
    @concurrent
    func daytimeSDNN(from start: Date, to end: Date) async throws -> [DaytimeVitals.Reading] {
        if let demo = DemoHealth.active { return demo.daytimeHRV(from: start, to: end) }
        return try await daytimeReadings(HKQuantityType(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli), from: start, to: end)
    }

    /// Apple Health's RMSSD readings (`recoveryHRVType`, iOS 27) in a range.
    /// Empty on iOS 26 and from a watch that doesn't write the type.
    @concurrent
    func daytimeRMSSD(from start: Date, to end: Date) async throws -> [DaytimeVitals.Reading] {
        guard DemoHealth.active == nil, let type = Self.recoveryHRVType else { return [] } // demo mode: SDNN only
        return try await daytimeReadings(type, unit: .secondUnit(with: .milli), from: start, to: end)
    }

    /// Blood-oxygen readings in a range, in percent (0-100).
    @concurrent
    func daytimeBloodOxygen(from start: Date, to end: Date) async throws -> [DaytimeVitals.Reading] {
        if let demo = DemoHealth.active { return demo.daytimeBloodOxygen(from: start, to: end) }
        return try await daytimeReadings(HKQuantityType(.oxygenSaturation), unit: .percent(), scale: 100, from: start, to: end)
    }

    /// The samples of one type in a range, oldest first, at most
    /// `maximumReadingsPerDay` for each day of the range.
    private func daytimeReadings(_ type: HKQuantityType, unit: HKUnit, scale: Double = 1,
                                 from start: Date, to end: Date) async throws -> [DaytimeVitals.Reading] {
        let days = max(1, Int((end.timeIntervalSince(start) / 86_400).rounded(.up)))
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: days * Self.maximumReadingsPerDay
        )
        do {
            return try await descriptor.result(for: store).map {
                DaytimeVitals.Reading(date: $0.startDate, value: $0.quantity.doubleValue(for: unit) * scale)
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    // MARK: Days

    /// The reduced days for `dates`, oldest first.
    ///
    /// Today and yesterday are always read (the watch syncs late). An earlier
    /// day comes from `DaytimeDayCache` when it was reduced with the same
    /// sleep and workouts Apple Health has for it now; otherwise it is read
    /// only if `readMissing` is true, so the screen can show today first and
    /// fill in the earlier days after. Days whose heart rate can't be read are
    /// left out.
    ///
    /// - Parameter ignoreStored: read every day again (pull to refresh).
    @concurrent
    func daytimeDays(_ dates: [Date], context: DaytimeContext, readMissing: Bool, ignoreStored: Bool = false) async -> [DaytimeVitals.Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)
        let days = Set(dates.map { calendar.startOfDay(for: $0) }).filter { $0 <= today }.sorted()
        func dayAfter(_ day: Date) -> Date {
            calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        }

        var result: [Date: DaytimeVitals.Day] = [:]
        var toRead: [Date] = []
        let stored = ignoreStored ? [:] : Self.daytimeCache.days(days.filter { $0 < yesterday })
        for day in days {
            if day >= yesterday {
                toRead.append(day)
            } else if let kept = stored[day], Self.matches(kept, context: context, end: dayAfter(day)) {
                result[day] = kept
            } else if readMissing {
                toRead.append(day)
            }
        }

        for run in Self.runs(toRead, calendar: calendar) {
            guard !Task.isCancelled, let start = run.first, let last = run.last else { break }
            let end = dayAfter(last)
            // A walk in the minutes before midnight still unsettles the first minutes of the day.
            let lead = start.addingTimeInterval(-(DaytimeVitals.exerciseSettleMinutes + 1) * 60)
            async let heartRate = heartRatePerMinute(from: start, to: end)
            async let exercise = exerciseMinutes(from: lead, to: end)
            async let steps = stepsPerMinute(from: lead, to: end)
            async let sdnn = daytimeSDNN(from: start, to: end)
            async let rmssd = daytimeRMSSD(from: start, to: end)
            async let oxygen = daytimeBloodOxygen(from: start, to: end)
            // Heart rate is the one read a day can't do without; the others may be empty.
            guard let minutes = try? await heartRate else { continue }
            let input = DaytimeVitals.Input(
                heartRate: minutes,
                sdnn: (try? await sdnn) ?? [],
                rmssd: (try? await rmssd) ?? [],
                bloodOxygen: (try? await oxygen) ?? [],
                sleep: context.sleep,
                workouts: context.workouts,
                exerciseMinutes: (try? await exercise) ?? [],
                steps: (try? await steps) ?? []
            )
            var finished: [DaytimeVitals.Day] = []
            for day in run {
                let reduced = DaytimeVitals.day(input, on: day, calendar: calendar)
                result[day] = reduced
                // A day with no heart rate is not kept: it may only mean Health
                // access hasn't been granted yet, or the watch hasn't synced.
                if day < yesterday, reduced.hasHeartRate { finished.append(reduced) }
            }
            Self.daytimeCache.store(finished)
        }
        return result.keys.sorted().compactMap { result[$0] }
    }

    /// True while a stored day's sleep and workouts are the ones Apple Health
    /// has now (within a minute), so an edited or late-synced sleep or workout
    /// has the day read again. (A workout that ended before midnight and was
    /// synced days later is not caught; pull to refresh reads everything again.)
    private static func matches(_ day: DaytimeVitals.Day, context: DaytimeContext, end: Date) -> Bool {
        func same(_ stored: [DateInterval], _ current: [DateInterval]) -> Bool {
            stored.count == current.count && zip(stored, current).allSatisfy { pair in
                abs(pair.0.start.timeIntervalSince(pair.1.start)) < 60 && abs(pair.0.end.timeIntervalSince(pair.1.end)) < 60
            }
        }
        return same(day.sleep, DaytimeVitals.clipped(context.sleep, from: day.date, to: end))
            && same(day.workouts, DaytimeVitals.clipped(context.workouts, from: day.date, to: end))
    }

    /// `days` (ascending) split into runs of consecutive days, each at most
    /// `daysPerRead` long, newest run first so the days nearest today arrive first.
    private static func runs(_ days: [Date], calendar: Calendar) -> [[Date]] {
        var result: [[Date]] = []
        for day in days {
            if let previous = result.last?.last, result[result.count - 1].count < daysPerRead,
               calendar.date(byAdding: .day, value: 1, to: previous) == day {
                result[result.count - 1].append(day)
            } else {
                result.append([day])
            }
        }
        return result.reversed()
    }
}
