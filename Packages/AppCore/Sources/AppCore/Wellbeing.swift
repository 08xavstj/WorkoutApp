import Foundation

// MARK: - Hydration

/// Daily water target and what today's intake means.
///
/// - Baseline total water (food + drinks): 3.7 L men / 2.7 L women (US National
///   Academies, 2004). About 20% usually comes from food, so drinks ≈ 3.0 / 2.2 L.
///   Cronometer's "Water" includes water in food, so the full figure is used.
/// - Exercise: sweat losses are typically 0.5-1 L an hour; ACSM advises
///   replacing them (Sawka et al., ACSM position stand, 2007).
/// - Heat adds roughly another 0.5-1 L.
/// - Losing 2% of body weight as water impairs endurance and raises heart
///   rate, about 3-8 bpm per 1% (Montain & Coyle, J Appl Physiol 1992;
///   Cheuvront & Kenefick, Compr Physiol 2014). Even ~1.5% lowers mood and
///   focus (Armstrong et al., J Nutr 2012).
/// - Too much too fast (over ~1 L an hour for hours) risks low blood sodium
///   (Hew-Butler et al., Clin J Sport Med 2015 consensus).
public enum Hydration {
    public struct Target: Sendable, Equatable {
        public var liters: Double
        public var base: Double
        public var exercise: Double
        public var heat: Double
    }

    public enum Status: String, Sendable {
        case low = "Behind"
        case onTrack = "On track"
        case high = "Very high"
    }

    public struct Assessment: Sendable, Equatable {
        public var target: Target
        public var drank: Double
        /// What you'd expect to have had by now.
        public var expectedByNow: Double
        public var status: Status
        public var effects: [String]
    }

    public static func target(sex: BiologicalSex, exerciseMinutes: Double, feelsLikeC: Double?) -> Target {
        let base = sex == .male ? 3.7 : 2.7
        let exercise = min(3, exerciseMinutes / 60 * 0.75)
        let heat: Double = {
            guard let feels = feelsLikeC else { return 0 }
            return feels >= 32 ? 1.0 : (feels >= 27 ? 0.5 : 0)
        }()
        return Target(liters: base + exercise + heat, base: base, exercise: exercise, heat: heat)
    }

    /// - Parameters:
    ///   - drank: litres logged today.
    ///   - hour: current hour (0-23). Intake is expected to build up from 7 am to 9 pm.
    public static func assess(drank: Double, target: Target, hour: Int) -> Assessment {
        let fraction = min(1, max(0, Double(hour - 7) / 14))
        let expected = target.liters * fraction
        var effects: [String] = []
        let status: Status
        if drank > max(5.5, target.liters * 1.6) {
            status = .high
            effects.append("That's a lot of water. Spread it out and add salt or electrolytes; more than about 1 L an hour for hours can dilute blood sodium.")
        } else if drank < expected * 0.7, hour >= 11 {
            status = .low
            effects.append("Running low raises your heart rate and makes training feel harder; losing 2% of body weight as water cuts endurance.")
            effects.append("Even mild dehydration can dip mood and focus, and can make your resting heart rate read higher tonight.")
            if target.exercise > 0 { effects.append("You trained today: drink about 0.5-0.75 L for each hour of exercise.") }
        } else {
            status = .onTrack
            effects.append("Well hydrated: heart rate stays lower at the same effort and recovery reads cleaner.")
        }
        if hour >= 20 && drank < target.liters * 0.6 {
            effects.append("Catch up gradually; a lot right before bed can wake you up to use the bathroom.")
        }
        return Assessment(target: target, drank: drank, expectedByNow: expected, status: status, effects: effects)
    }
}

// MARK: - Illness early warning

