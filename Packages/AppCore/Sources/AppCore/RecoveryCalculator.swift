import Foundation

/// Daily recovery 0-100: last night's HRV and resting heart rate compared with
/// your own recent baseline, plus how well you slept.
///
/// Each input becomes a z-score (how many "normal days" away from your average).
/// HRV above baseline is good; resting heart rate above baseline is bad.
///
/// The HRV trend rule is from research: the 7-day rolling average of ln HRV
/// against your normal range (baseline mean ± 0.5 SD, the "smallest
/// worthwhile change") is the method used to guide training in trials (Plews
/// et al., Eur J Appl Physiol 2012; Plews et al., Sports Med 2013; Buchheit,
/// Front Physiol 2014; Javaloyes et al., IJSPP 2019, with a 4-week baseline).
///
/// That trend sets the band (the validated part): below the normal range the
/// score is capped at 33 ("easy day"), within it the score stays 34-66, and
/// above it the score is 67 or more only when resting heart rate and sleep
/// aren't also off. The z-score blend still moves the number inside the band,
/// so the 0-100 figure (weights and curve) remains the app's own summary, not a
/// validated clinical score.
///
/// Each signal needs 14 nights before it's used, since a baseline from a few
/// nights is mostly noise.
public struct RecoveryCalculator: Sendable {
    public var baselineDays: Int = 30
    public var minimumBaselineDays: Int = 14
    /// Sleep scores needed before your own sleep baseline replaces the
    /// population one (the same 14-night rule as HRV and resting heart rate).
    public var minimumSleepBaselineNights: Int = 14
    public var hrvTrendWeight: Double = 0.35
    public var hrvWeight: Double = 0.20
    public var restingHeartRateWeight: Double = 0.25
    public var sleepWeight: Double = 0.20

    /// Score bands. They follow the 7-day HRV trend when it's known (see
    /// `band(for:rhrEffect:sleepEffect:)`); otherwise the score alone decides.
    public static let lowBand = 1...33
    public static let moderateBand = 34...66
    public static let highBand = 67...99

    public init() {}

    public enum Status: String, Sendable {
        case low, moderate, high

        /// Card wording. The low band reads "Easy day", not "Low": HRV-guided
        /// trials replace hard sessions with easy ones on those days rather
        /// than skipping training (Javaloyes et al., IJSPP 2019), and
        /// controlling, deficit-framed feedback lowers motivation (Deci et al.
        /// 1999; Ntoumanis et al. 2021, as cited in the research roadmap).
        public var label: String {
            switch self {
            case .low: "Easy day"
            case .moderate: "Normal"
            case .high: "Recovered"
            }
        }
    }

    /// The 7-day HRV average and where it sits against your normal range.
    public struct HRVTrend: Sendable, Equatable {
        public enum Status: String, Sendable { case below, within, above }
        public var average: Double
        public var normalRange: ClosedRange<Double>
        public var status: Status
        /// Day-to-day swing over the last 7 nights (coefficient of variation of ln HRV, %).
        public var variation: Double?
        public var nights: Int
    }

    public struct Result: Sendable, Equatable {
        public var score: Int
        public var hrvTrend: HRVTrend?
        public var status: Status
        /// True when the 7-day HRV trend set the band; false when the score alone did
        /// (no HRV, or not calibrated yet).
        public var bandFollowsTrend: Bool = false
        /// Percent difference from baseline, e.g. +8 means 8% above normal.
        public var hrvChangePercent: Double?
        public var restingHeartRateChange: Double?
        public var baselineHRV: Double?
        public var baselineRestingHeartRate: Double?
        /// Where the resting heart rate (today's and the baseline's) came from.
        public var restingHeartRateSource: RestingHeartRateSource = .healthKit
        /// False until there are enough nights to build a baseline.
        public var isCalibrated: Bool
        /// Nights behind the sleep baseline; 0 while the population fallback (75 ± 12) is used.
        public var sleepBaselineNights: Int = 0
        /// What pushed the score up or down, biggest effect first.
        public var contributors: [RecoveryContributor] = []
        /// True when there's no HRV or resting heart rate at all (e.g. iPhone-only
        /// sleep tracking), so the score is sleep alone and will never "calibrate".
        public var isSleepOnly: Bool = false
    }

    public struct Baseline: Sendable, Equatable {
        public var meanLogHRV: Double?
        public var sdLogHRV: Double?
        public var meanRHR: Double?
        public var sdRHR: Double?
        public var nights: Int
        public var hrvNights: Int = 0
        public var rhrNights: Int = 0
        public var restingHeartRateSource: RestingHeartRateSource = .healthKit
    }

