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
///     tested, so Mifflin-St Jeor is used from 40; from 36 to 39 the two are
///     blended (`athleteEquationWeight`, the app's choice) so a birthday
///     doesn't move the figure by 200 kcal. The Tinsley equations (Appl Physiol
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
/// - Exercise: the Keytel et al. heart-rate equation (J Sports Sci
///   2005;23:289-297), which was fitted on steady treadmill and cycle exercise
///   at 35%, 62% and 80% of VO₂ max (57%, 77% and 90% of max heart rate). It
///   is used in full inside logged workouts, and outside them only once heart
///   rate is clearly at exercise level (`everydayReserveThreshold`): a raised
///   heart rate while standing, in the heat or after coffee isn't oxygen use.
///   Logged gym sessions use METs alone (2024 Adult Compendium, Herrmann et
///   al., J Sport Health Sci 2024: vigorous weight lifting 6.0 METs, moderate
///   multi-exercise sessions 3.5), because heart rate in lifting swings with
///   the pressor response and rests, not with oxygen use: the equation put a
///   70-minute session at 100-135 bpm at about 600 kcal (7.5 METs) for an
///   80 kg man.
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
    /// Inside a logged workout (`workouts`), minutes below this fraction of
    /// heart-rate reserve count as rest instead of exercise (30% is the bottom
    /// of ACSM's "light" band).
    public var exerciseReserveThreshold: Double = 0.30
    /// Outside logged workouts the Keytel equation starts here: 40% of reserve,
    /// the bottom of ACSM's "moderate" band and the level `StrainCalculator`
    /// credits to an exercise minute. Keytel's lowest test stage was 35% of
    /// VO₂ max, 57% of max heart rate (Keytel 2005), which is 39% of reserve
    /// for a max of 187 and a resting rate of 55; under that the equation was
    /// never fitted, and it reads about 5 kcal a minute for an 80 kg man
    /// standing at 96 bpm (1,550 kcal for five hours on his feet).
    public var everydayReserveThreshold: Double = 0.40
    /// Outside logged workouts the equation counts in full from here, and in
    /// a straight line from 0 at `everydayReserveThreshold`, so there is no
    /// 300 → 2,100 kcal step at 40%. The 10-point ramp is the app's choice; no
    /// study sets it. (An unlogged brisk hour at 45% of reserve with 6,000
    /// steps reads about 340 kcal with it against about 480 without, for an
    /// 80 kg man; brisk walking at 4.3 METs is about 265 above rest.)
    public var everydayFullReserve: Double = 0.50
    /// Lowest gross METs credited to a raised-heart-rate minute inside a logged
    /// workout: the bottoms of ACSM's light (30-39% of reserve, 2.0-2.9 METs)
    /// and moderate (40-59%, 3.0-5.9 METs) bands (Garber et al., ACSM position
    /// stand, Med Sci Sports Exerc 2011; cited from memory). Keytel's weight
    /// term is negative for women, so for a heavy woman the equation alone can
    /// fall under any plausible cost of moving.
    public var lightFloorMETs: Double = 2.0
    public var moderateFloorMETs: Double = 3.0
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
    /// From this age a trained person gets Mifflin-St Jeor alone. Between the
    /// top of `athleteEquationAges` and it the two equations are blended.
    public static let athleteEquationFadeOutAge = 40

    /// The share of the ten Haaf equation in a trained person's resting
    /// energy: 1 for 18-35 (the ages it was built on), 0 from 40 and under 18,
    /// falling in a straight line between (0.8 at 36, 0.2 at 39). The fade is
    /// the app's choice: the equation is untested past 35, but metabolism per
    /// kg of lean mass doesn't change at a birthday (Pontzer et al., Science
    /// 2021), and a switch moved an 80 kg, 180 cm man from 1,949 to 1,750 kcal
    /// on his 36th. Across the fade the equation is used up to 4 years past
    /// its tested range, at a falling weight.
    public static func athleteEquationWeight(age: Int) -> Double {
        if athleteEquationAges.contains(age) { return 1 }
        guard age > athleteEquationAges.upperBound, age < athleteEquationFadeOutAge else { return 0 }
        return Double(athleteEquationFadeOutAge - age) / Double(athleteEquationFadeOutAge - athleteEquationAges.upperBound)
    }

    /// Method names shown in the app ("Resting energy: …").
    public static let tenHaafMethod = "ten Haaf equation for people who train"
    public static let cunninghamMethod = "Cunningham equation (lean mass)"
    /// Shown for trained people aged 36-39 (`athleteEquationWeight`).
    public static let blendedMethod = "ten Haaf and Mifflin-St Jeor equations, blended for your age"
    /// Shown when there is no body weight to work from.
    public static let missingWeightMethod = "no body weight yet"

    /// Basal metabolic rate, kcal/day, and the equation used (see the type's notes).
    /// Without a body weight (0 or less) it is 0, not a figure made from height and age alone.
    public func bmr(_ body: Body) -> (kcal: Double, method: String) {
        guard body.weightKg > 0, body.weightKg.isFinite else { return (0, Self.missingWeightMethod) }
        let trained = body.trainingStatus?.isTrained == true
        if body.bodyFatIsClinical, let fat = body.bodyFatPercent, fat > 2, fat < 60 {
            let leanMass = body.weightKg * (1 - fat / 100)
            // Cunningham 1980, confirmed in recreational athletes (ten Haaf & Weijs 2014).
            if trained { return (500 + 22 * leanMass, Self.cunninghamMethod) }
            return (370 + 21.6 * leanMass, "Katch-McArdle")
        }
        let height = body.heightCm ?? (body.sex == .male ? 176 : 163)
        let mifflin = 10 * body.weightKg + 6.25 * height - 5 * Double(body.age) + (body.sex == .male ? 5 : -161)
        let athleteShare = trained ? Self.athleteEquationWeight(age: body.age) : 0
        if athleteShare > 0, let heightCm = body.heightCm {
            // ten Haaf & Weijs, PLoS One 2014, in kJ/day: 49.940 × weight (kg)
            // + 2459.053 × height (m) − 34.014 × age + 799.257 (men) + 122.502.
            let kilojoules = 49.940 * body.weightKg + 2459.053 * heightCm / 100 - 34.014 * Double(body.age)
                + (body.sex == .male ? 799.257 : 0) + 122.502
            let tenHaaf = kilojoules / 4.184
            if athleteShare >= 1 { return (tenHaaf, Self.tenHaafMethod) }
            return (athleteShare * tenHaaf + (1 - athleteShare) * mifflin, Self.blendedMethod)
        }
        return (mifflin, body.heightCm == nil ? "Mifflin-St Jeor (estimated height)" : "Mifflin-St Jeor")
    }

    /// Keytel et al. (2005) gross energy expenditure, kcal/min, without VO2 max.
    /// 0 without a body weight (the weight term would otherwise be left out silently).
    public func keytelKcalPerMinute(bpm: Double, body: Body) -> Double {
        guard body.weightKg > 0 else { return 0 }
        let kj: Double
        switch body.sex {
        case .male: kj = -55.0969 + 0.6309 * bpm + 0.1988 * body.weightKg + 0.2017 * Double(body.age)
        case .female: kj = -20.4022 + 0.4472 * bpm - 0.1263 * body.weightKg + 0.074 * Double(body.age)
        }
        return max(0, kj / 4.184)
    }

    /// Session RPE at or under which a gym session counts at
    /// `moderateStrengthMETs`, and at or over which at `vigorousStrengthMETs`.
    /// The Compendium names effort in words, not ratings, so the mapping is
    /// the app's choice: 5 is the top of what 8-15-rep sessions were rated
    /// (3.3 at 15 reps, 5.2 at 10 reps; Day et al., J Strength Cond Res 2004),
    /// the kind of session the 3.5 MET entry describes, and 6.0 METs, the
    /// Compendium's highest lifting figure, is kept for near-maximal sessions.
    public var moderateStrengthRPE: Double = 5
    public var vigorousStrengthRPE: Double = 9
    /// 2024 Adult Compendium (Herrmann et al., J Sport Health Sci 2024):
    /// moderate multi-exercise resistance sessions 3.5 METs, vigorous weight
    /// lifting 6.0 METs. (The 3.5 entry reads "multiple exercises, 8-15 reps
    /// at varied resistance" in the 2011 edition; wording cited from memory.)
    public var moderateStrengthMETs: Double = 3.5
    public var vigorousStrengthMETs: Double = 6.0

    /// Gross METs for a gym session by its session RPE: a straight line from
    /// 3.5 METs at 5 or under to 6.0 at 9 or over (4.75 at RPE 7), so one
    /// step on the rating never doubles the calories (it used to jump from
    /// 3.5 to 6.0 at RPE 7). Unrated sessions count as
    /// `StrainCalculator.defaultSessionRPE`.
    public func strengthMETs(rpe: Double?) -> Double {
        let rating = rpe ?? StrainCalculator.defaultSessionRPE
        let span = vigorousStrengthRPE - moderateStrengthRPE
        guard span > 0 else { return rating >= vigorousStrengthRPE ? vigorousStrengthMETs : moderateStrengthMETs }
        let share = min(1, max(0, (rating - moderateStrengthRPE) / span))
        return moderateStrengthMETs + (vigorousStrengthMETs - moderateStrengthMETs) * share
    }

    /// Calories from a resistance session by METs, above resting.
    public func strengthKcal(minutes: Double, rpe: Double?, body: Body) -> Double {
        guard body.weightKg > 0, minutes > 0 else { return 0 }
        return max(0, (strengthMETs(rpe: rpe) - 1) * body.weightKg * minutes / 60)
    }

    /// The share of the Keytel equation counted for a minute outside any
    /// logged workout: 0 under `everydayReserveThreshold` (40% of reserve),
    /// rising in a straight line to 1 at `everydayFullReserve` (50%).
    public func everydayExerciseWeight(reserveFraction fraction: Double) -> Double {
        guard fraction >= everydayReserveThreshold else { return 0 }
        let span = everydayFullReserve - everydayReserveThreshold
        guard span > 0 else { return 1 }
        return min(1, max(0, ((fraction - everydayReserveThreshold) / span * 1e9).rounded() / 1e9))
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
    ///   - workouts: when other logged workouts ran today (a run, a match:
    ///     Apple Health workouts that aren't one of `strengthSessions`). The
    ///     heart-rate equation runs from 30% of reserve inside them and their
    ///     minutes never cancel steps (`stepsOutsideWorkouts` already leaves
    ///     their steps out). Without them a workout's heart rate is treated
    ///     like any other raised heart rate.
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
        measuredRestingPerDay: Double? = nil,
        workouts: [DateInterval] = []
    ) -> Result {
        let (bmrKcal, method): (Double, String) = {
            if let measured = measuredRestingPerDay, (800...4000).contains(measured) {
                return (measured, "your watch's resting calories")
            }
            return bmr(body)
        }()
        let bmrPerMinute = bmrKcal / 1440
        let elapsedMinutes = min(1440, max(0, now.timeIntervalSince(dayStart) / 60))

        // Exercise from heart rate: Keytel gross minus resting, for raised-HR minutes
        // outside gym sessions (those are counted by METs alone, below).
        let samples = heartRate.sorted { $0.date < $1.date }
        var workoutExercise = 0.0
        var everydayExercise = 0.0
        // Raised minutes outside workouts, weighted like their calories: the
        // steps taken in them are already in the heart-rate figure.
        var raisedMinutesOutside = 0.0
        for (current, next) in zip(samples, samples.dropFirst()) {
            let gap = next.date.timeIntervalSince(current.date)
            guard gap > 0, gap <= 600 else { continue }
            guard !strengthSessions.contains(where: { $0.contains(current.date) }) else { continue }
            let fraction = profile.reserveFraction(for: current.bpm)
            // One reading stands for at most 2 minutes (as in StrainCalculator),
            // so a single raised reading before a sync gap isn't 10 minutes of exercise.
            let minutes = min(gap / 60, maxMinutesPerSample)
            let keytel = max(0, keytelKcalPerMinute(bpm: current.bpm, body: body) - bmrPerMinute)
            if workouts.contains(where: { $0.contains(current.date) }) {
                guard fraction >= exerciseReserveThreshold else { continue }
                // Never under the bottom of the ACSM band the heart rate sits in.
                let floorMETs = fraction >= everydayReserveThreshold ? moderateFloorMETs : lightFloorMETs
                let floor = max(0, floorMETs - 1) * max(0, body.weightKg) / 60
                workoutExercise += max(keytel, floor) * minutes
            } else {
                let weight = everydayExerciseWeight(reserveFraction: fraction)
                guard weight > 0 else { continue }
                everydayExercise += keytel * weight * minutes
                raisedMinutesOutside += weight * minutes
            }
        }

        // Steps taken during raised-heart-rate minutes are already in the
        // heart-rate calories, so they aren't counted again as movement.
        // About 100 steps a minute is a brisk, moderate-intensity walk
        // (Tudor-Locke et al., Br J Sports Med 2020). Only raised minutes
        // outside logged workouts cancel steps: the caller has already left a
        // workout's own steps out, so a match no longer wipes the day's walking.
        let stepsOutside = max(0, stepsOutsideWorkouts)
        let stepsInRaisedMinutes = min(stepsOutside, raisedMinutesOutside * stepsPerRaisedMinute)
        let kcalPerStep = kcalPerStepPerKg * max(0, body.weightKg)
        // The heart-rate figure never reads lower than those steps alone would
        // (Keytel's weight term is negative for women, so a 125 kg woman's
        // brisk hour came out under her 6,000 steps).
        everydayExercise = max(everydayExercise, stepsInRaisedMinutes * kcalPerStep)
        let movement = (stepsOutside - stepsInRaisedMinutes) * kcalPerStep

        var exercise = workoutExercise + everydayExercise
        for session in strengthSessions {
            // METs alone (see the type's notes). Capped like sRPE load, so a
            // session left running overnight doesn't add thousands of kcal.
            exercise += strengthKcal(minutes: min(session.duration / 60, 180), rpe: session.sessionRPE, body: body)
        }
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