/// Flags when resting heart rate, breathing rate or temperature rise above your
/// own baseline together, a pattern that often comes before feeling sick
/// (Mishra et al., Nat Biomed Eng 2020: 63% of 32 COVID-19 cases flagged
/// before symptoms, retrospective; Quer et al., Nat Med 2021;27:73-77, DETECT
/// study: sensors plus symptoms worked better than resting heart rate alone;
/// Natarajan et al., npj Digit Med 2020: breathing rate and heart rate up, HRV
/// down, around onset).
///
/// One raised signal is common on a normal day, so it's only a "minor sign"
/// shown quietly. Two or more signals together (reported symptoms count as one)
/// are "major signs" and raise an alert, the multi-signal approach that cuts
/// false alarms. Without symptoms, a body signal also has to be up for two
/// days running before it counts toward "major", as the wearable studies
/// required (Mishra 2020; Quer 2021): one odd night is usually noise. Alcohol
/// and very hard training cause the same changes, so they lower the level
/// unless you also feel unwell.
///
/// Menstrual cycle: in the luteal phase sleeping temperature runs about
/// 0.3-0.5 °C higher and resting heart rate 2-4 bpm higher (figures from the
/// app's evidence audit, Nov 2026, problem 9; the pattern is well known but
/// was not re-verified against one study), which would trip both signals at
/// once. The rise starts after ovulation, about two weeks after a period
/// begins, and lasts until the next period (Baker & Driver, Sleep Med 2007),
/// so when the morning check-in last logged "On my period" `lutealWindowDays`
/// ago, the temperature bar rises by 0.3 °C and resting heart rate gets 3
/// bpm of extra room.
public enum IllnessWatch {
    /// Days since the last logged period day during which the cycle
    /// allowances apply: the luteal phase of a typical 24-35 day cycle. The
    /// app's choice of window; the phase itself is well documented.
    public static let lutealWindowDays: ClosedRange<Int> = 10...32
    /// Temperature rise vs your baseline mean that counts when the baseline's
    /// spread isn't known yet (Smarr et al., Sci Rep 2020: fever onset shows as
    /// a rise against your own baseline; the 0.5 °C figure isn't confirmed).
    public static let temperatureThreshold = 0.5
    /// With a baseline SD the bar is a z-score instead, as for heart and
    /// breathing rate: +1.5 SD above the 30-night mean. Per-person deviation
    /// from a wearable temperature baseline is what the TemPredict ring study
    /// used (Mason et al., Sci Rep 2022: 82% sensitivity, 63% specificity with
    /// temperature, heart and breathing rate) and the per-person residual
    /// approach is Mishra et al., Nat Biomed Eng 2020. The 1.5 figure is the
    /// app's choice between those studies' settings (docs/research/watch-features.md §1 note).
    public static let temperatureZThreshold = 1.5
    /// Smallest rise that counts whatever the SD, so a very steady baseline
    /// can't trip on sensor noise. App's choice, not from a study.
    public static let minimumTemperatureRise = 0.2
    /// Added to the temperature bar in the luteal phase (audit: luteal rise ≈ 0.3-0.5 °C).
    public static let lutealTemperatureAllowance = 0.3
    /// The fixed bar in the luteal phase when the SD isn't known.
    public static let lutealTemperatureThreshold = temperatureThreshold + lutealTemperatureAllowance
    /// Extra resting heart rate allowed in the luteal phase (audit: luteal rise ≈ 2-4 bpm).
    public static let lutealRestingHeartRateAllowance = 3.0

    /// The temperature rise that counts today: a z-score bar when the
    /// baseline SD is known, the fixed bar otherwise, plus the luteal allowance.
    public static func temperatureBar(baselineSD: Double?, luteal: Bool) -> Double {
        let base = baselineSD.map { max(temperatureZThreshold * $0, minimumTemperatureRise) } ?? temperatureThreshold
        return base + (luteal ? lutealTemperatureAllowance : 0)
    }

    // MARK: Nightly breathing disturbances (Apple Watch, iOS 18 type)

    /// Nights of baseline needed before the breathing-disturbance trend counts.
    public static let breathingDisturbanceBaselineNights = 7
    /// Recent nights averaged for the trend.
    public static let breathingDisturbanceRecentNights = 7
    /// The 7-night mean must sit this many baseline SDs above the baseline
    /// mean to count. A 7-night mean varies less than single nights, so one
    /// SD of nightly values is already a clear shift. App's choice: Apple's
    /// apnoea notification, built on this series, catches about two thirds of
    /// moderate-to-severe cases, and no study of the series as an illness
    /// signal was found (docs/research/watch-features.md 1.2), so this is one
    /// signal among several, never an alert on its own.
    public static let breathingDisturbanceZThreshold = 1.0

    /// True when the last 7 nights' breathing disturbances average well above
    /// the 30 nights before them (`breathingDisturbanceZThreshold`). `nightly`
    /// is oldest first; false with fewer than 14 nights.
    public static func breathingDisturbancesRising(nightly: [Double]) -> Bool {
        let recent = nightly.suffix(breathingDisturbanceRecentNights)
        let baseline = Array(nightly.dropLast(breathingDisturbanceRecentNights).suffix(30))
        guard recent.count == breathingDisturbanceRecentNights,
              baseline.count >= breathingDisturbanceBaselineNights else { return false }
        let recentMean = recent.reduce(0, +) / Double(recent.count)
        let mean = baseline.reduce(0, +) / Double(baseline.count)
        let variance = baseline.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(baseline.count - 1)
        let sd = variance.squareRoot()
        guard sd > 0 else { return recentMean > mean }
        return (recentMean - mean) / sd >= breathingDisturbanceZThreshold
    }

