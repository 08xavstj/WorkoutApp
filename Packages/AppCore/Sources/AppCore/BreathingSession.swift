import Foundation

/// A 5-minute paced-breathing session at about 6 breaths a minute.
///
/// Voluntary slow breathing near 0.1 Hz (about 6 breaths/min) raises HRV
/// during and right after the session (Laborde et al., Neurosci Biobehav Rev
/// 2022, meta-analysis) and lowers anxiety and arousal markers (Zaccaro et
/// al., Front Hum Neurosci 2018, systematic review). The evidence is for the
/// acute effect; long-term health effects are weaker (docs/research/competitors.md
/// item 6: "moderate for acute HRV and anxiety, weak for long-term health").
public enum PacedBreathing {
    /// 5.5 s in + 5.5 s out = 11 s a breath ≈ 5.5 breaths/min, the slow-
    /// breathing range the meta-analyses pooled (Laborde 2022; Zaccaro 2018).
    public static let inhaleSeconds: TimeInterval = 5.5
    public static let exhaleSeconds: TimeInterval = 5.5
    public static var cycleSeconds: TimeInterval { inhaleSeconds + exhaleSeconds }
    /// 5 minutes: the short end of the 5-10 min sessions in the reviews
    /// (competitors.md item 6); long enough for the acute HRV rise.
    public static let sessionSeconds: TimeInterval = 5 * 60
    public static var breathsPerMinute: Double { 60 / cycleSeconds }
    /// Heart rate is averaged over the 60 s before the session starts and
    /// the last 60 s of the session, when the watch recorded any.
    public static let heartRateWindowSeconds: TimeInterval = 60
    /// Evening check-in stress at or above this (4-5 on 1-5) offers a session.
    public static let stressOfferThreshold = 4

    public static let evidenceNote = "Slow breathing raises HRV and lowers anxiety right after a session (Laborde 2022; Zaccaro 2018); the long-term effect is less certain."

    public enum Phase: String, Sendable, Equatable {
        case inhale = "Breathe in"
        case exhale = "Breathe out"
    }

    /// Which half of the breath `elapsed` seconds into the session falls in,
    /// and how far through that half (0-1).
    public static func phase(at elapsed: TimeInterval) -> (phase: Phase, progress: Double) {
        let clamped = max(0, elapsed)
        let inCycle = clamped.truncatingRemainder(dividingBy: cycleSeconds)
        if inCycle < inhaleSeconds {
            return (.inhale, inCycle / inhaleSeconds)
        }
        return (.exhale, (inCycle - inhaleSeconds) / exhaleSeconds)
    }

    /// Size of the guide circle (0.55-1.0 of its full size), eased so the
    /// turn-arounds are soft: smallest at the start of a breath in, largest
    /// at the start of a breath out.
    public static func scale(at elapsed: TimeInterval) -> Double {
        let (phase, progress) = phase(at: elapsed)
        let eased = 0.5 - 0.5 * cos(progress * .pi)
        let fraction = phase == .inhale ? eased : 1 - eased
        return 0.55 + 0.45 * fraction
    }

    /// Seconds left, never negative.
    public static func remaining(at elapsed: TimeInterval) -> TimeInterval {
        max(0, sessionSeconds - elapsed)
    }

    public static func isComplete(at elapsed: TimeInterval) -> Bool {
        elapsed >= sessionSeconds
    }

    /// Offered on an easy (HRV-below-normal) day or after a stressful day in
    /// the evening check-in (competitors.md item 6: "offer it when recovery is
    /// low, stress check-in is high").
    public static func isOffered(easyDay: Bool, eveningStress: Int?) -> Bool {
        easyDay || (eveningStress ?? 0) >= stressOfferThreshold
    }

    /// Mean heart rate of the samples inside `window`, or nil when there were
    /// none (a watch at rest may not record for minutes at a time).
    public static func averageHeartRate(_ samples: [HeartRateSample], in window: DateInterval) -> Double? {
        let inside = samples.filter { window.contains($0.date) && $0.bpm > 0 }
        guard !inside.isEmpty else { return nil }
        return inside.map(\.bpm).reduce(0, +) / Double(inside.count)
    }

    /// "Heart rate 64 → 58 bpm" or a line saying there was no reading.
    public static func heartRateText(before: Double?, after: Double?) -> String {
        switch (before, after) {
        case let (before?, after?):
            let change = after - before
            let arrow = change <= -1 ? "down" : (change >= 1 ? "up" : "about the same")
            return "Heart rate \(Int(before.rounded())) → \(Int(after.rounded())) bpm, \(arrow)."
        case let (before?, nil):
            return "Heart rate \(Int(before.rounded())) bpm before; no reading at the end."
        case let (nil, after?):
            return "Heart rate \(Int(after.rounded())) bpm at the end; no reading before."
        default:
            return "No heart rate recorded around the session."
        }
    }
}

/// One finished session, kept locally with the heart rate before and after.
public struct BreathingSession: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var heartRateBefore: Double?
    public var heartRateAfter: Double?

    public init(id: UUID = UUID(), start: Date, end: Date, heartRateBefore: Double? = nil, heartRateAfter: Double? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.heartRateBefore = heartRateBefore
        self.heartRateAfter = heartRateAfter
    }

    public var minutes: Int { Int(end.timeIntervalSince(start) / 60) }

    /// Beats per minute the heart rate fell during the session, when both ends were read.
    public var heartRateDrop: Double? {
        guard let heartRateBefore, let heartRateAfter else { return nil }
        return heartRateBefore - heartRateAfter
    }
}
