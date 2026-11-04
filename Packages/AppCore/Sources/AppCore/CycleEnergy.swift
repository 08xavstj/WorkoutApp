import Foundation

/// Resting energy across the menstrual cycle: a note, not an adjustment.
///
/// Resting metabolic rate is a little higher in the luteal phase (the second
/// half of the cycle): a small effect in a meta-analysis of 26 studies and
/// 318 women (Benton, Hutchins & Dawes, PLoS One 2020: effect size 0.33,
/// smaller and not significant in the studies since 2000), about 30-120 kcal
/// a day or 3-5% in the newer studies (Hurtová et al., Front Physiol 2026,
/// systematic review of 7 studies). That is smaller than the error of any
/// equation or watch (±15-25%), inside the ±10% target band, and averaged
/// out by the 28-day maintenance estimate, which spans a whole cycle. So the
/// target isn't changed; the app only says why hunger may be up.
public enum CycleEnergy {
    /// Days since the last morning logged "On my period" (the period's last
    /// logged day, not its first) that roughly match the luteal phase of a
    /// 28-day cycle with a 4-5 day period: about cycle days 14-28. App
    /// approximation; cycles vary from about 21 to 35 days.
    public static let lutealDaysSincePeriod = 10...24

    /// "Probably in the second half of your cycle…", or nil for men, without
    /// a logged period, or outside the window.
    public static func note(sex: BiologicalSex, daysSinceLastPeriod: Int?) -> String? {
        guard sex == .female, let days = daysSinceLastPeriod, lutealDaysSincePeriod.contains(days) else { return nil }
        return "You're probably in the second half of your cycle, when resting burn runs a little higher, roughly 30-120 kcal a day (Benton 2020; Hurtová 2026; small and varies a lot). That's inside your ±10% band, so the target stays the same; if you're hungrier, eat toward the top of the band."
    }
}
