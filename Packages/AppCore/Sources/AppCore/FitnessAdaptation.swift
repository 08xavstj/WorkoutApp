import Foundation

/// Targets that follow your fitness instead of staying fixed: the strain
/// target scales with what your training days usually reach, max heart rate
/// is learned from your hardest efforts, and the step goal tracks your habits.

// MARK: - Max heart rate

/// Learns max heart rate from what your watch actually records. Age formulas
/// are off by ±10 bpm for many people (Tanaka et al., J Am Coll Cardiol 2001),
/// and every zone and strain number depends on max heart rate.
public enum ObservedMaxHeartRate {
    /// Highest believable heart rate in per-minute data: the lowest value of
    /// the best run of 3+ consecutive minutes (each within 2 minutes of the
    /// next and within 5 bpm of the run's first value). A single bad reading,
    /// or two, can't set your max.
    public static func peak(_ samples: [HeartRateSample], sustainedMinutes: Int = 3) -> Double? {
        let sorted = samples.filter { (90...230).contains($0.bpm) }.sorted { $0.date < $1.date }
        guard sorted.count >= sustainedMinutes else { return nil }
        var best: Double?
        for start in 0...(sorted.count - sustainedMinutes) {
            var low = sorted[start].bpm
            var ok = true
            for index in (start + 1)..<(start + sustainedMinutes) {
                let previous = sorted[index - 1], current = sorted[index]
                guard current.date.timeIntervalSince(previous.date) <= 120,
                      abs(current.bpm - sorted[start].bpm) <= 5 else { ok = false; break }
                low = min(low, current.bpm)
            }
            if ok, low > (best ?? 0) { best = low }
        }
        return best
    }

    /// Peaks far above the age estimate are almost always sensor errors
    /// (e.g. an optical sensor locking onto running cadence), so they're
    /// ignored rather than trusted for a year. The estimate's SD is about
    /// 10 bpm (Tanaka et al. 2001), so +15 allows genuinely high maxes.
    public static func plausible(_ peak: Double, estimate: Double) -> Double? {
        peak <= estimate + 15 ? peak : nil
    }

    public struct Learned: Sendable, Equatable, Codable {
        public var bpm: Double
        public var date: Date

        public init(bpm: Double, date: Date) {
            self.bpm = bpm
            self.date = date
        }
    }

    /// A learned max fades after a year without being reached again, since max
    /// heart rate falls slowly with age.
    public static let lifetime: TimeInterval = 365 * 86_400

    /// Keeps the higher of the stored and newly seen peak.
    public static func update(_ stored: Learned?, peak: Double?, at date: Date) -> Learned? {
        let current = stored.flatMap { date.timeIntervalSince($0.date) < lifetime ? $0 : nil }
        guard let peak else { return current }
        guard let current else { return Learned(bpm: peak, date: date) }
        return peak > current.bpm ? Learned(bpm: peak, date: date) : current
    }

    /// The learned max to use, only when it's above the age estimate. Lower
    /// peaks just mean you haven't gone all-out recently, not that your max fell.
    public static func override(learned: Learned?, estimate: Double, now: Date) -> Double? {
        guard let learned, now.timeIntervalSince(learned.date) < lifetime, learned.bpm > estimate else { return nil }
        return learned.bpm
    }
}

// MARK: - Strain target

extension StrainCalculator {
    /// Strain your training days usually reach: the median of days at 25% or
    /// more over the last 4 weeks. Nil until there are 6 training days.
    public static func usualTrainingStrain(_ dailyStrains: [Double]) -> Double? {
        let training = dailyStrains.filter { $0 >= 25 }.sorted()
        guard training.count >= 6 else { return nil }
        let middle = training.count / 2
        return training.count.isMultiple(of: 2) ? (training[middle - 1] + training[middle]) / 2 : training[middle]
    }

    /// The strain the fixed bands are built around (a regular trainee).
    public static let referenceUsualStrain = 65.0

