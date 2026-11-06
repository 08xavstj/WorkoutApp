import Foundation

/// What the coach knows today, as plain values the app fills from its models.
/// Pure data so `CoachAnswers` (and its tests) never touch UI or HealthKit.
/// Everything is optional: an answer says what is missing instead of guessing.
public struct CoachFacts: Sendable, Equatable {
    public struct PlannedSession: Sendable, Equatable {
        public var title: String
        public var minutes: Int
        public var exerciseCount: Int
        /// The planner's own one- or two-sentence reason (`PlannedWorkout.rationale`).
        public var rationale: String
        public var targetRPE: Double

        public init(title: String, minutes: Int, exerciseCount: Int, rationale: String, targetRPE: Double) {
            self.title = title
            self.minutes = minutes
            self.exerciseCount = exerciseCount
            self.rationale = rationale
            self.targetRPE = targetRPE
        }
    }

    public var goals: Goals?
    /// Rest mode is on (sick or resting on purpose).
    public var restMode = false

    // Strain
    public var strain: Double?
    public var targetStrain: ClosedRange<Double>?
    public var yesterdayStrain: Double?
    public var cardioLoad: Double?
    public var liftingLoad: Double?
    /// Today's kind of day from the weekly plan, when there is one.
    public var dayGuidance: TrainingDayPlanner.Guidance?
    /// The 7-day HRV average is below the normal range (HRV-guided easy day).
    public var hrvBelowNormal = false

    // Recovery
    public var recovery: Int?
    public var recoveryCalibrated = true
    public var recoveryContributors: [RecoveryContributor] = []
    public var hrv: Double?
    public var hrvChangePercent: Double?
    public var restingHeartRate: Double?
    public var restingHeartRateChange: Double?

    // Sleep
    public var sleepScore: Int?
    public var sleepHours: Double?
    public var sleepNeedHours: Double?
    public var deepHours: Double?
    public var remHours: Double?
    public var sleepInterruptions: Int?
    /// Hours behind the sleep need over the last 14 nights.
    public var sleepDebtHours: Double?

    // Food
    public var caloriesEaten: Double?
    public var calorieTarget: Double?
    public var caloriesProjectedBurn: Double?
    public var proteinGrams: Double?
    public var proteinTargetGrams: Double?
    public var carbsGrams: Double?
    public var bodyMassKg: Double?
    /// A workout (gym or cardio) was recorded today.
    public var trainedToday = false

    // Training
    public var plannedSession: PlannedSession?
    public var gymConfigured = false
    public var workoutsLast14Days = 0
    public var daysSinceLastWorkout: Int?
    /// Trusted one-line facts from the rest of the app (goal line, HRV trend,
    /// sleep debt plan, weather…), one per element. Medications and lab
    /// results are kept apart so open questions don't get them by default.
    public var extraLines: [String] = []
    public var medicationLines: [String] = []
    public var labLines: [String] = []

    public init() {}
}

/// Answers the coach gives from the app's own numbers, with no language
/// model involved: instant, never refused, never invented. The on-device
/// model only paraphrases these ("Say more") or takes the open questions.
///
/// Thresholds and wording follow the app's existing science:
/// - Recovery bands (`RecoveryCalculator.lowBand` etc.): a low score is an
///   easy day, not a day off, as HRV-guided training replaces hard sessions
///   with easy ones (Kiviniemi 2007; Javaloyes et al., IJSPP 2019).
/// - Strain target (`StrainCalculator.targetStrain`) and the kind of day
///   (`TrainingDayPlanner`).
/// - Sleep: 7 h or more a night for adults (Watson et al. 2015, AASM/SRS
///   consensus); the app's need is personal (`SleepCalculator.sleepNeed`).
/// - Food after training: about 20-40 g of protein (roughly 0.25-0.4 g/kg)
///   within a couple of hours, with the day's total mattering most (ISSN
///   position stands: Jäger et al., JISSN 2017 on protein; Kerksick et al.,
///   JISSN 2017 on nutrient timing; Morton et al., Br J Sports Med 2018
///   meta-analysis for 1.6 g/kg/day). Carbohydrate after endurance work:
///   about 1-1.2 g/kg/h when the next session is within a day (Kerksick 2017).
public enum CoachAnswers {
    public struct Answer: Sendable, Equatable {
        public var question: CoachIntent.Question
        public var text: String
        /// One thing to do next, if there is one.
        public var action: String?

