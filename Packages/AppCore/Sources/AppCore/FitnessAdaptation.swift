import Foundation

/// Targets that follow your fitness instead of staying fixed: the strain
/// target scales with what your training days usually reach, max heart rate
/// is learned from your hardest efforts, and the step goal tracks your habits.

// MARK: - Max heart rate

/// Learns max heart rate from what your watch actually records. Age formulas
/// are off by ±10 bpm for many people (Tanaka et al., J Am Coll Cardiol 2001),
/// and every zone and strain number depends on max heart rate.
public enum ObservedMaxHeartRate {
    /// Highest believable heart rate in per-minute data: a minute only counts
    /// if a neighbouring minute (within 2 minutes) was within 5 bpm of it, so a
    /// single bad reading (e.g. a loose strap) can't set your max.
    public static func peak(_ samples: [HeartRateSample]) -> Double? {
        let sorted = samples.filter { (90...230).contains($0.bpm) }.sorted { $0.date < $1.date }
        var best: Double?
        for (current, next) in zip(sorted, sorted.dropFirst()) {
            guard next.date.timeIntervalSince(current.date) <= 120,
                  abs(next.bpm - current.bpm) <= 5 else { continue }
            let confirmed = min(current.bpm, next.bpm)
            if confirmed > (best ?? 0) { best = confirmed }
        }
        return best
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

    /// Today's target, scaled to your fitness. Around your usual training-day
    /// strain (U): high recovery aims up to 20 points above it (room to
    /// progress), moderate recovery up to U, low recovery well below.
    ///
    /// As you get fitter, the same workout costs less heart rate and so less
    /// strain, while your usual days climb; both nudge you to do a little more.
    /// If you train less, U drops and so do the targets. Gradual progression
    /// keeps week-to-week load jumps modest (Gabbett, Br J Sports Med 2016).
    public static func targetStrain(forRecovery recovery: Int, usualTrainingStrain usual: Double?) -> ClosedRange<Double> {
        let u = min(85, max(35, usual ?? referenceUsualStrain))
        let low = max(10, u - 45)
        let moderate = max(25, u - 20)
        switch recovery {
        case ..<34: return low...moderate
        case 34..<67: return moderate...u
        default: return u...min(95, u + 20)
        }
    }
}

// MARK: - Steps

/// A step goal that grows with you: about 1,000 above your usual day, between
/// 6,000 and 12,000. Each extra 1,000 steps a day lowers risk until about
/// 8,000-10,000 for adults under 60 (Paluch et al., Lancet Public Health 2022),
/// and small, reachable goals are the ones people keep.
public enum StepGoal {
    public static let standard = 10_000.0

    /// - Parameter dailySteps: full days only (not today), ideally 28.
    public static func personal(dailySteps: [Double]) -> Double {
        let days = dailySteps.filter { $0 > 0 }.sorted()
        guard days.count >= 14 else { return standard }
        let median = days[days.count / 2]
        let goal = ((median + 1000) / 500).rounded() * 500
        return min(12_000, max(6_000, goal))
    }
}
