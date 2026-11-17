import Foundation

/// Tonight's "bed by" window: a 30-minute span to be in bed by, worked back
/// from when you usually get up, the time in bed your sleep need takes and
/// the part of your sleep debt to repay tonight.
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
/// - Why longer in bed than the need: the need is hours asleep, and nobody is
///   asleep for all the time in bed. Sleep efficiency of 85% or more is the
///   mark of good sleep (Ohayon et al., Sleep Health 2017, National Sleep
///   Foundation), and healthy adults in sleep-lab studies average in the high
///   80s, about 2 points lower per decade of age (Boulos et al., Lancet Respir
///   Med 2019, meta-analysis of 169 studies; figures as summarised from the
///   abstract, the full text wasn't opened). So the window starts at wake −
///   need ÷ 0.9 (`assumedSleepEfficiency`). Without that, a 7.5 h need and a
///   6:30 wake gave 23:00-23:30: 7.0-7.5 h in bed, about 6.3-6.7 h asleep,
///   which builds the very debt the window is meant to prevent.
/// - Tomorrow's planned session only brings the wake time forward when it
///   starts early; there's no trial support for needing more sleep before a
///   hard day (docs/research/competitors.md), so it doesn't add to the need.
public enum BedtimeWindow {
    /// Width of the window, minutes.
    public static let windowMinutes = 30
    /// Share of time in bed spent asleep that the window assumes: 0.9, the top
    /// of the typical healthy range (85% or more is good sleep quality, Ohayon
    /// et al., Sleep Health 2017; sleep-lab averages for healthy adults are in
    /// the high 80s, Boulos et al., Lancet Respir Med 2019). The single figure
    /// is the app's choice: it isn't measured for the user, and someone asleep
    /// for 85% of the night gets about 25 minutes less than the need even from
    /// the start of the window (7.5 h need: 8 h 20 min in bed, 7 h 05 asleep).
    public static let assumedSleepEfficiency = 0.9
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
        /// Hours in bed the need takes at `assumedSleepEfficiency`
        /// (need ÷ 0.9); the window starts this long, plus tonight's
        /// repayment, before `wake`.
        public var timeInBedHours: Double = 0
        /// Minutes of sleep debt repaid tonight (0 when caught up).
        public var repaymentMinutes: Int
        /// True when `wake` was brought forward for a planned session.
        public var wakeForSession: Bool
        /// Shown when the Sleep Regularity Index is low.
        public var regularityNote: String?
        /// True while the insomnia path is on (`SleepWindow`,
        /// `BedtimeWindow.sleepWindow`): `start` is then the earliest bedtime
        /// of a fixed sleep window, not a time to be in bed by, and the wake
        /// time is fixed. Show `headline`, not "in bed by".
        public var isSleepWindow = false

        /// "8 h need (about 8 h 55 min in bed) + 40 min of debt to repay, up at 6:30"
        /// In sleep-window mode: "6 h 45 min sleep window, up at 6:30 every day".
        public var reason: String {
            if isSleepWindow {
                return "\(Self.hoursMinutes(timeInBedHours)) sleep window, up at \(Self.clock(wake)) every day"
            }
            var parts = "\(Self.hours(needHours)) need"
            if timeInBedHours > needHours { parts += " (about \(Self.hoursMinutes(timeInBedHours)) in bed)" }
            if repaymentMinutes > 0 { parts += " + \(repaymentMinutes) min of debt to repay" }
            parts += ", up at \(Self.clock(wake))"
            if wakeForSession { parts += " for your session" }
            return parts
        }

        /// "21:50–22:20"
        public var windowText: String { "\(Self.clock(start))–\(Self.clock(end))" }

        /// "8 h need + 40 min of debt to repay, up at 6:30 → in bed by 21:50–22:20"
        /// In sleep-window mode: "… → bed from 23:45, when sleepy".
        public var line: String {
            isSleepWindow ? "\(reason) → bed from \(Self.clock(start)), when sleepy" : "\(reason) → in bed by \(windowText)"
        }

        /// The one line to show for tonight in either mode: "In bed by
        /// 21:50–22:20", or "Bed from 23:45, up at 6:30" in sleep-window mode.
        public var headline: String {
            isSleepWindow ? "Bed from \(Self.clock(start)), up at \(Self.clock(wake))" : "In bed by \(windowText)"
        }

        static func hours(_ value: Double) -> String {
            "\(value.formatted(.number.precision(.fractionLength(0...2)))) h"
        }

        /// "8 h 20 min", to the nearest 5 minutes.
        static func hoursMinutes(_ value: Double) -> String {
            let minutes = Int((value * 60 / 5).rounded()) * 5
            return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
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
        // Time in bed for the need, not the need itself: about 90% of time in bed is sleep.
        let timeInBed = need / assumedSleepEfficiency
        let exactStart = wake.addingTimeInterval(-(timeInBed * 3600 + Double(repayment) * 60))
        // Down to 5 minutes ("21:50", not "21:53"): a little earlier, never later (display choice).
        let start = Date(timeIntervalSinceReferenceDate: (exactStart.timeIntervalSinceReferenceDate / 300).rounded(.down) * 300)
        let end = start.addingTimeInterval(TimeInterval(windowMinutes * 60))
        var note: String?
        if let regularity, regularity < lowRegularity {
            note = "Your sleep timing varies a lot (regularity \(regularity)/100). The same bedtime every night matters more than the extra minutes."
        }
        return Result(start: start, end: end, wake: wake, needHours: need, timeInBedHours: timeInBed,
                      repaymentMinutes: repayment, wakeForSession: wakeForSession, regularityNote: note)
    }
}
