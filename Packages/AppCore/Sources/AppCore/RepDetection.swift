import Foundation

/// Rep counting and bar-speed loss from the Apple Watch's vertical
/// acceleration during a set (lifting-features.md, Pick 8). Experimental,
/// off by default, barbell squats and deadlifts only.
///
/// Evidence (docs/research/lifting-features.md §3.8):
/// - Wrist Apple Watch mean velocity correlated r 0.95–0.97 with motion
///   capture in squats; a barbell-mounted sensor was better (Achermann B, et
///   al. Velocity-based strength training: the validity and personal
///   monitoring of barbell velocity with the Apple Watch. Sports
///   2023;11(7):125) [E18].
/// - A smartwatch app counted squat and deadlift reps accurately but bench
///   reps poorly, and its 1RM prediction failed (Huber C, Lüthy S, Lorenzetti
///   S. Validation of a smartwatch-based workout analysis application in
///   exercise recognition, repetition count and prediction of 1RM in the
///   strength training-specific setting. Sports 2021;9(9):118, n = 30) [E19].
///   So: squat and deadlift only (`supports(exerciseID:)`), and no 1RM.
/// - Stopping a set at about 20–25 % velocity loss gave more strength than
///   larger losses (Hickmott LM, Chilibeck PD, Shaw KA, Butcher SJ. The effect
///   of load and volume autoregulation on muscular strength and hypertrophy: a
///   systematic review and meta-analysis. Sports Med Open 2022;8:9) [E2].
///   Velocity-based training overall is a wash to slightly positive against
///   percentage loading (Liao K-F, et al. PLoS ONE 2021;16:e0259790 [E20];
///   Zhang M, et al. Int J Sports Med 2022, SMD 0.26 [E21]). That outcome
///   evidence is for bar-mounted sensors in athletes, so the "slowing" hint is
///   a cross-check for the lifter's own effort rating, never a replacement.
///
/// The signal-processing settings below (filter lengths, minimum speed and
/// travel, the 8 s gap) are engineering choices tuned on synthetic squat and
/// deadlift signals in the tests, not values from a study.
///
/// This file has no dependencies on the rest of AppCore, so the Watch app can
/// compile it on its own.
public enum RepDetection {
    /// Reps needed before a count is shown or the hint can fire: false counts
    /// and taps are worse than none (lifting-features.md §3.8, risks).
    public static let minimumRepsToShow = 3
    /// Velocity loss from the fastest early rep at which the Watch taps once:
    /// the low end of the 20–25 % band where Hickmott 2022 [E2] found stopping
    /// a set gave more strength than going further. Reading it as "about 1–2
    /// reps left" is approximate and not re-verified here, so the UI says
    /// "about".
    public static let slowingLoss = 0.20
    /// The rep before the latest must already be at least this much slower, so
    /// one odd rep can't fire the tap (engineering choice: false taps are worse
    /// than none).
    public static let slowingTrendLoss = 0.10

    // Engineering choices, tuned on synthetic signals (see the type comment).
    /// Half-width of the smoothing window on acceleration, in seconds (5
    /// samples at 50 Hz).
    static let smoothingSeconds = 0.04
    /// Half-width of the moving average taken off the integrated velocity to
    /// cancel drift before finding the lifting phases, in seconds.
    static let driftWindowSeconds = 1.5
    /// A lifting phase must reach this upward speed, m/s.
    static let minimumPeakVelocity = 0.15
    /// …and move the wrist up at least this far, m (a squat or deadlift moves
    /// it about 0.4–0.6 m; lifting the bar out of the rack about 0.05 m).
    static let minimumTravel = 0.20
    /// The rep's speed is the mean over the part above this fraction of its
    /// peak, so the slow tails at the bottom and at lockout don't dominate.
    static let plateauFraction = 0.2
    /// Allowed length of that part, s.
    static let plateauSeconds = 0.15...4.0
    /// Reps more than this far apart belong to different bouts (e.g. raising
    /// the wrist to look at the Watch before the set); only the longest bout
    /// counts.
    static let maximumGapSeconds = 8.0
    /// m/s² per g (CoreMotion reports acceleration in g).
    static let standardGravity = 9.80665

