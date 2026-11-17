import Foundation

// An interval session's targets in beats per minute, from the zone scheme the
// user picked (`HeartRateZoneScheme`, the same one the Watch's cardio mode
// uses). Needs only Foundation, `IntervalSession.swift` and
// `HeartRateZoneScheme.swift`, so the Watch app can compile all three.

extension IntervalSession.Band {
    /// The bpm band to hold, or nil for no band. `.easy` is the scheme's easy
    /// band (as the Watch's "Easy" target); a zone range runs from the start
    /// of its lower zone to the end of its upper one (no top for zone 5).
    public nonisolated func heartRateBand(in scheme: HeartRateZoneScheme) -> HeartRateBand? {
        switch self {
        case .none:
            return nil
        case .easy:
            return scheme.easyBand
        case .zones(let low, let high):
            guard let lower = scheme.band(forZone: min(low, high)), let upper = scheme.band(forZone: max(low, high)) else { return nil }
            return HeartRateBand(lower: lower.lower, upper: upper.upper)
        }
    }

    /// "Zone 4-5 · 160+ bpm", "Easy · 120–140 bpm", or the title alone without a scheme.
    public nonisolated func text(in scheme: HeartRateZoneScheme?) -> String {
        guard let scheme, let band = heartRateBand(in: scheme) else { return title }
        return "\(title) · \(band.text) bpm"
    }
}
