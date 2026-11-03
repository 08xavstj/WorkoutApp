import Foundation

/// Combines heart rate from several sources (AirPods Pro recorded by this app,
/// an Apple Watch, a Garmin synced through its app...) into one per-minute
/// series, so strain never counts a minute twice and the better sensor wins
/// where two overlap. Sources are never averaged together: averaging a good
/// reading with a bad one gives a bad one.
///
/// Which sensor is "better" depends on what you're doing:
///
/// - **Lifting:** an ear sensor beats a wrist sensor. Wrist optical sensors
///   lose the signal when the wrist flexes and the grip tightens: against a
///   chest strap, a wrist device read 23 ± 32 bpm off during weight lifting,
///   versus 2-5 bpm while walking or cycling (Spierer et al., J Med Eng
///   Technol 2015;39:264-271). An earbud and a wristwatch compared against a
///   chest strap through aerobic and resistance training found the wrist
///   device least accurate in resistance exercise (Bunn et al., Int J Exerc
///   Sci 2019;12(4):374-384; abstract only, full text not re-verified).
/// - **Cardio:** wrist sensors are accurate during steady walking and running
///   (mean error 3-6 % across six devices; Stahl et al., BMJ Open Sport Exerc
///   Med 2016;2:e000106), so neither placement is favoured; the source whose
///   series is steadier over the surrounding 5 minutes wins, since optical
///   dropouts show up as minute-to-minute jumps rather than as a steady offset.
///
/// The thresholds (15 bpm for 3 minutes to flag a disagreement; 5 bpm
/// agreement or a clean run with no 20 bpm jump to trust a peak) are app
/// choices sized from those error figures, not published cut-offs.
public enum HeartRateMerge {
    public enum Placement: String, Sendable, Equatable {
        /// In-ear (AirPods) or whatever this app recorded live (AirPods, chest strap).
        case ear
        /// Apple Watch, Garmin and other watches.
        case wrist
    }

    /// One source's readings, as Apple Health labels them ("AirPods Pro (Tensile)",
    /// "Apple Watch", "Garmin Connect"...). Readings can be at any rate; they're
    /// averaged per minute before merging.
    public struct Source: Sendable, Equatable {
        public var name: String
        public var samples: [HeartRateSample]
        /// True when this app recorded the readings in a live workout session
        /// (AirPods Pro or a Bluetooth strap), whatever the device is called.
        public var isOwnRecording: Bool

        public init(name: String, samples: [HeartRateSample], isOwnRecording: Bool = false) {
            self.name = name
            self.samples = samples
            self.isOwnRecording = isOwnRecording
        }

        public var placement: Placement {
            if isOwnRecording || name.range(of: "AirPods", options: .caseInsensitive) != nil { return .ear }
            return .wrist
        }
    }

    /// A stretch where two sources read far apart. The preferred source was
    /// kept; this records what the other one said, for the workout detail and
    /// the source-bias readout.
    public struct Disagreement: Sendable, Equatable {
        public var start: Date
        /// End of the last disagreeing minute.
        public var end: Date
        public var minutes: Int
        /// The source whose readings were used for these minutes.
        public var preferredSource: String
        public var otherSource: String
        /// Mean of (other − preferred) over the window, bpm. Negative means the
        /// other source read lower.
        public var meanDifference: Double

        public init(start: Date, end: Date, minutes: Int, preferredSource: String, otherSource: String, meanDifference: Double) {
            self.start = start
            self.end = end
            self.minutes = minutes
            self.preferredSource = preferredSource
            self.otherSource = otherSource
            self.meanDifference = meanDifference
        }

        public var lowerSource: String { meanDifference < 0 ? otherSource : preferredSource }
        public var higherSource: String { meanDifference < 0 ? preferredSource : otherSource }
    }

    public struct Result: Sendable, Equatable {
        /// One reading per minute (dated at the start of the minute), sorted.
        public var samples: [HeartRateSample]
        /// Which source each merged minute came from, keyed by minute start.
        public var chosenSource: [Date: String]
        public var disagreements: [Disagreement]
        /// Sources that contributed at least one minute, most minutes first.
        public var sourceNames: [String]

        public init(samples: [HeartRateSample], chosenSource: [Date: String], disagreements: [Disagreement], sourceNames: [String]) {
            self.samples = samples
            self.chosenSource = chosenSource
            self.disagreements = disagreements
            self.sourceNames = sourceNames
        }

        public static let empty = Result(samples: [], chosenSource: [:], disagreements: [], sourceNames: [])

        /// Minutes that came from each source, most first.
        public var minutesBySource: [(name: String, minutes: Int)] {
            var counts: [String: Int] = [:]
            for name in chosenSource.values { counts[name, default: 0] += 1 }
            return sourceNames.map { (name: $0, minutes: counts[$0] ?? 0) }
        }
    }

