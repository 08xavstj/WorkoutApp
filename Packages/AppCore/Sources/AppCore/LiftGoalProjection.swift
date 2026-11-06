import Foundation

/// A long-term lift target: "Bench 100 kg" or "Squat 1.5 × body weight",
/// optionally by a date. Stored on `Goals.liftGoals`; weights in kg.
public struct LiftGoal: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// The exercise library ID the projection reads history for.
    public var exerciseID: String
    public var name: String
    /// Target estimated 1RM in kg; used when `bodyweightMultiple` is nil.
    public var targetKg: Double?
    /// Target as a multiple of body weight (e.g. 1.5); wins over `targetKg`.
    public var bodyweightMultiple: Double?
    /// Optional date to aim for; the projection still stops at 6 months.
    public var targetDate: Date?

    public init(id: UUID = UUID(), exerciseID: String, name: String, targetKg: Double? = nil,
                bodyweightMultiple: Double? = nil, targetDate: Date? = nil) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.targetKg = targetKg
        self.bodyweightMultiple = bodyweightMultiple
        self.targetDate = targetDate
    }

    /// The target in kg: the multiple × body mass, else `targetKg`. Nil when
    /// a bodyweight goal has no body mass to work from.
    public func resolvedTargetKg(bodyMassKg: Double?) -> Double? {
        if let multiple = bodyweightMultiple, multiple > 0 {
            guard let bodyMassKg, bodyMassKg > 0 else { return nil }
            return multiple * bodyMassKg
        }
        if let targetKg, targetKg > 0 { return targetKg }
        return nil
    }
}

/// Where a lift goal sits on the current estimated-1RM trend.
///
/// Evidence and framing (docs/research/lifting-features.md §3, pick 6):
/// - Goal setting raises physical activity moderately (McEwan D, et al.,
///   Health Psychol Rev 2016;10:67–88, meta-analysis, d ≈ 0.55) [E13].
/// - Specific hard goals help people who are already active but can backfire
///   when they're out of reach (Swann C, et al., Health Psychol Rev
///   2021;15:34–50 [E14]; Swann et al., Health Psychol Rev 2026, secondary
///   summary [E15]). So the band widens the further ahead it looks, an
///   off-trend goal is reported as "not on the current trend" without a
///   deficit tone, and the open alternative ("see how far you get") is offered.
/// - The projection itself is arithmetic, not science: a straight line
///   through the last 12 weeks, read as "if the last 12 weeks continue".
public enum LiftGoalProjection {
    // MARK: Constants

    /// Only sets of 10 reps or fewer feed the trend: Epley/Brzycki predict
    /// within about 3 kg from 3–5RM, and accuracy falls past 10 reps
    /// (watch-features.md 3.6 [B22]).
    public static let maximumReps = 10
    /// The trend window (app choice: about one training block of 4 weeks × 3,
    /// recent enough to reflect current training).
    public static let fitWeeks = 12.0
    /// Fewest sessions in the window for a line (app choice: a line through
    /// 2–3 points has almost no residual to measure the spread with).
    public static let minimumPoints = 4
    /// Shortest span of those sessions (app choice).
    public static let minimumSpanWeeks = 3.0
    /// Projections stop at 6 months: novices' linear gains flatten with
    /// training age (lifting-features.md §3 risk; 17-year powerlifting
    /// dataset, secondary summaries only, not re-verified [E26]).
    public static let maximumWeeksAhead = 26.0
    /// Smallest spread used for the band: e1RM estimates are good to about
    /// ±3 kg (watch-features.md 3.6 [B22]), so a near-perfect line doesn't
    /// draw a falsely thin band.
    public static let minimumSpreadKg = 3.0

    /// How much wider the lower edge is for more trained lifters. Gains
    /// flatten with training age [E26, secondary, not re-verified], so a
    /// straight line overstates where intermediate and advanced lifters land;
    /// widening only the lower edge says so. The factors are an app choice.
    public static func lowerEdgeFactor(_ status: TrainingStatus?) -> Double {
        switch status {
        case .intermediate: 1.5
        case .advanced: 2
        default: 1
        }
    }