    /// - Parameter restingHeartRateSource: what `history`'s resting heart rates
    ///   are (see `preferSleepingHeartRate`); recorded on the baseline so the
    ///   UI can say which it is.
    public func baseline(from history: [DailyVitals], restingHeartRateSource: RestingHeartRateSource = .healthKit) -> Baseline {
        let recent = history.sorted { $0.date > $1.date }.prefix(baselineDays)
        let logHRV = recent.compactMap(\.hrvMilliseconds).filter { $0 > 0 }.map { log($0) }
        let rhr = recent.compactMap(\.restingHeartRate).filter { $0 > 0 }
        let (meanH, sdH) = Self.meanAndSD(logHRV)
        let (meanR, sdR) = Self.meanAndSD(rhr)
        return Baseline(meanLogHRV: meanH, sdLogHRV: sdH, meanRHR: meanR, sdRHR: sdR, nights: max(logHRV.count, rhr.count),
                        hrvNights: logHRV.count, rhrNights: rhr.count, restingHeartRateSource: restingHeartRateSource)
    }

    /// Swaps the resting heart rate in `vitals` for the night's average
    /// sleeping heart rate, all nights or none, so a baseline never mixes the
    /// two. Sleep-period heart rate is steadier than a daytime estimate and is
    /// what the illness studies used (Mishra et al., Nat Biomed Eng 2020;
    /// Natarajan et al., npj Digit Med 2020); Apple's `restingHeartRate` is a
    /// daytime-stillness estimate and Garmin's is already a sleep-period value.
    ///
    /// - Parameters:
    ///   - sleeping: average heart rate asleep, keyed by the morning it ended.
    ///   - minimumNights: nights of sleeping heart rate needed before it's used
    ///     (pass one more than the baseline minimum when `vitals` includes today).
    ///   - current: the source used last time. Once sleeping heart rate is in
    ///     use it stays until fewer than `keepNights` nights remain, so one
    ///     night without the watch doesn't flip the baseline back and forth.
    ///   - keepNights: the lower threshold for `current == .sleeping`
    ///     (`sleepingHeartRateKeepNights` by default; the app's choice).
    /// - Returns: the vitals to use and which source they carry. With too few
    ///   sleeping nights the input comes back unchanged, as HealthKit data.
    public static func preferSleepingHeartRate(
        _ vitals: [DailyVitals],
        sleeping: [Date: Double],
        minimumNights: Int,
        current: RestingHeartRateSource? = nil,
        keepNights: Int = RecoveryCalculator.sleepingHeartRateKeepNights,
        calendar: Calendar = .current
    ) -> (vitals: [DailyVitals], source: RestingHeartRateSource) {
        var byNight: [Date: Double] = [:]
        for (date, bpm) in sleeping where bpm > 0 {
            byNight[calendar.startOfDay(for: date)] = bpm
        }
        let needed = current == .sleeping ? min(keepNights, minimumNights) : minimumNights
        guard byNight.count >= needed else { return (vitals, .healthKit) }
        var result: [DailyVitals] = []
        var seen: Set<Date> = []
        for entry in vitals {
            let night = calendar.startOfDay(for: entry.date)
            seen.insert(night)
            result.append(DailyVitals(date: entry.date, hrvMilliseconds: entry.hrvMilliseconds, restingHeartRate: byNight[night]))
        }
        for (night, bpm) in byNight where !seen.contains(night) {
            result.append(DailyVitals(date: night, hrvMilliseconds: nil, restingHeartRate: bpm))
        }
        return (result.sorted { $0.date > $1.date }, .sleeping)
    }

    /// Sleeping heart rate, once in use, is kept while at least this many
    /// nights have it (hysteresis below the 15 needed to switch; app's choice).
    public static let sleepingHeartRateKeepNights = 10

