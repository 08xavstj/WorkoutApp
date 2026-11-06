import Foundation

/// What the user is working toward. Drives the calorie target, protein and
/// how the trainer programs sets and reps.
public struct Goals: Codable, Sendable, Equatable {
    public enum Weight: String, Codable, Sendable, CaseIterable {
        case lose, maintain, gain
    }

    public enum Focus: String, Codable, Sendable, CaseIterable {
        case muscle, strength, endurance, health
    }

    public var weight: Weight
    /// Percent of body weight per week for lose/gain.
    public var weeklyRatePercent: Double
    public var focuses: [Focus]
    public var targetWeightKg: Double?
    /// Long-term lift targets ("Bench 100 kg"), projected by `LiftGoalProjection`.
    public var liftGoals: [LiftGoal]

    public init(weight: Weight = .maintain, weeklyRatePercent: Double = 0.5, focuses: [Focus] = [.muscle], targetWeightKg: Double? = nil,
                liftGoals: [LiftGoal] = []) {
        self.weight = weight
        self.weeklyRatePercent = weeklyRatePercent
        self.focuses = focuses
        self.targetWeightKg = targetWeightKg
        self.liftGoals = liftGoals
    }

    private enum CodingKeys: String, CodingKey {
        case weight, weeklyRatePercent, focuses, targetWeightKg, liftGoals
    }

    /// Goals saved before lift goals existed have no `liftGoals` key; they
    /// decode with none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weight = try container.decode(Weight.self, forKey: .weight)
        weeklyRatePercent = try container.decode(Double.self, forKey: .weeklyRatePercent)
        focuses = try container.decode([Focus].self, forKey: .focuses)
        targetWeightKg = try container.decodeIfPresent(Double.self, forKey: .targetWeightKg)
        liftGoals = try container.decodeIfPresent([LiftGoal].self, forKey: .liftGoals) ?? []
    }

    /// Losing fat while building muscle ("recomposition").
    public var isRecomp: Bool { weight == .lose && focuses.contains(.muscle) }

    /// "Maintain weight, build muscle & get stronger": every chosen focus is named.
    public var title: String {
        if isRecomp {
            let others = focuses.filter { $0 != .muscle }.map(\.label).joined(separator: " & ").lowercased()
            return others.isEmpty ? "Lose fat, build muscle" : "Lose fat, build muscle & \(others)"
        }
        let weightPart: String = switch weight {
        case .lose: "Lose weight"
        case .maintain: "Maintain weight"
        case .gain: "Gain weight"
        }
        let focusPart = focuses.map(\.label).joined(separator: " & ").lowercased()
        return focusPart.isEmpty ? weightPart : "\(weightPart), \(focusPart)"
    }
}

extension Goals.Focus {
    public var label: String {
        switch self {
        case .muscle: "Build muscle"
        case .strength: "Get stronger"
        case .endurance: "Stamina"
        case .health: "General health"
        }
    }
}

/// Research-based numbers for each goal.
///
/// - Rate of loss: about 0.5-1% of body weight a week keeps more muscle than
///   faster loss (Helms et al., JISSN 2014; Garthe et al., IJSNEM 2011).
/// - Rate of gain: about 0.25-0.5% a week; bigger surpluses mostly add fat
///   (Iraki et al., Sports 2019).
/// - Protein: 1.6 g/kg builds muscle (Morton et al., BJSM 2018); in a deficit
///   or recomposition, more helps keep muscle: 2.3-3.1 g per kg of *lean* mass
///   (Helms 2014; Barakat et al., Strength Cond J 2020). Grams per kg of total
///   weight overshoot for people with more body fat, so the target uses lean
///   mass when body fat is known, otherwise the goal weight or an adjusted
///   body weight when BMI is over 30.
public enum GoalPlanner {
    /// Daily calorie target from maintenance and the goal. The weekly rate is
    /// capped at the person's maximum (`maximumWeeklyRate`); without age, body
    /// fat or training status that is the general 1%/week loss and 0.5%/week
    /// gain limit.
    public static func calorieTarget(maintenance: Double, bodyMassKg: Double, goals: Goals, sex: BiologicalSex,
                                     age: Int? = nil, bodyFatPercent: Double? = nil,
                                     trainingStatus: TrainingStatus? = nil) -> Double {
        let limit = maximumWeeklyRate(goals: goals, sex: sex, age: age, bodyFatPercent: bodyFatPercent, trainingStatus: trainingStatus)
        let rate = min(goals.weeklyRatePercent, limit.percent)
        let weeklyKg = bodyMassKg * rate / 100
        let daily = weeklyKg * AdaptiveTDEE.kcalPerKg / 7
        let target: Double = switch goals.weight {
        case .maintain: maintenance
        case .lose: maintenance - daily
        case .gain: maintenance + daily
        }
        // Don't go below a safe floor without medical supervision.
        return max(calorieFloor(sex: sex), target)
    }

