import Foundation

/// Heart rate variability from the phone camera: with the flashlight on and a
/// fingertip over the lens, each heartbeat pushes blood into the finger and
/// the picture gets slightly darker. Timing those pulses gives beat-to-beat
/// intervals and RMSSD, the HRV measure Garmin reports. A 1-minute camera
/// reading agreed closely with ECG rMSSD in Plews et al. (IJSPP 2017).
///
/// Steps: resample to an even rate, band-pass 0.7-3.5 Hz (42-210 bpm) with a
/// zero-phase Butterworth filter, find pulse peaks with a refractory period,
/// refine each peak between frames, drop implausible intervals (outside
/// 300-2000 ms or more than 20% from the local median), and compute RMSSD only
/// from neighbouring clean intervals.
public enum PPGAnalyzer {
    public struct Sample: Sendable, Equatable {
        /// Seconds since the start of the recording.
        public var time: Double
        /// Brightness of the frame (e.g. mean red channel, 0-1).
        public var value: Double

        public init(time: Double, value: Double) {
            self.time = time
            self.value = value
        }
    }

    public struct Result: Sendable, Equatable {
        /// RMSSD in milliseconds.
        public var rmssd: Double
        public var meanHeartRate: Double
        /// Clean beat-to-beat intervals used.
        public var cleanIntervals: Int
        public var totalIntervals: Int
        /// 0-100: share of clean intervals, scaled down for short recordings.
        public var quality: Int
        public var intervals: [Double]
    }

    public enum Failure: Error, Equatable, Sendable {
        case tooShort
        case notEnoughBeats(found: Int)
        case tooNoisy
    }

    /// Clean intervals needed for a reading.
    public static let minimumCleanIntervals = 40
    static let resampleRate = 60.0

    public static func analyze(_ samples: [Sample]) -> Swift.Result<Result, Failure> {
        let sorted = samples.sorted { $0.time < $1.time }
        guard let first = sorted.first, let last = sorted.last, last.time - first.time >= 20 else {
            return .failure(.tooShort)
        }
        let signal = resample(sorted, rate: resampleRate)
        let filtered = bandPass(signal, rate: resampleRate)
        // The picture darkens with each pulse, so pulses are minima: flip them to peaks.
        let pulses = filtered.map { -$0 }
        let peaks = findPeaks(pulses, rate: resampleRate)
        guard peaks.count >= 3 else { return .failure(.notEnoughBeats(found: peaks.count)) }

        let intervals = zip(peaks, peaks.dropFirst()).map { ($1 - $0) * 1000 }
        let clean = cleanFlags(intervals)
        let cleanCount = clean.filter { $0 }.count
        guard cleanCount >= minimumCleanIntervals else {
            return .failure(cleanCount < intervals.count / 2 ? .tooNoisy : .notEnoughBeats(found: cleanCount))
        }

        var squares: [Double] = []
        for index in 1..<intervals.count where clean[index] && clean[index - 1] {
            let difference = intervals[index] - intervals[index - 1]
            squares.append(difference * difference)
        }
        guard squares.count >= minimumCleanIntervals / 2 else { return .failure(.tooNoisy) }
        let rmssd = sqrt(squares.reduce(0, +) / Double(squares.count))
        let cleanIntervals = intervals.indices.filter { clean[$0] }.map { intervals[$0] }
        let meanInterval = cleanIntervals.reduce(0, +) / Double(cleanIntervals.count)
        let cleanShare = Double(cleanCount) / Double(intervals.count)
        let lengthFactor = min(1, (last.time - first.time) / 60)
        return .success(Result(
            rmssd: rmssd,
            meanHeartRate: 60_000 / meanInterval,
            cleanIntervals: cleanCount,
            totalIntervals: intervals.count,
            quality: Int((cleanShare * lengthFactor * 100).rounded()),
            intervals: cleanIntervals
        ))
    }

    /// Whether a fingertip seems to cover the lens with the light on: the
    /// picture is bright and strongly red (light shining through skin).
    /// Channel means are 0-1.
    public static func fingerDetected(red: Double, green: Double, blue: Double) -> Bool {
        red > 0.3 && red > green * 1.8 && red > blue * 1.8
    }

    /// The last `seconds` of signal, detrended and scaled to -1...1, for a live
    /// waveform (pulses point up).
    public static func preview(_ samples: [Sample], seconds: Double = 5) -> [Double] {
        guard let last = samples.last else { return [] }
        let recent = samples.filter { $0.time >= last.time - seconds }.map(\.value)
        guard recent.count > 10 else { return [] }
        // Remove slow drift with a ~1 s moving average (at camera frame rates).
        let window = max(5, min(recent.count / 3, 30))
        var detrended: [Double] = []
        detrended.reserveCapacity(recent.count)
        for index in recent.indices {
            let low = max(0, index - window / 2)
            let high = min(recent.count - 1, index + window / 2)
            let mean = recent[low...high].reduce(0, +) / Double(high - low + 1)
            detrended.append(mean - recent[index])
        }
        let peak = detrended.map(abs).max() ?? 0
        return peak > 0 ? detrended.map { $0 / peak } : detrended
    }

    // MARK: - Steps