    /// The most a lift is projected to gain over the 6-month horizon, as a
    /// share of today's e1RM, by training status. From the ACSM position
    /// stand's typical strength gains: about 40% in untrained, 20% in
    /// moderately trained, 16% in trained, 10% in advanced lifters
    /// (Ratamess et al., ACSM Position Stand, Med Sci Sports Exerc
    /// 2009;41:687–708, after Kraemer & Ratamess 2004). Those figures span
    /// studies of 4 weeks to 2 years, so the evidence for a weekly rate is
    /// coarse: using them as a 6-month ceiling is an app choice, there to stop
    /// a fast few weeks becoming "+50 kg by spring". Novice (under 6
    /// consistent months) and unknown status count as untrained, intermediate
    /// as moderately trained.
    public static func maximumGainFraction(_ status: TrainingStatus?) -> Double {
        switch status {
        case .intermediate: 0.20
        case .advanced: 0.10
        default: 0.40
        }
    }

    /// The steepest line the projection draws, kg a week, from `reference` kg.
    public static func maximumSlopePerWeek(reference: Double, status: TrainingStatus?) -> Double {
        max(0, reference) * maximumGainFraction(status) / maximumWeeksAhead
    }

    // MARK: Series

    public struct Sample: Sendable, Equatable, Identifiable {
        public var date: Date
        /// Best estimated 1RM that session, kg.
        public var kg: Double
        public var id: Date { date }
        public init(date: Date, kg: Double) {
            self.date = date
            self.kg = kg
        }
    }

    /// Best e1RM per session (`OneRepMax` via `LiftProgress`) from working
    /// sets of 1–10 reps; sessions without such a set are skipped.
    public static func series(_ sessions: [LiftProgress.LoggedSession]) -> [Sample] {
        let filtered = sessions.map { session in
            LiftProgress.LoggedSession(date: session.date,
                                       sets: session.sets.filter { $0.reps > 0 && $0.reps <= maximumReps && $0.weight > 0 })
        }
        return LiftProgress.points(filtered).map { Sample(date: $0.date, kg: $0.estimatedOneRepMax) }
    }

    // MARK: Fit

    /// Least-squares line through the window, in weeks from `now` (x = 0 is
    /// now, earlier sessions are negative).
    public struct Fit: Sendable, Equatable {
        public var slopePerWeek: Double
        /// Fitted value now (x = 0), kg.
        public var intercept: Double
        /// Residual standard deviation (n − 2 degrees of freedom), kg.
        public var residualSD: Double
        public var count: Int
        /// Mean x of the sessions, weeks.
        public var meanWeeks: Double
        /// Σ(x − x̄)², weeks².
        public var sumSquares: Double
        /// Weeks between the first and last session in the window.
        public var spanWeeks: Double

        public func value(weeksAhead x: Double) -> Double { intercept + slopePerWeek * x }

        /// Half-width of the band x weeks ahead: one standard error of a
        /// new observation from the line, s·√(1 + 1/n + (x − x̄)²/Sxx), the
        /// textbook prediction interval at ±1 SE. It widens with distance from
        /// the logged sessions (about linearly far out). s is the residual SD,
        /// at least `minimumSpreadKg`. ±1 SE covers about 2 in 3 outcomes with
        /// normal errors and many sessions, fewer with only a handful (about
        /// 58% at 4 sessions by the t distribution), so the UI calls it a
        /// "rough 2-in-3 range", never a sure one.
        public func halfWidth(weeksAhead x: Double) -> Double {
            let spread = max(residualSD, LiftGoalProjection.minimumSpreadKg)
            let distance = x - meanWeeks
            return spread * (1 + 1 / Double(count) + distance * distance / sumSquares).squareRoot()
        }
    }