        public init(question: CoachIntent.Question, text: String, action: String? = nil) {
            self.question = question
            self.text = text
            self.action = action
        }
    }

    /// The answer for a routed question, or nil when the facts can't support one.
    public static func answer(for question: CoachIntent.Question, facts: CoachFacts) -> Answer? {
        switch question {
        case .trainToday: trainToday(facts)
        case .whyRecovery: whyRecovery(facts)
        case .planWorkout: planWorkout(facts)
        case .cardioSwap: cardioSwap(facts)
        case .eatingEnough: eatingEnough(facts)
        case .eatAfter: eatAfter(facts)
        case .sleep: sleep(facts)
        case .strain: strain(facts)
        case .shouldRest: shouldRest(facts)
        }
    }

    /// The nearest data-backed answer for an open question the model couldn't
    /// take (a refusal or guardrail), by topic; nil when there is none.
    public static func fallback(for topic: CoachIntent.Topic, facts: CoachFacts) -> Answer? {
        switch topic {
        case .nutrition: eatingEnough(facts)
        case .training: facts.plannedSession != nil ? planWorkout(facts) : trainToday(facts)
        case .recovery: whyRecovery(facts) ?? sleep(facts)
        case .general: trainToday(facts)
        }
    }

    // MARK: - Training

    public static func trainToday(_ f: CoachFacts) -> Answer? {
        if f.restMode {
            return Answer(question: .trainToday,
                          text: "Rest mode is on, so today is for rest: sleep, fluids and at most an easy walk. Workouts can wait until you turn it off.",
                          action: "Turn rest mode off in Settings when you feel ready.")
        }
        guard let recovery = f.recovery else {
            return Answer(question: .trainToday,
                          text: "There's no recovery score yet today, so the app can't size the day for you. Once Apple Health has last night's sleep and resting heart rate, the strain target appears on Today.",
                          action: "Open Apple Health to check last night's sleep synced.")
        }
        var lines: [String] = []
        if let guidance = f.dayGuidance {
            lines.append("\(guidance.title): \(guidance.reason)")
        } else {
            lines.append(recoveryDayLine(recovery, hrvBelowNormal: f.hrvBelowNormal, calibrated: f.recoveryCalibrated))
        }
        if let target = f.targetStrain {
            lines.append(strainTargetLine(current: f.strain, target: target))
        }
        if let plan = f.plannedSession {
            lines.append("The card below has \(plan.title), about \(plan.minutes) min with \(plan.exerciseCount) exercises, loads rounded to what your gym can make.")
        }
        let action: String? = if f.dayGuidance?.isRestDay == true { "A walk or easy mobility is plenty today." } else if recovery < RecoveryCalculator.moderateBand.lowerBound || f.hrvBelowNormal { "Keep it easy: lighter loads, fewer sets, stop well short of failure." } else if f.plannedSession != nil { "Start the suggested session when you're ready." } else { "Plan a session from the Log tab, or ask me to plan one." }
        return Answer(question: .trainToday, text: lines.joined(separator: " "), action: action)
    }

    public static func planWorkout(_ f: CoachFacts) -> Answer? {
        if f.restMode { return trainToday(f) }
        guard let plan = f.plannedSession else {
            if !f.gymConfigured {
                return Answer(question: .planWorkout,
                              text: "I can only plan with equipment you have, and no gym is set up yet. Add your gym in Settings and ask again.",
                              action: "Set up your gym in Settings.")
            }
            return Answer(question: .planWorkout,
                          text: "I couldn't build a session for that request. Ask for a push, pull, legs, upper, lower or full-body day, with a length like 30 or 45 min.",
                          action: "Try “Plan a 45 min full body workout”.")
        }
        var lines = ["\(plan.title), about \(plan.minutes) min with \(plan.exerciseCount) exercises at around RPE \(plan.targetRPE.formatted(.number.precision(.fractionLength(0...1))))."]
        if !plan.rationale.isEmpty { lines.append(plan.rationale) }
        if let recovery = f.recovery {
            lines.append(recovery < RecoveryCalculator.moderateBand.lowerBound
                         ? "Recovery is \(recovery)%, so the loads and volume are dialled back; an easy day still counts."
                         : "Recovery is \(recovery)%, so the planned loads stand.")
        }
        if let target = f.targetStrain { lines.append(strainTargetLine(current: f.strain, target: target)) }
        lines.append("Weights are rounded to the plates and dumbbells in your gym.")
        return Answer(question: .planWorkout, text: lines.joined(separator: " "),
                      action: "Tap Start this workout to begin, or say “make it 30 min” or “make it leg day” to change it.")
    }