    /// - Parameters:
    ///   - today: last night's vitals.
    ///   - history: previous nights, not including `today`.
    ///   - sleepScore: 0-100 from `SleepCalculator`, if available.
    ///   - sleepScoreHistory: previous nights' sleep scores (up to the last 30,
    ///     any order), so sleep is compared with your own usual like HRV and
    ///     resting heart rate are. Until 14 nights, 75 ± 12 is used.
    ///   - restingHeartRateSource: what the resting heart rates in `today` and
    ///     `history` are (see `preferSleepingHeartRate`).
    public func score(
        today: DailyVitals,
        history: [DailyVitals],
        sleepScore: Int?,
        sleepScoreHistory: [Int] = [],
        restingHeartRateSource: RestingHeartRateSource = .healthKit
    ) -> Result? {
        let base = baseline(from: history, restingHeartRateSource: restingHeartRateSource)
        let calibrated = base.nights >= minimumBaselineDays
        let hrvReady = base.hrvNights >= minimumBaselineDays
        let rhrReady = base.rhrNights >= minimumBaselineDays

        var combined = 0.0
        var weightUsed = 0.0
        var hrvChange: Double?
        var rhrChange: Double?
        var trend: HRVTrend?
        var contributors: [RecoveryContributor] = []
        var rhrEffect: RecoveryContributor.Effect = .neutral
        var sleepEffect: RecoveryContributor.Effect = .neutral
        var sleepBaselineNights = 0

        // 7-day rolling ln HRV (tonight + up to 6 previous nights).
        let lastWeek = ([today] + history.sorted { $0.date > $1.date }.prefix(6))
            .compactMap(\.hrvMilliseconds).filter { $0 > 0 }.map { log($0) }
        if lastWeek.count >= 3, let mean = base.meanLogHRV, let sd = base.sdLogHRV, hrvReady {
            let rolling = lastWeek.reduce(0, +) / Double(lastWeek.count)
            // SWC = 0.5 × SD of ln HRV (Javaloyes et al., IJSPP 2019; Buchheit, Front Physiol 2014).
            let swc = 0.5 * max(sd, 0.05)
            let status: HRVTrend.Status = rolling < mean - swc ? .below : (rolling > mean + swc ? .above : .within)
            let (_, weekSD) = Self.meanAndSD(lastWeek)
            trend = HRVTrend(
                average: exp(rolling),
                normalRange: exp(mean - swc)...exp(mean + swc),
                status: status,
                variation: weekSD.map { $0 / rolling * 100 },
                nights: lastWeek.count
            )
            let z = (rolling - mean) / max(sd, 0.10)
            combined += hrvTrendWeight * Self.clampZ(z)
            weightUsed += hrvTrendWeight
            let rangeText = "\(Int(exp(mean - swc).rounded()))-\(Int(exp(mean + swc).rounded())) ms"
            let averageText = "7-day average \(Int(exp(rolling).rounded())) ms"
            let trendDetail: String
            let trendNote: String?
            let trendEffect: RecoveryContributor.Effect
            switch status {
            case .below:
                trendDetail = "\(averageText), below your normal \(rangeText)"
                trendNote = "A sign to train easier, so recovery stays in the easy-day band today."
                trendEffect = .lowers
            case .above:
                trendDetail = "\(averageText), above your normal \(rangeText)"
                trendNote = nil
                trendEffect = .raises
            case .within:
                trendDetail = "\(averageText), within your normal \(rangeText)"
                trendNote = "So recovery stays in the moderate band."
                trendEffect = .neutral
            }
            contributors.append(RecoveryContributor(
                id: "hrvTrend", name: "7-day HRV",
                detail: trendDetail,
                note: trendNote,
                effect: trendEffect,
                weight: hrvTrendWeight * abs(Self.clampZ(z))
            ))
        }

        if let hrv = today.hrvMilliseconds, hrv > 0, let mean = base.meanLogHRV, let sd = base.sdLogHRV, hrvReady {
            // Floor the SD so a very steady baseline doesn't make small changes look huge.
            let z = (log(hrv) - mean) / max(sd, 0.10)
            combined += hrvWeight * Self.clampZ(z)
            weightUsed += hrvWeight
            hrvChange = (hrv / exp(mean) - 1) * 100
            let change = Int(((hrv / exp(mean) - 1) * 100).rounded())
            contributors.append(RecoveryContributor(
                id: "hrv", name: "Last night's HRV",
                detail: "\(Int(hrv.rounded())) ms, \(change >= 0 ? "+" : "")\(change)% vs your usual \(Int(exp(mean).rounded())) ms",
                effect: Self.effect(z), weight: hrvWeight * abs(Self.clampZ(z))
            ))
        }
        if let rhr = today.restingHeartRate, rhr > 0, let mean = base.meanRHR, let sd = base.sdRHR, rhrReady {
            let z = (rhr - mean) / max(sd, 1.5)
            combined -= restingHeartRateWeight * Self.clampZ(z)
            weightUsed += restingHeartRateWeight
            rhrChange = rhr - mean
            rhrEffect = Self.effect(-z)
            let difference = Int((rhr - mean).rounded())
            contributors.append(RecoveryContributor(
                id: "rhr", name: restingHeartRateSource.label,
                detail: "\(Int(rhr.rounded())) bpm, \(difference >= 0 ? "+" : "")\(difference) vs your usual \(Int(mean.rounded()))",
                note: difference > 0 ? "Higher than usual often means stress, alcohol, illness or hard training." : nil,
                effect: rhrEffect, weight: restingHeartRateWeight * abs(Self.clampZ(z))
            ))
        }
        if let sleepScore {
            // Your own 30-night mean and SD, like the HRV and RHR baselines; the
            // population anchor (75 ± 12) is only a stand-in while calibrating.
            let sleepBase = Self.sleepBaseline(sleepScoreHistory, minimumNights: minimumSleepBaselineNights)
            let z = (Double(sleepScore) - sleepBase.mean) / sleepBase.sd
            combined += sleepWeight * Self.clampZ(z)
            weightUsed += sleepWeight
            sleepEffect = Self.effect(z)
            sleepBaselineNights = sleepBase.nights
            let detail = sleepBase.nights > 0
                ? "Score \(sleepScore), vs your usual \(Int(sleepBase.mean.rounded()))"
                : "Score \(sleepScore) of 100"
            contributors.append(RecoveryContributor(
                id: "sleep", name: "Sleep",
                detail: detail,
                effect: sleepEffect, weight: sleepWeight * abs(Self.clampZ(z))
            ))
        }
        // No HRV or resting heart rate at all: sleep is the only input, so say
        // so instead of "learning" forever.
        let sleepOnly = sleepScore != nil && base.hrvNights == 0 && base.rhrNights == 0
            && (today.hrvMilliseconds ?? 0) <= 0 && (today.restingHeartRate ?? 0) <= 0
        if sleepOnly {
            contributors.append(RecoveryContributor(
                id: "sleepOnly", name: "Sleep only",
                detail: "Apple Health has no HRV or resting heart rate for you, so this is a sleep-only estimate. A watch that records them overnight makes recovery personal.",
                effect: .neutral
            ))
        }
        guard weightUsed > 0 else { return nil }

        // Rescale so missing inputs don't drag the score toward 50.
        let normalized = combined / weightUsed
        let logistic = 1 / (1 + exp(-(1.5 * normalized + 0.3)))
        let raw = min(99, max(1, Int((logistic * 100).rounded())))
        // The 7-day HRV trend picks the band; the blend moves the number inside it.
        let trendBand = trend.map { Self.band(for: $0.status, rhrEffect: rhrEffect, sleepEffect: sleepEffect) }
        let score = trendBand.map { Self.scale(raw, into: $0) } ?? raw

        return Result(
            score: score,
            hrvTrend: trend,
            status: Self.status(for: score),
            bandFollowsTrend: trendBand != nil,
            hrvChangePercent: hrvChange,
            restingHeartRateChange: rhrChange,
            baselineHRV: base.meanLogHRV.map { exp($0) },
            baselineRestingHeartRate: base.meanRHR,
            restingHeartRateSource: restingHeartRateSource,
            isCalibrated: calibrated,
            sleepBaselineNights: sleepBaselineNights,
            contributors: contributors.sorted { $0.weight > $1.weight },
            isSleepOnly: sleepOnly
        )
    }

