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
/// (Mishra et al., Nat Biomed Eng 2020: 63% of COVID-19 cases flagged before
/// symptoms; Quer et al., Nat Med 2021, DETECT study). Alcohol and very hard
/// training cause the same signs, so those are noted.
public enum IllnessWatch {
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

        public init(restingHeartRate: Double? = nil, rhrBaseline: (mean: Double, sd: Double)? = nil,
                    respiratoryRate: Double? = nil, respiratoryBaseline: (mean: Double, sd: Double)? = nil,
                    temperatureDelta: Double? = nil, hrvChangePercent: Double? = nil,
                    drinksLastNight: Int? = nil, yesterdayStrain: Double? = nil, reportedSymptoms: Bool = false) {
            self.restingHeartRate = restingHeartRate
            self.rhrBaseline = rhrBaseline
            self.respiratoryRate = respiratoryRate
            self.respiratoryBaseline = respiratoryBaseline
            self.temperatureDelta = temperatureDelta
            self.hrvChangePercent = hrvChangePercent
            self.drinksLastNight = drinksLastNight
            self.yesterdayStrain = yesterdayStrain
            self.reportedSymptoms = reportedSymptoms
        }

        public static func == (a: Inputs, b: Inputs) -> Bool {
            a.restingHeartRate == b.restingHeartRate && a.respiratoryRate == b.respiratoryRate
                && a.temperatureDelta == b.temperatureDelta && a.hrvChangePercent == b.hrvChangePercent
        }
    }

    public enum Level: Int, Sendable, Comparable {
        case watch = 1, likely = 2
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Alert: Sendable, Equatable {
        public var level: Level
        public var signals: [String]
        public var message: String
    }

    public static func evaluate(_ inputs: Inputs) -> Alert? {
        var signals: [String] = []
        if let rhr = inputs.restingHeartRate, let base = inputs.rhrBaseline,
           rhr - base.mean >= max(2 * base.sd, 4) {
            signals.append("Resting heart rate +\(Int((rhr - base.mean).rounded())) bpm")
        }
        if let rate = inputs.respiratoryRate, let base = inputs.respiratoryBaseline,
           rate - base.mean >= max(2 * base.sd, 1) {
            signals.append(String(format: "Breathing rate +%.1f/min", rate - base.mean))
        }
        if let delta = inputs.temperatureDelta, delta >= 0.5 {
            signals.append(String(format: "Temperature +%.1f °C", delta))
        }
        if let hrv = inputs.hrvChangePercent, hrv <= -20, !signals.isEmpty {
            signals.append("HRV \(Int(hrv.rounded()))%")
        }
        let bodySignals = signals.count
        guard bodySignals > 0 || inputs.reportedSymptoms else { return nil }
        var level: Level = bodySignals >= 2 || (bodySignals >= 1 && inputs.reportedSymptoms) ? .likely : .watch
        let explained = (inputs.drinksLastNight ?? 0) >= 2 || (inputs.yesterdayStrain ?? 0) >= 80
        if explained && !inputs.reportedSymptoms && bodySignals < 3 { level = .watch }
        guard bodySignals > 0 || level == .likely else { return nil }

        var message: String
        switch level {
        case .likely:
            message = "Your body may be fighting something. Keep today easy, sleep early and drink fluids. If you feel unwell, skip hard training."
        case .watch:
            message = "Some of your vitals are up compared with your normal. Worth an easier day and an eye on how you feel."
        }
        if explained {
            message += " Alcohol or yesterday's hard training can also cause this."
        }
        return Alert(level: level, signals: signals, message: message)
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
