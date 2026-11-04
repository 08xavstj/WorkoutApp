import Foundation

/// Estimates calories burned in a day from published equations, so it can be
/// compared with calories eaten.
///
/// Total = resting + exercise (above resting) + everyday movement + digestion.
/// - Resting (BMR), chosen per person (docs/research/calories.md):
///   - Mifflin-St Jeor by default (best general equation for adults;
///     Frankenfield et al., J Am Diet Assoc 2005). Sex, age, height and weight
///     are its inputs.
///   - People aged 18-35 who have lifted regularly for 6+ months
///     (`TrainingStatus.isTrained`): the ten Haaf & Weijs weight-based
///     equation (PLoS One 2014), built on recreational athletes aged 18-35
///     (about 5 sessions a week), where Mifflin-St Jeor was accurate for
///     fewer than half. A meta-analysis of 29 studies in athletes found it the
///     most accurate and precise equation (80% of people within ±10%; O'Neill,
///     Corish & Horner, Sports Med 2023). Outside 18-35 it hasn't been
///     tested, so Mifflin-St Jeor stays. The Tinsley equations (Appl Physiol
///     Nutr Metab 2019) were built on a small group of physique athletes and need
///     outside validation, so they aren't used.
///   - With body fat from DXA or a clinic (`Body.bodyFatIsClinical`) a
///     lean-mass equation: Cunningham (500 + 22 × lean mass; Am J Clin Nutr
///     1980) for trained people, which ten Haaf & Weijs 2014 confirmed in
///     athletes, otherwise Katch-McArdle (370 + 21.6 × lean mass). Smart-scale
///     bioimpedance is off by about ±5-8 points, so a scale reading never
///     switches the equation.
///   - Age: energy use per kg of lean mass is stable from 20 to 60 and falls
///     after 60 (Pontzer et al., Science 2021); the equations' own age terms
///     cover this, so nothing extra is subtracted.
/// - Exercise: Keytel et al. (2005) heart-rate equation for minutes when heart
///   rate is clearly raised; for logged gym sessions, at least a MET-based floor
///   (2024 Adult Compendium, Herrmann et al., J Sport Health Sci 2024: vigorous
///   weight lifting 6.0 METs, moderate multi-exercise sessions 3.5),
///   because heart rate swings during lifting.
/// - Everyday movement (NEAT): steps outside workouts, ~0.00042 kcal per step
///   per kg net of rest (ACSM walking equation: net VO₂ = 0.1 mL/kg/min per
///   m/min of speed; at 100 steps/min and 0.8 m steps that is about 0.0004
///   kcal/kg/step).
/// - Digestion (thermic effect of food): from macros when they're logged,
///   about 25% of protein calories, 7.5% of carbohydrate and 2% of fat
///   (Westerterp, Nutr Metab 2004: protein 20-30%, carbs 5-10%, fat 0-3%),
///   otherwise 10% of calories eaten.
///
/// Accuracy: for one person, wearable and equation estimates miss by 15-25%
/// and more on training days (no wrist device under 20% in Shcherbina et al.,
/// J Pers Med 2017; over 30% in the Germini et al., JMIR 2022 review), so the
/// result is a guide, not a measurement.
///
/// HRV is not part of any validated energy-expenditure equation, so it isn't used.
public struct EnergyCalculator: Sendable {
    /// Thermic effect of food as a share of calories when macros aren't known (Westerterp 2004: ~10%).
    public var thermicEffect: Double = 0.10
    /// Thermic effect per macronutrient, as a share of its calories (Westerterp 2004; mid-points of the ranges).
    public var proteinThermicEffect: Double = 0.25
    public var carbThermicEffect: Double = 0.075
    public var fatThermicEffect: Double = 0.02
    /// Net calories per step per kg (ACSM walking equation at ~100 steps/min, 0.8 m steps).
    public var kcalPerStepPerKg: Double = 0.00042
    /// Keytel is validated for exercise; below this fraction of heart-rate reserve
    /// a minute counts as rest/everyday movement instead.
    public var exerciseReserveThreshold: Double = 0.30
    /// The most time one heart-rate reading stands for (as in StrainCalculator).
    public var maxMinutesPerSample: Double = 2
    /// Steps per raised-heart-rate minute already covered by heart-rate calories.
    public var stepsPerRaisedMinute: Double = 100

    /// What to tell the user about the error (Shcherbina 2017; Germini 2022).
    public static let accuracyNote = "about ±15-25%, more on training days"

    public init() {}

    public struct Body: Sendable, Equatable {
        public var weightKg: Double
        public var heightCm: Double?
        public var age: Int
        public var sex: BiologicalSex
        public var bodyFatPercent: Double?
        /// True when the body-fat % came from DXA or a clinic (a 4-compartment
        /// or similar method), not a smart scale. Only then is a lean-mass equation used.
        public var bodyFatIsClinical: Bool
        /// From the lifting log (`TrainingStatus.estimate`); nil when unknown,
        /// which keeps Mifflin-St Jeor.
        public var trainingStatus: TrainingStatus?