    /// Yesterday's values, compared with the same baselines, so a signal can
    /// be checked for two consecutive days.
    public struct PreviousDay: Sendable, Equatable {
        public var restingHeartRate: Double?
        public var respiratoryRate: Double?
        /// Wrist/body temperature difference from usual that day, °C.
        public var temperatureDelta: Double?

        public init(restingHeartRate: Double? = nil, respiratoryRate: Double? = nil, temperatureDelta: Double? = nil) {
            self.restingHeartRate = restingHeartRate
            self.respiratoryRate = respiratoryRate
            self.temperatureDelta = temperatureDelta
        }
    }

    public struct Inputs: Sendable, Equatable {
        public var restingHeartRate: Double?
        public var rhrBaseline: (mean: Double, sd: Double)?
        public var respiratoryRate: Double?
        public var respiratoryBaseline: (mean: Double, sd: Double)?
        /// Wrist/body temperature difference from usual, °C.
        public var temperatureDelta: Double?
        /// HRV vs baseline, percent.
        public var hrvChangePercent: Double?
        public var drinksLastNight: Int?
        public var yesterdayStrain: Double?
        public var reportedSymptoms: Bool
        /// Yesterday's signals, for the two-day rule. Nil when unknown.
        public var previousDay: PreviousDay?
        /// Days since the morning check-in last logged "On my period"; nil when
        /// not tracked or none logged.
        public var daysSinceLastPeriod: Int?
        /// Night-to-night SD of the sleeping temperature over the 30-night
        /// baseline, °C; nil until enough nights, when the fixed bar is used
        /// (`temperatureBar`).
        public var temperatureBaselineSD: Double?
        /// The last 7 nights' breathing disturbances are up on the 30 before
        /// (`breathingDisturbancesRising`). A week-long trend already spans
        /// days, so it satisfies the two-day rule by itself.
        public var breathingDisturbancesRising: Bool

        public init(restingHeartRate: Double? = nil, rhrBaseline: (mean: Double, sd: Double)? = nil,
                    respiratoryRate: Double? = nil, respiratoryBaseline: (mean: Double, sd: Double)? = nil,
                    temperatureDelta: Double? = nil, hrvChangePercent: Double? = nil,
                    drinksLastNight: Int? = nil, yesterdayStrain: Double? = nil, reportedSymptoms: Bool = false,
                    previousDay: PreviousDay? = nil, daysSinceLastPeriod: Int? = nil,
                    temperatureBaselineSD: Double? = nil, breathingDisturbancesRising: Bool = false) {
            self.restingHeartRate = restingHeartRate
            self.rhrBaseline = rhrBaseline
            self.respiratoryRate = respiratoryRate
            self.respiratoryBaseline = respiratoryBaseline
            self.temperatureDelta = temperatureDelta
            self.hrvChangePercent = hrvChangePercent
            self.drinksLastNight = drinksLastNight
            self.yesterdayStrain = yesterdayStrain
            self.reportedSymptoms = reportedSymptoms
            self.previousDay = previousDay
            self.daysSinceLastPeriod = daysSinceLastPeriod
            self.temperatureBaselineSD = temperatureBaselineSD
            self.breathingDisturbancesRising = breathingDisturbancesRising
        }

        /// Whether the cycle allowances apply (see `lutealWindowDays`).
        public var inCycleWindow: Bool {
            guard let days = daysSinceLastPeriod else { return false }
            return IllnessWatch.lutealWindowDays.contains(days)
        }

        public static func == (a: Inputs, b: Inputs) -> Bool {
            a.restingHeartRate == b.restingHeartRate && a.respiratoryRate == b.respiratoryRate
                && a.temperatureDelta == b.temperatureDelta && a.hrvChangePercent == b.hrvChangePercent
                && a.rhrBaseline?.mean == b.rhrBaseline?.mean && a.rhrBaseline?.sd == b.rhrBaseline?.sd
                && a.respiratoryBaseline?.mean == b.respiratoryBaseline?.mean
                && a.respiratoryBaseline?.sd == b.respiratoryBaseline?.sd
                && a.drinksLastNight == b.drinksLastNight && a.yesterdayStrain == b.yesterdayStrain
                && a.reportedSymptoms == b.reportedSymptoms
                && a.previousDay == b.previousDay && a.daysSinceLastPeriod == b.daysSinceLastPeriod
                && a.temperatureBaselineSD == b.temperatureBaselineSD
                && a.breathingDisturbancesRising == b.breathingDisturbancesRising
        }
    }

