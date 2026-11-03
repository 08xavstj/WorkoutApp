import Foundation

/// Tonight's "bed by" window: a 30-minute span to be in bed by, worked back
/// from when you usually get up, your sleep need and the part of your sleep
/// debt to repay tonight.
///
/// - Why a bedtime and not a wake time: regular sleep timing predicted
///   mortality more strongly than sleep length in 60,977 UK Biobank adults
///   (Windred et al., Sleep 2024), so the wake time stays where it is and the
///   extra sleep comes from going to bed earlier.
/// - Why repay debt at all: extending sleep improved sprint times, reaction
///   time and mood in college athletes (Mah et al., Sleep 2011).
/// - Why at most an hour a night: debt is paid back over days, not in one
///   long night (Kitamura et al., Sci Rep 2016), and an hour is already the
///   top of the `SleepDebt` plan.
/// - Tomorrow's planned session only brings the wake time forward when it
///   starts early; there's no trial support for needing more sleep before a
///   hard day (docs/research/competitors.md), so it doesn't add to the need.
public enum BedtimeWindow {
    /// Width of the window, minutes.
    public static let windowMinutes = 30
    /// Most sleep debt repaid in one night, minutes (Kitamura et al., Sci Rep 2016).
    public static let maxRepaymentMinutes = 60
    /// Time to get up and get going before an early planned session, minutes
    /// (an app choice, not a study).
    public static let preSessionMinutes = 60
    /// Below this Sleep Regularity Index you're in the least regular fifth of
    /// UK Biobank adults (Windred et al., Sleep 2024), so the note stresses
    /// keeping the same time rather than the extra minutes.
    public static let lowRegularity = 72
    /// A wake time has to be at least this far ahead to be "tomorrow's";
    /// closer than that and the night has already started (app choice).
    static let minimumHoursAhead = 4.0

    public struct Result: Sendable, Equatable {
        /// Be in bed between `start` and `end`.
        public var start: Date
        public var end: Date
        /// The wake time the window is worked back from.
        public var wake: Date
        public var needHours: Double
        /// Minutes of sleep debt repaid tonight (0 when caught up).
        public var repaymentMinutes: Int
        /// True when `wake` was brought forward for a planned session.
        public var wakeForSession: Bool
        /// Shown when the Sleep Regularity Index is low.
        public var regularityNote: String?

        /// "8 h need + 40 min of debt to repay, up at 6:30"
        public var reason: String {
            var parts = "\(Self.hours(needHours)) need"
            if repaymentMinutes > 0 { parts += " + \(repaymentMinutes) min of debt to repay" }
            parts += ", up at \(Self.clock(wake))"
            if wakeForSession { parts += " for your session" }
            return parts
        }

        /// "21:50–22:20"
        public var windowText: String { "\(Self.clock(start))–\(Self.clock(end))" }

        /// "8 h need + 40 min of debt to repay, up at 6:30 → in bed by 21:50–22:20"
        public var line: String { "\(reason) → in bed by \(windowText)" }

        static func hours(_ value: Double) -> String {
            "\(value.formatted(.number.precision(.fractionLength(0...2)))) h"
        }

        static func clock(_ date: Date) -> String {
            date.formatted(date: .omitted, time: .shortened)
        }
    }

    /// Your usual wake time as minutes after midnight: the median of recent
    /// wake times (nil without any).
    public static func usualWakeMinutes(_ wakes: [Date], calendar: Calendar = .current) -> Int? {
        let minutes = wakes.map { wake -> Int in
            let parts = calendar.dateComponents([.hour, .minute], from: wake)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }.sorted()
        guard !minutes.isEmpty else { return nil }
        return minutes[minutes.count / 2]
    }

    /// - Parameters:
    ///   - sleepNeedHours: hours of sleep you need (6-11).
    ///   - sleepDebt: the 14-night sleep debt; its nightly plan sets tonight's repayment.
    ///   - usualWakeMinutes: when you usually get up, minutes after midnight (`usualWakeMinutes(_:)`).
    ///   - regularity: your Sleep Regularity Index, 0-100, if known.
    ///   - plannedSessionStart: tomorrow's planned session, if any.
    ///   - now: when the window is being worked out.
    /// - Returns: nil without a wake time.
    public static func compute(
        sleepNeedHours: Double,
        sleepDebt: SleepDebt.Result?,
        usualWakeMinutes: Int?,
        regularity: Int?,
        plannedSessionStart: Date? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Result? {
        guard let usualWakeMinutes else { return nil }
        let need = min(11, max(6, sleepNeedHours))
        // The next time your usual wake time comes round, at least a few hours away.
        let today = calendar.startOfDay(for: now)
        let earliest = now.addingTimeInterval(minimumHoursAhead * 3600)
        var wake = today.addingTimeInterval(TimeInterval(usualWakeMinutes * 60))
        while wake < earliest {
            wake = calendar.date(byAdding: .day, value: 1, to: wake) ?? wake.addingTimeInterval(86_400)
        }
        var wakeForSession = false
        if let session = plannedSessionStart {
            let upBy = session.addingTimeInterval(-TimeInterval(preSessionMinutes * 60))
            if upBy > earliest && upBy < wake {
                wake = upBy
                wakeForSession = true
            }
        }
        let repayment = min(maxRepaymentMinutes, max(0, sleepDebt?.extraMinutesPerNight ?? 0))
        let start = wake.addingTimeInterval(-(need * 3600 + Double(repayment) * 60))
        let end = start.addingTimeInterval(TimeInterval(windowMinutes * 60))
        var note: String?
        if let regularity, regularity < lowRegularity {
            note = "Your sleep timing varies a lot (regularity \(regularity)/100). The same bedtime every night matters more than the extra minutes."
        }
        return Result(start: start, end: end, wake: wake, needHours: need, repaymentMinutes: repayment,
                      wakeForSession: wakeForSession, regularityNote: note)
    }
}