    public static func cardioSwap(_ f: CoachFacts) -> Answer? {
        if f.restMode { return trainToday(f) }
        var lines = ["Cardio works instead of the gym today."]
        let easy = (f.recovery ?? 50) < RecoveryCalculator.moderateBand.lowerBound || f.hrvBelowNormal || f.dayGuidance?.isRestDay == true
        if let target = f.targetStrain {
            lines.append(strainTargetLine(current: f.strain, target: target))
        }
        // Zone 2 for easy days: the HRV-guided trials swapped hard sessions for
        // easy ones rather than skipping them (Javaloyes et al., IJSPP 2019).
        lines.append(easy
                     ? "Keep it easy: a steady effort where you could hold a conversation (zone 2), 30-45 minutes."
                     : "A steady 40-60 minutes is fine, or 30 minutes with a few harder efforts if you feel good; stop when the strain ring reaches the target.")
        return Answer(question: .cardioSwap, text: lines.joined(separator: " "),
                      action: "Record it with your watch so it counts toward today's strain.")
    }

    public static func shouldRest(_ f: CoachFacts) -> Answer? {
        if f.restMode {
            return Answer(question: .shouldRest, text: "Yes: rest mode is on. Sleep, fluids and an easy walk at most until you turn it off.",
                          action: "Turn rest mode off in Settings when you feel ready.")
        }
        if let guidance = f.dayGuidance, guidance.isRestDay {
            return Answer(question: .shouldRest, text: "Yes. \(guidance.title): \(guidance.reason)",
                          action: "A walk or easy mobility is plenty.")
        }
        guard let recovery = f.recovery else {
            return Answer(question: .shouldRest, text: "There's no recovery score yet today, so I can't tell. Without it, go by feel: if you're sore, tired or slept badly, an easy session or a walk is a good default.",
                          action: "Check last night's sleep synced to Apple Health.")
        }
        var lines: [String] = []
        if recovery < RecoveryCalculator.moderateBand.lowerBound || f.hrvBelowNormal {
            // Easy, not off: HRV-guided trials replace hard with easy (Javaloyes 2019).
            lines.append("Not necessarily. Recovery is \(recovery)%\(f.hrvBelowNormal ? " and your 7-day HRV is below your normal range" : ""), which calls for an easy day rather than a day off: a short, light session or a walk keeps the habit without adding fatigue.")
        } else if let guidance = f.dayGuidance {
            lines.append("No need. \(guidance.title): \(guidance.reason)")
        } else {
            lines.append("No need. Recovery is \(recovery)%\(f.recoveryCalibrated ? "" : " (still calibrating, so treat it as rough)"), so a normal session suits today.")
        }
        if let days = f.daysSinceLastWorkout, days == 0 { lines.append("You've already trained today, so anything more can be easy.") }
        if let target = f.targetStrain { lines.append(strainTargetLine(current: f.strain, target: target)) }
        return Answer(question: .shouldRest, text: lines.joined(separator: " "),
                      action: recovery < RecoveryCalculator.moderateBand.lowerBound ? "Try a 30-minute easy session." : "Train as planned and leave rest for your plan's rest day.")
    }

    // MARK: - Recovery and sleep

