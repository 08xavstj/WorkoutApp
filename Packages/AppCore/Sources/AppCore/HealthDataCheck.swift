import Foundation

/// The Health data check (Settings › Health data check): whether each
/// measure an Apple Watch writes to Apple Health reaches the app, and what to
/// do when it doesn't.
///
/// Apple Health never tells an app that read access is off: a type the user
/// switched off simply returns no readings, the same as a type with no data
/// (Apple, "Protecting user privacy", HealthKit documentation: "your app
/// can't determine whether the user granted permission to read data"). So the
/// check can only say "nothing reached Tensile" and name both causes. The
/// thresholds below are the app's, set from how often Apple Watch writes each
/// kind of measure; nothing here is a health threshold.
public enum HealthDataCheck {
    /// How often a measure normally arrives.
    public enum Cadence: Sendable, Equatable {
        /// Through the day (heart rate, steps, energy): expected within a day.
        case continuous
        /// While you sleep (breathing rate, wrist temperature, overnight HRV):
        /// expected for last night or the one before (a morning that hasn't
        /// synced yet).
        case nightly
        /// Every so often (VO₂ max after outdoor walks and runs, walking
        /// speed): expected within the 30-day window.
        case occasional
        /// Only when something is flagged (high heart rate, sleep apnoea,
        /// hypertension): none is the usual, good answer.
        case alert
    }

    public enum Status: Sendable, Equatable {
        /// Arriving as expected.
        case current
        /// There were readings in the window, but the newest is older than expected.
        case late(days: Int)
        /// Nothing in the window.
        case none
    }

    /// How far back the check looks.
    public static let windowDays = 30

    /// The newest reading's age a cadence allows, in days.
    static func allowedDays(_ cadence: Cadence) -> Int {
        switch cadence {
        case .continuous: 1
        case .nightly: 2
        case .occasional, .alert: windowDays
        }
    }

    /// The status of a measure whose newest reading (within `windowDays`) is `newest`.
    public static func status(newest: Date?, cadence: Cadence, now: Date, calendar: Calendar = .current) -> Status {
        guard let newest, newest <= now.addingTimeInterval(60) else { return .none }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: newest), to: calendar.startOfDay(for: now)).day ?? 0
        guard days <= windowDays else { return .none }
        return days <= allowedDays(cadence) ? .current : .late(days: days)
    }

    /// Where to switch read access on (iOS 26 and 27: Settings › Privacy &
    /// Security › Health › the app, the same switches as in the Health app's
    /// profile › Apps).
    public static func accessPath(healthName: String) -> String {
        "Settings › Privacy & Security › Health › Tensile, and turn on \(healthName)"
    }

    /// What to say under a measure, nil when it's arriving as expected.
    /// - Parameter healthName: the name the Health app uses ("Respiratory Rate").
    public static func advice(status: Status, cadence: Cadence, healthName: String) -> String? {
        switch (status, cadence) {
        case (.current, _):
            return nil
        case (.late(let days), .nightly):
            return "Nothing for the last \(days) nights. Apple Watch records this while you sleep, with Sleep on and the watch worn to bed."
        case (.late(let days), _):
            return "The newest reading is \(days) days old. Check that your watch is syncing with this iPhone."
        case (.none, .alert):
            return "No notifications in the last \(windowDays) days, which is the usual answer. If you've had one, Tensile can't read it: \(accessPath(healthName: healthName))."
        case (.none, .occasional):
            return "Nothing in the last \(windowDays) days. If the Health app shows \(healthName), Tensile can't read it: \(accessPath(healthName: healthName))."
        case (.none, _):
            return "Nothing in the last \(windowDays) days. If the Health app shows \(healthName), Tensile can't read it: \(accessPath(healthName: healthName))."
        }
    }
}