    /// Lowest daily target without medical supervision: 1,500 kcal (men) / 1,200 kcal (women).
    public static func calorieFloor(sex: BiologicalSex) -> Double {
        sex == .male ? 1500 : 1200
    }

    /// The flexible ±10% band around a daily target (Conlin et al., JISSN 2021; see `CalorieBand`).
    public static func calorieBand(target: Double) -> ClosedRange<Double> {
        CalorieBand.range(target: target)
    }

    /// This week's change to the daily target, kcal (at most ±100), or nil
    /// when it should stay. Needs 14 fully logged days behind the measured
    /// maintenance; guarded by the 1%/week loss and 0.5%/week gain limits.
    /// See `CalorieBand.weeklyAdjustment` for the reason text.
    public static func weeklyAdjustment(
        measuredMaintenance: Double,
        currentTarget: Double,
        goals: Goals,
        bodyMassKg: Double,
        weeklyChangeKg: Double,
        loggedDays: Int = AdaptiveTDEE.minimumLoggedDays,
        sex: BiologicalSex = .male
    ) -> Double? {
        CalorieBand.weeklyAdjustment(
            measuredMaintenance: measuredMaintenance, currentTarget: currentTarget, goals: goals,
            bodyMassKg: bodyMassKg, weeklyChangeKg: weeklyChangeKg, loggedDays: loggedDays, sex: sex
        )?.deltaKcal
    }

    public static func proteinPerKg(_ goals: Goals) -> Double {
        if goals.weight == .lose { return 2.2 }
        return goals.focuses.contains(.muscle) || goals.focuses.contains(.strength) ? 1.6 : 1.2
    }

    /// Lean-mass protein in a deficit: the middle of Helms' 2.3-3.1 g/kg range.
    public static let deficitProteinPerKgLeanMass = 2.6

    /// The weight protein is worked out from: current weight, or an adjusted
    /// body weight when BMI is over 30 (weight at BMI 25 plus 40% of the
    /// excess), or the goal weight when losing if that's lower.
    public static func proteinReferenceWeight(goals: Goals?, bodyMassKg: Double, heightCm: Double?) -> Double {
        var reference = bodyMassKg
        if let heightCm, heightCm > 100 {
            let meters = heightCm / 100
            let atBMI25 = 25 * meters * meters
            if bodyMassKg / (meters * meters) > 30 {
                reference = atBMI25 + 0.4 * (bodyMassKg - atBMI25)
            }
        }
        if let goals, goals.weight == .lose, let target = goals.targetWeightKg, target > 0 {
            reference = min(reference, target)
        }
        return reference
    }

    /// Daily protein in grams for the goal.
    /// - Parameter minimumPerKg: a floor per kg of reference weight (e.g. 2.0
    ///   for some medications).
    public static func proteinGrams(goals: Goals?, bodyMassKg: Double?, bodyFatPercent: Double?,
                                    heightCm: Double?, minimumPerKg: Double? = nil) -> Double? {
        guard let bodyMassKg, bodyMassKg > 0 else { return nil }
        let reference = proteinReferenceWeight(goals: goals, bodyMassKg: bodyMassKg, heightCm: heightCm)
        let grams: Double
        if let goals, goals.weight == .lose, let fat = bodyFatPercent, fat > 3, fat < 60 {
            grams = bodyMassKg * (1 - fat / 100) * deficitProteinPerKgLeanMass
        } else {
            grams = reference * (goals.map(proteinPerKg) ?? 1.6)
        }
        let floor = reference * (minimumPerKg ?? 0)
        return max(grams, floor).rounded()
    }