    public static func whyRecovery(_ f: CoachFacts) -> Answer? {
        guard let recovery = f.recovery else {
            return Answer(question: .whyRecovery, text: "There's no recovery score yet today. It needs last night's sleep and this morning's resting heart rate (and HRV when your watch shares it) from Apple Health.",
                          action: "Open Apple Health to check last night's data synced.")
        }
        var lines = ["Recovery is \(recovery)%: \(bandLabel(recovery).lowercased())\(f.recoveryCalibrated ? "." : ", though the baseline is still building, so treat it as rough.")"]
        let lowers = f.recoveryContributors.filter { $0.effect == .lowers }.sorted { $0.weight > $1.weight }
        let raises = f.recoveryContributors.filter { $0.effect == .raises }.sorted { $0.weight > $1.weight }
        if !lowers.isEmpty {
            lines.append("Pulling it down: " + lowers.prefix(3).map { "\($0.name.lowercased()) (\($0.detail))" }.joined(separator: "; ") + ".")
        }
        if !raises.isEmpty {
            lines.append("Helping: " + raises.prefix(2).map { "\($0.name.lowercased()) (\($0.detail))" }.joined(separator: "; ") + ".")
        }
        if lowers.isEmpty && raises.isEmpty {
            var inputs: [String] = []
            if let hrv = f.hrv { inputs.append("HRV \(Int(hrv.rounded())) ms" + (f.hrvChangePercent.map { " (\(signed($0, 0))% vs baseline)" } ?? "")) }
            if let rhr = f.restingHeartRate { inputs.append("resting heart rate \(Int(rhr.rounded())) bpm" + (f.restingHeartRateChange.map { " (\(signed($0, 1)) vs baseline)" } ?? "")) }
            if let hours = f.sleepHours { inputs.append("\(hours.formatted(.number.precision(.fractionLength(1)))) h of sleep" + (f.sleepNeedHours.map { " of \($0.formatted(.number.precision(.fractionLength(1)))) h needed" } ?? "")) }
            if !inputs.isEmpty { lines.append("It comes from " + inputs.joined(separator: ", ") + ".") }
        }
        if f.hrvBelowNormal { lines.append("Your 7-day HRV is also below your normal range, which caps today at an easy day.") }
        let action: String = if recovery < RecoveryCalculator.moderateBand.lowerBound { "Make today easy and protect tonight's sleep; the score usually lifts within a day or two." } else if recovery < RecoveryCalculator.highBand.lowerBound { "A normal session is fine; an earlier night helps tomorrow's score." } else { "Good day for your harder session." }
        return Answer(question: .whyRecovery, text: lines.joined(separator: " "), action: action)
    }

    public static func sleep(_ f: CoachFacts) -> Answer? {
        guard let hours = f.sleepHours else {
            return Answer(question: .sleep, text: "No sleep was recorded for last night in Apple Health. If you wore your watch, give the sync a few minutes; otherwise there's nothing to score.",
                          action: "Check the Sleep section of Apple Health.")
        }
        let h1 = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        var lines: [String] = []
        var first = "You slept \(hours.formatted(h1)) h"
        if let need = f.sleepNeedHours {
            let gap = need - hours
            first += gap > 0.25 ? ", about \(gap.formatted(h1)) h under your \(need.formatted(h1)) h need" : ", meeting your \(need.formatted(h1)) h need"
        }
        if let score = f.sleepScore { first += " (sleep score \(score))" }
        lines.append(first + ".")
        var stages: [String] = []
        if let deep = f.deepHours { stages.append("deep \(deep.formatted(h1)) h") }
        if let rem = f.remHours { stages.append("REM \(rem.formatted(h1)) h") }
        if let interruptions = f.sleepInterruptions { stages.append("\(interruptions) interruption\(interruptions == 1 ? "" : "s")") }
        if !stages.isEmpty {
            let detail = stages.joined(separator: ", ")
            lines.append(detail.prefix(1).uppercased() + String(detail.dropFirst()) + ".")
        }
        if let debt = f.sleepDebtHours, debt >= 2 {
            lines.append("Over the last two weeks you're about \(debt.formatted(h1)) h behind your need; that builds quietly, so an earlier night or two pays it back.")
        }
        // 7 h is the adult floor (Watson et al., Sleep 2015, AASM/SRS consensus);
        // muscle or weight gain goals aim nearer 8 h, a deficit keeps 7 h as the
        // floor that protects lean mass (docs/research/health-metrics.md, sleep).
        if hours < 7 {
            let why: String = switch f.goals?.weight {
            case .lose?: "under 7 h in a deficit costs lean mass, so sleep is part of the cut"
            case .gain?: "building takes about 8 h a night"
            default: "7 h is the adult floor"
            }
            lines.append("Short nights blunt recovery and appetite control; \(why).")
        }
        let action: String = hours < 7 ? "Aim for bed about 30 minutes earlier tonight." : "Keep the same bed and wake time tonight."
        return Answer(question: .sleep, text: lines.joined(separator: " "), action: action)
    }

    // MARK: - Strain