    /// Two sources more than this far apart count as disagreeing (app choice;
    /// wrist error during lifting averaged 23 bpm in Spierer 2015).
    public static let disagreementThresholdBPM = 15.0
    /// A disagreement has to last this many minutes to be recorded, so one
    /// bad reading isn't reported.
    public static let disagreementMinimumMinutes = 3
    /// Minutes either side of a minute that the steadiness check looks at (5 in all).
    public static let steadinessHalfWindow = 2
    /// Two sources this close in a minute confirm each other's peak.
    public static let peakAgreementBPM = 5.0
    /// A single source's peak counts only when the minutes either side of it
    /// don't jump by more than this (a cadence lock or a dropout does).
    public static let peakCleanRunJumpBPM = 20.0

    /// Merges `sources` minute by minute. `liftingWindows` are logged gym
    /// sessions and external strength workouts, where ear sensors are preferred.
    /// O(n log n) in the number of readings.
    public static func merge(sources: [Source], liftingWindows: [DateInterval]) -> Result {
        let series = sources.map { HeartRateComparison.perMinute($0.samples) }
        guard series.contains(where: { !$0.isEmpty }) else { return .empty }
        let coverage = series.map(\.count)
        var minuteSet = Set<Int>()
        for minutes in series { minuteSet.formUnion(minutes.keys) }
        let minutes = minuteSet.sorted()

        let lifting = mergedMinuteRanges(liftingWindows)
        var liftingIndex = 0

        var merged: [HeartRateSample] = []
        merged.reserveCapacity(minutes.count)
        var chosen: [Date: String] = [:]
        var chosenCounts = Array(repeating: 0, count: sources.count)
        var runs: [PairKey: Run] = [:]
        var disagreements: [Disagreement] = []

        for minute in minutes {
            while liftingIndex < lifting.count, lifting[liftingIndex].upperBound < minute { liftingIndex += 1 }
            let isLifting = liftingIndex < lifting.count && lifting[liftingIndex].contains(minute)

            var candidates: [Int] = []
            for index in series.indices where series[index][minute] != nil { candidates.append(index) }
            guard let pick = choose(candidates, minute: minute, lifting: isLifting, sources: sources, series: series, coverage: coverage) else { continue }
            let value = series[pick][minute]!
            let date = Date(timeIntervalSince1970: Double(minute) * 60)
            merged.append(HeartRateSample(date: date, bpm: value))
            chosen[date] = sources[pick].name
            chosenCounts[pick] += 1

            // Disagreements between the chosen source and every other one present.
            for other in candidates where other != pick {
                let key = PairKey(first: min(pick, other), second: max(pick, other))
                let difference = series[key.second][minute]! - series[key.first][minute]!
                if abs(difference) > disagreementThresholdBPM {
                    if var run = runs[key], minute - run.lastMinute <= 2 {
                        run.extend(minute: minute, difference: difference, chosen: pick, key: key)
                        runs[key] = run
                    } else {
                        if let run = runs[key] { close(run, key: key, sources: sources, into: &disagreements) }
                        var run = Run(firstMinute: minute)
                        run.extend(minute: minute, difference: difference, chosen: pick, key: key)
                        runs[key] = run
                    }
                } else if let run = runs[key] {
                    close(run, key: key, sources: sources, into: &disagreements)
                    runs[key] = nil
                }
            }
        }
        for (key, run) in runs { close(run, key: key, sources: sources, into: &disagreements) }
        disagreements.sort { $0.start < $1.start }

        let names = sources.indices
            .filter { chosenCounts[$0] > 0 }
            .sorted { chosenCounts[$0] == chosenCounts[$1] ? $0 < $1 : chosenCounts[$0] > chosenCounts[$1] }
            .map { sources[$0].name }
        return Result(samples: merged, chosenSource: chosen, disagreements: disagreements, sourceNames: names)
    }

