import Foundation
import Testing
@testable import AppCore

/// Synthetic wrist signals: each rep lowers the bar `depth` metres in `eccentric`
/// seconds, optionally pauses at the bottom, lifts it in the given concentric
/// time, then pauses at the top. Position follows a half-cosine, so the true
/// mean concentric speed is `depth / concentric`. Noise and a constant bias
/// stand in for the Watch's accelerometer.
private struct SquatSignal {
    var concentric: [Double]
    var sampleRate = 50.0
    var depth = 0.5
    var eccentric = 1.2
    var bottomPause = 0.0
    var topPause = 1.0
    var lead = 1.5
    var noise = 0.0
    var bias = 0.0
    var seed: UInt64 = 1

    var samples: [Double] {
        var clean: [Double] = []
        func hold(_ seconds: Double) {
            clean.append(contentsOf: [Double](repeating: 0, count: Int((seconds * sampleRate).rounded())))
        }
        func move(_ seconds: Double, sign: Double) {
            let count = Int((seconds * sampleRate).rounded())
            let omega = Double.pi / seconds
            for index in 0..<count {
                let time = (Double(index) + 0.5) / sampleRate
                clean.append(sign * depth / 2 * omega * omega * cos(omega * time))
            }
        }
        hold(lead)
        for lift in concentric {
            move(eccentric, sign: -1)
            hold(bottomPause)
            move(lift, sign: 1)
            hold(topPause)
        }
        hold(lead)
        var random = TestNoise(seed: seed)
        return clean.map { $0 + bias + noise * random.gaussian() }
    }
}

/// Deterministic noise (64-bit LCG; sum of 12 uniforms ≈ N(0, 1)).
private struct TestNoise {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func uniform() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / 9007199254740992.0
    }

    mutating func gaussian() -> Double {
        var total = 0.0
        for _ in 0..<12 { total += uniform() }
        return total - 6
    }
}

struct RepDetectionTests {
    /// Squats getting slower rep by rep (true loss 0 → 36 %): every rep is
    /// counted and the loss rises past the 20 % hint.
    @Test(arguments: [UInt64(1), 7, 42])
    func countsSlowingSquatsAndFlagsTheLoss(seed: UInt64) {
        let signal = SquatSignal(concentric: [0.8, 0.85, 0.9, 1.0, 1.1, 1.25], noise: 0.3, bias: 0.15, seed: seed)
        let analysis = RepDetection.analyze(signal.samples, sampleRate: signal.sampleRate)
        #expect(analysis.reps.count == 6)
        #expect(analysis.shownCount == 6)
        let losses = analysis.losses
        #expect(losses.count == 6)
        #expect((losses.last ?? 0) >= 0.3)
        #expect((losses.last ?? 0) > losses[2])
        #expect(losses[2] < RepDetection.slowingLoss)
        #expect(analysis.isSlowing)
        // Mean speed is a rough proxy, but each rep should land near its true speed.
        for (rep, lift) in zip(analysis.reps, signal.concentric) {
            let truth = signal.depth / lift
            #expect(abs(rep.meanVelocity / truth - 1) < 0.25, "rep at \(rep.start)s: \(rep.meanVelocity) vs \(truth)")
            #expect(rep.travel > 0.3)
        }
    }

    /// Steady reps: counted, and no hint.
    @Test(arguments: [UInt64(1), 7, 42])
    func steadyRepsDoNotTap(seed: UInt64) {
        let signal = SquatSignal(concentric: Array(repeating: 0.8, count: 5), noise: 0.3, bias: 0.15, seed: seed)
        let analysis = RepDetection.analyze(signal.samples, sampleRate: signal.sampleRate)
        #expect(analysis.reps.count == 5)
        #expect(analysis.losses.allSatisfy { $0 < 0.1 })
        #expect(!analysis.isSlowing)
    }

    /// Deadlifts from the floor: short lockout, a pause on the floor, shorter travel.
    @Test func countsDeadlifts() {
        let signal = SquatSignal(concentric: [0.9, 1.0, 1.1, 1.3, 1.5], depth: 0.45, eccentric: 0.8,
                                 bottomPause: 0.6, topPause: 0.5, noise: 0.3, bias: 0.1)
        let analysis = RepDetection.analyze(signal.samples, sampleRate: signal.sampleRate)
        #expect(analysis.reps.count == 5)
        #expect(analysis.isSlowing)
    }

    /// Two reps are found but not shown, and can't fire the hint.
    @Test func twoRepsShowNoCount() {
        let signal = SquatSignal(concentric: [0.8, 0.9], noise: 0.3)
        let analysis = RepDetection.analyze(signal.samples, sampleRate: signal.sampleRate)
        #expect(analysis.reps.count == 2)
        #expect(analysis.shownCount == nil)
        #expect(!analysis.isSlowing)
    }