    /// Linear interpolation onto an even time grid.
    static func resample(_ samples: [Sample], rate: Double) -> [Double] {
        guard let first = samples.first, let last = samples.last, samples.count > 1 else { return samples.map(\.value) }
        let count = Int((last.time - first.time) * rate)
        var output: [Double] = []
        output.reserveCapacity(count)
        var j = 0
        for i in 0..<count {
            let t = first.time + Double(i) / rate
            while j < samples.count - 2 && samples[j + 1].time < t { j += 1 }
            let a = samples[j]
            let b = samples[j + 1]
            let span = b.time - a.time
            let fraction = span > 0 ? (t - a.time) / span : 0
            output.append(a.value + (b.value - a.value) * min(1, max(0, fraction)))
        }
        return output
    }

    /// Second-order Butterworth sections (Q = 1/√2), run forwards and backwards
    /// so peaks don't shift in time.
    static func bandPass(_ signal: [Double], rate: Double, low: Double = 0.7, high: Double = 3.5) -> [Double] {
        guard !signal.isEmpty else { return [] }
        let mean = signal.reduce(0, +) / Double(signal.count)
        var x = signal.map { $0 - mean }
        let highPass = Biquad.highPass(cutoff: low, rate: rate)
        let lowPass = Biquad.lowPass(cutoff: high, rate: rate)
        x = zeroPhase(x, highPass)
        x = zeroPhase(x, lowPass)
        return x
    }

    static func zeroPhase(_ signal: [Double], _ filter: Biquad) -> [Double] {
        let forward = filter.apply(signal)
        return Array(filter.apply(Array(forward.reversed())).reversed())
    }

    /// Peak times (seconds from the start). A peak must be the highest point
    /// within the refractory period (0.33 s, i.e. under 180 bpm) and above a
    /// fraction of the typical pulse height. Peaks near the edges, where the
    /// filter settles, are skipped.
    static func findPeaks(_ signal: [Double], rate: Double, refractory: Double = 0.33) -> [Double] {
        guard signal.count > 5 else { return [] }
        let edge = Int(1.5 * rate)
        let radius = max(1, Int(refractory * rate))
        let positives = signal.filter { $0 > 0 }.sorted()
        let typical = positives.isEmpty ? 0 : positives[Int(Double(positives.count) * 0.9)]
        let threshold = typical * 0.3
        var peaks: [Double] = []
        var index = max(1, edge)
        let end = signal.count - max(1, edge)
        while index < end {
            let value = signal[index]
            if value > threshold, value >= signal[index - 1], value > signal[index + 1] {
                let low = max(0, index - radius)
                let high = min(signal.count - 1, index + radius)
                if signal[low...high].allSatisfy({ $0 <= value }) {
                    // Parabolic refinement between frames.
                    let a = signal[index - 1], b = value, c = signal[index + 1]
                    let denominator = a - 2 * b + c
                    let offset = denominator != 0 ? 0.5 * (a - c) / denominator : 0
                    peaks.append((Double(index) + max(-0.5, min(0.5, offset))) / rate)
                    index += radius
                    continue
                }
            }
            index += 1
        }
        return peaks
    }

    /// Which intervals look like real beats: 300-2000 ms and within 20% of
    /// the median of their neighbours.
    static func cleanFlags(_ intervals: [Double]) -> [Bool] {
        intervals.indices.map { index in
            let interval = intervals[index]
            guard (300...2000).contains(interval) else { return false }
            let low = max(0, index - 3)
            let high = min(intervals.count - 1, index + 3)
            let neighbours = intervals[low...high].filter { (300...2000).contains($0) }.sorted()
            guard !neighbours.isEmpty else { return false }
            let median = neighbours[neighbours.count / 2]
            return abs(interval - median) <= 0.2 * median
        }
    }

    /// A second-order IIR filter (Robert Bristow-Johnson's audio EQ cookbook formulas).
    struct Biquad {
        var b0, b1, b2, a1, a2: Double

        static func lowPass(cutoff: Double, rate: Double) -> Biquad {
            let w = 2 * Double.pi * cutoff / rate
            let alpha = sin(w) / (2 * (1 / 2.0.squareRoot()))
            let cosine = cos(w)
            let a0 = 1 + alpha
            return Biquad(b0: (1 - cosine) / 2 / a0, b1: (1 - cosine) / a0, b2: (1 - cosine) / 2 / a0,
                          a1: -2 * cosine / a0, a2: (1 - alpha) / a0)
        }

        static func highPass(cutoff: Double, rate: Double) -> Biquad {
            let w = 2 * Double.pi * cutoff / rate
            let alpha = sin(w) / (2 * (1 / 2.0.squareRoot()))
            let cosine = cos(w)
            let a0 = 1 + alpha
            return Biquad(b0: (1 + cosine) / 2 / a0, b1: -(1 + cosine) / a0, b2: (1 + cosine) / 2 / a0,
                          a1: -2 * cosine / a0, a2: (1 - alpha) / a0)
        }

        func apply(_ input: [Double]) -> [Double] {
            var output = [Double](repeating: 0, count: input.count)
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            for (index, x) in input.enumerated() {
                let feedForward: Double = b0 * x + b1 * x1 + b2 * x2
                let feedBack: Double = a1 * y1 + a2 * y2
                let y = feedForward - feedBack
                output[index] = y
                x2 = x1; x1 = x
                y2 = y1; y1 = y
            }
            return output
        }
    }
}
