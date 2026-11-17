import Foundation
import Testing
@testable import AppCore

struct CardioZoneTrackerTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    /// Resting 55, maximum 185: zones start at 120, 133, 146, 159, 172; easy is 107–133.
    let scheme = HeartRateZoneScheme.reserve(resting: 55, maximum: 185)

    /// A fixed pseudo-random stream (the same every run).
    struct Noise {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 33) / Double(1 << 31)
        }
    }

    /// Feeds readings every `step` seconds from `from` to `to` (seconds since the
    /// start), with heart rate from `bpm(seconds)`. Returns each tap with its time.
    func run(
        _ tracker: inout CardioZoneTracker, from: Double, to: Double, step: Double = 5,
        bpm: (Double) -> Double
    ) -> [(seconds: Double, alert: CardioZoneTracker.Alert)] {
        var alerts: [(Double, CardioZoneTracker.Alert)] = []
        var seconds = from
        while seconds <= to {
            if let alert = tracker.reading(bpm: bpm(seconds), at: start.addingTimeInterval(seconds)) {
                alerts.append((seconds, alert))
            }
            seconds += step
        }
        return alerts
    }

    // MARK: Time in zones

    @Test func countsTimeInTheZoneOfEachReading() {
        var tracker = CardioZoneTracker(scheme: scheme)
        // 10 minutes in zone 2 (140), then 5 minutes in zone 4 (165).
        _ = run(&tracker, from: 0, to: 595) { _ in 140 }
        _ = run(&tracker, from: 600, to: 900) { _ in 165 }
        tracker.end(at: start.addingTimeInterval(900))
        #expect(tracker.zoneSeconds == [0, 600, 0, 300, 0])
        #expect(tracker.measuredSeconds == 900)
        #expect(tracker.belowZoneSeconds == 0)
        #expect(tracker.maximumBpm == 165)
        #expect(tracker.currentZone == 4)
        // Time-weighted: (140 × 600 + 165 × 300) / 900.
        #expect(abs((tracker.averageBpm ?? 0) - 148.333) < 0.01)
        // No target: no state, no taps, no band time.
        #expect(tracker.state == .off)
        #expect(tracker.bandSeconds == 0)
    }

    @Test func liveZoneTimeMatchesThePhonesCountFromTheSameReadings() {
        var noise = Noise(state: 7)
        var tracker = CardioZoneTracker(scheme: scheme)
        var samples: [HeartRateSample] = []
        var seconds = 0.0
        while seconds < 1800 {
            let bpm = 110 + 60 * abs(sin(seconds / 240)) + (noise.next() - 0.5) * 6
            samples.append(HeartRateSample(date: start.addingTimeInterval(seconds), bpm: bpm))
            _ = tracker.reading(bpm: bpm, at: start.addingTimeInterval(seconds))
            seconds += noise.next() < 0.9 ? 5 : 20
        }
        let phone = scheme.minutes(samples)
        for zone in 0..<5 {
            #expect(abs(tracker.zoneSeconds[zone] / 60 - phone[zone]) < 0.0001)
        }
    }

    @Test func aPauseIsNotCounted() {
        var tracker = CardioZoneTracker(scheme: scheme, target: .easy)
        _ = run(&tracker, from: 0, to: 600) { _ in 125 }
        tracker.pause(at: start.addingTimeInterval(602))
        // Readings keep coming while paused (the watch still measures): ignored.
        let whilePaused = run(&tracker, from: 605, to: 895) { seconds in 125 - (seconds - 600) / 10 }
        #expect(whilePaused.isEmpty)
        tracker.resume(at: start.addingTimeInterval(900))
        #expect(tracker.state == .settling)
        // Heart rate climbs back from 95: under the band for a minute, no "below" tap.
        let after = run(&tracker, from: 900, to: 1500) { seconds in min(125, 95 + (seconds - 900) / 4) }
        tracker.end(at: start.addingTimeInterval(1500))
        #expect(after.map(\.alert) == [.inBand])
        // 602 s before the pause and 600 s after it; the 298 s paused are gone.
        #expect(abs(tracker.measuredSeconds - 1202) < 0.001)
        #expect(tracker.zoneSeconds.reduce(0, +) + tracker.belowZoneSeconds == tracker.measuredSeconds)
        // Pausing or resuming twice changes nothing.
        var again = tracker
        again.pause(at: start.addingTimeInterval(1600))
        again.resume(at: start.addingTimeInterval(1700))
        again.resume(at: start.addingTimeInterval(1800))
        #expect(again.measuredSeconds == tracker.measuredSeconds)
    }

    @Test func dropoutsCountForLittleOrNothing() {
        var tracker = CardioZoneTracker(scheme: scheme)
        _ = tracker.reading(bpm: 150, at: start)
        _ = tracker.reading(bpm: 150, at: start.addingTimeInterval(5))
        // The strap loses contact for 3 minutes: the last reading stands for 2 at most.
        _ = tracker.reading(bpm: 150, at: start.addingTimeInterval(185))
        #expect(tracker.zoneSeconds[2] == 125)
        // And for 11 minutes: nothing is counted.
        _ = tracker.reading(bpm: 150, at: start.addingTimeInterval(185 + 660))
        #expect(tracker.zoneSeconds[2] == 125)
        // The same reading again, an older one, and rubbish: ignored.
        _ = tracker.reading(bpm: 190, at: start.addingTimeInterval(185 + 660))
        _ = tracker.reading(bpm: 190, at: start)
        _ = tracker.reading(bpm: 0, at: start.addingTimeInterval(900))
        _ = tracker.reading(bpm: .nan, at: start.addingTimeInterval(901))
        #expect(tracker.maximumBpm == 150)
        #expect(tracker.currentBpm == 150)
    }

    @Test func schemeWithNoFloorPutsLowHeartRateInZoneOne() throws {
        let easy = HeartRateBand(lower: 107, upper: 133)
        let apple = try #require(HeartRateZoneScheme.appleHealth(floor: nil, boundaries: [137, 149, 160, 172], easyBand: easy))
        var noFloor = CardioZoneTracker(scheme: apple)
        var withFloor = CardioZoneTracker(scheme: scheme)
        for index in 0...12 {
            _ = noFloor.reading(bpm: 100, at: start.addingTimeInterval(Double(index) * 5))
            _ = withFloor.reading(bpm: 100, at: start.addingTimeInterval(Double(index) * 5))
        }
        #expect(noFloor.zoneSeconds[0] == 60)
        #expect(noFloor.belowZoneSeconds == 0)
        #expect(withFloor.zoneSeconds[0] == 0)
        #expect(withFloor.belowZoneSeconds == 60)
        #expect(withFloor.currentZone == nil)
    }

    // MARK: Target taps

    @Test func fortyMinuteEasyRunWithDrift() {
        var noise = Noise(state: 11)
        var tracker = CardioZoneTracker(scheme: scheme, target: .easy)
        #expect(tracker.band == HeartRateBand(lower: 107, upper: 133))
        #expect(tracker.state == .settling)
        // Warm-up from 92 bpm, settling near 122 after three minutes, then a
        // slow upward drift of 18 beats over the rest of the run (cardiac
        // drift at a steady pace), with ±2 beats of sensor noise.
        let alerts = run(&tracker, from: 0, to: 2400) { seconds in
            let warm = min(1, seconds / 180)
            let drift = max(0, seconds - 180) / 2220 * 18
            return 92 + 30 * warm + drift + (noise.next() - 0.5) * 4
        }
        tracker.end(at: start.addingTimeInterval(2400))
        // One tap on reaching the band, none for being under it while warming up.
        #expect(alerts.first?.alert == .inBand)
        #expect(!alerts.contains { $0.alert == .below })
        #expect((100...200).contains(alerts.first?.seconds ?? 0))
        // The drift crosses 133 around minute 26; once it holds there, "above"
        // taps, then repeats no more than every two minutes.
        let above = alerts.filter { $0.alert == .above }
        #expect(!above.isEmpty)
        #expect((1300...1900).contains(above.first?.seconds ?? 0))
        for (earlier, later) in zip(above, above.dropFirst()) {
            #expect(later.seconds - earlier.seconds >= CardioZoneTracker.remindSeconds)
        }
        // Never buzzing constantly: a 40-minute run at the top edge of its
        // band, noise and all, taps the wrist a handful of times.
        #expect(alerts.count <= 14)
        #expect(tracker.state == .above)
        // Most of the run was inside the band, and all of it was counted.
        #expect(abs(tracker.measuredSeconds - 2400) < 0.001)
        #expect(tracker.bandSeconds > 1300)
        #expect(tracker.bandSeconds < 2000)
    }

    @Test func hoveringAtTheEdgeDoesNotBuzz() {
        var noise = Noise(state: 3)
        var tracker = CardioZoneTracker(scheme: scheme, target: .easy)
        _ = run(&tracker, from: 0, to: 60) { _ in 125 }
        #expect(tracker.state == .inBand)
        // Ten minutes flickering either side of the 133 limit, reading by reading.
        let alerts = run(&tracker, from: 65, to: 665) { _ in 133 + (noise.next() - 0.5) * 6 }
        #expect(alerts.count <= 4)
        // A 15-second spike over the band (a kerb, a wave to a neighbour): nothing.
        var spike = CardioZoneTracker(scheme: scheme, target: .easy)
        _ = run(&spike, from: 0, to: 60) { _ in 125 }
        let spikeAlerts = run(&spike, from: 65, to: 300) { seconds in (100..<115).contains(seconds) ? 150 : 125 }
        #expect(spikeAlerts.isEmpty)
        #expect(spike.state == .inBand)
    }

    @Test func leavingAndReturningEachTapOnce() {
        var tracker = CardioZoneTracker(scheme: scheme, target: .easy)
        var alerts = run(&tracker, from: 0, to: 120) { _ in 120 }
        // In the band from the first reading; the tap comes after 10 s there.
        #expect(alerts.map(\.seconds) == [10])
        #expect(alerts.map(\.alert) == [.inBand])
        // Too hard from 125 s: tap once it has held for 20 s.
        alerts = run(&tracker, from: 125, to: 200) { _ in 150 }
        #expect(alerts.map(\.seconds) == [145])
        #expect(alerts.map(\.alert) == [.above])
        #expect(tracker.state == .above)
        // Back down from 205 s: tap after 10 s inside.
        alerts = run(&tracker, from: 205, to: 300) { _ in 125 }
        #expect(alerts.map(\.seconds) == [215])
        #expect(alerts.map(\.alert) == [.inBand])
        // Walking for a while, heart rate under the band: one tap, and no reminders.
        alerts = run(&tracker, from: 305, to: 400) { _ in 98 }
        #expect(alerts.map(\.seconds) == [325])
        #expect(alerts.map(\.alert) == [.below])
        var walking = tracker
        #expect(run(&walking, from: 405, to: 1000) { _ in 98 }.isEmpty)
        // Straight from under to over without settling inside: "above" after its own 20 s.
        alerts = run(&tracker, from: 405, to: 460) { _ in 150 }
        #expect(alerts.map(\.seconds) == [425])
        #expect(alerts.map(\.alert) == [.above])
        // Still over two minutes later: one reminder, then another two minutes on.
        alerts = run(&tracker, from: 465, to: 700) { _ in 150 }
        #expect(alerts.map(\.seconds) == [545, 665])
        #expect(alerts.allSatisfy { $0.alert == .above })
    }

    @Test func goingOutTooHardFromTheStartStillTaps() {
        var tracker = CardioZoneTracker(scheme: scheme, target: .easy)
        // Heart rate is over the band before it was ever inside it.
        let alerts = run(&tracker, from: 0, to: 60) { seconds in 100 + seconds * 3 }
        #expect(alerts.map(\.alert) == [.above])
    }

    @Test func intervalsAgainstAZoneFourTarget() {
        var noise = Noise(state: 5)
        var tracker = CardioZoneTracker(scheme: scheme, target: .zone(4))
        #expect(tracker.band == HeartRateBand(lower: 159, upper: 172))
        // 5 min warm-up, then 6 × (2 min hard, 2 min easy). Heart rate lags
        // the effort: it moves a fifth of the way to its target every 5 s.
        var bpm = 100.0
        let alerts = run(&tracker, from: 0, to: 300 + 6 * 240) { seconds in
            let target: Double
            if seconds < 300 {
                target = 125
            } else {
                target = Int((seconds - 300) / 120).isMultiple(of: 2) ? 166 : 128
            }
            bpm += (target - bpm) * 0.2
            return bpm + (noise.next() - 0.5) * 3
        }
        tracker.end(at: start.addingTimeInterval(300 + 6 * 240))
        // Each hard rep reaches the band once and each recovery leaves it once.
        #expect(alerts.filter { $0.alert == .inBand }.count == 6)
        #expect(alerts.filter { $0.alert == .below }.count == 6)
        #expect(!alerts.contains { $0.alert == .above })
        // No "below" during the warm-up: the band hadn't been reached yet.
        #expect(alerts.first?.alert == .inBand)
        #expect((alerts.first?.seconds ?? 0) > 300)
        // About 12 minutes of hard work, less the lag getting there.
        #expect((480...720).contains(tracker.bandSeconds))
        #expect(tracker.zoneSeconds[3] == tracker.bandSeconds)
    }

    @Test func aDropoutRestartsTheCount() {
        var tracker = CardioZoneTracker(scheme: scheme, target: .easy)
        _ = run(&tracker, from: 0, to: 60) { _ in 125 }
        // Over the band for 15 s, then no readings for 40 s, then over again:
        // the 20 s must be measured, so the count starts again after the gap.
        var alerts = run(&tracker, from: 65, to: 80) { _ in 150 }
        #expect(alerts.isEmpty)
        alerts = run(&tracker, from: 120, to: 135) { _ in 150 }
        #expect(alerts.isEmpty)
        alerts = run(&tracker, from: 140, to: 150) { _ in 150 }
        #expect(alerts.map(\.seconds) == [140])
    }

    // MARK: Targets

    @Test func targetsRoundTripThroughStorage() {
        for target in CardioTarget.all {
            #expect(CardioTarget(storage: target.storage) == target)
        }
        #expect(CardioTarget.all.count == 7)
        #expect(CardioTarget(storage: "") == .off)
        #expect(CardioTarget(storage: "z9") == .off)
        #expect(CardioTarget(storage: "zebra") == .off)
        #expect(CardioTarget.zone(2).band(in: scheme) == scheme.band(forZone: 2))
        #expect(CardioTarget.easy.band(in: scheme) == scheme.easyBand)
        #expect(CardioTarget.off.band(in: scheme) == nil)
        #expect(CardioTarget.zone(5).band(in: scheme)?.text == "172+")
    }

    @Test func everyActivityIsDescribed() {
        #expect(CardioActivity.allCases.count == 10)
        for activity in CardioActivity.allCases {
            #expect(!activity.title.isEmpty)
            #expect(!activity.systemImage.isEmpty)
        }
        #expect(CardioActivity.outdoorRun.movement == .onFoot)
        #expect(CardioActivity.treadmill.isOutdoor == false)
        #expect(CardioActivity.outdoorCycle.movement == .cycling)
        #expect(CardioActivity.indoorCycle.movement == .stationary)
        #expect(CardioActivity.other.isOutdoor == nil)
    }

    // MARK: Summary

    @Test func summaryOfAnEasyRun() {
        var tracker = CardioZoneTracker(scheme: scheme, target: .easy)
        _ = run(&tracker, from: 0, to: 1795) { seconds in seconds < 1500 ? 126 : 138 }
        tracker.end(at: start.addingTimeInterval(1800))
        let summary = CardioSummary(
            activity: .outdoorRun, target: .easy, tracker: tracker, activeSeconds: 1800,
            distanceMeters: 5020, averageBpm: 128, maximumBpm: 141, activeKilocalories: 402, saved: true
        )
        #expect(summary.zoneSeconds == [1500, 300, 0, 0, 0])
        #expect(summary.zoneMinutes == [25, 5, 0, 0, 0])
        #expect(summary.bandSeconds == 1500)
        #expect(abs((summary.bandShare ?? 0) - 1500.0 / 1800) < 0.0001)
        // HealthKit's heart-rate figures are shown when it has them.
        #expect(summary.averageBpm == 128)
        #expect(summary.maximumBpm == 141)
        // 1800 s over 5.02 km is 5:59 a kilometre; over 3.12 miles, 9:37 a mile.
        #expect(summary.paceOrSpeedText(miles: false) == "5:59 /km")
        #expect(summary.paceOrSpeedText(miles: true) == "9:37 /mi")
        #expect(CardioSummary.distanceText(meters: 5020, miles: false) == "5.02 km")
        #expect(CardioSummary.distanceText(meters: 5020, miles: true) == "3.12 mi")
        // Without HealthKit's figures the tracker's own stand in.
        let alone = CardioSummary(
            activity: .outdoorRun, target: .easy, tracker: tracker, activeSeconds: 1800,
            distanceMeters: nil, averageBpm: nil, maximumBpm: nil, activeKilocalories: nil, saved: false
        )
        #expect(alone.maximumBpm == 138)
        #expect(abs((alone.averageBpm ?? 0) - 128) < 0.001)
        #expect(alone.paceOrSpeedText(miles: false) == nil)
    }

    @Test func speedForARideAndNothingForAMachine() {
        let tracker = CardioZoneTracker(scheme: scheme)
        let ride = CardioSummary(
            activity: .outdoorCycle, target: .off, tracker: tracker, activeSeconds: 3600,
            distanceMeters: 24_640, averageBpm: nil, maximumBpm: nil, activeKilocalories: nil, saved: true
        )
        #expect(ride.paceOrSpeedText(miles: false) == "24.6 km/h")
        #expect(ride.paceOrSpeedText(miles: true) == "15.3 mph")
        #expect(ride.bandShare == nil)
        #expect(ride.target == .off)
        let row = CardioSummary(
            activity: .rower, target: .off, tracker: tracker, activeSeconds: 1200,
            distanceMeters: 4000, averageBpm: nil, maximumBpm: nil, activeKilocalories: nil, saved: true
        )
        #expect(row.paceOrSpeedText(miles: false) == nil)
        // The first few metres give no pace.
        #expect(CardioSummary.pace(seconds: 20, meters: 60, miles: false) == nil)
        #expect(CardioSummary.pace(seconds: 0, meters: 500, miles: false) == nil)
        #expect(CardioSummary.pace(seconds: 300, meters: 1000, miles: false) == 300)
        #expect(CardioSummary.paceText(299.6, miles: false) == "5:00 /km")
        #expect(CardioSummary.paceText(65, miles: true) == "1:05 /mi")
        #expect(CardioSummary.speedText(9.96, miles: false) == "10.0 km/h")
        #expect(CardioSummary.distanceText(meters: 0, miles: false) == "0.00 km")
    }
}