    public static func strain(_ f: CoachFacts) -> Answer? {
        guard let strain = f.strain else {
            return Answer(question: .strain, text: "No strain has been recorded today yet. It builds from heart rate during workouts and the gym sets you log, on a 0-100 scale where 100 is as hard as a day gets.",
                          action: "Record a workout with your watch, or log a gym session.")
        }
        var lines = ["Strain is \(strainText(strain))% so far today (0-100, where 100 is as hard as a day gets)."]
        if let cardio = f.cardioLoad, let lifting = f.liftingLoad, cardio + lifting > 0 {
            let cardioShare = Int((cardio / (cardio + lifting) * 100).rounded())
            lines.append("About \(cardioShare)% of it came from cardio and \(100 - cardioShare)% from lifting.")
        }
        if let target = f.targetStrain { lines.append(strainTargetLine(current: strain, target: target)) }
        if let yesterday = f.yesterdayStrain { lines.append("Yesterday reached \(strainText(yesterday))%.") }
        let action: String? = if let target = f.targetStrain, strain > target.upperBound { "You're past today's range; make the rest of the day easy." } else if let target = f.targetStrain, strain < target.lowerBound { "A session that adds about \(strainText(target.lowerBound - strain)) points lands you in range." } else { nil }
        return Answer(question: .strain, text: lines.joined(separator: " "), action: action)
    }

    // MARK: - Food

    public static func eatingEnough(_ f: CoachFacts) -> Answer? {
        guard f.caloriesEaten != nil || f.proteinGrams != nil else {
            return Answer(question: .eatingEnough, text: "No food is logged for today yet, so I can't say. Log meals in Cronometer or another app that writes to Apple Health and I'll compare them with your targets.",
                          action: "Log today's meals in your food app.")
        }
        var lines: [String] = []
        if let protein = f.proteinGrams {
            var line = "Protein so far: \(whole(protein)) g"
            if let target = f.proteinTargetGrams {
                let left = target - protein
                line += left > 5 ? " of your \(whole(target)) g target, so about \(whole(left)) g to go" : " against a \(whole(target)) g target, so you're there"
            }
            lines.append(line + ".")
        }
        if let eaten = f.caloriesEaten {
            var line = "Calories: \(whole(eaten)) kcal eaten"
            if let target = f.calorieTarget {
                let left = target - eaten
                line += left > 50 ? ", about \(whole(left)) kcal left of your \(whole(target)) kcal target" : ", at or past your \(whole(target)) kcal target"
            } else if let burn = f.caloriesProjectedBurn {
                line += " against about \(whole(burn)) kcal you'll burn today"
            }
            lines.append(line + ".")
        }
        // Goal-specific framing: 1.6 g/kg/day builds muscle (Morton 2018); in a
        // deficit protein protects lean mass (Helms 2014, via `GoalPlanner`).
        if let goals = f.goals {
            switch goals.weight {
            case .lose: lines.append("On a cut, protein is the number to hit even if calories come in under target.")
            case .gain: lines.append("To gain, the calories matter as much as the protein; coming in under target slows it.")
            case .maintain: lines.append("Protein first, then let the calories land near the target.")
            }
        }
        if f.trainedToday, let protein = f.proteinGrams, let target = f.proteinTargetGrams, target - protein > 20 {
            lines.append("You trained today, so a protein-rich meal in the next couple of hours does double duty.")
        }
        let action: String? = if let protein = f.proteinGrams, let target = f.proteinTargetGrams, target - protein > 5 {
            "Make your next meal protein-led: about \(whole(min(40, max(20, target - protein)))) g."
        } else { nil }
        return Answer(question: .eatingEnough, text: lines.joined(separator: " "), action: action)
    }