    /// Sessions in the last 12 weeks, oldest first.
    public static func window(_ samples: [Sample], now: Date) -> [Sample] {
        let start = now.addingTimeInterval(-fitWeeks * 7 * 86_400)
        return samples.filter { $0.date > start && $0.date <= now && $0.kg > 0 }.sorted { $0.date < $1.date }
    }

    /// The line, or nil with fewer than 4 sessions over 3+ weeks in the window.
    public static func fit(_ samples: [Sample], now: Date) -> Fit? {
        let recent = window(samples, now: now)
        guard recent.count >= minimumPoints, let first = recent.first, let last = recent.last else { return nil }
        let week = 7 * 86_400.0
        let span = last.date.timeIntervalSince(first.date) / week
        guard span >= minimumSpanWeeks - 1e-9 else { return nil }
        let xs = recent.map { $0.date.timeIntervalSince(now) / week }
        let ys = recent.map(\.kg)
        let n = Double(recent.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var sxx = 0.0
        var sxy = 0.0
        for index in xs.indices {
            sxx += (xs[index] - meanX) * (xs[index] - meanX)
            sxy += (xs[index] - meanX) * (ys[index] - meanY)
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        var residuals = 0.0
        for index in xs.indices {
            let error = ys[index] - (intercept + slope * xs[index])
            residuals += error * error
        }
        let sd = (residuals / (n - 2)).squareRoot()
        return Fit(slopePerWeek: slope, intercept: intercept, residualSD: sd, count: recent.count,
                   meanWeeks: meanX, sumSquares: sxx, spanWeeks: span)
    }

    // MARK: Projection

    public enum Status: String, Sendable, Equatable {
        /// Fewer than 4 sessions over 3+ weeks in the last 12 weeks.
        case needsMoreData
        /// A session in the last 12 weeks already hit the target.
        case reached
        /// The trend line itself reaches the target before the horizon.
        case onTrend
        /// Only the band's upper edge does: possible, but the line gets there
        /// later (or not before the horizon).
        case possible
        /// Neither does, within the horizon (target date or 6 months).
        case notOnTrend
    }

    public struct BandPoint: Sendable, Equatable, Identifiable {
        public var date: Date
        public var low: Double
        public var mid: Double
        public var high: Double
        public var id: Date { date }
    }

    public struct Projection: Sendable, Equatable {
        public var status: Status
        public var targetKg: Double
        /// Latest session's e1RM in the window, kg.
        public var latestKg: Double?
        public var fit: Fit?
        /// Where the band ends: the target date, at most 6 months ahead.
        public var horizon: Date
        /// The band at the horizon, kg.
        public var range: ClosedRange<Double>?
        /// First day the upper edge reaches the target.
        public var reachFrom: Date?
        /// First day the trend line reaches it.
        public var reachLine: Date?
        /// First day the lower edge reaches it (nil if not before the horizon).
        public var reachBy: Date?
        /// Weekly band from now to the horizon, for the chart.
        public var band: [BandPoint]
        /// The last 12 weeks' sessions.
        public var recent: [Sample]
        /// True when the lower edge is widened for training status.
        public var widenedForTrainingAge: Bool
        /// True when the trend was steeper than `maximumSlopePerWeek` and
        /// the line was drawn at that ceiling instead.
        public var slopeCapped = false

        /// Latest e1RM as a share of the target (0...1).
        public var progress: Double? {
            guard let latestKg, targetKg > 0 else { return nil }
            return min(1, max(0, latestKg / targetKg))
        }
    }

    /// Projects the e1RM trend toward `targetKg`.
    /// - Parameters:
    ///   - targetDate: used as the horizon when it's in the future and within 6 months.
    ///   - trainingStatus: widens the lower edge for intermediate and advanced lifters.
    public static func project(samples: [Sample], targetKg: Double, targetDate: Date? = nil,
                               trainingStatus: TrainingStatus? = nil, now: Date = .now) -> Projection {
        let week = 7 * 86_400.0
        let cap = now.addingTimeInterval(maximumWeeksAhead * week)
        var horizon = cap
        if let targetDate, targetDate > now, targetDate < cap { horizon = targetDate }
        let recent = window(samples, now: now)
        let latest = recent.last?.kg
        let factor = lowerEdgeFactor(trainingStatus)
        var projection = Projection(status: .needsMoreData, targetKg: targetKg, latestKg: latest, fit: nil, horizon: horizon,
                                    range: nil, reachFrom: nil, reachLine: nil, reachBy: nil, band: [], recent: recent,
                                    widenedForTrainingAge: factor > 1)
        if recent.contains(where: { $0.kg >= targetKg }) {
            projection.status = .reached
            return projection
        }
        guard var capped = fit(samples, now: now) else { return projection }
        // No faster than typical gains for this training level (`maximumGainFraction`).
        let ceiling = maximumSlopePerWeek(reference: latest ?? capped.intercept, status: trainingStatus)
        if capped.slopePerWeek > ceiling {
            capped.slopePerWeek = ceiling
            projection.slopeCapped = true
        }
        let line = capped
        projection.fit = line

        let horizonWeeks = horizon.timeIntervalSince(now) / week
        // The low edge never drops further than one spread under your best
        // recent session (but never above the line): strength already shown
        // is mostly kept while you keep training, so a "likely" low end well
        // under today's lift reads as a loss nobody expects (app choice; the
        // spread is the same `minimumSpreadKg`-floored residual SD the band
        // uses, times the training-status factor so the wider low edge for
        // trained lifters still shows).
        let best = recent.map(\.kg).max()
        let floorKg = best.map { $0 - factor * max(line.residualSD, minimumSpreadKg) }
        func low(_ x: Double) -> Double {
            let raw = line.value(weeksAhead: x) - factor * line.halfWidth(weeksAhead: x)
            guard let floorKg else { return raw }
            return max(raw, min(floorKg, line.value(weeksAhead: x)))
        }
        func high(_ x: Double) -> Double { line.value(weeksAhead: x) + line.halfWidth(weeksAhead: x) }

        // Weekly band points plus the horizon itself.
        var band: [BandPoint] = []
        var x = 0.0
        while x < horizonWeeks {
            band.append(BandPoint(date: now.addingTimeInterval(x * week), low: low(x), mid: line.value(weeksAhead: x), high: high(x)))
            x += 1
        }
        band.append(BandPoint(date: horizon, low: low(horizonWeeks), mid: line.value(weeksAhead: horizonWeeks), high: high(horizonWeeks)))
        projection.band = band
        projection.range = min(low(horizonWeeks), high(horizonWeeks))...max(low(horizonWeeks), high(horizonWeeks))

        // Day-by-day crossings up to the horizon.
        let days = Int(horizon.timeIntervalSince(now) / 86_400)
        for day in 0...max(0, days) {
            let weeksAhead = Double(day) / 7
            if projection.reachFrom == nil, high(weeksAhead) >= targetKg {
                projection.reachFrom = now.addingTimeInterval(Double(day) * 86_400)
            }
            if projection.reachLine == nil, line.value(weeksAhead: weeksAhead) >= targetKg {
                projection.reachLine = now.addingTimeInterval(Double(day) * 86_400)
            }
            if projection.reachBy == nil, low(weeksAhead) >= targetKg {
                projection.reachBy = now.addingTimeInterval(Double(day) * 86_400)
                break
            }
        }
        // "On trend" needs the line itself to get there; the upper edge alone
        // (a rough 1-in-6 chance) is only "possible". A flat or falling line
        // isn't heading to the target, even when the upper edge brushes it.
        if line.slopePerWeek <= 0 || projection.reachFrom == nil {
            projection.status = .notOnTrend
        } else {
            projection.status = projection.reachLine != nil ? .onTrend : .possible
        }
        if projection.status == .notOnTrend {
            projection.reachFrom = nil
            projection.reachLine = nil
            projection.reachBy = nil
        }
        return projection
    }

    // MARK: Text

    /// Within this many days of now counts as "now" in the text.
    static let nowDays = 14.0

    /// One line: "At your last 12 weeks' rate, 100 kg falls between March
    /// and June." `weight` formats kg with the unit; `month` formats a date
    /// as a month (with the year when it isn't this year).
    public static func headline(_ projection: Projection, weight: (Double) -> String, month: (Date) -> String,
                                now: Date = .now) -> String {
        let target = weight(projection.targetKg)
        switch projection.status {
        case .needsMoreData:
            return "Log a few more sessions to see a projection."
        case .reached:
            let latest = projection.recent.map(\.kg).max().map(weight) ?? target
            return "You've reached it: \(latest) estimated 1RM. Set the next one whenever you like."
        case .onTrend:
            guard let from = projection.reachFrom else { return "At your last 12 weeks' rate, \(target) is in reach." }
            let soon = from.timeIntervalSince(now) <= nowDays * 86_400
            if let by = projection.reachBy {
                let byText = month(by)
                return soon ? "At your last 12 weeks' rate, \(target) could come within weeks and is likely by \(byText)."
                    : "At your last 12 weeks' rate, \(target) falls between \(month(from)) and \(byText)."
            }
            let endText = month(projection.horizon)
            return soon ? "At your last 12 weeks' rate, \(target) could come within weeks; past \(endText) is too far to say more."
                : "At your last 12 weeks' rate, \(target) comes into range from about \(month(from))."
        case .possible:
            return "At your last 12 weeks' rate, \(target) is possible by \(month(projection.horizon)), but the trend line gets there later."
        case .notOnTrend:
            return "\(target) isn't on the current trend by \(month(projection.horizon))."
        }
    }

    /// The range at the horizon, "If the last 12 weeks continue: likely
    /// 95–105 kg by June (a rough 2-in-3 range).", or nil without a line.
    public static func rangeLine(_ projection: Projection, weight: (Double) -> String, month: (Date) -> String) -> String? {
        guard let range = projection.range,
              [.onTrend, .possible, .notOnTrend].contains(projection.status) else { return nil }
        var low = weight(max(0, range.lowerBound))
        let high = weight(range.upperBound)
        // "112–140 kg", not "112 kg–140 kg": drop the shared unit from the low end.
        if let space = high.lastIndex(of: " ") {
            let unit = String(high[space...])
            if low.hasSuffix(unit) { low = String(low.dropLast(unit.count)) }
        }
        var line = "If the last 12 weeks continue: likely \(low)–\(high) by \(month(projection.horizon)) (a rough 2-in-3 range)."
        if projection.slopeCapped {
            line += " Your recent rate was faster than lifters at your level usually keep up, so the line uses the typical pace for your level instead."
        }
        if projection.widenedForTrainingAge {
            line += " Progress usually slows, so the low end is more likely."
        }
        return line
    }

    /// The open alternative to a specific target (Swann 2021 [E14]).
    public static func openAlternative(_ projection: Projection, month: (Date) -> String) -> String? {
        switch projection.status {
        case .possible, .notOnTrend, .needsMoreData:
            return "Or keep it open: see how far you get by \(month(projection.horizon))."
        case .onTrend, .reached:
            return nil
        }
    }

    /// The note under the chart.
    public static let evidenceNote = "The projection is arithmetic, not a forecast: a straight line through your last 12 weeks of estimated 1RMs (sets of 10 reps or fewer). The band is a rough 2-in-3 range for the session-to-session spread, wider further ahead; it's \"on trend\" only when the line itself reaches the target. It's never steeper than typical gains for your training level (ACSM 2009), and it stops at 6 months because gains usually slow. Setting goals helps people train more (McEwan 2016 meta-analysis), but specific goals that feel out of reach can backfire (Swann 2021), so treat the target as a direction, not a test."
}