    /// Allowed weekly rates (% body weight) for the picker.
    /// - Parameter maximum: the person's fastest rate (`maximumWeeklyRate`);
    ///   faster options are left out, but the slowest one always stays.
    public static func rateOptions(for weight: Goals.Weight, maximum: Double? = nil) -> [Double] {
        let all: [Double] = switch weight {
        case .lose: [0.25, 0.5, 0.75, 1.0]
        case .gain: [0.25, 0.5]
        case .maintain: []
        }
        guard let maximum else { return all }
        let allowed = all.filter { $0 <= maximum + 0.001 }
        return allowed.isEmpty ? Array(all.prefix(1)) : allowed
    }

    // MARK: Personal maximum rate

    /// Age from which the older-adult limits apply (the trials and the
    /// PROT-AGE protein guidance use 65+).
    public static let olderAdultAge = 65

    /// The fastest weekly rate for this person, and why.
    public struct RateLimit: Sendable, Equatable {
        public enum Reason: String, Sendable {
            /// The general limits: 1%/week loss, 0.5%/week gain.
            case general
            /// Lean: men under 15% / women under 23% body fat.
            case lean
            /// Very lean: men under 10% / women under 18% body fat.
            case veryLean
            /// 65 or older.
            case olderAdult
            /// 2+ years of consistent lifting (gain only).
            case advancedLifter
        }

        /// % of body weight a week (0 when maintaining).
        public var percent: Double
        public var reason: Reason
        public var weight: Goals.Weight
        /// True when the body fat behind the limit was estimated from BMI.
        public var bodyFatIsEstimate: Bool

        public init(percent: Double, reason: Reason, weight: Goals.Weight, bodyFatIsEstimate: Bool = false) {
            self.percent = percent
            self.reason = reason
            self.weight = weight
            self.bodyFatIsEstimate = bodyFatIsEstimate
        }

        /// Plain text for Goals, e.g. "For your body fat, losing faster than
        /// 0.75% a week costs muscle (Forbes 2000; Garthe 2011)."
        public var message: String {
            let rate = "\(percent.formatted(.number.precision(.fractionLength(0...2))))% a week"
            let rough = bodyFatIsEstimate ? " Your body fat is estimated from BMI, so this is rough; a smart-scale reading makes it personal." : ""
            switch (weight, reason) {
            case (.maintain, _):
                return "Calories match what you burn."
            case (.lose, .veryLean):
                return "For your body fat, losing faster than \(rate) costs muscle: the leaner you are, the more of each kilo lost is lean tissue rather than fat (Forbes 2000; Helms 2014)." + rough
            case (.lose, .lean):
                return "For your body fat, losing faster than \(rate) costs muscle; athletes losing about 0.7% a week kept more muscle than those losing 1.4% (Garthe 2011; Forbes 2000)." + rough
            case (.lose, .olderAdult):
                return "At your age, losing faster than \(rate) costs muscle and bone; with lifting, trials in over-65s lost about 9% in 6 months and kept most of their muscle (Villareal 2017)."
            case (.lose, _):
                return "Losing faster than \(rate) costs muscle (Helms 2014; Garthe 2011)."
            case (.gain, .advancedLifter):
                return "After 2+ years of steady lifting, muscle comes slowly, so gaining faster than \(rate) mostly adds fat (Iraki 2019)."
            case (.gain, _):
                return "Gaining faster than \(rate) mostly adds fat (Iraki 2019)."
            }
        }
    }

    /// Body fat under these is "lean" (men / women). App choice: about the top
    /// of the "athletes" band, with women about 8 points higher because of
    /// essential fat (ACE body-fat categories). The evidence says only "the
    /// leaner, the slower" (Forbes, Ann N Y Acad Sci 2000; Ruiz-Castellano et
    /// al., Nutrients 2021); no study sets the cut-off.
    public static func leanBodyFat(sex: BiologicalSex) -> Double { sex == .male ? 15 : 23 }
    /// Body fat under these is "very lean" (men / women; app choice, as above).
    public static func veryLeanBodyFat(sex: BiologicalSex) -> Double { sex == .male ? 10 : 18 }

