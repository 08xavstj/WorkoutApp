import Foundation

/// Estimates calories burned in a day from published equations, so it can be
/// compared with calories eaten.
///
/// Total = resting + exercise (above resting) + everyday movement + digestion.
/// - Resting (BMR): Katch-McArdle when body fat is known (more accurate for lean,
///   muscular people), otherwise Mifflin-St Jeor (best general equation for adults).
/// - Exercise: Keytel et al. (2005) heart-rate equation for minutes when heart
///   rate is clearly raised; for logged gym sessions, at least a MET-based floor
///   (Ainsworth Compendium: vigorous resistance training ≈ 5 METs, moderate ≈ 3.5),
///   because heart rate swings during lifting.
/// - Everyday movement (NEAT): steps outside workouts, ~0.00057 kcal per step per kg.
/// - Digestion (thermic effect of food): ~10% of calories eaten.
///
/// HRV is not part of any validated energy-expenditure equation, so it isn't used.
public struct EnergyCalculator: Sendable {
    public var thermicEffect: Double = 0.10
    public var kcalPerStepPerKg: Double = 0.00057
    /// Keytel is validated for exercise; below this fraction of heart-rate reserve
    /// a minute counts as rest/everyday movement instead.
    public var exerciseReserveThreshold: Double = 0.30

    public init() {}

    public struct Body: Sendable, Equatable {
        public var weightKg: Double
        public var heightCm: Double?
        public var age: Int
        public var sex: BiologicalSex
        public var bodyFatPercent: Double?

        public init(weightKg: Double, heightCm: Double?, age: Int, sex: BiologicalSex, bodyFatPercent: Double? = nil) {
            self.weightKg = weightKg
            self.heightCm = heightCm
            self.age = age
            self.sex = sex
            self.bodyFatPercent = bodyFatPercent
        }
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

        /// Calories burned so far today.
        public var burnedSoFar: Double { restingSoFar + exercise + everydayMovement + digestion }
        /// Expected total by the end of the day if you do nothing else.
        public var projectedTotal: Double { restingFullDay + exercise + everydayMovement + digestion }
        /// Positive = surplus, negative = deficit (against the projected total).
        public var balance: Double? { intake.map { $0 - projectedTotal } }
    }

    /// Basal metabolic rate, kcal/day.
    public func bmr(_ body: Body) -> (kcal: Double, method: String) {
        if let fat = body.bodyFatPercent, fat > 2, fat < 60 {
            let leanMass = body.weightKg * (1 - fat / 100)
            return (370 + 21.6 * leanMass, "Katch-McArdle")
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
        let mets = (rpe ?? 7) >= 7 ? 5.0 : 3.5
        return max(0, (mets - 1) * body.weightKg * minutes / 60)
    }

    /// - Parameters:
    ///   - heartRate: today's samples (any order).
    ///   - strengthSessions: logged gym sessions today.
    ///   - stepsOutsideWorkouts: steps today not inside a workout window.
    ///   - intake: calories eaten today (from Cronometer via Apple Health).
    ///   - dayStart / now: the day being measured.
    public func estimate(
        body: Body,
        profile: HeartRateProfile,
        heartRate: [HeartRateSample],
        strengthSessions: [StrengthSessionSummary],
        stepsOutsideWorkouts: Double,
        intake: Double?,
        dayStart: Date,
        now: Date
    ) -> Result {
        let (bmrKcal, method) = bmr(body)
        let bmrPerMinute = bmrKcal / 1440
        let elapsedMinutes = min(1440, max(0, now.timeIntervalSince(dayStart) / 60))

        // Exercise from heart rate: Keytel gross minus resting, for raised-HR minutes.
        let samples = heartRate.sorted { $0.date < $1.date }
        var hrExercise = 0.0
        var sessionHR = Array(repeating: 0.0, count: strengthSessions.count)
        for (current, next) in zip(samples, samples.dropFirst()) {
            let gap = next.date.timeIntervalSince(current.date)
            guard gap > 0, gap <= 600 else { continue }
            guard profile.reserveFraction(for: current.bpm) >= exerciseReserveThreshold else { continue }
            let kcal = max(0, keytelKcalPerMinute(bpm: current.bpm, body: body) - bmrPerMinute) * gap / 60
            if let index = strengthSessions.firstIndex(where: { $0.contains(current.date) }) {
                sessionHR[index] += kcal
            } else {
                hrExercise += kcal
            }
        }
        var exercise = hrExercise
        for (index, session) in strengthSessions.enumerated() {
            let floor = strengthKcal(minutes: session.duration / 60, rpe: session.sessionRPE, body: body)
            exercise += max(sessionHR[index], floor)
        }

        let movement = max(0, stepsOutsideWorkouts) * kcalPerStepPerKg * body.weightKg
        let digestion = (intake ?? 0) * thermicEffect

        return Result(
            restingFullDay: bmrKcal,
            restingSoFar: bmrPerMinute * elapsedMinutes,
            exercise: exercise,
            everydayMovement: movement,
            digestion: digestion,
            intake: intake,
            bmrMethod: method
        )
    }
}
