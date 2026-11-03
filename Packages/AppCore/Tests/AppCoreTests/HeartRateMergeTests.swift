import Foundation
import Testing
@testable import AppCore

struct HeartRateMergeTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let airPods = "AirPods Pro (Tensile)"
    let watch = "Apple Watch"

    /// One reading per minute; nil leaves that minute out.
    func minutes(_ values: [Double?], offset: Int = 0) -> [HeartRateSample] {
        values.enumerated().compactMap { index, value in
            value.map { HeartRateSample(date: start.addingTimeInterval(Double(index + offset) * 60), bpm: $0) }
        }
    }

    func minute(_ index: Int) -> Date { start.addingTimeInterval(Double(index) * 60) }

    func window(_ from: Int, _ to: Int) -> DateInterval {
        DateInterval(start: minute(from), end: minute(to))
    }

    @Test func singleSourcePassesThrough() {
        let source = HeartRateMerge.Source(name: watch, samples: minutes([120, 125, 130]))
        let result = HeartRateMerge.merge(sources: [source], liftingWindows: [])
        #expect(result.samples.map(\.bpm) == [120, 125, 130])
        #expect(result.chosenSource[minute(1)] == watch)
        #expect(result.disagreements.isEmpty)
        #expect(result.sourceNames == [watch])
    }

    @Test func noSourcesGivesEmpty() {
        #expect(HeartRateMerge.merge(sources: [], liftingWindows: []) == .empty)
    }

    @Test func theOtherSourceFillsGaps() {
        // AirPods drop out for minutes 5-7 during a lift; the watch fills them.
        let ear = HeartRateMerge.Source(name: airPods, samples: minutes([140, 140, 140, 140, 140, nil, nil, nil, 140, 140]))
        let wrist = HeartRateMerge.Source(name: watch, samples: minutes([Double?](repeating: 130, count: 10)))
        let result = HeartRateMerge.merge(sources: [ear, wrist], liftingWindows: [window(0, 10)])
        #expect(result.samples.count == 10)
        #expect(result.samples.map(\.bpm) == [140, 140, 140, 140, 140, 130, 130, 130, 140, 140])
        #expect(result.chosenSource[minute(6)] == watch)
        #expect(result.chosenSource[minute(1)] == airPods)
        #expect(result.sourceNames == [airPods, watch])
        #expect(result.minutesBySource.map(\.minutes) == [7, 3])
    }

    @Test func liftingPrefersEarOverWrist() {
        let ear = HeartRateMerge.Source(name: airPods, samples: minutes([150, 152, 151, 153]))
        let wrist = HeartRateMerge.Source(name: watch, samples: minutes([150, 150, 150, 150]))
        let result = HeartRateMerge.merge(sources: [ear, wrist], liftingWindows: [window(0, 4)])
        #expect(result.samples.map(\.bpm) == [150, 152, 151, 153])
        #expect(result.chosenSource.values.allSatisfy { $0 == airPods })
    }

    @Test func ownRecordingCountsAsEarWhateverItsName() {
        let strap = HeartRateMerge.Source(name: "Polar H10 (Tensile)", samples: minutes([150, 152, 151, 153]), isOwnRecording: true)
        #expect(strap.placement == .ear)
        #expect(HeartRateMerge.Source(name: "Garmin Connect", samples: []).placement == .wrist)
        #expect(HeartRateMerge.Source(name: "AirPods Pro 3 (Health)", samples: []).placement == .ear)
    }

    @Test func cardioPrefersTheSteadierSeries() {
        let steady = HeartRateMerge.Source(name: airPods, samples: minutes([120, 121, 122, 123, 124, 125, 126, 127]))
        let jumpy = HeartRateMerge.Source(name: watch, samples: minutes([120, 135, 118, 133, 120, 136, 119, 134]))
        let result = HeartRateMerge.merge(sources: [steady, jumpy], liftingWindows: [])
        #expect(result.samples.map(\.bpm) == steady.samples.map(\.bpm))
        #expect(result.disagreements.isEmpty)
    }

    @Test func cardioTieGoesToTheWristDeviceWithLongerCoverage() {
        let ear = HeartRateMerge.Source(name: airPods, samples: minutes([Double?](repeating: 140, count: 5)))
        let wrist = HeartRateMerge.Source(name: watch, samples: minutes([Double?](repeating: 130, count: 8)))
        let result = HeartRateMerge.merge(sources: [ear, wrist], liftingWindows: [])
        #expect(result.samples.map(\.bpm) == [Double](repeating: 130, count: 8))
    }

    @Test func valuesAreNeverAveraged() {
        let ear = HeartRateMerge.Source(name: airPods, samples: minutes([150, 150, 150]))
        let wrist = HeartRateMerge.Source(name: watch, samples: minutes([130, 130, 130]))
        let result = HeartRateMerge.merge(sources: [ear, wrist], liftingWindows: [window(0, 3)])
        for sample in result.samples {
            #expect(sample.bpm == 150 || sample.bpm == 130)
        }
    }

    @Test func threeMinutesFifteenApartIsADisagreement() throws {
        let ear = HeartRateMerge.Source(name: airPods, samples: minutes([150, 152, 151, 153, 150, 152]))
        let wrist = HeartRateMerge.Source(name: watch, samples: minutes([150, 135, 133, 135, 150, 152]))
        let result = HeartRateMerge.merge(sources: [ear, wrist], liftingWindows: [window(0, 6)])
        let disagreement = try #require(result.disagreements.first)
        #expect(result.disagreements.count == 1)
        #expect(disagreement.preferredSource == airPods)
        #expect(disagreement.otherSource == watch)
        #expect(disagreement.lowerSource == watch)
        #expect(disagreement.minutes == 3)
        #expect(disagreement.start == minute(1))
        #expect(disagreement.end == minute(4))
        #expect(abs(disagreement.meanDifference - (-53.0 / 3)) < 0.001)
    }

    @Test func twoMinutesApartIsNotADisagreement() {
        let ear = HeartRateMerge.Source(name: airPods, samples: minutes([150, 152, 151, 153, 150]))
        let wrist = HeartRateMerge.Source(name: watch, samples: minutes([150, 135, 133, 153, 150]))
        let result = HeartRateMerge.merge(sources: [ear, wrist], liftingWindows: [window(0, 5)])
        #expect(result.disagreements.isEmpty)
    }

    @Test func irregularSamplingIsAlignedByMinute() {
        // AirPods every 5 s, the watch once a minute.
        let fast = (0..<36).map { HeartRateSample(date: start.addingTimeInterval(Double($0) * 5), bpm: 140) }
        let ear = HeartRateMerge.Source(name: airPods, samples: fast)
        let wrist = HeartRateMerge.Source(name: watch, samples: minutes([130, 130, 130]))
        let result = HeartRateMerge.merge(sources: [ear, wrist], liftingWindows: [window(0, 3)])
        #expect(result.samples.count == 3)
        #expect(result.samples.map(\.bpm) == [140, 140, 140])
    }

    @Test func peakIsSupportedWhenTwoSourcesAgree() {
        let ear = HeartRateMerge.Source(name: airPods, samples: minutes([180, 181, 182, 183, 184]))
        let wrist = HeartRateMerge.Source(name: watch, samples: minutes([179, 182, 181, 185, 183]))
        let windows = [window(0, 5)]
        let result = HeartRateMerge.merge(sources: [ear, wrist], liftingWindows: windows)
        let supported = HeartRateMerge.peakSupport(result, sources: [ear, wrist], windows: windows)
        #expect(supported.count == 5)
        // The best 3-minute run within 5 bpm of its first value is 182-184; its low is 182.
        #expect(ObservedMaxHeartRate.peak(supported) == 182)
    }

    @Test func singleSourceSpikeIsNotSupported() {
        let wrist = HeartRateMerge.Source(name: watch, samples: minutes([160, 190, 162, 163, 164]))
        let windows = [window(0, 5)]
        let result = HeartRateMerge.merge(sources: [wrist], liftingWindows: [])
        let supported = HeartRateMerge.peakSupport(result, sources: [wrist], windows: windows)
        // Only minute 3 sits between two minutes within 20 bpm of it.
        #expect(supported.map(\.bpm) == [163])
    }

    @Test func singleSourceCleanRunIsSupported() {
        let wrist = HeartRateMerge.Source(name: watch, samples: minutes([170, 175, 178, 180, 181, 179, 176]))
        let windows = [window(0, 7)]
        let result = HeartRateMerge.merge(sources: [wrist], liftingWindows: [])
        let supported = HeartRateMerge.peakSupport(result, sources: [wrist], windows: windows)
        #expect(supported.map(\.bpm) == [175, 178, 180, 181, 179])
        // Best sustained run: 180, 181, 179 (all within 5 bpm of 180); its low is 179.
        #expect(ObservedMaxHeartRate.peak(supported) == 179)
    }

    @Test func peakSupportIgnoresMinutesOutsideWorkouts() {
        let wrist = HeartRateMerge.Source(name: watch, samples: minutes([170, 175, 178, 180, 181, 179, 176]))
        let result = HeartRateMerge.merge(sources: [wrist], liftingWindows: [])
        #expect(HeartRateMerge.peakSupport(result, sources: [wrist], windows: []).isEmpty)
        let late = HeartRateMerge.peakSupport(result, sources: [wrist], windows: [window(4, 7)])
        #expect(late.map(\.bpm) == [181, 179])
    }

    @Test func windowsMergeIntoMinuteRanges() {
        let ranges = HeartRateMerge.mergedMinuteRanges([window(5, 10), window(0, 3), window(9, 12)])
        let base = Int(start.timeIntervalSince1970 / 60)
        #expect(ranges == [(base + 0)...(base + 3), (base + 5)...(base + 12)])
    }

    @Test func steadinessIsTheMeanAbsoluteJump() {
        let series: [Int: Double] = [0: 100, 1: 110, 2: 105, 3: 105, 4: 120]
        #expect(HeartRateMerge.steadiness(series, around: 2) == 7.5)
        #expect(HeartRateMerge.steadiness([7: 100], around: 7) == nil)
    }
}