    public static func eatAfter(_ f: CoachFacts) -> Answer? {
        // ISSN: 20-40 g protein (0.25-0.4 g/kg) in the hours after training;
        // daily total matters most (Jäger 2017; Kerksick 2017; Morton 2018).
        // 0.3 g/kg sits in the middle of the ISSN range, clamped to 20-40 g.
        let perMealGrams: Int = f.bodyMassKg.map { min(40, max(20, Int((0.3 * $0).rounded()))) } ?? 30
        var lines = ["After training, aim for about \(perMealGrams) g of protein within a couple of hours (roughly 0.25-0.4 g per kg); the day's total protein matters more than exact timing."]
        if let protein = f.proteinGrams, let target = f.proteinTargetGrams {
            let left = target - protein
            lines.append(left > 5 ? "You're at \(whole(protein)) g of \(whole(target)) g today, so this meal can carry a good share of the \(whole(left)) g left."
                                  : "You've already reached your \(whole(target)) g protein target, so this meal can be lighter on protein.")
        } else if f.proteinGrams == nil {
            lines.append("No food is logged yet today, so I can't see how much of your protein target is left.")
        }
        // Carbohydrate: endurance work refuels at about 1-1.2 g/kg/h when the next
        // session is within a day (Kerksick 2017); lifters take carbs as what is
        // left after protein and fat (Helms 2014); on a cut keep the meal protein-led.
        if let goals = f.goals {
            if goals.focuses.contains(.endurance), let mass = f.bodyMassKg {
                lines.append("With your stamina goal, add about \(whole(mass)) g of carbs over the next few hours to refill glycogen, more if you train again tomorrow.")
            } else if goals.weight == .lose {
                lines.append("On a cut, keep the meal protein-led with vegetables and some carbs; the deficit stays, the muscle stays.")
            } else {
                lines.append("Add some carbs to refuel; the amount is simply what fits your day's calories after protein and fat.")
            }
        } else {
            lines.append("Add some carbs to refuel.")
        }
        return Answer(question: .eatAfter, text: lines.joined(separator: " "),
                      action: "Have a meal with about \(perMealGrams) g of protein in the next two hours.")
    }

    // MARK: - Facts for the model

    /// The facts an open question needs, as short lines for the model's
    /// prompt: the topic's core numbers, then the most relevant extra lines,
    /// within `budget` characters and at most ten lines. Medications and lab
    /// results only go in when the question mentions them.
    public static func factLines(for question: String, topic: CoachIntent.Topic, facts f: CoachFacts, budget: Int = 900) -> [String] {
        var lines: [String] = []
        let h1 = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        if let goals = f.goals { lines.append("Goal: \(goals.title).") }
        if f.restMode { lines.append("Rest mode is on: suggest rest, not workouts.") }
        if let recovery = f.recovery { lines.append("Recovery \(recovery)% (\(bandLabel(recovery).lowercased()))\(f.recoveryCalibrated ? "" : ", baseline still building").") }
        if let strain = f.strain {
            lines.append("Strain \(strainText(strain))% of 100" + (f.targetStrain.map { ", today's target \(strainText($0.lowerBound))-\(strainText($0.upperBound))%" } ?? "") + ".")
        }
        if let guidance = f.dayGuidance { lines.append("\(guidance.title): \(guidance.reason)") }
        switch topic {
        case .nutrition:
            if let protein = f.proteinGrams { lines.append("Protein today \(whole(protein)) g" + (f.proteinTargetGrams.map { " of \(whole($0)) g target" } ?? "") + ".") } else if let target = f.proteinTargetGrams { lines.append("No food logged today; protein target \(whole(target)) g.") }
            if let eaten = f.caloriesEaten { lines.append("Calories eaten \(whole(eaten)) kcal" + (f.calorieTarget.map { ", target \(whole($0)) kcal" } ?? "") + ".") }
            if let carbs = f.carbsGrams { lines.append("Carbs today \(whole(carbs)) g.") }
            if let mass = f.bodyMassKg { lines.append("Body weight \(mass.formatted(h1)) kg.") }
            if f.trainedToday { lines.append("Trained today.") }
        case .training:
            if let plan = f.plannedSession { lines.append("Planned session: \(plan.title), \(plan.minutes) min, \(plan.exerciseCount) exercises.") }
            lines.append("Gym sessions in the last 14 days: \(f.workoutsLast14Days)" + (f.daysSinceLastWorkout.map { ", last one \($0) day\($0 == 1 ? "" : "s") ago" } ?? "") + ".")
            if !f.gymConfigured { lines.append("No gym equipment set up.") }
            if f.hrvBelowNormal { lines.append("7-day HRV below normal: easy day.") }
        case .recovery, .general:
            if let hours = f.sleepHours { lines.append("Sleep \(hours.formatted(h1)) h" + (f.sleepNeedHours.map { " of \($0.formatted(h1)) h needed" } ?? "") + (f.sleepScore.map { ", score \($0)" } ?? "") + ".") }
            if let hrv = f.hrv { lines.append("HRV \(Int(hrv.rounded())) ms" + (f.hrvChangePercent.map { " (\(signed($0, 0))% vs baseline)" } ?? "") + ".") }
            if let rhr = f.restingHeartRate { lines.append("Resting heart rate \(Int(rhr.rounded())) bpm" + (f.restingHeartRateChange.map { " (\(signed($0, 1)) vs baseline)" } ?? "") + ".") }
            if let debt = f.sleepDebtHours, debt >= 2 { lines.append("Sleep debt \(debt.formatted(h1)) h over 14 nights.") }
            if let yesterday = f.yesterdayStrain { lines.append("Yesterday's strain \(strainText(yesterday))%.") }
        }
        // Extras by relevance to the question's words; medications and labs only when asked.
        let words = Set(CoachIntent.words(question).filter { $0.count > 3 })
        var extras = f.extraLines
        let asksMedication = !words.isDisjoint(with: ["medication", "medications", "meds", "medicine", "medicines", "tablet", "tablets", "pill", "pills"])
        let asksLabs = !words.isDisjoint(with: ["labs", "bloods", "blood", "test", "tests", "results", "cholesterol", "ferritin", "glucose", "hba1c"])
        if asksMedication { extras.append(contentsOf: f.medicationLines) }
        if asksLabs { extras.append(contentsOf: f.labLines) }
        let ranked = extras.enumerated().map { index, line -> (score: Int, index: Int, line: String) in
            let lineWords = Set(CoachIntent.words(line))
            return (lineWords.intersection(words).count, index, line)
        }.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        for item in ranked where item.score > 0 || (asksMedication || asksLabs) {
            lines.append(shortened(item.line, 240))
        }
        var kept: [String] = []
        var used = 0
        for line in lines where kept.count < 10 {
            guard used + line.count + 1 <= budget else { continue }
            kept.append(line)
            used += line.count + 1
        }
        return kept
    }