    /// One lifting (concentric) phase.
    public struct Rep: Equatable, Sendable {
        /// Seconds from the first sample to the start of the measured part.
        public var start: Double
        /// Length of the part above `plateauFraction` of peak speed, s.
        public var duration: Double
        public var peakVelocity: Double
        /// Mean upward speed over that part, m/s. A rough wrist estimate: the
        /// app compares reps with each other and doesn't show this number.
        public var meanVelocity: Double
        /// Upward travel of the wrist, m.
        public var travel: Double

        public init(start: Double, duration: Double, peakVelocity: Double, meanVelocity: Double, travel: Double) {
            self.start = start
            self.duration = duration
            self.peakVelocity = peakVelocity
            self.meanVelocity = meanVelocity
            self.travel = travel
        }
    }

    public struct Analysis: Equatable, Sendable {
        public var reps: [Rep]
        /// The faster of the first two reps' mean speed (the first rep of a
        /// deadlift from the floor is often not the fastest).
        public var referenceVelocity: Double?
        /// Per rep, 0–1: how much slower it was than the reference.
        public var losses: [Double]

        public init(reps: [Rep]) {
            self.reps = reps
            guard let first = reps.first else {
                referenceVelocity = nil
                losses = []
                return
            }
            let reference = reps.count >= 2 ? max(first.meanVelocity, reps[1].meanVelocity) : first.meanVelocity
            referenceVelocity = reference
            losses = reps.map { reference > 0 ? max(0, 1 - $0.meanVelocity / reference) : 0 }
        }

        public static let empty = Analysis(reps: [])

        /// The count to show: nil until `minimumRepsToShow` reps.
        public var shownCount: Int? {
            reps.count >= RepDetection.minimumRepsToShow ? reps.count : nil
        }

        public var latestLoss: Double? { losses.last }

        /// True once the bar has slowed by `slowingLoss`, with the rep before
        /// already `slowingTrendLoss` slower, after at least 3 reps.
        public var isSlowing: Bool {
            guard reps.count >= RepDetection.minimumRepsToShow, losses.count >= 2 else { return false }
            return losses[losses.count - 1] >= RepDetection.slowingLoss
                && losses[losses.count - 2] >= RepDetection.slowingTrendLoss
        }

        /// Each rep's speed as a share of the reference, 0–1 (for the dots).
        public var relativeSpeeds: [Double] {
            losses.map { 1 - $0 }
        }
    }

    /// Upward acceleration in m/s² from CoreMotion's `userAcceleration` and
    /// `gravity` (both in g, device frame): the user acceleration projected on
    /// the gravity direction, sign flipped so up is positive. 0 when gravity is
    /// unknown.
    public static func verticalAcceleration(
        userX: Double, userY: Double, userZ: Double,
        gravityX: Double, gravityY: Double, gravityZ: Double
    ) -> Double {
        let length = (gravityX * gravityX + gravityY * gravityY + gravityZ * gravityZ).squareRoot()
        guard length > 0.5 else { return 0 }
        let along = (userX * gravityX + userY * gravityY + userZ * gravityZ) / length
        return -along * standardGravity
    }