    /// Today's target, scaled to your fitness, following HRV-guided training.
    ///
    /// The trials all use the same simple rule: when HRV is in your normal
    /// range, train as planned; when it's below normal, go easy or rest
    /// (Kiviniemi et al., Eur J Appl Physiol 2007; Vesterinen et al., Med Sci
    /// Sports Exerc 2016; Javaloyes et al., IJSPP 2019). Done that way, it
    /// matches or beats a fixed plan (meta-analyses: Granero-Gallegos et al.,
    /// IJERPH 2020; Manresa-Rocamora et al., IJERPH 2021). None of them told
    /// people to train harder than planned on a good day, so high recovery
    /// doesn't raise the target past your usual training day (U), apart from
    /// a little room to progress gradually (ACSM, Med Sci Sports Exerc 2009).
    ///
    /// - Normal or high recovery: train as planned, U − 15 to U + 5.
    /// - Low recovery: an easy day, U − 45 to U − 20.
    /// The 7-day HRV trend being below normal also caps the target at an easy
    /// day (see `DailyMetricsModel.targetStrain`).
    ///
    /// As you get fitter, the same workout costs less heart rate and so less
    /// strain, while your usual days climb; both nudge you to do a little more.
    /// If you train less, U drops and so do the targets.
    ///
    /// **An app estimate, not a published target.** No study gives a daily
    /// strain range; the band widths (−15/+5, −45/−20) are app choices around
    /// the HRV-guided rule above. **Not tailored to `Goals` on purpose:** the
    /// HRV-guided trials were in endurance athletes and recreational runners,
    /// and no trial compares daily load targets between goals (strength, muscle,
    /// fat loss, endurance). What differs by goal is the week (sessions, volume,
    /// cardio: `GoalPlanner`, `CardioPlanner`), and U already follows how each
    /// person trains, so an endurance trainee's usual days set a higher U by
    /// themselves. For fat loss, total activity and steps matter (`StepGoal`),
    /// not a higher strain target. A goal offset here would be invented precision.
    public static func targetStrain(forRecovery recovery: Int, usualTrainingStrain usual: Double?) -> ClosedRange<Double> {
        let u = min(85, max(35, usual ?? referenceUsualStrain))
        switch recovery {
        case ..<34: return max(10, u - 45)...max(25, u - 20)
        default: return max(25, u - 15)...min(95, u + 5)
        }
    }
}

// MARK: - Steps

/// A step goal that grows with you: about 1,000 above your usual day, from
/// 7,000 up to 12,000.
///
/// - 7,000 a day vs 2,000 was linked with about half the risk of death, and
///   gains past 7,000 were modest (Ding et al., Lancet Public Health 2025), so
///   7,000 is the floor.
/// - Risk falls until about 8,000-10,000 a day under 60 and 6,000-8,000 from 60
///   (Paluch et al., Lancet Public Health 2022), so the starting goal is 8,000
///   under 60 and 7,000 from 60.
/// - The +1,000 step is a behaviour choice: small, reachable goals are the ones
///   people keep.
public enum StepGoal {
    public static let minimumGoal = 7_000.0
    public static let maximumGoal = 12_000.0

    /// Goal before there are two weeks of steps.
    public static func standard(age: Int) -> Double {
        age >= 60 ? 7_000 : 8_000
    }

    /// - Parameter dailySteps: full days only (not today), ideally 28.
    public static func personal(dailySteps: [Double], age: Int = 30) -> Double {
        let days = dailySteps.filter { $0 > 0 }.sorted()
        guard days.count >= 14 else { return standard(age: age) }
        let median = days[days.count / 2]
        let goal = ((median + 1000) / 500).rounded() * 500
        return min(maximumGoal, max(minimumGoal, goal))
    }
}

// MARK: - Cardio fitness: norms, fitness age and the 90-day trend

/// VO₂ max is the single number most strongly tied to how long people live:
/// each extra MET (≈3.5 ml/kg/min) was linked with 11–17% lower all-cause
/// mortality with no upper limit of benefit (Mandsager et al., JAMA Netw Open
/// 2018, 122,007 patients; Kokkinos et al., J Am Coll Cardiol 2022, 750,302
/// veterans; Laukkanen et al., Mayo Clin Proc 2022 meta-analysis). The lever
/// when it stalls is long intervals: HIIT beat steady cardio by about 1.2
/// ml/kg/min (Milanović et al., Sports Med 2015, 28 trials), and intervals of
/// 2 minutes or longer with 15+ minutes of work a session did best (Wen et al.,
/// J Sci Med Sport 2019, 53 RCTs).
extension CardioFitness {
    /// The average VO₂ max by age and sex from the HUNT3 reference data (Loe
    /// et al., PLoS One 2013: 3,816 healthy adults): about 54.4 ml/kg/min at 25
    /// for men falling 0.40 a year, 43.0 and 0.30 for women. Kept for
    /// reference only: the app's norms, fitness age and body age all use the
    /// FRIEND medians (`Biomarkers.medianVO2Max`), so the "Good" label and the
    /// fitness age can't disagree (HUNT means run about 6 higher).
    public static func normLine(sex: BiologicalSex) -> (atTwentyFive: Double, perYear: Double) {
        sex == .male ? (54.4, 0.40) : (43.0, 0.30)
    }