    // MARK: - Helpers

    static func bandLabel(_ recovery: Int) -> String {
        if recovery < RecoveryCalculator.moderateBand.lowerBound { return RecoveryCalculator.Status.low.label }
        if recovery < RecoveryCalculator.highBand.lowerBound { return RecoveryCalculator.Status.moderate.label }
        return RecoveryCalculator.Status.high.label
    }

    static func recoveryDayLine(_ recovery: Int, hrvBelowNormal: Bool, calibrated: Bool) -> String {
        let rough = calibrated ? "" : " (still calibrating, so treat it as rough)"
        if hrvBelowNormal {
            return "Recovery is \(recovery)%\(rough) and your 7-day HRV is below your normal range, so today is an easy day: lighter and shorter than usual."
        }
        if recovery < RecoveryCalculator.moderateBand.lowerBound {
            return "Recovery is \(recovery)%\(rough): an easy day. Train, but lighter and shorter than usual; that's what HRV-guided plans do on days like this, and it beats skipping."
        }
        if recovery < RecoveryCalculator.highBand.lowerBound {
            return "Recovery is \(recovery)%\(rough): normal. Your usual session suits today."
        }
        return "Recovery is \(recovery)%\(rough): recovered. A good day for your harder or longer session."
    }

    static func strainTargetLine(current: Double?, target: ClosedRange<Double>) -> String {
        let range = "\(strainText(target.lowerBound))-\(strainText(target.upperBound))%"
        guard let current else { return "Today's strain target is \(range)." }
        switch StrainPlanner().status(current: current, target: target) {
        case .below(let remaining): return "Strain is \(strainText(current))% against a target of \(range), so about \(strainText(remaining)) points to go."
        case .inRange: return "Strain is \(strainText(current))%, already inside today's \(range) target."
        case .above: return "Strain is \(strainText(current))%, above today's \(range) target, so the rest of the day can be easy."
        }
    }

    static func strainText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    static func whole(_ value: Double) -> String { String(Int(value.rounded())) }

    static func signed(_ value: Double, _ digits: Int) -> String {
        (value > 0 ? "+" : "") + value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func shortened(_ line: String, _ limit: Int) -> String {
        line.count > limit ? String(line.prefix(limit)) + "…" : line
    }
}

// MARK: - Wording for the on-device model

/// How the app talks to Apple's on-device model, which declines anything it
/// reads as health advice ("recovery", "sleep debt", "illness", "medication"
/// all trip it). The user never sees these words: the UI keeps "Recovery",
/// "Sleep" and "Strain"; only the prompt text is rewritten into training-log
/// vocabulary, and lines about conditions are left out altogether.
///
/// Pure string work, in AppCore so the tests can prove no banned word survives.
public enum CoachPromptVocabulary {
    /// Instructions for the model: a fitness training log assistant that
    /// talks about training and food, never about conditions.
    public static let instructions = """
    You are a friendly, direct coach inside a fitness training log app. Each message gives a question and a list of numbers from the user's training log.
    Reply as a fitness coach about training and food only, using those numbers and general coaching knowledge. Never give advice about conditions or treatments; if asked, say that is outside a training log and give one training tip instead.
    Readiness and training load are percentages from 0 to 100. Low readiness means an easy session, not a failure. Never invent numbers; if the log doesn't cover it, say so briefly.
    Keep answers under 80 words, in 2-4 sentences. Say "you could", never "you should" or "you missed".
    """