    /// Finds the reps in a set from evenly spaced upward-acceleration samples
    /// (m/s², up positive). Call it again as samples arrive: a rep counts once
    /// its lifting phase has ended.
    ///
    /// 1. Smooth, and take off the mean (sensor bias).
    /// 2. Integrate to velocity and take off a ±1.5 s moving average (drift).
    /// 3. Each stretch of upward velocity is a candidate. Re-integrate it from
    ///    zero and remove the linear drift so it also ends at zero (the bar is
    ///    still at the bottom turnaround and at lockout).
    /// 4. Keep it if it is fast and long enough; measure its mean speed over
    ///    the part above 20 % of its peak.
    /// 5. Keep the longest bout of reps no more than 8 s apart.
    public static func analyze(_ samples: [Double], sampleRate: Double) -> Analysis {
        guard sampleRate > 0, samples.count >= Int(sampleRate) else { return .empty }
        let count = samples.count
        let dt = 1 / sampleRate

        let smoothed = movingAverage(samples, halfWidth: max(1, Int((smoothingSeconds * sampleRate).rounded())))
        let mean = smoothed.reduce(0, +) / Double(count)
        let acceleration = smoothed.map { $0 - mean }

        var velocity = [Double](repeating: 0, count: count)
        var running = 0.0
        for index in 0..<count {
            running += acceleration[index] * dt
            velocity[index] = running
        }
        let baseline = movingAverage(velocity, halfWidth: max(1, Int((driftWindowSeconds * sampleRate).rounded())))

        var reps: [Rep] = []
        var index = 0
        while index < count {
            if velocity[index] - baseline[index] <= 0 {
                index += 1
                continue
            }
            let start = index
            while index < count, velocity[index] - baseline[index] > 0 {
                index += 1
            }
            // Still going up at the end of the samples: wait for lockout.
            guard index < count else { break }
            if let rep = measure(acceleration, from: start, to: index, dt: dt) {
                reps.append(rep)
            }
        }
        return Analysis(reps: longestBout(reps))
    }

    /// One candidate lifting phase, `acceleration[from..<to]`, or nil if it
    /// isn't a rep.
    private static func measure(_ acceleration: [Double], from start: Int, to end: Int, dt: Double) -> Rep? {
        let length = end - start
        guard length > 1 else { return nil }
        var speed = [Double](repeating: 0, count: length)
        var running = 0.0
        for offset in 0..<length {
            running += acceleration[start + offset] * dt
            speed[offset] = running
        }
        let drift = speed[length - 1]
        for offset in 0..<length {
            speed[offset] -= drift * Double(offset + 1) / Double(length)
        }

        var peakIndex = 0
        for offset in 1..<length where speed[offset] > speed[peakIndex] {
            peakIndex = offset
        }
        let peak = speed[peakIndex]
        guard peak >= minimumPeakVelocity else { return nil }

        var travel = 0.0
        for value in speed where value > 0 {
            travel += value * dt
        }

        let threshold = plateauFraction * peak
        var low = peakIndex
        while low > 0, speed[low - 1] > threshold {
            low -= 1
        }
        var high = peakIndex
        while high < length - 1, speed[high + 1] > threshold {
            high += 1
        }
        let samplesAbove = high - low + 1
        let duration = Double(samplesAbove) * dt
        guard travel >= minimumTravel, plateauSeconds.contains(duration) else { return nil }

        var total = 0.0
        for offset in low...high {
            total += speed[offset]
        }
        return Rep(
            start: Double(start + low) * dt,
            duration: duration,
            peakVelocity: peak,
            meanVelocity: total / Double(samplesAbove),
            travel: travel
        )
    }

    /// The longest run of reps whose starts are at most `maximumGapSeconds`
    /// apart (the later one on a tie).
    private static func longestBout(_ reps: [Rep]) -> [Rep] {
        var best: [Rep] = []
        var current: [Rep] = []
        for rep in reps {
            if let last = current.last, rep.start - last.start > maximumGapSeconds {
                if current.count >= best.count { best = current }
                current = []
            }
            current.append(rep)
        }
        if current.count >= best.count { best = current }
        return best
    }

    /// Centered moving average; the window shrinks at the ends.
    private static func movingAverage(_ values: [Double], halfWidth: Int) -> [Double] {
        let count = values.count
        var prefix = [Double](repeating: 0, count: count + 1)
        for index in 0..<count {
            prefix[index + 1] = prefix[index] + values[index]
        }
        var result = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let low = max(0, index - halfWidth)
            let high = min(count, index + halfWidth + 1)
            result[index] = (prefix[high] - prefix[low]) / Double(high - low)
        }
        return result
    }
}
