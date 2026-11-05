import Foundation

/// Home blood pressure, done the way guidelines recommend.
///
/// - Categories (ACC/AHA 2017, kept in the 2025 AHA/ACC guideline): normal
///   under 120/80; elevated 120-129 over under 80; stage 1 high 130-139 or
///   80-89; stage 2 high 140+ or 90+. Category is set by the higher of the two.
/// - A single reading isn't a diagnosis. The home protocol is two readings a
///   minute apart, morning and evening, for 7 days; leave out day 1 (readings
///   run high while you get used to it) and average the rest, ideally 12 or
///   more readings (AHA/ACC 2025; ESH home monitoring guidance).
/// - Readings of 180+ or 120+ need prompt attention.
/// - Cuffless (watch or ring) estimates aren't used: guidelines advise against
///   them for assessing blood pressure.
public enum HomeBloodPressure {
    public struct Reading: Sendable, Equatable {
        public var date: Date
        public var systolic: Double
        public var diastolic: Double

        public init(date: Date, systolic: Double, diastolic: Double) {
            self.date = date
            self.systolic = systolic
            self.diastolic = diastolic
        }
    }

    public enum Category: String, Sendable, CaseIterable {
        case normal = "Normal"
        case elevated = "Elevated"
        case stage1 = "High (stage 1)"
        case stage2 = "High (stage 2)"
        case severe = "Very high"
    }

    public static func category(systolic: Double, diastolic: Double) -> Category {
        if systolic >= 180 || diastolic >= 120 { return .severe }
        if systolic >= 140 || diastolic >= 90 { return .stage2 }
        if systolic >= 130 || diastolic >= 80 { return .stage1 }
        if systolic >= 120 { return .elevated }
        return .normal
    }

    /// What a category means, in plain words.
    public static func advice(_ category: Category) -> String {
        switch category {
        case .normal:
            "Normal. Keep it there with activity, sleep and not too much salt or alcohol."
        case .elevated:
            "Slightly above normal. Regular exercise, less salt and alcohol, and keeping a healthy weight bring it down."
        case .stage1:
            "In the high range (130/80 or more). Lifestyle changes help a lot; share your home average with your doctor."
        case .stage2:
            "In the high range (140/90 or more). Book a visit with your doctor and bring your home readings."
        case .severe:
            "Very high (180/120 or more). Rest 5 minutes and measure again. If it's still this high, contact your doctor right away. If you also have chest pain, shortness of breath, back pain, numbness, weakness, or changes in vision or speech, call emergency services."
        }
    }

    /// Readings recommended for a reliable home average.
    public static let recommendedReadings = 12

    public struct WeekCheck: Sendable, Equatable {
        /// Days in the last 7 with at least one reading.
        public var days: Int
        /// Readings averaged (day 1 left out).
        public var readingsUsed: Int
        public var systolic: Double?
        public var diastolic: Double?
        public var category: Category?
        /// Enough readings for a reliable average.
        public var isReliable: Bool { readingsUsed >= HomeBloodPressure.recommendedReadings }
    }

    /// The 7-day home check from the readings of the last 7 days (today included).
    public static func weekCheck(_ readings: [Reading], asOf: Date = .now, calendar: Calendar = .current) -> WeekCheck {
        let today = calendar.startOfDay(for: asOf)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else {
            return WeekCheck(days: 0, readingsUsed: 0)
        }
        let recent = readings.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
        let days = Set(recent.map { calendar.startOfDay(for: $0.date) })
        // Leave out the first day once there's a second day to average.
        var used = recent
        if days.count >= 2, let first = days.min() {
            used = recent.filter { calendar.startOfDay(for: $0.date) != first }
        }
        guard !used.isEmpty else { return WeekCheck(days: days.count, readingsUsed: 0) }
        let systolic = used.map(\.systolic).reduce(0, +) / Double(used.count)
        let diastolic = used.map(\.diastolic).reduce(0, +) / Double(used.count)
        return WeekCheck(
            days: days.count,
            readingsUsed: used.count,
            systolic: systolic,
            diastolic: diastolic,
            category: category(systolic: systolic, diastolic: diastolic)
        )
    }

    // MARK: Repeat cadence

    /// How often to repeat the 7-day home check: every 3 months when the
    /// last average was elevated or high, every 6 months when it was normal.
    /// Guidelines ask for home monitoring to be repeated at intervals rather
    /// than once (ESH 2021 home BP practice guidelines; ACC/AHA 2017 and the
    /// 2025 AHA/ACC guideline); the research round put the interval at 3-6
    /// months (docs/research/health-metrics.md, section 3), and the exact
    /// months here are the app's choice within that. A doctor's plan wins.
    public static func repeatMonths(after category: Category?) -> Int {
        switch category {
        case .normal, nil: 6
        case .elevated, .stage1, .stage2, .severe: 3
        }
    }

    /// When the next 7-day check is due, from the day the last one ended.
    public static func nextCheckDue(lastCheck: Date, category: Category?, calendar: Calendar = .current) -> Date {
        let months = repeatMonths(after: category)
        return calendar.date(byAdding: .month, value: months, to: calendar.startOfDay(for: lastCheck))
            ?? lastCheck.addingTimeInterval(Double(months) * 30 * 86_400)
    }

    public static func isCheckDue(lastCheck: Date, category: Category?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: now) >= nextCheckDue(lastCheck: lastCheck, category: category, calendar: calendar)
    }

    /// The most recent completed home check: the 7 days ending on the day of
    /// the latest reading, when that week had enough readings to count
    /// (`recommendedReadings`). Nil until a full check exists.
    public static func lastCompletedCheck(_ readings: [Reading], calendar: Calendar = .current) -> (ended: Date, check: WeekCheck)? {
        guard let latest = readings.map(\.date).max() else { return nil }
        let check = weekCheck(readings, asOf: latest, calendar: calendar)
        guard check.isReliable else { return nil }
        return (calendar.startOfDay(for: latest), check)
    }

    // MARK: Apple Watch hypertension notification

    /// Apple Watch's hypertension notification (Series 9+/Ultra 2+, watchOS 26,
    /// FDA-cleared Sept 2025) reviews 30 days of optical data and notifies on
    /// consistent signs of hypertension; Apple's validation against 30-day
    /// home blood pressure found sensitivity 41% and specificity 92%, so a
    /// notification is a good reason to do the home check and a missing one
    /// doesn't rule hypertension out (docs/research/watch-features.md 1.1,
    /// refs B1 MacRumors/Apple Sept 2025, B2 AAFP Community Blog, B3 JAMA
    /// research letter Dec 2025).
    public static let hypertensionNotificationSensitivity = 0.41
    public static let hypertensionNotificationSpecificity = 0.92
    /// How long after a notification the app keeps prompting the 7-day check:
    /// the notification itself covers 30 days of data (app's choice).
    public static let hypertensionPromptDays = 30

    /// The latest notification that still needs a home check: within the last
    /// `hypertensionPromptDays` and not followed by a completed 7-day check
    /// (`lastCompletedCheck` ending on or after the notification's day).
    public static func pendingHypertensionEvent(events: [Date], readings: [Reading], now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let latest = events.filter({ $0 <= now }).max() else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -hypertensionPromptDays, to: today), latest >= cutoff else { return nil }
        if let completed = lastCompletedCheck(readings, calendar: calendar),
           completed.ended >= calendar.startOfDay(for: latest) {
            return nil
        }
        return latest
    }
}