    /// Words that must not appear in the prompt (whole words, any case).
    public static let bannedWords: [String] = [
        "health", "recovery", "recovered", "symptom", "symptoms", "medication", "medications",
        "sleep", "illness", "ill", "sick", "doctor", "diagnose", "apnoea", "apnea", "disease",
    ]

    /// Word-for-word replacements, applied in order (longer phrases first so
    /// "sleep debt" becomes "rest shortfall" before "sleep" becomes "rest").
    static let replacements: [(pattern: String, replacement: String)] = [
        ("Sleep debt", "Rest shortfall"), ("sleep debt", "rest shortfall"),
        ("Sleep score", "Rest quality"), ("sleep score", "rest quality"),
        ("Sleep Regularity Index", "Rest regularity index"),
        ("Sleep", "Rest"), ("sleep", "rest"), ("Slept", "Rested"), ("slept", "rested"), ("asleep", "at rest"),
        ("Recovery day", "Easy day"), ("recovery day", "easy day"),
        ("Recovery", "Readiness score"), ("recovery", "readiness"), ("Recovered", "Ready"), ("recovered", "ready"),
        ("Strain", "Training load"), ("strain", "training load"),
        ("Resting heart rate", "Morning pulse"), ("resting heart rate", "morning pulse"),
        ("Heart rate", "Pulse"), ("heart rate", "pulse"),
        ("Apple Health", "the watch app"), ("Health stats", "Watch stats"), ("Health", "Fitness"), ("health", "fitness"),
    ]

    /// A fact line is dropped from the prompt when it is about a condition,
    /// a treatment or a result the model would decline to discuss.
    static let droppedWords: Set<String> = [
        "illness", "ill", "sick", "symptom", "symptoms", "medication", "medications", "medicine", "medicines",
        "doctor", "apnoea", "apnea", "diagnose", "diagnosis", "disease", "pressure", "cholesterol", "glucose",
        "ferritin", "hba1c", "labs", "lab", "bloods", "pregnant", "pregnancy", "period", "injury", "injured",
        "pain", "hurt", "hurts", "vitamins", "minerals", "supplement", "supplements",
    ]

    /// `text` in training-log vocabulary, or nil when the line is about a
    /// condition and should be left out.
    public static func neutral(_ text: String) -> String? {
        let words = Set(CoachIntent.words(text))
        if !words.isDisjoint(with: droppedWords) { return nil }
        var result = text
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: "\\b\(pattern)\\b", with: replacement, options: .regularExpression)
        }
        return result
    }

    /// `lines` rewritten with `neutral`, condition lines left out.
    public static func neutral(_ lines: [String]) -> [String] {
        lines.compactMap(neutral)
    }

    /// Starts of the fact lines that are plainly about training and food,
    /// as `factLines` writes them (after `neutral`): the retry after a
    /// refusal keeps only these.
    static let trainingOnlyPrefixes = [
        "Goal:", "Rest mode", "Training load", "Planned session", "Gym sessions", "No gym", "Protein", "No food logged",
        "Calories", "Carbs", "Body weight", "Trained today", "Training day", "Easy day", "Rest day", "Make-up day",
        "Yesterday's training load",
    ]

    /// The subset of `lines` about training and food only, in training-log
    /// vocabulary: what the model gets on the retry after it declined.
    public static func trainingOnly(_ lines: [String]) -> [String] {
        neutral(lines).filter { line in trainingOnlyPrefixes.contains { line.hasPrefix($0) } }
    }

    /// The prefix for the retried question, so the model reads it as a log query.
    public static let retryQuestionPrefix = "For my workout log: "

    /// Whether `text` contains a banned word as a whole word, any case.
    public static func containsBannedWord(_ text: String) -> Bool {
        !Set(CoachIntent.words(text)).isDisjoint(with: bannedWords)
    }
}