    /// The fastest weekly rate (% of body weight) for this person.
    ///
    /// Losing (general limit 1%/week: Helms et al., JISSN 2014; Garthe et
    /// al., IJSNEM 2011):
    /// - The leaner you are, the larger the share of weight lost that is lean
    ///   tissue (Forbes 2000; Hall, Br J Nutr 2007), and resistance-trained
    ///   reviews say the leaner the athlete, the smaller the deficit
    ///   (Ruiz-Castellano et al., Nutrients 2021). Lean → 0.75%/week, about
    ///   the rate at which elite athletes kept more lean mass than at
    ///   1.4%/week (Garthe 2011: 0.7% vs 1.4%/week); very lean → 0.5%/week,
    ///   the bottom of Helms 2014's range. Moderate evidence for the
    ///   direction, none for the exact cut-offs.
    /// - 65 and older → 0.5%/week. Weight loss costs older adults muscle and
    ///   bone (ASN/TOS position statement, Villareal et al., Am J Clin Nutr
    ///   2005); the trial that protected them best lost about 9% in 26 weeks
    ///   (≈0.35%/week) with resistance plus aerobic training (Villareal et al.,
    ///   N Engl J Med 2017). The 0.5 cap is the nearest picker option.
    /// - Sex: no trial compares safe rates for men and women; the lean
    ///   cut-offs differ by sex, the rate itself doesn't.
    ///
    /// Gaining (Iraki et al., Sports 2019: about 0.25-0.5%/week for novice and
    /// intermediate lifters, more conservative for advanced ones):
    /// - Advanced → 0.25%/week; everyone else 0.5%/week. Relative muscle growth
    ///   is similar in men and women (Roberts, Nuckols & Krieger, J Strength
    ///   Cond Res 2020; Refalo et al., PeerJ 2025), so the % limit is the same.
    ///
    /// - Parameters:
    ///   - bodyFatPercent: a scale or clinical reading, or an estimate from
    ///     `estimatedBodyFatPercent`; nil skips the lean limits.
    ///   - bodyFatIsEstimate: true when it came from BMI (the message says so).
    public static func maximumWeeklyRate(goals: Goals, sex: BiologicalSex, age: Int?, bodyFatPercent: Double?,
                                         trainingStatus: TrainingStatus?, bodyFatIsEstimate: Bool = false) -> RateLimit {
        switch goals.weight {
        case .maintain:
            return RateLimit(percent: 0, reason: .general, weight: .maintain)
        case .gain:
            if trainingStatus == .advanced {
                return RateLimit(percent: 0.25, reason: .advancedLifter, weight: .gain)
            }
            return RateLimit(percent: CalorieBand.maxGainPercentPerWeek, reason: .general, weight: .gain)
        case .lose:
            var limit = RateLimit(percent: CalorieBand.maxLossPercentPerWeek, reason: .general, weight: .lose)
            if let fat = bodyFatPercent, fat > 3, fat < 60 {
                if fat < veryLeanBodyFat(sex: sex) {
                    limit = RateLimit(percent: 0.5, reason: .veryLean, weight: .lose, bodyFatIsEstimate: bodyFatIsEstimate)
                } else if fat < leanBodyFat(sex: sex) {
                    limit = RateLimit(percent: 0.75, reason: .lean, weight: .lose, bodyFatIsEstimate: bodyFatIsEstimate)
                }
            }
            if let age, age >= olderAdultAge, 0.5 < limit.percent {
                limit = RateLimit(percent: 0.5, reason: .olderAdult, weight: .lose)
            }
            return limit
        }
    }

    /// The goals with the weekly rate capped at the person's maximum.
    public static func cappedGoals(_ goals: Goals, limit: RateLimit) -> Goals {
        guard goals.weight != .maintain, goals.weeklyRatePercent > limit.percent else { return goals }
        var capped = goals
        capped.weeklyRatePercent = limit.percent
        return capped
    }

