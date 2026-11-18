import Foundation

/// Apple Watch's own heart notifications (high and low heart rate, irregular
/// rhythm), counted for one line in Health's heart section
/// (docs/research/next-features-2026-11.md, W5; §5 item 11). Tensile sends no
/// alerts of its own: Apple's notifications already run system-wide, and no
/// evidence says a second alert helps (W6).
///
/// Evidence and its limits: in a 2026 living meta-analysis, Apple Watch AF
/// detection had specificity 0.91 and sensitivity 0.79 (Lambe et al., NPJ
/// Digit Med 2026), and the base rate of AF is low at younger ages
/// (watch-features.md 1.9), so most irregular-rhythm notifications in young
/// adults are false alarms and a quiet month isn't an all-clear. High and low
/// heart rate notifications fire on thresholds the person sets in the Watch
/// app; there is no outcome evidence for counting them. The line therefore
/// only reports and points to the Health app, where the readings are.
public enum HeartEvents {
    /// Window counted (the research file's "this month"; 30 days is the app's choice).
    public static let windowDays = 30

    public struct Counts: Sendable, Equatable {
        public var high: Int
        public var low: Int
        public var irregular: Int

        public init(high: Int, low: Int, irregular: Int) {
            self.high = high
            self.low = low
            self.irregular = irregular
        }

        public var total: Int { high + low + irregular }

        /// "Apple flagged 2 high and 1 irregular rhythm alerts in the last 30
        /// days; see the Health app." Nil when there were none (the line is hidden).
        public var line: String? {
            guard total > 0 else { return nil }
            var parts: [String] = []
            if high > 0 { parts.append("\(high) high") }
            if low > 0 { parts.append("\(low) low") }
            if irregular > 0 { parts.append("\(irregular) irregular rhythm") }
            let listed: String
            switch parts.count {
            case 1: listed = parts[0]
            case 2: listed = parts[0] + " and " + parts[1]
            default: listed = parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
            }
            let noun = total == 1 ? "alert" : "alerts"
            return "Apple flagged \(listed) \(noun) in the last \(HeartEvents.windowDays) days; see the Health app."
        }
    }

    /// Counts from the event dates, keeping those in the last `windowDays`.
    public static func counts(high: [Date], low: [Date], irregular: [Date], now: Date = .now) -> Counts {
        let start = now.addingTimeInterval(-Double(windowDays) * 86_400)
        func count(_ dates: [Date]) -> Int { dates.filter { $0 >= start && $0 <= now }.count }
        return Counts(high: count(high), low: count(low), irregular: count(irregular))
    }

    /// The plain context under the line.
    public static let note = "These are Apple Watch's own notifications. Tensile doesn't add alerts. Irregular-rhythm notifications miss about 1 in 5 cases of AF and some are false alarms (Lambe et al. 2026), so talk to a doctor about symptoms whatever the count."
}
