import Foundation

/// What the Apple Watch complications show: today's recovery and strain, and
/// the planned sessions coming up. The phone (`WatchSync.updateFace`) sends
/// it; the Watch app stores it in the App Group (`WatchFaceStore`) for the
/// widget extension. Foundation only: compiled into the iPhone app, its
/// widget, the Watch app and the Watch widget extension.
nonisolated struct WatchFaceData: Codable, Sendable, Equatable {
    /// One planned session (`PlannedDay` on a date).
    nonisolated struct Slot: Codable, Sendable, Equatable {
        var start: Date
        /// e.g. "Push Day".
        var title: String
        /// e.g. "Push".
        var shortTitle: String
        /// SF Symbol for the focus.
        var symbol: String?
    }

    /// Today's recovery, 0-100 (nil: not scored yet).
    var recovery: Int?
    /// `RecoveryCalculator.Status.rawValue`: "low", "moderate" or "high".
    var band: String?
    /// True while the recovery baseline is still building.
    var calibrating: Bool
    /// Today's strain so far, 0-100.
    var strain: Double?
    /// Today's strain target (`DailyMetricsModel.targetStrain`).
    var targetLower: Double?
    var targetUpper: Double?
    /// HRV-guided easy day (`DailyMetricsModel.trainEasyToday`).
    var easyDay: Bool
    /// Planned sessions from the start of today, about a week ahead.
    var slots: [Slot]
    /// When the last gym session logged on the phone ended.
    var lastWorkoutEnd: Date?
    var updated: Date

    /// The recovery band as the app words it.
    var bandLabel: String? {
        switch band {
        case "low": "Easy day"
        case "moderate": "Normal"
        case "high": "Recovered"
        default: nil
        }
    }

    var target: ClosedRange<Double>? {
        guard let targetLower, let targetUpper, targetLower <= targetUpper else { return nil }
        return targetLower...targetUpper
    }

    /// True when the scores are from the same day as `date` (yesterday's
    /// recovery and strain shouldn't show as today's after midnight).
    func scoresAreCurrent(at date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(updated, inSameDayAs: date)
    }

    /// Same on the watch face: recovery, band and plan unchanged and strain
    /// and target within a point. Used to skip needless transfers.
    func looksSame(as other: WatchFaceData, calendar: Calendar = .current) -> Bool {
        recovery == other.recovery && band == other.band && calibrating == other.calibrating
            && easyDay == other.easyDay && slots == other.slots && lastWorkoutEnd == other.lastWorkoutEnd
            && Self.withinAPoint(strain, other.strain)
            && Self.withinAPoint(targetLower, other.targetLower)
            && Self.withinAPoint(targetUpper, other.targetUpper)
            && calendar.isDate(updated, inSameDayAs: other.updated)
    }

    private static func withinAPoint(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (x?, y?): abs(x - y) < 1
        default: false
        }
    }

    // MARK: Next session

    nonisolated enum Upcoming: Equatable, Sendable {
        /// Today's session, not done yet.
        case today(Slot)
        /// Today's session is done (or its time has passed): the next one.
        case later(Slot)
        /// Nothing planned today; the next session if there is one.
        case rest(next: Slot?)
        /// No sessions planned at all.
        case noPlan
    }

    /// A session counts as current until 2 hours after its start (the app's
    /// display choice, not a training rule).
    static let sessionWindow: TimeInterval = 2 * 3600

    /// What the "next session" complication shows at `now`. `doneAt` is the
    /// latest workout end (phone or Watch): a session on that day is done.
    func upcoming(at now: Date, doneAt: Date?, calendar: Calendar = .current) -> Upcoming {
        let sorted = slots.sorted { $0.start < $1.start }
        func isDone(_ slot: Slot) -> Bool {
            guard let doneAt else { return false }
            return calendar.isDate(doneAt, inSameDayAs: slot.start)
        }
        let today = sorted.filter { calendar.isDate($0.start, inSameDayAs: now) }
        if let current = today.first(where: { !isDone($0) && $0.start.addingTimeInterval(Self.sessionWindow) > now }) {
            return .today(current)
        }
        let next = sorted.first { !calendar.isDate($0.start, inSameDayAs: now) && $0.start > now && !isDone($0) }
        if today.isEmpty {
            return sorted.isEmpty ? .noPlan : .rest(next: next)
        }
        if let next { return .later(next) }
        return .rest(next: nil)
    }

    /// Times the "next session" complication should redraw on its own: each
    /// slot's start and end of window, and each midnight, for the next week.
    func changeDates(after now: Date, calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        let horizon = now.addingTimeInterval(8 * 86_400)
        for slot in slots {
            dates.append(slot.start)
            dates.append(slot.start.addingTimeInterval(Self.sessionWindow))
        }
        var day = calendar.startOfDay(for: now)
        for _ in 0..<8 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            dates.append(next)
            day = next
        }
        return Array(Set(dates.filter { $0 > now && $0 < horizon })).sorted()
    }

    /// Sample data for the face editor and placeholders.
    static func sample(now: Date = .now, calendar: Calendar = .current) -> WatchFaceData {
        let today = calendar.startOfDay(for: now)
        let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: today) ?? now
        let start = evening > now ? evening : now.addingTimeInterval(3600)
        let later = calendar.date(byAdding: .day, value: 2, to: start) ?? start
        return WatchFaceData(
            recovery: 72, band: "moderate", calibrating: false, strain: 34,
            targetLower: 50, targetUpper: 70, easyDay: false,
            slots: [
                Slot(start: start, title: "Push Day", shortTitle: "Push", symbol: "dumbbell.fill"),
                Slot(start: later, title: "Pull Day", shortTitle: "Pull", symbol: "dumbbell.fill"),
            ],
            lastWorkoutEnd: nil, updated: now
        )
    }
}

/// The complications' data in the Watch's App Group, written by the Watch
/// app and read by its widget extension.
nonisolated enum WatchFaceStore {
    static let appGroup = "group.com.lontraindustries.workoutapp"
    static let key = "watchFaceData"
    /// When a workout last ended on the Watch.
    static let workoutEndKey = "watchFaceWorkoutEnd"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load() -> WatchFaceData? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchFaceData.self, from: data)
    }

    /// Saves newer data. Returns true when the face would look different
    /// (so the complications are worth reloading), false when the data was
    /// older or only its timestamp moved.
    @discardableResult
    static func save(_ value: WatchFaceData) -> Bool {
        let current = load()
        if let current, current.updated >= value.updated { return false }
        guard let data = try? JSONEncoder().encode(value) else { return false }
        defaults.set(data, forKey: key)
        return current.map { !value.looksSame(as: $0) } ?? true
    }

    static var watchWorkoutEnd: Date? {
        defaults.object(forKey: workoutEndKey) as? Date
    }

    static func markWorkoutEnded(at date: Date) {
        defaults.set(date, forKey: workoutEndKey)
    }

    /// The latest workout end, from the phone's log or the Watch.
    static func lastWorkoutEnd(_ data: WatchFaceData?) -> Date? {
        [data?.lastWorkoutEnd, watchWorkoutEnd].compactMap { $0 }.max()
    }
}