    /// Rough body fat % from BMI, age and sex when there's no reading
    /// (Deurenberg, Weststrate & Seidell, Br J Nutr 1991: 1.2 × BMI + 0.23 ×
    /// age − 10.8 × (1 for men) − 5.4; standard error about 4 points). It
    /// reads high for muscular people, whose BMI is muscle rather than fat,
    /// and slightly high in obesity, so it is used only for the pace limit
    /// and labelled as an estimate. Nil without height.
    public static func estimatedBodyFatPercent(weightKg: Double, heightCm: Double?, age: Int, sex: BiologicalSex) -> Double? {
        guard weightKg > 0, let heightCm, heightCm > 100 else { return nil }
        let meters = heightCm / 100
        let bmi = weightKg / (meters * meters)
        let fat = 1.2 * bmi + 0.23 * Double(age) - (sex == .male ? 10.8 : 0) - 5.4
        return min(60, max(3, fat))
    }

    /// The trainer's set and rep style for these goals.
    public static func trainingStyle(_ goals: Goals) -> TrainingStyle {
        if goals.focuses.contains(.strength) && !goals.focuses.contains(.muscle) { return .strength }
        if goals.focuses.contains(.muscle) { return .muscle }
        if goals.focuses.contains(.endurance) { return .endurance }
        return .balanced
    }

    /// A starting suggestion from body composition (the user can change it).
    ///
    /// The cut-offs sit near the ends of the "healthy" body-fat ranges that
    /// Gallagher et al. derived from BMI cut-offs (Am J Clin Nutr 2000; ages
    /// 20-59: men about 8-21%, women about 21-33%): above 22% (men) or 32%
    /// (women) suggests losing, below 12% or 20% suggests gaining. The exact
    /// numbers, and BMI 27 / 20 when there's no body-fat reading (WHO's
    /// overweight line is 25), are the app's choice, not tested thresholds,
    /// and the screen says it's only a starting point.
    public static let highBodyFatPercent: (male: Double, female: Double) = (22, 32)
    public static let lowBodyFatPercent: (male: Double, female: Double) = (12, 20)

    public static func suggest(bodyFatPercent: Double?, bmi: Double?, sex: BiologicalSex) -> Goals {
        let highFat: Bool = {
            if let fat = bodyFatPercent { return fat > (sex == .male ? highBodyFatPercent.male : highBodyFatPercent.female) }
            if let bmi { return bmi >= 27 }
            return false
        }()
        let lowFat: Bool = {
            if let fat = bodyFatPercent { return fat < (sex == .male ? lowBodyFatPercent.male : lowBodyFatPercent.female) }
            if let bmi { return bmi < 20 }
            return false
        }()
        if highFat { return Goals(weight: .lose, weeklyRatePercent: 0.5, focuses: [.muscle]) }
        if lowFat { return Goals(weight: .gain, weeklyRatePercent: 0.25, focuses: [.muscle]) }
        return Goals(weight: .maintain, focuses: [.muscle, .health])
    }

    /// Weeks to reach the target weight at the chosen rate.
    public static func weeksToTarget(currentKg: Double, goals: Goals) -> Double? {
        guard let target = goals.targetWeightKg, goals.weight != .maintain else { return nil }
        let weekly = currentKg * goals.weeklyRatePercent / 100
        guard weekly > 0 else { return nil }
        let remaining = goals.weight == .lose ? currentKg - target : target - currentKg
        return remaining > 0 ? remaining / weekly : 0
    }
}

/// How the trainer sets reps and effort.
public enum TrainingStyle: String, Codable, Sendable {
    /// 6-8 on big lifts, 10-12 on small ones (the default).
    case balanced
    /// Heavier: 3-6 reps on big lifts, 2-3 reps left in the tank.
    case strength
    /// Muscle growth: 6-10 / 10-15, sets taken closer to failure (Robinson et al., Sports Med 2024).
    case muscle
    /// Lighter and higher reps with shorter rests.
    case endurance
}