    public enum Level: Int, Sendable, Comparable {
        /// One signal: shown quietly, no alert.
        case minor = 1
        /// Two or more signals together.
        case major = 2
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        public var label: String {
            switch self {
            case .minor: "Minor signs"
            case .major: "Major signs"
            }
        }
    }

    public struct Alert: Sendable, Equatable {
        public var level: Level
        public var signals: [String]
        public var message: String
        /// True when two or more signals are up today but none was up yesterday
        /// and no symptoms were reported: held at "minor" until a second day.
        public var awaitingSecondDay: Bool = false
    }

    /// One raised body signal and its wording.
    struct Signal: Equatable {
        var id: String
        var text: String
    }

    /// Which of resting heart rate, breathing rate and temperature are up.
    /// Thresholds: RHR ≥ max(2 SD, 4 bpm) above baseline (Mishra et al., Nat
    /// Biomed Eng 2020 used RHR residuals); breathing ≥ max(2 SD, 1/min)
    /// (Natarajan et al., npj Digit Med 2020); temperature ≥ `temperatureBar`
    /// (+1.5 SD vs the 30-night mean, Mason et al., Sci Rep 2022; or +0.5 °C
    /// without an SD, Smarr et al., Sci Rep 2020). The luteal allowances are
    /// added when `luteal` is true.
    static func bodySignals(
        restingHeartRate: Double?, rhrBaseline: (mean: Double, sd: Double)?,
        respiratoryRate: Double?, respiratoryBaseline: (mean: Double, sd: Double)?,
        temperatureDelta: Double?, temperatureBaselineSD: Double? = nil, luteal: Bool
    ) -> [Signal] {
        var signals: [Signal] = []
        if let rhr = restingHeartRate, let base = rhrBaseline,
           rhr - base.mean >= max(2 * base.sd, 4) + (luteal ? lutealRestingHeartRateAllowance : 0) {
            signals.append(Signal(id: "rhr", text: "Resting heart rate +\(Int((rhr - base.mean).rounded())) bpm"))
        }
        if let rate = respiratoryRate, let base = respiratoryBaseline,
           rate - base.mean >= max(2 * base.sd, 1) {
            signals.append(Signal(id: "breathing", text: String(format: "Breathing rate +%.1f/min", rate - base.mean)))
        }
        if let delta = temperatureDelta, delta >= temperatureBar(baselineSD: temperatureBaselineSD, luteal: luteal) {
            signals.append(Signal(id: "temperature", text: String(format: "Temperature +%.1f °C", delta)))
        }
        return signals
    }

