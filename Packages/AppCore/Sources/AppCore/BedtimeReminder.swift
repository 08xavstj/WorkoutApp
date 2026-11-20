import Foundation

/// The bedtime reminder: one notification an evening, `windDownMinutes`
/// before tonight's bed-by window (`BedtimeWindow`), so there is time to
/// wind down and still be in bed inside the window.
///
/// Evidence, and its limits:
/// - A regular sleep schedule: sleep regularity predicted all-cause
///   mortality more strongly than sleep duration in about 60,000 UK Biobank
///   adults with accelerometers (Windred et al., Sleep 2024;47(1):zsad253).
///   The window comes from the same wake time every day, so a reminder at the
///   same clock time supports a regular bedtime.
/// - Wind-down: reading on a light-emitting e-reader in the 4 hours before
///   bed delayed melatonin and sleep onset against a printed book (Chang et
///   al., PNAS 2015;112(4):1232-7, n = 12, lab study). How long a wind-down
///   should be isn't settled: 30 minutes is the app's choice.
/// - Timing: a prompt helps when the person can act on it (Nahum-Shani et
///   al., Ann Behav Med 2018), and prompts lose effect with repetition
///   (Klasnja et al., Ann Behav Med 2019), so there is one a night, at the
///   moment it applies. The coach's quiet hours don't move it: they start at
///   22:00 by default, which is where a bedtime belongs; it has its own switch
///   (Settings › Sleep & rest).
/// - No trial was found showing that a bedtime notification by itself lengthens
///   sleep, so the app claims nothing beyond the window it reminds of.
public enum BedtimeReminder {
    /// Minutes before the start of the bed-by window (app's choice, see above).
    public static let windDownMinutes = 30
    /// Nights scheduled ahead, at the same clock time, until the app next
    /// refreshes them with the latest window (app's choice: iOS keeps 64
    /// pending notifications per app, and doses come first).
    public static let nightsAhead = 3

    /// When the reminder goes out for each of the next `nightsAhead` nights:
    /// `windDownMinutes` before `windowStart`'s clock time, from tonight,
    /// skipping any time already past.
    public static func fireDates(windowStart: Date, now: Date, calendar: Calendar = .current) -> [Date] {
        let first = windowStart.addingTimeInterval(-Double(windDownMinutes) * 60)
        return (0..<(nightsAhead + 1)).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
            .filter { $0 > now }
            .prefix(nightsAhead)
            .map { $0 }
    }

    /// Title and body for the window.
    /// - Parameters:
    ///   - windowText: "22:30–23:00".
    ///   - startText: "22:30", the window's start.
    ///   - reason: `BedtimeWindow.Result.reason`.
    ///   - sleepWindow: the insomnia path is on: bed only when sleepy, from the start.
    public static func content(windowText: String, startText: String, reason: String, sleepWindow: Bool) -> (title: String, body: String) {
        if sleepWindow {
            // CBT-I's stimulus control: to bed when sleepy, not before the window (`SleepWindow`).
            return ("Bed from \(startText), when sleepy",
                    "Wind down now: lights low, screens away. Tonight: \(reason).")
        }
        return ("In bed by \(windowText)",
                "Time to wind down: lights low and screens away for the next \(windDownMinutes) minutes. Worked back from \(reason).")
    }
}