    public static func status(for score: Int) -> Status {
        switch score {
        case ..<Self.moderateBand.lowerBound: .low
        case Self.moderateBand: .moderate
        default: .high
        }
    }

    /// The score band the 7-day HRV trend allows. Below the normal range is an
    /// easy day whatever last night looked like (the trial rule: Plews et al.,
    /// Sports Med 2013; Javaloyes et al., IJSPP 2019); within it the score is
    /// moderate; above it the score is high only when resting heart rate and
    /// sleep don't disagree (HRV can also rise with overreaching, so a high
    /// trend on its own isn't proof of readiness: Buchheit, Front Physiol
    /// 2014). The 34/67 cut-offs are the app's.
    public static func band(
        for trend: HRVTrend.Status,
        rhrEffect: RecoveryContributor.Effect,
        sleepEffect: RecoveryContributor.Effect
    ) -> ClosedRange<Int> {
        switch trend {
        case .below: lowBand
        case .within: moderateBand
        case .above: rhrEffect != .lowers && sleepEffect != .lowers ? highBand : moderateBand
        }
    }

    /// Maps a raw 1-99 score onto a band so it still moves with the inputs.
    static func scale(_ raw: Int, into band: ClosedRange<Int>) -> Int {
        let fraction = Double(min(99, max(1, raw)) - 1) / 98
        return band.lowerBound + Int((fraction * Double(band.upperBound - band.lowerBound)).rounded())
    }

