import Foundation

/// Two measures that show only when they apply
/// (docs/research/evidence-audit-2026-11.md, Gaps, items 2 and 3):
/// - **Blood tests due**: one row in "Not measured yet" when a lipid panel,
///   Lp(a) or HbA1c is due (`BloodTestSchedule`). Nothing while all are up to date.
/// - **Saturated fat**: the week's share of energy against WHO's under 10%
///   (`SaturatedFat`). Nothing when the food app sends no saturated fat.
extension Longevity {
    /// Measures left out entirely until they apply.
    public static let conditionalMeasures: Set<MeasureID> = [.bloodTests, .saturatedFat]

    static func gapMeasures(_ i: Inputs) -> [Measure] {
        [bloodTests(i), saturatedFat(i)].compactMap { $0 }
    }

    /// Nil unless a test is due now. Status stays `.noData`, so the page lists
    /// it with the measures to add, not as on or off target.
    static func bloodTests(_ i: Inputs) -> Measure? {
        let due = BloodTestSchedule.dueNow(i.bloodTests)
        guard let summary = BloodTestSchedule.summary(i.bloodTests), !due.isEmpty else { return nil }
        let apoB = due.contains { $0.check == .lipids && $0.askForApoB } ? " Ask for ApoB with the cholesterol panel." : ""
        return Measure(
            id: .bloodTests, area: .bodyMetabolic, title: "Blood tests due", valueText: nil,
            targetText: "Cholesterol every \(BloodTestSchedule.lipidYears) years, Lp(a) once, HbA1c every \(BloodTestSchedule.glucoseYears) years from \(BloodTestSchedule.glucoseStartAge)",
            status: .noData,
            standing: summary + ".",
            nextStep: "Ask your doctor at your next visit, then add the results in Health › Records › Lab results.\(apoB) A doctor may advise a different schedule.",
            why: "Raised LDL, ApoB and Lp(a), and early high blood sugar, cause no symptoms for years. Finding them early is what lets you act on them.",
            grade: .strong,
            gradeNote: "Guideline recommendations. LDL causes atherosclerosis (genetic, cohort and trial evidence); the testing intervals themselves are expert consensus.",
            sources: [
                Source("Arnett et al., Circulation 2019;140:e596", kind: "ACC/AHA primary prevention guideline",
                       finding: "For adults 20-39, it is reasonable to assess traditional risk factors, cholesterol included, at least every 4 to 6 years."),
                Source("Kronenberg et al., Eur Heart J 2022;43:3925", kind: "European Atherosclerosis Society consensus",
                       finding: "Test Lp(a) at least once in adults; above about 50 mg/dL (125 nmol/L) it raises heart and aortic-valve risk."),
                Source("Blumenthal et al., J Am Coll Cardiol 2026;87:2624", kind: "ACC/AHA dyslipidemia guideline",
                       finding: "Lp(a) at least once in adulthood; ApoB to assess remaining risk. Interval details from a summary, not re-read.", verified: false),
                Source("ADA Standards of Care 2026, Diabetes Care 49 Suppl 1:S27", kind: "American Diabetes Association guideline",
                       finding: "Screen everyone from 35, every 3 years when normal and yearly in the prediabetes range; earlier with overweight and a risk factor.")
            ])
    }

    /// Nil when the food app sends no saturated fat (never a zero).
    static func saturatedFat(_ i: Inputs) -> Measure? {
        guard let week = i.saturatedFat else { return nil }
        var measure = Measure(
            id: .saturatedFat, area: .nutrition, title: "Saturated fat", valueText: week.shareText,
            targetText: "Under \(whole(SaturatedFat.limitShare))% of energy over the week",
            status: .onTarget,
            standing: "Last \(week.days) logged days, about \(whole(week.gramsPerDay)) g a day.",
            nextStep: week.line,
            why: "Eating less saturated fat lowers LDL cholesterol, and in trials lasting 2 years or more it cut heart attacks and strokes by about a sixth.",
            grade: .moderate,
            gradeNote: "Randomised trials, moderate quality: fewer cardiovascular events, but little or no change in overall mortality. What replaces it matters: unsaturated fats or whole grains, not refined carbs.",
            sources: [
                Source("Hooper et al., Cochrane Database Syst Rev 2020;8:CD011737", kind: "Cochrane review of 15 randomised trials, 56,675 people",
                       finding: "Cutting saturated fat for 2+ years lowered combined cardiovascular events by 17% (RR 0.83); all-cause mortality RR 0.96."),
                Source("WHO guideline, 2023", kind: "World Health Organization guideline on saturated and trans fats",
                       finding: "No more than 10% of energy from saturated fat, replaced by unsaturated plant fats or fibre-rich carbohydrates.")
            ])
        switch week.status {
        case .under: measure.status = .onTarget
        case .close: measure.status = .close
        case .over: measure.status = .off
        }
        return measure
    }
}