    public static func evaluate(_ inputs: Inputs) -> Alert? {
        let luteal = inputs.inCycleWindow
        let today = bodySignals(
            restingHeartRate: inputs.restingHeartRate, rhrBaseline: inputs.rhrBaseline,
            respiratoryRate: inputs.respiratoryRate, respiratoryBaseline: inputs.respiratoryBaseline,
            temperatureDelta: inputs.temperatureDelta, temperatureBaselineSD: inputs.temperatureBaselineSD, luteal: luteal
        )
        var signals = today.map(\.text)
        if inputs.breathingDisturbancesRising {
            // Fourth body signal: the week's nightly breathing disturbances are up (watch-features.md 1.2).
            signals.append("Breathing disturbances up this week")
        }
        if let hrv = inputs.hrvChangePercent, hrv <= -20, !signals.isEmpty {
            // HRV falls days before diagnosis (Hirten et al., JMIR 2021), but only counts alongside another signal.
            signals.append("HRV \(Int(hrv.rounded()))%")
        }
        let bodySignalCount = signals.count
        let total = bodySignalCount + (inputs.reportedSymptoms ? 1 : 0)
        guard total > 0 else { return nil }

        // Two-day rule: without symptoms, at least one of today's signals must
        // also have been up yesterday before the alert can be "major".
        let yesterday = inputs.previousDay.map { previous in
            bodySignals(
                restingHeartRate: previous.restingHeartRate, rhrBaseline: inputs.rhrBaseline,
                respiratoryRate: previous.respiratoryRate, respiratoryBaseline: inputs.respiratoryBaseline,
                temperatureDelta: previous.temperatureDelta, temperatureBaselineSD: inputs.temperatureBaselineSD, luteal: luteal
            )
        } ?? []
        let repeated = today.contains { signal in yesterday.contains { $0.id == signal.id } }
        // A week-long breathing-disturbance trend already spans more than two days.
        let confirmed = inputs.reportedSymptoms || repeated || inputs.breathingDisturbancesRising

        var level: Level = total >= 2 ? .major : .minor
        let awaitingSecondDay = level == .major && !confirmed
        if awaitingSecondDay { level = .minor }
        let explained = (inputs.drinksLastNight ?? 0) >= 2 || (inputs.yesterdayStrain ?? 0) >= 80
        if explained && !inputs.reportedSymptoms && bodySignalCount < 3 { level = .minor }
        if inputs.reportedSymptoms { signals.append("You feel unwell") }

        var message: String
        switch level {
        case .major:
            message = "Several signs together suggest your body may be fighting something. Keep today easy, sleep early and drink fluids. Consider rest mode until you feel better."
        case .minor where bodySignalCount == 0:
            message = "You said you're feeling unwell. Your vitals look normal so far, but keep today easy and see how you feel."
        case .minor where awaitingSecondDay && !explained:
            message = "A couple of your vitals are up compared with your normal. One day is often noise; if they're still up tomorrow, treat it as a sign to rest."
        case .minor:
            message = "One of your vitals is up compared with your normal. On its own that's common; keep an eye on how you feel."
        }
        if explained {
            message += " Alcohol or yesterday's hard training can also cause this."
        }
        if luteal && !today.isEmpty {
            message += " Temperature and heart rate also shift across a menstrual cycle, so the bar is set higher for now."
        }
        return Alert(level: level, signals: signals, message: message, awaitingSecondDay: awaitingSecondDay)
    }
}

// MARK: - Deload

/// Suggests an easier week when your main lifts stop improving, especially if
/// HRV is also trending down. Deloads are standard practice in strength
/// sports (Bell et al., Sports Med Open 2023, international Delphi consensus);
/// typical deload: same weights, about half the sets, for about a week.
public enum DeloadAdvisor {
    public struct LiftPoint: Sendable, Equatable {
        public var exercise: String
        public var date: Date
        /// Best estimated 1RM that session.
        public var estimatedOneRepMax: Double

        public init(exercise: String, date: Date, estimatedOneRepMax: Double) {
            self.exercise = exercise
            self.date = date
            self.estimatedOneRepMax = estimatedOneRepMax
        }
    }

    public struct Advice: Sendable, Equatable {
        public var strong: Bool
        public var stalledLifts: [String]
        public var message: String
    }

    /// - Parameters:
    ///   - lifts: per-session bests over the last ~6 weeks.
    ///   - hrvBelowNormal: 7-day HRV is below the normal range.
    public static func evaluate(_ lifts: [LiftPoint], hrvBelowNormal: Bool, now: Date = .now) -> Advice? {
        let recentStart = now.addingTimeInterval(-14 * 86_400)
        let previousStart = now.addingTimeInterval(-28 * 86_400)
        var checked = 0
        var stalled: [String] = []
        for (exercise, points) in Dictionary(grouping: lifts, by: \.exercise) {
            let recent = points.filter { $0.date >= recentStart }
            let previous = points.filter { $0.date >= previousStart && $0.date < recentStart }
            guard recent.count >= 2, previous.count >= 2,
                  let bestRecent = recent.map(\.estimatedOneRepMax).max(),
                  let bestPrevious = previous.map(\.estimatedOneRepMax).max() else { continue }
            checked += 1
            if bestRecent <= bestPrevious * 1.005 { stalled.append(exercise) }
        }
        guard checked >= 2, stalled.count >= 2, Double(stalled.count) / Double(checked) >= 0.5 else { return nil }
        let names = stalled.sorted()
        if hrvBelowNormal {
            return Advice(strong: true, stalledLifts: names,
                          message: "Your main lifts have stalled for 2 weeks and your HRV is below normal. Take a deload week: same weights, about half the sets.")
        }
        return Advice(strong: false, stalledLifts: names,
                      message: "Your main lifts haven't improved in 2 weeks. If you also feel run down, a lighter week (half the sets) usually gets progress moving again.")
    }
}
