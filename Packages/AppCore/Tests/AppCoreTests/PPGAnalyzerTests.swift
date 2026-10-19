import Foundation
import Testing
@testable import AppCore

struct PPGAnalyzerTests {
    /// A fingertip signal: brightness dips at each beat, plus slow drift and a
    /// little noise. Beats alternate 800 / 850 ms apart, so RMSSD is 50 ms.
    func signal(duration: Double = 60, fps: Double = 60, skipBeat: Int? = nil) -> [PPGAnalyzer.Sample] {
        var beats: [Double] = []
        var t = 0.5
        var index = 0
        while t < duration {
            if index != skipBeat { beats.append(t) }
            t += index.isMultiple(of: 2) ? 0.800 : 0.850
            index += 1
        }
        var seed: UInt64 = 42
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31) - 0.5
        }
        return (0..<Int(duration * fps)).map { frame in
            let time = Double(frame) / fps
            let pulse = beats.reduce(0.0) { sum, beat in
                let d = time - beat
                return abs(d) > 0.4 ? sum : sum + exp(-(d * d) / (2 * 0.06 * 0.06))
            }
            let value = 0.8 - 0.02 * pulse + 0.01 * sin(2 * .pi * 0.15 * time) + 0.0008 * noise()
            return PPGAnalyzer.Sample(time: time, value: value)
        }
    }

    @Test func measuresRMSSDAndHeartRate() throws {
        let result = try PPGAnalyzer.analyze(signal()).get()
        #expect(abs(result.rmssd - 50) < 8)
        #expect(abs(result.meanHeartRate - 60_000 / 825) < 2)
        #expect(result.cleanIntervals >= 60)
        #expect(result.quality >= 90)
    }

    @Test func worksAtThirtyFramesASecond() throws {
        let result = try PPGAnalyzer.analyze(signal(fps: 30)).get()
        #expect(abs(result.rmssd - 50) < 10)
    }

    @Test func aMissedBeatIsDropped() throws {
        let result = try PPGAnalyzer.analyze(signal(skipBeat: 30)).get()
        #expect(abs(result.rmssd - 50) < 8)
        #expect(result.cleanIntervals < result.totalIntervals)
        #expect(result.intervals.allSatisfy { $0 < 1000 })
    }

    @Test func shortRecordingsAreRejected() {
        switch PPGAnalyzer.analyze(signal(duration: 10)) {
        case .failure(let failure): #expect(failure == .tooShort)
        case .success: Issue.record("10 s shouldn't produce a reading")
        }
        switch PPGAnalyzer.analyze(signal(duration: 22)) {
        case .failure: break
        case .success: Issue.record("22 s has too few beats")
        }
    }

    @Test func fingerDetection() {
        #expect(PPGAnalyzer.fingerDetected(red: 0.85, green: 0.2, blue: 0.15))
        #expect(!PPGAnalyzer.fingerDetected(red: 0.5, green: 0.45, blue: 0.4))
        #expect(!PPGAnalyzer.fingerDetected(red: 0.1, green: 0.02, blue: 0.02))
    }

    @Test func previewIsScaled() {
        let preview = PPGAnalyzer.preview(signal(duration: 10))
        #expect(!preview.isEmpty)
        #expect((preview.map(abs).max() ?? 0) <= 1.0001)
    }
}
