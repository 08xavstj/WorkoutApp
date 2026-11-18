import Foundation
import Testing
@testable import AppCore

struct IntervalProgressTests {
    let session = IntervalSession.fourByFour(.bike)

    @Test func walksThroughTheSteps() throws {
        // 10 min warm-up, then 4 min hard.
        let start = try #require(session.progress(at: 0))
        #expect(start.index == 0)
        #expect(start.step.phase == .warmUp)
        #expect(start.remaining == 600)
        let hard = try #require(session.progress(at: 610))
        #expect(hard.step.phase == .work)
        #expect(hard.step.title(rounds: session.rounds) == "Hard 1 of 4")
        #expect(hard.elapsedInStep == 10)
        #expect(hard.remaining == 230)
        #expect(hard.next?.phase == .recovery)
        #expect(abs(hard.fractionLeft - 230.0 / 240) < 0.0001)
    }

    @Test func isOverAfterTheCoolDown() {
        #expect(session.progress(at: Double(session.totalSeconds)) == nil)
        #expect(session.progress(at: Double(session.totalSeconds) - 1)?.step.phase == .coolDown)
        #expect(session.progress(at: Double(session.totalSeconds) - 1)?.next == nil)
    }

    @Test func skippingLandsOnTheNextStepsStart() throws {
        let skip = try #require(session.skipSeconds(at: 100))
        #expect(skip == 500)
        #expect(session.progress(at: 100 + skip)?.index == 1)
        #expect(session.startOffset(ofStep: 2) == 840)
        #expect(session.skipSeconds(at: Double(session.totalSeconds) + 5) == nil)
    }

    @Test func matchesTheSessionsOwnStepLookup() {
        for second in stride(from: 0.0, to: Double(session.totalSeconds), by: 37) {
            #expect(session.progress(at: second)?.step == session.step(at: second)?.step)
        }
    }
}

struct CardioZoneTrackerRetargetTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    /// Zones start at 120, 133, 146, 159, 172; easy is 107–133.
    let scheme = HeartRateZoneScheme.reserve(resting: 55, maximum: 185)

    func feed(_ tracker: inout CardioZoneTracker, from: Double, to: Double, bpm: Double) -> [CardioZoneTracker.Alert] {
        var alerts: [CardioZoneTracker.Alert] = []
        var second = from
        while second <= to {
            if let alert = tracker.reading(bpm: bpm, at: start.addingTimeInterval(second)) { alerts.append(alert) }
            second += 5
        }
        return alerts
    }

    @Test func keepsZoneTimeAcrossABandChange() {
        var tracker = CardioZoneTracker(scheme: scheme, target: .easy)
        _ = feed(&tracker, from: 0, to: 300, bpm: 125)
        let before = tracker.zoneSeconds
        let hard = IntervalSession.workBand.heartRateBand(in: scheme)
        tracker.retarget(hard, at: start.addingTimeInterval(302))
        #expect(tracker.band == hard)
        #expect(tracker.state == .settling)
        #expect(tracker.zoneSeconds[0] >= before[0])
        _ = feed(&tracker, from: 305, to: 600, bpm: 165)
        #expect(tracker.zoneSeconds[3] > 250)
        // Time in the band counted against the easy band first, then the hard one.
        #expect(tracker.bandSeconds > 550)
    }

    @Test func staysQuietWhileHeartRateCatchesUp() {
        var tracker = CardioZoneTracker(scheme: scheme, target: .easy)
        _ = feed(&tracker, from: 0, to: 120, bpm: 125)
        // Into the recovery minutes with heart rate still high: no tap in the first minute.
        tracker.retarget(scheme.easyBand, at: start.addingTimeInterval(120))
        let early = feed(&tracker, from: 125, to: 175, bpm: 165)
        #expect(early.isEmpty)
        // Still too hard after the quiet minute: one "ease off".
        let later = feed(&tracker, from: 180, to: 240, bpm: 165)
        #expect(later == [.above])
    }

    @Test func noBandMeansNoTaps() {
        var tracker = CardioZoneTracker(scheme: scheme, target: .easy)
        tracker.retarget(nil, at: start, quiet: 0)
        #expect(tracker.state == .off)
        #expect(feed(&tracker, from: 0, to: 120, bpm: 180).isEmpty)
    }
}