    /// The merged minutes inside `windows` whose peak can be trusted for
    /// learning max heart rate: another source agrees within 5 bpm that
    /// minute, or the chosen source's run through the minute has no jump
    /// over 20 bpm (the 3 minutes around it). Feed the result to
    /// `ObservedMaxHeartRate.peak`, which keeps its own sustained-run rule.
    public static func peakSupport(_ result: Result, sources: [Source], windows: [DateInterval]) -> [HeartRateSample] {
        guard !windows.isEmpty, !result.samples.isEmpty else { return [] }
        let series = sources.map { HeartRateComparison.perMinute($0.samples) }
        let indexByName = Dictionary(sources.enumerated().map { ($0.element.name, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let ranges = mergedMinuteRanges(windows)
        var rangeIndex = 0
        var supported: [HeartRateSample] = []
        for sample in result.samples {
            let minute = Int((sample.date.timeIntervalSince1970 / 60).rounded(.down))
            while rangeIndex < ranges.count, ranges[rangeIndex].upperBound < minute { rangeIndex += 1 }
            guard rangeIndex < ranges.count, ranges[rangeIndex].contains(minute) else { continue }
            guard let name = result.chosenSource[sample.date], let pick = indexByName[name] else { continue }
            let agreed = series.indices.contains { other in
                other != pick && series[other][minute].map { abs($0 - sample.bpm) <= peakAgreementBPM } == true
            }
            let clean: Bool = {
                guard let before = series[pick][minute - 1], let after = series[pick][minute + 1] else { return false }
                return abs(sample.bpm - before) <= peakCleanRunJumpBPM && abs(after - sample.bpm) <= peakCleanRunJumpBPM
            }()
            if agreed || clean { supported.append(sample) }
        }
        return supported
    }

    // MARK: - Choosing a source for one minute

    private static func choose(
        _ candidates: [Int], minute: Int, lifting: Bool,
        sources: [Source], series: [[Int: Double]], coverage: [Int]
    ) -> Int? {
        guard candidates.count > 1 else { return candidates.first }
        if lifting {
            let ears = candidates.filter { sources[$0].placement == .ear }
            if !ears.isEmpty {
                return ears.max { coverage[$0] == coverage[$1] ? $0 > $1 : coverage[$0] < coverage[$1] }
            }
        }
        // Cardio (or two wrist devices while lifting): the steadier series wins.
        var best: Int?
        var bestSteadiness = Double.infinity
        for index in candidates {
            let steadiness = self.steadiness(series[index], around: minute) ?? .infinity
            if best == nil || steadiness < bestSteadiness - 1e-9 {
                best = index
                bestSteadiness = steadiness
            } else if abs(steadiness - bestSteadiness) <= 1e-9, let current = best, prefer(index, over: current, sources: sources, coverage: coverage) {
                best = index
            }
        }
        return best
    }

    /// Tie-break: the wrist device with the longer coverage.
    private static func prefer(_ index: Int, over current: Int, sources: [Source], coverage: [Int]) -> Bool {
        let wristA = sources[index].placement == .wrist
        let wristB = sources[current].placement == .wrist
        if wristA != wristB { return wristA }
        return coverage[index] > coverage[current]
    }

    /// Mean absolute minute-to-minute change over the 5 minutes around `minute`
    /// in one source's series; nil when the source has no adjacent minutes there.
    static func steadiness(_ series: [Int: Double], around minute: Int) -> Double? {
        var total = 0.0
        var count = 0
        for from in (minute - steadinessHalfWindow)..<(minute + steadinessHalfWindow) {
            guard let a = series[from], let b = series[from + 1] else { continue }
            total += abs(b - a)
            count += 1
        }
        return count > 0 ? total / Double(count) : nil
    }

    // MARK: - Disagreement runs

    private struct PairKey: Hashable {
        var first: Int
        var second: Int
    }

    private struct Run {
        var firstMinute: Int
        var lastMinute: Int
        var minutes = 0
        var differenceSum = 0.0
        var chosenFirst = 0
        var chosenSecond = 0

        init(firstMinute: Int) {
            self.firstMinute = firstMinute
            self.lastMinute = firstMinute
        }

        mutating func extend(minute: Int, difference: Double, chosen: Int, key: PairKey) {
            lastMinute = minute
            minutes += 1
            differenceSum += difference
            if chosen == key.first { chosenFirst += 1 } else { chosenSecond += 1 }
        }
    }

    private static func close(_ run: Run, key: PairKey, sources: [Source], into disagreements: inout [Disagreement]) {
        guard run.minutes >= disagreementMinimumMinutes else { return }
        let preferredIsFirst = run.chosenFirst >= run.chosenSecond
        let mean = run.differenceSum / Double(run.minutes)
        disagreements.append(Disagreement(
            start: Date(timeIntervalSince1970: Double(run.firstMinute) * 60),
            end: Date(timeIntervalSince1970: Double(run.lastMinute + 1) * 60),
            minutes: run.minutes,
            preferredSource: sources[preferredIsFirst ? key.first : key.second].name,
            otherSource: sources[preferredIsFirst ? key.second : key.first].name,
            meanDifference: preferredIsFirst ? mean : -mean
        ))
    }

    // MARK: - Windows as minute ranges

    /// Windows as sorted, non-overlapping closed ranges of minute indices.
    static func mergedMinuteRanges(_ windows: [DateInterval]) -> [ClosedRange<Int>] {
        let ranges = windows
            .map { window -> ClosedRange<Int> in
                let start = Int((window.start.timeIntervalSince1970 / 60).rounded(.down))
                let end = Int((window.end.timeIntervalSince1970 / 60).rounded(.down))
                return start...max(start, end)
            }
            .sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Int>] = []
        for range in ranges {
            if let last = merged.last, range.lowerBound <= last.upperBound + 1 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