        public init(weightKg: Double, heightCm: Double?, age: Int, sex: BiologicalSex, bodyFatPercent: Double? = nil,
                    bodyFatIsClinical: Bool = false, trainingStatus: TrainingStatus? = nil) {
            self.weightKg = weightKg
            self.heightCm = heightCm
            self.age = age
            self.sex = sex
            self.bodyFatPercent = bodyFatPercent
            self.bodyFatIsClinical = bodyFatIsClinical
            self.trainingStatus = trainingStatus
        }
    }

    /// Macronutrients eaten, for the thermic effect of food.
    public struct Macros: Sendable, Equatable {
        public var proteinGrams: Double
        public var carbsGrams: Double
        public var fatGrams: Double

        public init(proteinGrams: Double, carbsGrams: Double, fatGrams: Double) {
            self.proteinGrams = proteinGrams
            self.carbsGrams = carbsGrams
            self.fatGrams = fatGrams
        }

        /// From a logged day; nil when no macro was logged.
        public init?(_ day: NutritionDay) {
            guard day.proteinGrams != nil || day.carbsGrams != nil || day.fatGrams != nil else { return nil }
            self.init(proteinGrams: day.proteinGrams ?? 0, carbsGrams: day.carbsGrams ?? 0, fatGrams: day.fatGrams ?? 0)
        }

        /// Atwater factors: 4 kcal/g protein and carbohydrate, 9 kcal/g fat.
        public var proteinKcal: Double { proteinGrams * 4 }
        public var carbsKcal: Double { carbsGrams * 4 }
        public var fatKcal: Double { fatGrams * 9 }
        public var totalKcal: Double { proteinKcal + carbsKcal + fatKcal }
    }

    public struct Result: Sendable, Equatable {
        /// Resting calories for the whole day.
        public var restingFullDay: Double
        /// Resting calories up to `now`.
        public var restingSoFar: Double
        public var exercise: Double
        public var everydayMovement: Double
        public var digestion: Double
        public var intake: Double?
        public var bmrMethod: String
        /// True when digestion came from logged macros rather than the 10% rule.
        public var digestionFromMacros: Bool = false

        /// Calories burned so far today.
        public var burnedSoFar: Double { restingSoFar + exercise + everydayMovement + digestion }
        /// Expected total by the end of the day if you do nothing else.
        public var projectedTotal: Double { restingFullDay + exercise + everydayMovement + digestion }
        /// Positive = surplus, negative = deficit (against the projected total).
        public var balance: Double? { intake.map { $0 - projectedTotal } }
    }

    /// Ages the ten Haaf & Weijs (2014) equation was built on.
    public static let athleteEquationAges = 18...35

    /// Method names shown in the app ("Resting energy: …").
    public static let tenHaafMethod = "ten Haaf equation for people who train"
    public static let cunninghamMethod = "Cunningham equation (lean mass)"

    /// Basal metabolic rate, kcal/day, and the equation used (see the type's notes).
    public func bmr(_ body: Body) -> (kcal: Double, method: String) {
        let trained = body.trainingStatus?.isTrained == true
        if body.bodyFatIsClinical, let fat = body.bodyFatPercent, fat > 2, fat < 60 {
            let leanMass = body.weightKg * (1 - fat / 100)
            // Cunningham 1980, confirmed in recreational athletes (ten Haaf & Weijs 2014).
            if trained { return (500 + 22 * leanMass, Self.cunninghamMethod) }
            return (370 + 21.6 * leanMass, "Katch-McArdle")
        }
        if trained, Self.athleteEquationAges.contains(body.age), let heightCm = body.heightCm {
            // ten Haaf & Weijs, PLoS One 2014, in kJ/day: 49.940 × weight (kg)
            // + 2459.053 × height (m) − 34.014 × age + 799.257 (men) + 122.502.
            let kilojoules = 49.940 * body.weightKg + 2459.053 * heightCm / 100 - 34.014 * Double(body.age)
                + (body.sex == .male ? 799.257 : 0) + 122.502
            return (kilojoules / 4.184, Self.tenHaafMethod)
        }
        let height = body.heightCm ?? (body.sex == .male ? 176 : 163)
        let base = 10 * body.weightKg + 6.25 * height - 5 * Double(body.age)
        return (base + (body.sex == .male ? 5 : -161), body.heightCm == nil ? "Mifflin-St Jeor (estimated height)" : "Mifflin-St Jeor")
    }

    /// Keytel et al. (2005) gross energy expenditure, kcal/min, without VO2 max.
    public func keytelKcalPerMinute(bpm: Double, body: Body) -> Double {
        let kj: Double
        switch body.sex {
        case .male: kj = -55.0969 + 0.6309 * bpm + 0.1988 * body.weightKg + 0.2017 * Double(body.age)
        case .female: kj = -20.4022 + 0.4472 * bpm - 0.1263 * body.weightKg + 0.074 * Double(body.age)
        }
        return max(0, kj / 4.184)
    }

