import Foundation

/// The menstrual cycle in "What moved recovery": a context note, not an
/// adjustment to the score.
///
/// Evidence: a meta-analysis of 37 studies (1,004 women) found vagally
/// mediated HRV falls from the follicular to the luteal phase, a small to
/// moderate within-person effect (d ≈ −0.4; Schmalenberger et al., J Clin
/// Med 2019;8:1946). The studies were small and varied in how they timed
/// the phase, and individual women differ a lot; here the phase is only guessed from the last logged period, and cycles vary from
/// about 21 to 35 days. That's weak ground for moving a score, so recovery
/// isn't changed: the note just says why HRV may sit lower.
public enum CycleRecovery {
    /// The same luteal-phase guess as the calorie note (`CycleEnergy`).
    public static var lutealDaysSincePeriod: ClosedRange<Int> { CycleEnergy.lutealDaysSincePeriod }

    /// A neutral contributor for women who logged a period 10-24 days ago;
    /// nil for men, without a logged period, or outside the window.
    public static func contributor(sex: BiologicalSex, daysSinceLastPeriod: Int?) -> RecoveryContributor? {
        guard sex == .female, let days = daysSinceLastPeriod, lutealDaysSincePeriod.contains(days) else { return nil }
        return RecoveryContributor(
            id: "cycle", name: "Menstrual cycle",
            detail: "Probably the second half of your cycle (\(days) days since your last logged period)",
            note: "HRV tends to dip a little in this phase (Schmalenberger 2019). Weak evidence for any one person, so your score isn't adjusted.",
            effect: .neutral
        )
    }
}
