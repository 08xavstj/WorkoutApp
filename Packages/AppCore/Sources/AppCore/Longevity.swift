import Foundation

/// The handful of measures most strongly linked with living longer and
/// better, and where the user stands on each (docs/research/longevity-insights.md).
///
/// What this is not: a score. There is no composite "longevity score" and no
/// "years gained" here, because no validated published model supports one
/// from this data (the body-age composite was removed for that reason:
/// evidence-audit-2026-11.md). Each measure stands alone with its own published target, its
/// source and an evidence grade.
///
/// Almost all of the evidence is observational: people who had the better
/// number lived longer, which is not proof that changing the number changes
/// the outcome. So the copy says "linked with", and `Grade` and
/// `Source.kind` say what kind of study stands behind each line. Blood
/// pressure and protein are the two with randomised-trial evidence.
///
/// Citations were checked against the PubMed record (title, authors, journal,
/// year and the numbers quoted) in November 2026 unless `Source.verified` is
/// false; those are shown as "not re-verified".
public enum Longevity {
    // MARK: Types

    public enum Area: String, CaseIterable, Sendable, Codable, Identifiable {
        case heartFitness, movement, strength, sleep, bodyMetabolic, nutrition, alcohol, hearing, mind

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .heartFitness: "Heart and fitness"
            case .movement: "Movement"
            case .strength: "Strength"
            case .sleep: "Sleep"
            case .bodyMetabolic: "Body and blood pressure"
            case .nutrition: "Nutrition"
            case .alcohol: "Alcohol"
            case .hearing: "Hearing"
            case .mind: "Mood"
            }
        }
    }

    /// How strong the evidence for a measure's target is. Same scale as
    /// docs/research/health-metrics.md: strong = meta-analyses of trials,
    /// large pooled cohorts with a consistent dose-response, or guideline
    /// consensus; moderate = one large cohort, or a guideline resting on
    /// lower-quality evidence; limited = weak, mixed or no published target.
    public enum Grade: Int, Sendable, Codable, CaseIterable, Comparable {
        case limited = 0, moderate, strong

        public var label: String {
            switch self {
            case .strong: "Strong evidence"
            case .moderate: "Moderate evidence"
            case .limited: "Limited evidence"
            }
        }

        public static func < (lhs: Grade, rhs: Grade) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Status: String, Sendable, Codable, CaseIterable {
        case onTarget, close, off
        /// There is a value, but no published target to judge it by (mood).
        case tracking
        case noData

        public var label: String {
            switch self {
            case .onTarget: "On target"
            case .close: "Close"
            case .off: "Off target"
            case .tracking: "No set target"
            case .noData: "No data yet"
            }
        }
    }

    public struct Source: Sendable, Equatable, Identifiable {
        /// "Laukkanen et al., Mayo Clin Proc 2022"
        public var citation: String
        /// "Meta-analysis of 37 cohort studies"
        public var kind: String
        /// What it found, with the numbers.
        public var finding: String
        /// Checked against the published record this round.
        public var verified: Bool

        public var id: String { citation }

        public init(_ citation: String, kind: String, finding: String, verified: Bool = true) {
            self.citation = citation
            self.kind = kind
            self.finding = finding
            self.verified = verified
        }
    }

    public enum MeasureID: String, CaseIterable, Sendable, Codable {
        case vo2Max, restingHeartRate
        case steps, activeMinutes
        case strengthDays, gripStrength
        case sleepDuration, sleepRegularity
        case waistToHeight, bloodPressure
        case fiber, protein
        case alcohol
        case headphoneSound
        case mood
    }

    public struct Measure: Sendable, Equatable, Identifiable {
        public var id: MeasureID
        public var area: Area
        public var title: String
        /// "44 ml/kg/min"; nil without data.
        public var valueText: String?
        /// "42 or more" (for the user's age, sex and goals).
        public var targetText: String
        public var status: Status
        /// One line on where the value sits, or what's missing.
        public var standing: String
        /// The one most useful next step.
        public var nextStep: String
        /// Why it's on the page, in "linked with" terms.
        public var why: String
        public var grade: Grade
        /// What kind of evidence the grade rests on, and its limits.
        public var gradeNote: String
        public var sources: [Source]
    }

    public struct AreaResult: Sendable, Equatable, Identifiable {
        public var area: Area
        public var measures: [Measure]
        public var id: Area { area }

        /// Measures with a value, for the page's rows.
        public var measured: [Measure] { measures.filter { $0.status != .noData } }
        public var missing: [Measure] { measures.filter { $0.status == .noData } }
    }

    public struct Assessment: Sendable, Equatable {
        public var areas: [AreaResult]

        public var measures: [Measure] { areas.flatMap(\.measures) }

        public func count(_ status: Status) -> Int { measures.filter { $0.status == status }.count }

        public func measure(_ id: MeasureID) -> Measure? { measures.first { $0.id == id } }

        /// Measures that are off or close, the ones to act on first: off
        /// before close, stronger evidence before weaker, then page order.
        public var toWorkOn: [Measure] {
            measures.enumerated()
                .filter { $0.element.status == .off || $0.element.status == .close }
                .sorted { a, b in
                    let rank: (Measure) -> Int = { $0.status == .off ? 0 : 1 }
                    if rank(a.element) != rank(b.element) { return rank(a.element) < rank(b.element) }
                    if a.element.grade != b.element.grade { return a.element.grade > b.element.grade }
                    return a.offset < b.offset
                }
                .map(\.element)
        }

        /// The single most useful next step, if anything is off or close.
        public var focus: Measure? { toWorkOn.first }

        /// "6 on target · 2 close · 1 off target"; nil with no data at all.
        public var summary: String? {
            let parts = [
                (count(.onTarget), "on target"),
                (count(.close), "close"),
                (count(.off), "off target")
            ].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    /// Everything `assess` needs, all optional: the app fills in what its
    /// models already hold (`LongevityAssembler`).
    public struct Inputs: Sendable, Equatable {
        public var age: Int
        public var sex: BiologicalSex
        public var goals: Goals?
        /// The VO₂ max the app scores with (watch reading or the app's estimate).
        public var vo2Max: Double?
        public var vo2IsEstimate = false
        /// 14-day average, bpm.
        public var restingHeartRate: Double?
        public var systolic: Double?
        public var diastolic: Double?
        /// True when the pair is a 7-day home average; a single reading isn't classed.
        public var bloodPressureIsHomeAverage = false
        /// Average of full days over about 30 days.
        public var dailySteps: Double?
        /// Last 7 days, from heart rate.
        public var moderateMinutes: Int?
        public var vigorousMinutes: Int?
        /// Strength days in each of the last 4 weeks, oldest first.
        public var strengthDaysByWeek: [Int]?
        public var gripKg: Double?
        /// 14-night average hours asleep, and how many nights it covers.
        public var sleepHours: Double?
        public var sleepNights = 0
        /// Sleep Regularity Index, 0-100.
        public var sleepRegularity: Int?
        public var waistToHeight: Double?
        /// 7-day average from the food log.
        public var fiberGrams: Double?
        public var proteinGrams: Double?
        public var proteinTargetGrams: Double?
        /// Standard drinks over the last 7 evenings, and how many were logged.
        public var drinksPerWeek: Double?
        public var drinkNightsLogged = 0
        /// Share of the WHO-ITU weekly headphone budget, percent.
        public var headphoneBudgetPercent: Double?
        /// 14-day average State of Mind valence, -1...1, and its entry count.
        public var moodValence: Double?
        public var moodEntries = 0

        public init(age: Int, sex: BiologicalSex, goals: Goals? = nil) {
            self.age = age
            self.sex = sex
            self.goals = goals
        }
    }

    // MARK: Assess

    public static func assess(_ inputs: Inputs) -> Assessment {
        let all: [Measure] = [
            vo2Max(inputs), restingHeartRate(inputs),
            steps(inputs), activeMinutes(inputs),
            strengthDays(inputs), gripStrength(inputs),
            sleepDuration(inputs), sleepRegularity(inputs),
            waistToHeight(inputs), bloodPressure(inputs),
            fiber(inputs), protein(inputs),
            alcohol(inputs),
            headphoneSound(inputs),
            mood(inputs)
        ]
        let areas = Area.allCases.map { area in
            AreaResult(area: area, measures: all.filter { $0.area == area })
        }
        return Assessment(areas: areas)
    }

    // MARK: - Heart and fitness

    /// VO₂ max percentile groups as Mandsager et al. defined them (JAMA Netw
    /// Open 2018): low under the 25th percentile for age and sex, below
    /// average 25th-49th, above average 50th-74th, high 75th-97.6th, elite
    /// above that. Low fitness carried the highest risk (low vs elite hazard
    /// ratio 5.04; below vs above average 1.41), so under the 25th is "off".
    public static let vo2LowPercentile = 25.0
    /// The line for "on target": the age-and-sex median (above-average group
    /// and up). With a stamina goal it is the 75th percentile, Mandsager's
    /// "high" group: risk kept falling with no upper limit (elite vs high
    /// hazard ratio 0.77; Kokkinos et al., J Am Coll Cardiol 2022: lowest
    /// risk near 14 METs). Which band a goal aims at is the app's choice; the
    /// bands are the published ones.
    public static func vo2TargetPercentile(goals: Goals?) -> Double {
        goals?.focuses.contains(.endurance) == true ? 75 : 50
    }

    static func vo2Max(_ i: Inputs) -> Measure {
        let sources = [
            Source("Laukkanen et al., Mayo Clin Proc 2022;97:1054", kind: "Meta-analysis of 37 cohort studies, 2.26 million people",
                   finding: "Each 1-MET (3.5 ml/kg/min) higher fitness was linked with 11% lower all-cause mortality; top vs bottom third 45% lower."),
            Source("Mandsager et al., JAMA Netw Open 2018;1:e183605", kind: "Cohort of 122,007 treadmill-tested adults",
                   finding: "Mortality fell with every step up in fitness and was lowest in the fittest group, with no upper limit of benefit. Low fitness (under the 25th percentile) carried the highest risk."),
            Source("Kokkinos et al., J Am Coll Cardiol 2022;80:598", kind: "Cohort of 750,302 US veterans",
                   finding: "The link was graded across age, sex and race; the least fit had about 4 times the risk of the fittest."),
            Source("Kaminsky et al., Mayo Clin Proc 2015;90:1515", kind: "Reference values (FRIEND registry)",
                   finding: "The age-and-sex percentiles used for your target."),
            Source("Wen et al., J Sci Med Sport 2019;22:941", kind: "Meta-analysis of 53 trials",
                   finding: "Intervals of 2 minutes or longer, 15 minutes or more of hard work a session, over 4-12 weeks raised VO₂ max most.")
        ]
        let cuts = VO2Norms.cutPoints(age: i.age, sex: i.sex)
        let wantsStamina = vo2TargetPercentile(goals: i.goals) > 50
        var measure = Measure(
            id: .vo2Max, area: .heartFitness, title: "VO₂ max", valueText: nil,
            targetText: "At or above the middle for your age and sex", status: .noData,
            standing: "No VO₂ max yet.",
            nextStep: "An outdoor walk or run of 20 minutes with your watch gives a reading.",
            why: "Aerobic fitness is the measure most strongly linked with a longer life. The link holds at every age, and no level was found where more stopped helping.",
            grade: .strong,
            gradeNote: "Large cohorts and a meta-analysis agree, with a clear dose-response. Observational: fitter people lived longer, which doesn't prove that raising yours lengthens life. Watch values are estimates (about ±5).",
            sources: sources)
        guard cuts.count >= 5 else { return measure }
        let target = wantsStamina ? cuts[4] : cuts[3]
        let low = cuts[2]
        measure.targetText = "\(whole(target)) or more"
            + (wantsStamina ? " (top quarter for your age and sex, for your stamina goal)" : " (the middle for your age and sex)")
        guard let vo2 = i.vo2Max, vo2 > 10 else { return measure }
        measure.valueText = "\(whole(vo2)) ml/kg/min" + (i.vo2IsEstimate ? " (estimate)" : "")
        let percentile = VO2Norms.percentile(vo2: vo2, age: i.age, sex: i.sex)
        let place = "About the \(VO2Norms.ordinal(Int(percentile.rounded()))) percentile for people \(VO2Norms.peerText(age: i.age))."
        if vo2 >= target {
            measure.status = .onTarget
            measure.standing = place
            measure.nextStep = "Keep one harder cardio session a week to hold it."
        } else if vo2 >= low {
            measure.status = .close
            measure.standing = place + " \(whole(target - vo2 + 0.499)) below your target."
            measure.nextStep = "Add one interval session a week: 4 rounds of 4 minutes hard, 3 minutes easy."
        } else {
            measure.status = .off
            measure.standing = place + " The lowest quarter had the highest risk."
            measure.nextStep = "Start with brisk walks or easy rides, 3 a week of 20-30 minutes. The first step up is the one with the biggest gain."
        }
        return measure
    }

    /// Resting heart rate bands from the one meta-analysis that reports them
    /// (Zhang et al., CMAJ 2016, 46 studies): against the lowest category,
    /// 60-80 bpm had a relative risk of 1.12 for all-cause mortality and over
    /// 80 bpm 1.45; each 10 bpm was 9% more. The studies measured it sitting
    /// in a clinic, and a watch reads a few beats lower overnight, so the
    /// bands flatter a watch value a little.
    public static let restingHeartRateTarget = 60.0
    public static let restingHeartRateHigh = 80.0

    static func restingHeartRate(_ i: Inputs) -> Measure {
        var measure = Measure(
            id: .restingHeartRate, area: .heartFitness, title: "Resting heart rate", valueText: nil,
            targetText: "Under 60 bpm", status: .noData,
            standing: "No resting heart rate yet.",
            nextStep: "Wear your watch overnight for a few nights.",
            why: "A lower resting heart rate is linked with lower risk of early death, and it falls as fitness improves.",
            grade: .moderate,
            gradeNote: "A meta-analysis of 46 cohort studies. Observational, and partly a mirror of fitness: it is a marker to watch more than a target to chase. Studies measured it in a clinic; watches read a little lower.",
            sources: [
                Source("Zhang, Shen & Qi, CMAJ 2016;188:E53", kind: "Meta-analysis of 46 cohort studies, 1.2 million people",
                       finding: "Each 10 bpm higher went with 9% higher all-cause mortality. Against the lowest group, 60-80 bpm had 12% higher risk and over 80 bpm 45% higher."),
                Source("Reimers, Knapp & Reimers, J Clin Med 2018;7:503", kind: "Systematic review of controlled trials",
                       finding: "Regular exercise, endurance training most of all, lowers resting heart rate.")
            ])
        guard let rhr = i.restingHeartRate, rhr > 25 else { return measure }
        measure.valueText = "\(whole(rhr)) bpm"
        if rhr < restingHeartRateTarget {
            measure.status = .onTarget
            measure.standing = "In the lowest-risk group in the studies."
            measure.nextStep = "Nothing to change. A rise of several beats over a week is the thing to notice."
        } else if rhr <= restingHeartRateHigh {
            measure.status = .close
            measure.standing = "In the 60-80 group, which had slightly higher risk than under 60."
            measure.nextStep = "Regular cardio brings it down over months: two or three sessions a week."
        } else {
            measure.status = .off
            measure.standing = "Over 80, the group with clearly higher risk in the studies."
            measure.nextStep = "Build up easy cardio, and mention it at your next check-up if it stays over 80."
        }
        return measure
    }

    // MARK: - Movement

    /// Steps: 7,000 a day against 2,000 was linked with 47% lower all-cause
    /// mortality, with the curve bending at about 5,000-7,000 (Ding et al.,
    /// Lancet Public Health 2025); risk kept falling to 8,000-10,000 under 60
    /// and 6,000-8,000 from 60 (Paluch et al., Lancet Public Health 2022).
    /// The on-target line is the health floor the weekly review also ticks
    /// (`HealthFloors.dailySteps`: 7,000 at every age, where most of the
    /// benefit is in; why not 8,000 under 60 is argued there). Under 5,000,
    /// the bottom of Ding's bend where the curve is steepest, is "off".
    public static let stepsLow = 5_000.0

    static func steps(_ i: Inputs) -> Measure {
        let target = HealthFloors.dailySteps
        var measure = Measure(
            id: .steps, area: .movement, title: "Daily steps", valueText: nil,
            targetText: "\(grouped(target)) a day or more", status: .noData,
            standing: "No step counts yet.",
            nextStep: "Carry your phone or wear your watch through the day.",
            why: "More daily steps are linked with lower risk of early death, heart disease, dementia and depression. Most of the gain comes by about 7,000 a day.",
            grade: .strong,
            gradeNote: "Two meta-analyses of device-measured steps with a consistent dose-response. Observational: people who are well walk more, so part of the link runs the other way.",
            sources: [
                Source("Ding et al., Lancet Public Health 2025;10:e668", kind: "Dose-response meta-analysis, 31 studies from 24 cohorts",
                       finding: "7,000 steps a day against 2,000 was linked with 47% lower all-cause mortality. The curve bends at about 5,000-7,000."),
                Source("Paluch et al., Lancet Public Health 2022;7:e219", kind: "Meta-analysis of 15 cohorts, 47,471 adults",
                       finding: "Risk kept falling up to 8,000-10,000 steps a day under age 60 and 6,000-8,000 from 60.")
            ])
        guard let steps = i.dailySteps, steps > 0 else { return measure }
        measure.valueText = "\(grouped(steps)) a day"
        if HealthFloors.stepsMet(steps) {
            measure.status = .onTarget
            measure.standing = "In the range where the studies found most of the benefit."
            measure.nextStep = "Keep it up. More is fine, but the extra gain past here is small."
        } else if steps >= stepsLow {
            measure.status = .close
            measure.standing = "\(grouped(target - steps)) a day short of your target."
            measure.nextStep = "A 10-15 minute walk after a meal each day closes most of the gap."
        } else {
            measure.status = .off
            measure.standing = "Under 5,000, where each extra 1,000 steps counted most in the studies."
            measure.nextStep = "Add one 10-minute walk a day this week, then a second."
        }
        return measure
    }

    /// Weekly moderate-equivalent minutes (moderate + 2 x vigorous). WHO 2020:
    /// 150-300 moderate or 75-150 vigorous a week (Bull et al., Br J Sports
    /// Med 2020). On target is the lower end, 150; with a stamina goal it is
    /// the upper end, 300, where a 30-year cohort found a little more benefit
    /// (Lee et al., Circulation 2022). "Close" from half the target is the
    /// app's choice, not a published band. Without a stamina goal the line
    /// is the floor the weekly review ticks (`HealthFloors.activeMinutes`).
    public static func activeMinutesTarget(goals: Goals?) -> Int {
        goals?.focuses.contains(.endurance) == true ? 300 : HealthFloors.activeMinutes
    }

    static func activeMinutes(_ i: Inputs) -> Measure {
        let target = activeMinutesTarget(goals: i.goals)
        var measure = Measure(
            id: .activeMinutes, area: .movement, title: "Active minutes", valueText: nil,
            targetText: "\(target) a week or more" + (target > IntensityMinutes.weeklyGoal ? " (the top of WHO's range, for your stamina goal)" : ""),
            status: .noData,
            standing: "No heart-rate minutes yet.",
            nextStep: "Wear your watch during the day and in workouts.",
            why: "Meeting the activity guideline is linked with about 20% lower risk of early death. Hard minutes count double.",
            grade: .strong,
            gradeNote: "A WHO guideline built on many cohorts, plus a 30-year cohort. Observational. Minutes here come from your heart rate, so lifting counts when it raises it.",
            sources: [
                Source("Bull et al., Br J Sports Med 2020;54:1451", kind: "WHO guideline",
                       finding: "Adults: 150-300 minutes of moderate or 75-150 minutes of vigorous activity a week, plus muscle strengthening."),
                Source("Lee et al., Circulation 2022;146:523", kind: "Cohort of 116,221 US adults over 30 years",
                       finding: "Meeting the guideline was linked with 19-25% lower mortality; 2-4 times the minimum added a little more."),
                Source("Ahmadi et al., Eur Heart J 2022;43:4801", kind: "Cohort of 71,893 UK adults wearing an accelerometer",
                       finding: "15-20 vigorous minutes a week went with a 16-40% lower mortality hazard; the lowest risk was at about 54 minutes a week.")
            ])
        guard let moderate = i.moderateMinutes, let vigorous = i.vigorousMinutes else { return measure }
        let total = IntensityMinutes.Result(moderate: moderate, vigorous: vigorous).total
        measure.valueText = "\(total) this week"
        if total >= target {
            measure.status = .onTarget
            measure.standing = "\(moderate) moderate and \(vigorous) hard minutes in the last 7 days."
            measure.nextStep = "Keep the week as it is."
        } else if total * 2 >= target {
            measure.status = .close
            measure.standing = "\(target - total) short of \(target) in the last 7 days."
            measure.nextStep = "One more 30-minute brisk walk or easy ride this week gets you there or close."
        } else {
            measure.status = .off
            measure.standing = "\(target - total) short of \(target) in the last 7 days."
            measure.nextStep = "Brisk walking counts: 20 minutes a day reaches 150 a week."
        }
        return measure
    }

    // MARK: - Strength

    static func strengthDays(_ i: Inputs) -> Measure {
        let target = HealthFloors.strengthDays
        let lifter = i.goals?.focuses.contains(where: { $0 == .muscle || $0 == .strength }) == true
        var measure = Measure(
            id: .strengthDays, area: .strength, title: "Strength days", valueText: nil,
            targetText: "\(target) or more a week", status: .noData,
            standing: "No strength sessions logged yet.",
            nextStep: "Log a strength workout in the Train tab.",
            why: "Strength training is linked with 10-17% lower risk of early death, heart disease, cancer and diabetes. Most of that came by 30-60 minutes a week.",
            grade: .strong,
            gradeNote: "A WHO guideline and a meta-analysis of 16 cohort studies. Observational, and based on what people reported doing.",
            sources: [
                Source("Momma et al., Br J Sports Med 2022;56:755", kind: "Meta-analysis of 16 cohort studies",
                       finding: "Muscle strengthening was linked with 10-17% lower all-cause mortality, heart disease, cancer and diabetes, with the largest reduction at about 30-60 minutes a week."),
                Source("Bull et al., Br J Sports Med 2020;54:1451", kind: "WHO guideline",
                       finding: "Muscle-strengthening activity on 2 or more days a week for all adults.")
            ])
        guard let weeks = i.strengthDaysByWeek, !weeks.isEmpty else { return measure }
        let average = Double(weeks.reduce(0, +)) / Double(weeks.count)
        measure.valueText = "\(one(average)) a week"
        measure.standing = "Average over the last \(weeks.count) week\(weeks.count == 1 ? "" : "s")."
        if HealthFloors.strengthDaysMet(average) {
            measure.status = .onTarget
            measure.nextStep = lifter
                ? "You're past the health line. Extra sessions serve your training goal; the health benefit levelled off well before this."
                : "Keep two sessions a week. More is for strength goals, not extra health."
        } else if average >= 1 {
            measure.status = .close
            measure.nextStep = "A second short session a week reaches the guideline. 20-30 minutes is enough."
        } else {
            measure.status = .off
            measure.nextStep = "One full-body session a week is the place to start."
        }
        return measure
    }

    static func gripStrength(_ i: Inputs) -> Measure {
        var measure = Measure(
            id: .gripStrength, area: .strength, title: "Grip strength", valueText: nil,
            targetText: "Average or above for your age and sex", status: .noData,
            standing: "No grip reading. It needs a hand dynamometer.",
            nextStep: "If you have a dynamometer, add a reading in Log under Waist & grip twice a year.",
            why: "Grip strength stands in for whole-body strength. In a 17-country study, weaker grip predicted early death better than systolic blood pressure did.",
            grade: .moderate,
            gradeNote: "One large cohort. Observational: grip is a marker of overall strength, and training grip alone isn't shown to help.",
            sources: [
                Source("Leong et al., Lancet 2015;386:266", kind: "Cohort of 139,691 adults in 17 countries (PURE)",
                       finding: "Each 5 kg lower grip strength went with 16% higher all-cause mortality."),
                Source("Bohannon et al., Physiotherapy 2006;92:11", kind: "Reference values (meta-analysis)",
                       finding: "The age-and-sex averages used for your band.", verified: false),
                Source("Cruz-Jentoft et al., Age Ageing 2019;48:16", kind: "European consensus (EWGSOP2)",
                       finding: "Under 27 kg for men and 16 kg for women marks low strength.", verified: false)
            ])
        guard let kg = i.gripKg, kg > 0 else { return measure }
        measure.valueText = "\(whole(kg)) kg"
        let reading = GripStrength.reading(kg: kg, age: i.age, sex: i.sex)
        measure.standing = reading.rawValue + "."
        switch reading {
        case .aboveAverage, .average:
            measure.status = .onTarget
            measure.nextStep = "Keep lifting. Re-test in six months."
        case .belowAverage:
            measure.status = .close
            measure.nextStep = "Keep heavy pulling in your week: deadlifts, rows and carries train grip."
        case .belowCutoff:
            measure.status = .off
            measure.nextStep = "Re-test on another day. If it stays this low, mention it at your next check-up."
        }
        return measure
    }

    // MARK: - Sleep

    /// Sleep duration bands from the National Sleep Foundation panel
    /// (Hirshkowitz et al., Sleep Health 2015): recommended 7-9 h for adults
    /// 18-64 and 7-8 h from 65; "may be appropriate" 6-10 h (5-9 h from 65);
    /// outside that not recommended. The AASM/SRS consensus (Watson et al.,
    /// Sleep 2015) gives the same floor: 7 or more hours. The recommended
    /// ranges were checked against the abstract; the "may be appropriate"
    /// edges were not re-verified this round.
    public static func sleepRecommendedHours(age: Int) -> ClosedRange<Double> { age >= 65 ? 7...8 : 7...9 }
    public static func sleepAcceptableHours(age: Int) -> ClosedRange<Double> { age >= 65 ? 5...9 : 6...10 }
    /// Nights needed before an average is judged (app's choice: a week).
    public static let sleepMinimumNights = 5

    static func sleepDuration(_ i: Inputs) -> Measure {
        let recommended = sleepRecommendedHours(age: i.age)
        let acceptable = sleepAcceptableHours(age: i.age)
        var measure = Measure(
            id: .sleepDuration, area: .sleep, title: "Sleep length", valueText: nil,
            targetText: "\(whole(recommended.lowerBound))-\(whole(recommended.upperBound)) hours a night", status: .noData,
            standing: "Not enough nights yet.",
            nextStep: "Wear your watch to sleep for a week.",
            why: "Regularly sleeping under 7 hours is linked with weight gain, diabetes, high blood pressure, heart disease, low mood and early death.",
            grade: .strong,
            gradeNote: "Two expert consensus statements built on many cohort studies. Observational for long-term outcomes; short-term sleep-loss effects are from trials. Very long sleep often reflects illness, not harm from sleep.",
            sources: [
                Source("Watson et al., Sleep 2015;38:843", kind: "AASM and Sleep Research Society consensus",
                       finding: "Adults should sleep 7 or more hours a night on a regular basis."),
                Source("Hirshkowitz et al., Sleep Health 2015;1:40", kind: "National Sleep Foundation expert panel",
                       finding: "7-9 hours for adults, 7-8 from age 65.")
            ])
        guard let hours = i.sleepHours, hours > 0, i.sleepNights >= sleepMinimumNights else { return measure }
        measure.valueText = hoursText(hours)
        measure.standing = "Average of the last \(i.sleepNights) nights."
        if recommended.contains(hours) {
            measure.status = .onTarget
            measure.nextStep = "Keep it here. Regular times are the next thing that counts."
        } else if acceptable.contains(hours) {
            measure.status = .close
            measure.nextStep = hours < recommended.lowerBound
                ? "About \(minutesText((recommended.lowerBound - hours) * 60)) more a night reaches 7 hours. An earlier bedtime is easier to hold than a later alarm."
                : "Longer than the usual range. If you still wake tired, mention it at your next check-up."
        } else {
            measure.status = .off
            measure.nextStep = hours < recommended.lowerBound
                ? "Protect a fixed bedtime that allows 7 hours, starting with work nights."
                : "Much longer than the usual range. Worth mentioning at your next check-up."
        }
        return measure
    }

    /// Sleep Regularity Index lines from the one cohort that tied it to
    /// mortality (Windred et al., Sleep 2024; 60,977 UK Biobank adults with a
    /// week of wrist accelerometry): median 81.0, interquartile range
    /// 73.8-86.3, and each of the top four fifths had 20-48% lower all-cause
    /// mortality than the least regular fifth. The full text gives the fifth
    /// cut-offs (71.65, 78.56, 83.16, 87.31): "off" is the least regular fifth
    /// (under 72) and "on target" the most regular (87 and up), where risk was
    /// lowest. The app's index is worked out from watch sleep over a week,
    /// not accelerometry.
    public static let sleepRegularityTarget = HealthFloors.sleepRegularity
    public static let sleepRegularityLow = SleepRegularity.leastRegularFifth

    static func sleepRegularity(_ i: Inputs) -> Measure {
        var measure = Measure(
            id: .sleepRegularity, area: .sleep, title: "Sleep regularity", valueText: nil,
            targetText: "\(sleepRegularityTarget) or more out of 100", status: .noData,
            standing: "Not enough nights yet.",
            nextStep: "Wear your watch to sleep for a week.",
            why: "Going to sleep and waking at the same times is linked with lower risk of early death, more strongly than sleep length in the one large study that compared them.",
            grade: .moderate,
            gradeNote: "One large cohort (UK Biobank), a week of measurement each. Observational, and not yet repeated at this scale. The lines come from that study's spread; it sets no official target.",
            sources: [
                Source("Windred et al., Sleep 2024;47:zsad253", kind: "Cohort of 60,977 UK adults",
                       finding: "The more regular four fifths had 20-48% lower all-cause mortality than the least regular fifth. Typical index 81.")
            ])
        guard let index = i.sleepRegularity else { return measure }
        measure.valueText = "\(index) of 100"
        if HealthFloors.sleepRegularityMet(index) {
            measure.status = .onTarget
            measure.standing = "In the most regular fifth in the study (87 and up), where risk was lowest."
            measure.nextStep = "Keep your wake time steady, weekends too."
        } else if index >= sleepRegularityLow {
            measure.status = .close
            measure.standing = index >= SleepRegularity.typicalIndex
                ? "Around the typical 81; risk was lowest in the most regular fifth, 87 and up."
                : "A little under the typical 81; the least regular fifth is under 72."
            measure.nextStep = "Hold one wake time for 7 days, within half an hour. It moves the index most."
        } else {
            measure.status = .off
            measure.standing = "In the range of the study's least regular fifth (under 72), where risk was highest."
            measure.nextStep = "Pick one wake time and keep it every day for two weeks, then let bedtime follow."
        }
        return measure
    }

    // MARK: - Body and blood pressure

    static func waistToHeight(_ i: Inputs) -> Measure {
        var measure = Measure(
            id: .waistToHeight, area: .bodyMetabolic, title: "Waist-to-height", valueText: nil,
            targetText: "Under 0.5 (waist less than half your height)", status: .noData,
            standing: "No waist measurement yet.",
            nextStep: "Measure your waist at the navel once a month and add it in Log under Waist & grip.",
            why: "Fat around the waist is the kind tied to diabetes, high blood pressure and heart disease. Unlike BMI, this ratio isn't thrown off by muscle.",
            grade: .strong,
            gradeNote: "Two systematic reviews. It is a screening line for risk factors, checked against who had them, not a trial of what happens when the ratio changes.",
            sources: [
                Source("Ashwell, Gunn & Gibson, Obes Rev 2012;13:275", kind: "Meta-analysis of 31 studies",
                       finding: "Waist-to-height ratio picked out high blood pressure, diabetes and heart-disease risk better than BMI or waist alone."),
                Source("Browning, Hsieh & Ashwell, Nutr Res Rev 2010;23:247", kind: "Systematic review of 78 studies",
                       finding: "The boundary averaged 0.5 for men and women across 14 countries.")
            ])
        guard let ratio = i.waistToHeight else { return measure }
        measure.valueText = two(ratio)
        switch WaistToHeightRatio.category(ratio) {
        case .healthy:
            measure.status = .onTarget
            measure.standing = "Under 0.5."
            measure.nextStep = i.goals?.weight == .gain
                ? "Re-measure monthly while you gain: staying under 0.5 keeps the gain mostly muscle."
                : "Re-measure monthly."
        case .low:
            measure.status = .close
            measure.standing = "Under 0.4, which is low."
            measure.nextStep = "Check you are eating enough for your training."
        case .raised:
            measure.status = .close
            measure.standing = "Between 0.5 and 0.6."
            measure.nextStep = "A slow loss of a few centimetres brings it under 0.5. Steps and a small calorie deficit do most of it."
        case .high:
            measure.status = .off
            measure.standing = "Over 0.6."
            measure.nextStep = "Worth a talk with your doctor, alongside a steady calorie deficit and daily walking."
        }
        return measure
    }

    static func bloodPressure(_ i: Inputs) -> Measure {
        var measure = Measure(
            id: .bloodPressure, area: .bodyMetabolic, title: "Blood pressure", valueText: nil,
            targetText: "Under 120/80 mmHg (7-day home average)", status: .noData,
            standing: "No blood pressure readings yet.",
            nextStep: "With a cuff, do the 7-day home check from Health › Blood pressure.",
            why: "High blood pressure is a major cause of heart attack and stroke, and one of the few measures here tested in trials: lowering it prevented them.",
            grade: .strong,
            gradeNote: "Randomised trials and the 2025 guideline. The categories are for an average of home readings, not one reading.",
            sources: [
                Source("Ettehad et al., Lancet 2016;387:957", kind: "Meta-analysis of 123 randomised trials, 613,815 people",
                       finding: "Each 10 mmHg lower systolic pressure cut major heart events by 20% and all-cause mortality by 13%."),
                Source("Jones et al., Hypertension 2025;82:e212", kind: "AHA/ACC guideline",
                       finding: "Normal is under 120/80; 120-129 over under 80 is elevated; 130/80 or more is high. Home readings improve the diagnosis.", verified: false)
            ])
        guard let systolic = i.systolic, let diastolic = i.diastolic else { return measure }
        measure.valueText = "\(whole(systolic))/\(whole(diastolic)) mmHg"
        guard i.bloodPressureIsHomeAverage else {
            // Stays "no data yet": the categories are for a home average (AHA/ACC 2025).
            measure.standing = "Not a full 7-day home average yet, so it isn't classed."
            return measure
        }
        let category = HomeBloodPressure.category(systolic: systolic, diastolic: diastolic)
        measure.standing = category.rawValue + " on the 7-day home average."
        switch category {
        case .normal:
            measure.status = .onTarget
            measure.nextStep = "Repeat the home check in 6-12 months."
        case .elevated:
            measure.status = .close
            measure.nextStep = "Less salt, regular cardio and a waist under half your height all lower it. Repeat the check in 3 months."
        case .stage1, .stage2, .severe:
            measure.status = .off
            measure.nextStep = HomeBloodPressure.advice(category)
        }
        return measure
    }

    // MARK: - Nutrition

    static func fiber(_ i: Inputs) -> Measure {
        let range = NutritionTargets.fiberTargetGrams
        var measure = Measure(
            id: .fiber, area: .nutrition, title: "Fibre", valueText: nil,
            targetText: "\(whole(range.lowerBound)) g a day or more", status: .noData,
            standing: "No food log yet.",
            nextStep: "Log food for 4 days in your food app, with Apple Health sharing on.",
            why: "People eating the most fibre had 15-30% lower rates of early death, heart disease, stroke, type 2 diabetes and bowel cancer than those eating the least.",
            grade: .strong,
            gradeNote: "185 cohort studies plus 58 trials; the trials showed lower weight, blood pressure and cholesterol. The mortality link itself is observational.",
            sources: [
                Source("Reynolds et al., Lancet 2019;393:434", kind: "Systematic reviews and meta-analyses: 185 cohort studies, 58 trials",
                       finding: "15-30% lower all-cause and heart mortality in the highest fibre eaters; the reduction was greatest at 25-29 g a day.")
            ])
        guard let grams = i.fiberGrams, let status = NutritionTargets.fiberStatus(grams: grams) else { return measure }
        measure.valueText = "\(whole(grams)) g a day"
        measure.standing = "7-day average from your food log."
        switch status {
        case .onTarget:
            measure.status = .onTarget
            measure.nextStep = i.goals?.weight == .gain
                ? "Enough. Much more than \(whole(NutritionTargets.fiberGainCapGrams)) g can blunt appetite while you're gaining."
                : "Keep it here."
        case .nearTarget:
            measure.status = .close
            measure.nextStep = "About \(whole(range.lowerBound - grams + 0.499)) g more a day: one serving of beans, lentils or oats."
        case .low:
            measure.status = .off
            measure.nextStep = i.goals?.weight == .lose
                ? "Add beans, lentils, oats or berries once a day. Fibre also makes a calorie deficit easier to hold."
                : "Add beans, lentils, oats or berries once a day."
        }
        return measure
    }

    /// Protein against the user's own target, which already follows their
    /// goal and weight (`DailyMetricsModel.proteinTarget`: about 1.6 g/kg with
    /// lifting, more in a deficit; Morton et al., Br J Sports Med 2018 found
    /// no further gain in lean mass past 1.62 g/kg a day). "On target" from
    /// 90% and "off" under 70% of it are the app's choices: a food log is
    /// rarely closer than that.
    public static let proteinOnTargetShare = 0.9
    public static let proteinLowShare = 0.7

    static func protein(_ i: Inputs) -> Measure {
        var measure = Measure(
            id: .protein, area: .nutrition, title: "Protein", valueText: nil,
            targetText: "Your goal's daily target", status: .noData,
            standing: "No food log yet.",
            nextStep: "Log food for a few days in your food app, with Apple Health sharing on.",
            why: "With strength training, enough protein builds and keeps muscle, and muscle strength is linked with a longer life. The step from protein to lifespan is indirect.",
            grade: .moderate,
            gradeNote: "Trials show protein adds muscle and strength with training (strong). That it lengthens life is inferred from the strength studies, not shown.",
            sources: [
                Source("Morton et al., Br J Sports Med 2018;52:376", kind: "Meta-analysis of 49 trials, 1,863 people",
                       finding: "Protein supplements added strength and lean mass during resistance training, with no further gain past 1.62 g/kg a day.")
            ])
        guard let target = i.proteinTargetGrams, target > 0 else { return measure }
        measure.targetText = "\(whole(target)) g a day (from your goal and weight)"
        guard let grams = i.proteinGrams, grams > 0 else { return measure }
        measure.valueText = "\(whole(grams)) g a day"
        measure.standing = "7-day average from your food log."
        let share = grams / target
        if share >= proteinOnTargetShare {
            measure.status = .onTarget
            measure.nextStep = "Keep it here. More than your target adds nothing for muscle."
        } else if share >= proteinLowShare {
            measure.status = .close
            measure.nextStep = "About \(whole(target - grams)) g more a day: one extra portion of meat, fish, tofu or dairy."
        } else {
            measure.status = .off
            measure.nextStep = "About \(whole(target - grams)) g short a day. Add a protein food to the two meals that have least."
        }
        return measure
    }

    // MARK: - Alcohol

    /// Evenings logged in the last 7 before the week's total is judged (app's
    /// choice; the weekly review uses the same number).
    public static let alcoholMinimumNights = HealthFloors.drinksMinimumNights

    static func alcohol(_ i: Inputs) -> Measure {
        var measure = Measure(
            id: .alcohol, area: .alcohol, title: "Drinks a week", valueText: nil,
            targetText: "\(whole(HealthFloors.drinks)) or fewer", status: .noData,
            standing: "Fewer than \(alcoholMinimumNights) evenings logged this week.",
            nextStep: "Answer the drinks question in the evening check-in, zero included.",
            why: "Alcohol raises the risk of several cancers at any regular amount, and of heart disease and stroke at higher amounts. Less is lower risk.",
            grade: .moderate,
            gradeNote: "That alcohol causes harm is well established. Where the low-risk line sits is not: the guidance rates its own evidence as low quality, and a global analysis put the lowest-risk amount for under-40s near zero.",
            sources: [
                Source("Canadian Centre on Substance Use and Addiction, Canada's Guidance on Alcohol and Health, 2023", kind: "National guidance",
                       finding: "2 standard drinks or fewer a week: low risk. 3-6: moderate. 7 or more: increasingly high."),
                Source("GBD 2020 Alcohol Collaborators, Lancet 2022;400:185", kind: "Global modelling study",
                       finding: "For ages 15-39 the amount with the least health loss was between 0 and 0.6 drinks a day; for 40 and over the curve was J-shaped.")
            ])
        guard let drinks = i.drinksPerWeek, drinks >= 0, i.drinkNightsLogged >= alcoholMinimumNights else { return measure }
        measure.valueText = "\(one(drinks)) this week"
        measure.standing = "\(i.drinkNightsLogged) of 7 evenings logged."
        switch AlcoholWeek.tier(drinks: drinks) {
        case .low:
            measure.status = .onTarget
            measure.nextStep = "Nothing to change."
        case .moderate:
            measure.status = .close
            measure.nextStep = "Two alcohol-free days more a week would bring it into the low band."
        case .high:
            measure.status = .off
            measure.nextStep = "Each drink fewer lowers the risk. Your alcohol page shows what it does to your sleep and recovery."
        }
        return measure
    }

    // MARK: - Hearing

    /// Headphone sound against the WHO-ITU weekly budget (80 dB(A) for 40
    /// hours, 3 dB exchange; H.870, 2018, revised 2022; figures checked via a
    /// secondary summary). Over the budget is "off". "Close" from 80% (about
    /// 1 dB under the limit) is the app's choice.
    public static let headphoneCloseShare = 80.0

    static func headphoneSound(_ i: Inputs) -> Measure {
        var measure = Measure(
            id: .headphoneSound, area: .hearing, title: "Headphone sound", valueText: nil,
            targetText: "Under 100% of the weekly limit", status: .noData,
            standing: "No headphone levels in Apple Health.",
            nextStep: "Headphone levels are recorded when you listen through your iPhone or Apple Watch.",
            why: "Loud sound damages hearing for good, and hearing loss in midlife is one of the largest known risk factors for dementia that can be changed.",
            grade: .moderate,
            gradeNote: "The limit comes from workplace noise standards with a safety margin, so it is a guideline, not a tested line. The dementia link is observational.",
            sources: [
                Source("WHO-ITU, Safe listening devices and systems (H.870), 2018, revised 2022", kind: "International standard",
                       finding: "For adults: 80 dB for 40 hours a week; each 3 dB louder halves the time.", verified: false),
                Source("Livingston et al., Lancet 2024;404:572", kind: "Lancet Commission report",
                       finding: "Hearing loss is one of 14 modifiable risk factors for dementia, and among the largest.", verified: false)
            ])
        guard let percent = i.headphoneBudgetPercent, percent >= 0 else { return measure }
        measure.valueText = "\(whole(percent))% of the limit"
        measure.standing = "Last 7 days."
        if percent < headphoneCloseShare {
            measure.status = .onTarget
            measure.nextStep = "Nothing to change."
        } else if percent < 100 {
            measure.status = .close
            measure.nextStep = "Near the limit. One notch lower on the volume gives a lot more room."
        } else {
            measure.status = .off
            measure.nextStep = "Turn the volume down: 3 dB lower doubles the safe time. Noise cancelling lets you listen quieter."
        }
        return measure
    }

    // MARK: - Mood

    /// Entries in 14 days before the average is shown (app's choice).
    public static let moodMinimumEntries = 5
    /// At or under this 14-day average ("Meh" or lower on `MoodScale.word`)
    /// the next step mentions the two-week line. The two weeks echo the
    /// PHQ-2's window (Kroenke et al., Med Care 2003; not re-verified); the
    /// value itself is the app's choice, and this is not a screen.
    public static let moodLowValence = -0.2

    static func mood(_ i: Inputs) -> Measure {
        var measure = Measure(
            id: .mood, area: .mind, title: "Mood", valueText: nil,
            targetText: "No published target for a mood rating", status: .noData,
            standing: "Fewer than \(moodMinimumEntries) mood entries in two weeks.",
            nextStep: "Answer the mood question in the check-ins.",
            why: "Low mood and depression go with worse health and shorter lives. Your own trend is the thing to watch; there's no healthy number to aim for.",
            grade: .limited,
            gradeNote: "No study sets a target for a daily mood rating, so this one is tracked, not judged. The next step rests on trials of exercise for depression.",
            sources: [
                Source("Noetel et al., BMJ 2024;384:e075847", kind: "Network meta-analysis of 218 randomised trials, 14,170 people",
                       finding: "Walking or jogging, yoga and strength training gave moderate reductions in depression; harder exercise helped more. Only one trial was at low risk of bias.")
            ])
        guard let valence = i.moodValence, i.moodEntries >= moodMinimumEntries else { return measure }
        measure.status = .tracking
        measure.valueText = MoodScale.word(valence: valence)
        measure.standing = "Average of \(i.moodEntries) entries in the last 14 days."
        measure.nextStep = valence < moodLowValence
            ? "Exercise helped low mood in trials, and you already train. If it stays low for two weeks or more, talking to a doctor is worth it."
            : "Keep checking in. Exercise and sleep are the two levers with the best evidence."
        return measure
    }

    // MARK: - Text helpers (no locale, so tests and the coach read the same)

    static func whole(_ value: Double) -> String { "\(Int(value.rounded()))" }

    /// One decimal, dropped when it is zero: "2", "2.5".
    static func one(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))" : "\(rounded)"
    }

    /// Two decimals: "0.47".
    static func two(_ value: Double) -> String {
        let hundredths = Int((value * 100).rounded())
        let fraction = abs(hundredths) % 100
        return "\(hundredths / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }

    /// "9,000", to the nearest hundred.
    static func grouped(_ value: Double) -> String {
        let rounded = Int((value / 100).rounded()) * 100
        guard rounded >= 1000 else { return "\(rounded)" }
        let rest = rounded % 1000
        return "\(rounded / 1000),\(rest < 100 ? (rest < 10 ? "00" : "0") : "")\(rest)"
    }

    /// "6 h 30 min"
    static func hoursText(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// "25 minutes", to the nearest 5.
    static func minutesText(_ minutes: Double) -> String {
        let rounded = max(5, Int((minutes / 5).rounded()) * 5)
        return "\(rounded) minutes"
    }
}