    /// Mean and SD of your last sleep scores (SD floored at 6 points so a very
    /// steady month doesn't make one night look extreme); 75 ± 12 with fewer
    /// than `minimumNights`. The app's choice: no study sets a sleep-score
    /// baseline, but comparing with your own usual is how the HRV and RHR
    /// inputs work (Plews et al., Sports Med 2013; Buchheit, Front Physiol 2014).
    static func sleepBaseline(_ history: [Int], minimumNights: Int) -> (mean: Double, sd: Double, nights: Int) {
        let recent = history.suffix(30).map(Double.init)
        let (meanValue, sdValue) = Self.meanAndSD(recent)
        guard recent.count >= minimumNights, let mean = meanValue, let sd = sdValue else {
            return (75, 12, 0)
        }
        return (mean, max(sd, 6), recent.count)
    }

    static func clampZ(_ z: Double) -> Double { min(3, max(-3, z)) }

    /// Small changes (under a third of a normal day's swing) count as neutral.
    static func effect(_ z: Double) -> RecoveryContributor.Effect {
        z > 0.33 ? .raises : (z < -0.33 ? .lowers : .neutral)
    }

    static func meanAndSD(_ values: [Double]) -> (Double?, Double?) {
        guard !values.isEmpty else { return (nil, nil) }
        let mean = values.reduce(0, +) / Double(values.count)
        guard values.count > 1 else { return (mean, nil) }
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count - 1)
        return (mean, sqrt(variance))
    }
}

/// When last night is over, so today's recovery can be scored. Before that
/// (after midnight, still asleep) today's HRV would come only from the
/// evening before bed, with no sleep or resting heart rate yet.
///
/// Over when the main sleep has woken after midnight with 3 h asleep or a wake
/// at 4 am or later (a 1 am trip to the bathroom isn't the morning). With no
/// sleep recorded tonight: from 4 am for someone who never tracks sleep, from
/// noon for someone who does (they may sync late). All app choices.
public enum RecoveryTiming {
    public static let earliestWakeHour = 4
    public static let minimumAsleepHours = 3.0
    public static let untrackedHour = 4
    public static let trackedFallbackHour = 12

    /// - Parameters:
    ///   - wake: the end of tonight's main sleep, if recorded.
    ///   - asleepHours: hours asleep in that sleep.
    ///   - tracksSleep: sleep was recorded on any of the last 7 nights.
    public static func nightIsOver(now: Date, wake: Date?, asleepHours: Double?, tracksSleep: Bool,
                                   calendar: Calendar = .current) -> Bool {
        let midnight = calendar.startOfDay(for: now)
        if let wake, wake >= midnight, wake <= now.addingTimeInterval(60) {
            let wakeHour = calendar.component(.hour, from: wake)
            if wakeHour >= earliestWakeHour || (asleepHours ?? 0) >= minimumAsleepHours { return true }
        }
        let hour = calendar.component(.hour, from: now)
        return hour >= (tracksSleep ? trackedFallbackHour : untrackedHour)
    }
}

/// Where a resting heart rate came from. One source per baseline: the two
/// are measured differently (Apple's from daytime stillness, sleeping heart
/// rate from the night), so days are never mixed.
public enum RestingHeartRateSource: String, Sendable {
    /// HealthKit's `restingHeartRate` (the fallback).
    case healthKit
    /// The app's own average heart rate during the main sleep.
    case sleeping

    public var label: String {
        switch self {
        case .healthKit: "Resting heart rate"
        case .sleeping: "Sleeping heart rate"
        }
    }
}

/// One thing that moved recovery, in plain words.
public struct RecoveryContributor: Sendable, Equatable, Identifiable {
    public enum Effect: String, Sendable {
        case raises, lowers, neutral
    }

    public var id: String
    public var name: String
    /// The reading itself, short and without a final period, so it can sit
    /// inside a sentence ("sleeping heart rate (53 bpm, +2 vs your usual 51)").
    public var detail: String
    /// An optional explanatory sentence shown under the reading, kept apart so
    /// the coach doesn't paste it into the middle of a list.
    public var note: String?
    public var effect: Effect
    /// How much it moved the score (for ordering); 0 for context-only items.
    public var weight: Double

    public init(id: String, name: String, detail: String, note: String? = nil, effect: Effect, weight: Double = 0) {
        self.id = id
        self.name = name
        self.detail = detail
        self.note = note
        self.effect = effect
        self.weight = weight
    }

    /// Detail and note as full sentences, for a list row or VoiceOver.
    public var explanation: String {
        let reading = detail.hasSuffix(".") ? detail : detail + "."
        guard let note, !note.isEmpty else { return reading }
        return reading + " " + note
    }
}
