import Foundation
import AppCore

/// Loads the daytime vitals for today and yesterday (`DaytimeVitals`), each
/// against the four weeks before it. Owned by `DaytimeVitalsView`; nothing
/// else reads it, and nothing here is shown on Today.
///
/// Two steps, so the screen isn't blank on the first visit: today, yesterday
/// and the finished days already on disk (`DaytimeDayCache`) are shown first,
/// then any earlier day not yet read is read from Apple Health and the usual
/// ranges are filled in.
@Observable
final class DaytimeVitalsModel {
    private(set) var today: DaytimeVitals.Summary?
    private(set) var yesterday: DaytimeVitals.Summary?
    private(set) var isLoading = false
    /// Earlier days are being read from Apple Health, so a missing usual range
    /// may only mean "not read yet".
    private(set) var isReadingEarlierDays = false
    /// True once a load has finished (with or without data).
    private(set) var hasLoaded = false
    @ObservationIgnored private var isRunning = false

    /// - Parameters:
    ///   - logged: gym sessions logged in this app over the last month.
    ///   - force: read every day again instead of using the stored ones.
    func load(health: HealthKitClient, logged: [DateInterval], force: Bool = false) async {
        guard health.isAvailable else {
            hasLoaded = true
            return
        }
        guard !isRunning else { return }
        isRunning = true
        isLoading = true
        defer {
            isRunning = false
            isLoading = false
            isReadingEarlierDays = false
            hasLoaded = true
        }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        // Today, yesterday, and the 28 days before yesterday.
        let dates = (0...(DaytimeVitals.baselineWindowDays + 1)).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: todayStart)
        }
        guard let first = dates.min() else { return }
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400)
        let context = await health.daytimeContext(from: first, to: end, logged: logged)

        var days = await health.daytimeDays(dates, context: context, readMissing: false, ignoreStored: force)
        await publish(days, today: todayStart)
        let have = Set(days.map(\.date))
        let missing = dates.filter { !have.contains($0) }
        guard !missing.isEmpty, !Task.isCancelled else { return }

        isReadingEarlierDays = true
        days += await health.daytimeDays(missing, context: context, readMissing: true, ignoreStored: force)
        guard !Task.isCancelled else { return }
        await publish(days, today: todayStart)
    }

    private func publish(_ days: [DaytimeVitals.Day], today todayStart: Date) async {
        let result = await Self.summaries(days, today: todayStart)
        today = result.today
        yesterday = result.yesterday
    }

    /// Worked out off the main thread: four weeks of days, twice.
    @concurrent
    nonisolated private static func summaries(
        _ days: [DaytimeVitals.Day], today: Date
    ) async -> (today: DaytimeVitals.Summary?, yesterday: DaytimeVitals.Summary?) {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86_400)
        func summary(_ date: Date) -> DaytimeVitals.Summary? {
            guard let day = days.first(where: { $0.date == date }) else { return nil }
            return DaytimeVitals.summary(for: day, history: days, calendar: calendar)
        }
        return (summary(today), summary(yesterday))
    }
}