    /// Average VO₂ max for an age and sex on the Loe 2013 line, never below 15.
    public static func norm(age: Int, sex: BiologicalSex) -> Double {
        let line = normLine(sex: sex)
        return max(15, line.atTwentyFive - line.perYear * (Double(age) - 25))
    }

    /// "Fitness age": the age whose FRIEND median VO₂ max matches yours
    /// (`Biomarkers.fitnessAge`; Kaminsky et al., Mayo Clin Proc 2015; after
    /// Nes et al., Med Sci Sports Exerc 2011), clamped to 18–90. With your age,
    /// a VO₂ max at or above your age's median never reads older than you. It
    /// is an estimate from one measure, so show it with `watchUncertaintyYears`.
    public static func fitnessAge(vo2Max: Double, age: Int? = nil, sex: BiologicalSex) -> Int {
        Int(Biomarkers.fitnessAge(vo2Max: vo2Max, age: age, sex: sex).rounded())
    }

    /// Half-width of the fitness-age range when VO₂ max is a watch estimate:
    /// watches under-read fit people by ~6 ml/kg/min (health-metrics.md §8,
    /// which asks for ±5 years).
    public static let watchUncertaintyYears = 5

    /// Days the trend looks back (health-metrics.md item 1: a 90-day trend).
    public static let trendDays = 90

    public enum TrendDirection: String, Sendable, Equatable {
        case rising, flat, falling
        /// Readings in only one end of the window.
        case unknown
    }

    public struct Trend: Sendable, Equatable {
        public var direction: TrendDirection
        /// Mean of the last 30 days minus the mean of the first 30 days of the window.
        public var change: Double?
        /// The most recent reading.
        public var latest: Double
        /// Readings inside the window.
        public var readings: Int

        public init(direction: TrendDirection, change: Double?, latest: Double, readings: Int) {
            self.direction = direction
            self.change = change
            self.latest = latest
            self.readings = readings
        }
    }

    /// The 90-day trend: the last 30 days against the first 30 days of the
    /// window. Rising or falling from `meaningfulChange` (0.5 ml/kg/min; watch
    /// estimates move by about 1). Nil without any reading in the window.
    public static func trend(_ points: [DayValue], now: Date = .now) -> Trend? {
        let day = 86_400.0
        let windowStart = now.addingTimeInterval(-Double(trendDays) * day)
        let window = points.filter { $0.value > 10 && $0.date >= windowStart && $0.date <= now }.sorted { $0.date < $1.date }
        guard let last = window.last else { return nil }
        let early = window.filter { $0.date < windowStart.addingTimeInterval(30 * day) }.map(\.value)
        let late = window.filter { $0.date >= now.addingTimeInterval(-30 * day) }.map(\.value)
        guard !early.isEmpty, !late.isEmpty else {
            return Trend(direction: .unknown, change: nil, latest: last.value, readings: window.count)
        }
        let change = late.reduce(0, +) / Double(late.count) - early.reduce(0, +) / Double(early.count)
        let direction: TrendDirection = change >= meaningfulChange ? .rising : (change <= -meaningfulChange ? .falling : .flat)
        return Trend(direction: direction, change: change, latest: last.value, readings: window.count)
    }

    /// Shown when the 90-day trend is flat or falling (Milanović 2015; Wen 2019;
    /// Mandsager 2018 for why it matters).
    public static let intervalNudge = "1–2 sessions a week of 4 × 4-minute hard intervals (3 minutes easy between) raise VO₂ max the most (Milanović 2015; Wen 2019). Higher fitness is linked with longer life, with no upper limit found (Mandsager 2018)."

    public static func nudge(for trend: Trend) -> String? {
        switch trend.direction {
        case .flat, .falling: return intervalNudge
        case .rising, .unknown: return nil
        }
    }
}

// MARK: - Weekly moderate/vigorous minutes band

/// Weekly moderate-to-vigorous minutes as a band: 150 is the floor and 300
/// the "best" end. WHO 2020: 150–300 min moderate or 75–150 vigorous a week
/// (Bull et al., Br J Sports Med 2020). In 116,221 US adults followed for 30
/// years, mortality was lowest at 300–600 min moderate or 150–300 vigorous a
/// week, with no extra benefit or harm above that (Lee et al., Circulation
/// 2022). Vigorous minutes count double, as in `IntensityMinutes`.
public enum WeeklyActivityBand {
    /// WHO floor, moderate-equivalent minutes (Bull 2020).
    public static let floorMinutes = IntensityMinutes.weeklyGoal
    /// Top of the WHO range, where Lee 2022's lowest-risk band begins.
    public static let bestMinutes = 300
    /// Right end of the bar (app choice: a little past "best").
    public static let scaleMinutes = 360