    /// Standing still with sensor noise and bias: nothing is counted.
    @Test(arguments: [UInt64(1), 7, 42])
    func noiseAloneCountsNothing(seed: UInt64) {
        let quiet = SquatSignal(concentric: [], lead: 15, noise: 0.3, bias: 0.1, seed: seed)
        #expect(RepDetection.analyze(quiet.samples, sampleRate: 50).reps.isEmpty)
        // Much noisier than a still wrist: at most a stray rep, never a shown count.
        let rough = SquatSignal(concentric: [], lead: 30, noise: 0.8, bias: 0.2, seed: seed)
        #expect(RepDetection.analyze(rough.samples, sampleRate: 50).shownCount == nil)
    }

    /// Raising the wrist to look at the Watch 12 s before the set isn't a rep.
    @Test func strayLiftBeforeTheSetIsIgnored() {
        let glance = SquatSignal(concentric: [0.6], depth: 0.35, eccentric: 0.5, topPause: 0.5, lead: 0.5, noise: 0.3, seed: 3)
        var random = TestNoise(seed: 9)
        let wait = (0..<600).map { _ in 0.3 * random.gaussian() }
        let set = SquatSignal(concentric: [0.8, 0.85, 0.9, 1.0], noise: 0.3, seed: 5)
        let analysis = RepDetection.analyze(glance.samples + wait + set.samples, sampleRate: 50)
        #expect(analysis.reps.count == 4)
        #expect((analysis.reps.first?.start ?? 0) > 12)
    }

    /// Live use: re-run as samples arrive. The count never goes down, a rep
    /// counts only after lockout, and the final count is right.
    @Test func liveCountOnlyGrows() {
        let samples = SquatSignal(concentric: [0.8, 0.85, 0.9, 1.0, 1.1], noise: 0.3, seed: 2).samples
        var previous = 0
        for end in stride(from: 50, through: samples.count, by: 25) {
            let count = RepDetection.analyze(Array(samples[..<end]), sampleRate: 50).reps.count
            #expect(count >= previous, "at sample \(end)")
            previous = count
        }
        #expect(previous == 5)
    }

    @Test func tooLittleDataIsEmpty() {
        #expect(RepDetection.analyze([0.1, 0.2, 0.3], sampleRate: 50) == .empty)
        #expect(RepDetection.analyze(Array(repeating: 0, count: 200), sampleRate: 0) == .empty)
        #expect(RepDetection.Analysis.empty.shownCount == nil)
        #expect(RepDetection.Analysis.empty.latestLoss == nil)
    }

    /// Losses are against the faster of the first two reps; the hint needs
    /// the rep before the latest to be slowing too.
    @Test func lossUsesTheFasterOfTheFirstTwoReps() {
        func rep(_ speed: Double) -> RepDetection.Rep {
            RepDetection.Rep(start: 0, duration: 1, peakVelocity: speed * 1.5, meanVelocity: speed, travel: 0.5)
        }
        let slowing = RepDetection.Analysis(reps: [rep(0.5), rep(0.6), rep(0.52), rep(0.45)])
        #expect(slowing.referenceVelocity == 0.6)
        #expect(abs(slowing.losses[0] - 1.0 / 6) < 1e-9)
        #expect(slowing.losses[1] == 0)
        #expect(abs(slowing.losses[3] - 0.25) < 1e-9)
        #expect(abs(slowing.relativeSpeeds[3] - 0.75) < 1e-9)
        #expect(slowing.isSlowing)

        // One slow rep after steady ones: no tap.
        let blip = RepDetection.Analysis(reps: [rep(0.5), rep(0.6), rep(0.58), rep(0.45)])
        #expect(!blip.isSlowing)
        // Two reps can't tap, however slow the second.
        #expect(!RepDetection.Analysis(reps: [rep(0.6), rep(0.3)]).isSlowing)
    }

    /// Up is positive whichever way the Watch is turned.
    @Test func verticalAccelerationFollowsGravity() {
        // Face up: gravity along −z; moving up pushes +z.
        let up = RepDetection.verticalAcceleration(userX: 0, userY: 0, userZ: 0.5, gravityX: 0, gravityY: 0, gravityZ: -1)
        #expect(abs(up - 0.5 * 9.80665) < 1e-9)
        // On its side: gravity along +x; moving up pushes −x.
        let side = RepDetection.verticalAcceleration(userX: -0.2, userY: 0.3, userZ: 0, gravityX: 1, gravityY: 0, gravityZ: 0)
        #expect(abs(side - 0.2 * 9.80665) < 1e-9)
        #expect(RepDetection.verticalAcceleration(userX: 1, userY: 1, userZ: 1, gravityX: 0, gravityY: 0, gravityZ: 0) == 0)
    }

    /// Barbell squats and deadlifts only (Huber 2021: bench counts poor).
    @Test func supportsBarbellSquatsAndDeadliftsOnly() {
        for id in ["Barbell_Squat", "Romanian_Deadlift", "Barbell_Deadlift", "Front_Barbell_Squat", "Sumo_Deadlift"] {
            #expect(RepDetection.supports(exerciseID: id), "\(id)")
        }
        for id in ["Barbell_Bench_Press_-_Medium_Grip", "Leg_Press", "Goblet_Squat", "One-Arm_Kettlebell_Swings",
                   "Stiff-Legged_Dumbbell_Deadlift", "Barbell_Lunge", "unknown"] {
            #expect(!RepDetection.supports(exerciseID: id), "\(id)")
        }
    }
}