    /// Calories from a resistance session by METs, above resting.
    public func strengthKcal(minutes: Double, rpe: Double?, body: Body) -> Double {
        let mets = (rpe ?? 7) >= 7 ? 6.0 : 3.5
        return max(0, (mets - 1) * body.weightKg * minutes / 60)
    }

    /// Thermic effect of food. With macros: 25% of protein calories, 7.5% of
    /// carbohydrate, 2% of fat (Westerterp 2004), plus 10% of any calories the
    /// macros don't account for (e.g. alcohol). Without macros: 10% of intake.
    public func digestion(intake: Double?, macros: Macros?) -> Double {
        guard let macros, macros.totalKcal > 0 else { return (intake ?? 0) * thermicEffect }
        let fromMacros = macros.proteinKcal * proteinThermicEffect + macros.carbsKcal * carbThermicEffect + macros.fatKcal * fatThermicEffect
        let unaccounted = max(0, (intake ?? 0) - macros.totalKcal)
        return fromMacros + unaccounted * thermicEffect
    }

    /// - Parameters:
    ///   - heartRate: today's samples (any order).
    ///   - strengthSessions: logged gym sessions today.
    ///   - stepsOutsideWorkouts: steps today not inside a workout window.
    ///   - intake: calories eaten today (from Cronometer via Apple Health).
    ///   - macros: protein, carbs and fat eaten today, if logged (for digestion).
    ///   - dayStart / now: the day being measured.
    ///   - measuredRestingPerDay: resting calories a day as measured by the
    ///     user's watch (average of recent full days from Apple Health). Used
    ///     instead of the formula when it's plausible, so totals line up with the watch.
    public func estimate(
        body: Body,
        profile: HeartRateProfile,
        heartRate: [HeartRateSample],
        strengthSessions: [StrengthSessionSummary],
        stepsOutsideWorkouts: Double,
        intake: Double?,
        macros: Macros? = nil,
        dayStart: Date,
        now: Date,
        measuredRestingPerDay: Double? = nil
    ) -> Result {
        let (bmrKcal, method): (Double, String) = {
            if let measured = measuredRestingPerDay, (800...4000).contains(measured) {
                return (measured, "your watch's resting calories")
            }
            return bmr(body)
        }()
        let bmrPerMinute = bmrKcal / 1440
        let elapsedMinutes = min(1440, max(0, now.timeIntervalSince(dayStart) / 60))

        // Exercise from heart rate: Keytel gross minus resting, for raised-HR minutes.
        let samples = heartRate.sorted { $0.date < $1.date }
        var hrExercise = 0.0
        var raisedMinutesOutside = 0.0
        var sessionHR = Array(repeating: 0.0, count: strengthSessions.count)
        for (current, next) in zip(samples, samples.dropFirst()) {
            let gap = next.date.timeIntervalSince(current.date)
            guard gap > 0, gap <= 600 else { continue }
            guard profile.reserveFraction(for: current.bpm) >= exerciseReserveThreshold else { continue }
            // One reading stands for at most 2 minutes (as in StrainCalculator),
            // so a single raised reading before a sync gap isn't 10 minutes of exercise.
            let minutes = min(gap / 60, maxMinutesPerSample)
            let kcal = max(0, keytelKcalPerMinute(bpm: current.bpm, body: body) - bmrPerMinute) * minutes
            if let index = strengthSessions.firstIndex(where: { $0.contains(current.date) }) {
                sessionHR[index] += kcal
            } else {
                hrExercise += kcal
                raisedMinutesOutside += minutes
            }
        }
        var exercise = hrExercise
        for (index, session) in strengthSessions.enumerated() {
            // Capped like sRPE load, so a session left running overnight doesn't add thousands of kcal.
            let floor = strengthKcal(minutes: min(session.duration / 60, 180), rpe: session.sessionRPE, body: body)
            exercise += max(sessionHR[index], floor)
        }

        // Steps taken during raised-heart-rate minutes are already in the
        // heart-rate calories, so they aren't counted again as movement.
        // About 100 steps a minute is a brisk, moderate-intensity walk
        // (Tudor-Locke et al., Br J Sports Med 2020).
        let stepsInRaisedMinutes = min(max(0, stepsOutsideWorkouts), raisedMinutesOutside * stepsPerRaisedMinute)
        let movement = max(0, stepsOutsideWorkouts - stepsInRaisedMinutes) * kcalPerStepPerKg * body.weightKg
        let fromMacros = (macros?.totalKcal ?? 0) > 0

        return Result(
            restingFullDay: bmrKcal,
            restingSoFar: bmrPerMinute * elapsedMinutes,
            exercise: exercise,
            everydayMovement: movement,
            digestion: digestion(intake: intake, macros: macros),
            intake: intake,
            bmrMethod: method,
            digestionFromMacros: fromMacros
        )
    }
}