    public enum Emphasis: Sendable, Equatable {
        /// Shown high on the Fitness tab with the 300 target.
        case primary
        /// A line under the strength floor with the 150 target.
        case secondary
    }

    /// Health, stamina and weight-loss goals aim at the top of the band and
    /// see it high on the Fitness tab; muscle and strength goals need only the
    /// floor and more cardio is optional (health-metrics.md §1: He/En/L → 300,
    /// others → 150). No goals set counts as general health.
    public static func emphasis(for goals: Goals?) -> Emphasis {
        guard let goals else { return .primary }
        if goals.weight == .lose { return .primary }
        if goals.focuses.contains(.health) || goals.focuses.contains(.endurance) { return .primary }
        return .secondary
    }

    /// 300 for health, stamina and weight-loss goals; 150 otherwise.
    public static func target(for goals: Goals?) -> Int {
        emphasis(for: goals) == .primary ? bestMinutes : floorMinutes
    }

    public enum Status: String, Sendable, Equatable {
        case belowFloor = "Under the floor"
        case inBand = "In the band"
        case atBest = "At the best end"
    }

    public static func status(total: Int) -> Status {
        if total >= bestMinutes { return .atBest }
        if total >= floorMinutes { return .inBand }
        return .belowFloor
    }

    /// One line for the band: where the week sits and what the goal calls for.
    public static func line(total: Int, goals: Goals?) -> String {
        let goalPart: String = emphasis(for: goals) == .primary
            ? "For your goal, aim toward \(bestMinutes): risk kept falling to about there in a 30-year cohort (Lee 2022)."
            : "For your goal the \(floorMinutes)-minute floor is enough; more cardio is optional."
        switch status(total: total) {
        case .belowFloor:
            return "\(total) of the \(floorMinutes)-minute WHO floor this week (vigorous counts double). \(goalPart)"
        case .inBand:
            return "\(total) minutes: past the \(floorMinutes)-minute floor. \(goalPart)"
        case .atBest:
            return "\(total) minutes: at the best end of the band (\(bestMinutes)+). No extra benefit was seen beyond about twice that, and no harm (Lee 2022)."
        }
    }
}

// MARK: - Strength health floor

/// The lifting "health floor": 2 or more days and 30–60 minutes a week.
/// Muscle-strengthening on 2+ days a week is the WHO guideline (Bull et al.,
/// Br J Sports Med 2020). Across 16 cohorts the mortality benefit peaked at
/// about 30–60 minutes a week (10–20% lower risk; Momma et al., Br J Sports
/// Med 2022), and any resistance training vs none was RR 0.85 (Shailendra et
/// al., Am J Prev Med 2022). More is fine for muscle and strength goals: the
/// J-curve is a population mortality association, not a cap (health-metrics.md
/// §2). The floor is what a deload or an illness week should still clear.
public enum StrengthHealthFloor {
    public static let minimumDays = StrengthDays.weeklyTarget
    /// Lower end of the 30–60 min/week band (Momma 2022).
    public static let minimumMinutes = 30
    public static let bestMinutes = 60
    /// Most a single session counts for, minutes, so a session left running
    /// can't meet the floor on its own (app choice).
    static let sessionCapMinutes = 180

    public struct Result: Sendable, Equatable {
        /// Different days with a session in the last 7.
        public var days: Int
        /// Minutes of lifting in the last 7 days.
        public var minutes: Int

        public init(days: Int, minutes: Int) {
            self.days = days
            self.minutes = minutes
        }

        public var isMet: Bool { days >= StrengthHealthFloor.minimumDays && minutes >= StrengthHealthFloor.minimumMinutes }

        /// "Met this week: 3 days, 140 min" / "Not yet this week: 1 day, 40 min"
        public var summary: String {
            "\(isMet ? "Met this week" : "Not yet this week"): \(days) day\(days == 1 ? "" : "s"), \(minutes) min"
        }
    }

    /// Sessions in the last 7 days (today included), as `StrengthDays` counts them.
    public static func assess(_ sessions: [StrengthSessionSummary], now: Date = .now, calendar: Calendar = .current) -> Result {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let recent = sessions.filter { $0.start >= start && $0.start <= now }
        let days = StrengthDays.lastSevenDays(recent.map(\.start), now: now, calendar: calendar)
        let minutes = recent.map { min(Double(sessionCapMinutes), $0.duration / 60) }.reduce(0, +)
        return Result(days: days, minutes: Int(minutes.rounded()))
    }

    public static let explanation = "2 or more days and 30–60 minutes a week of lifting keeps the mortality benefit (Momma 2022; Shailendra 2022). More is fine for your goals; this is the floor."

    /// One line for the deload card.
    public static let deloadNote = "The health floor still applies: two light sessions keep it."
}
