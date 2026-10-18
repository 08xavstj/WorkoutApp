import Foundation
import Testing
@testable import AppCore

struct HeartRateComparisonTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func series(_ values: [Double], offset: Double = 0, every seconds: Double = 60) -> [HeartRateSample] {
        values.enumerated().map { HeartRateSample(date: start.addingTimeInterval(Double($0.offset) * seconds + offset), bpm: $0.element) }
    }

    @Test func identicalSourcesAgree() throws {
        let a = series([100, 120, 140, 130])
        let result = try #require(HeartRateComparison.compare(a, a))
        #expect(result.meanAbsoluteDifference == 0)
        #expect(result.overlappingMinutes == 4)
        #expect(abs((result.correlation ?? 0) - 1) < 0.0001)
    }

    @Test func offsetSourceShowsBias() throws {
        let a = series([100, 120, 140, 130])
        let b = series([95, 115, 135, 125])
        let result = try #require(HeartRateComparison.compare(a, b))
        #expect(result.bias == 5)
        #expect(result.meanAbsoluteDifference == 5)
        #expect((result.correlation ?? 0) > 0.99)
    }

    @Test func differentSampleRatesAreAlignedByMinute() throws {
        // A every 5 s, B once a minute.
        let a = series(Array(repeating: 120, count: 36), every: 5)
        let b = series([118, 122, 120])
        let result = try #require(HeartRateComparison.compare(a, b))
        #expect(result.overlappingMinutes == 3)
        #expect(result.meanAbsoluteDifference < 2)
    }

    @Test func noOverlapGivesNil() {
        let a = series([100, 110])
        let b = series([100, 110], offset: 3600)
        #expect(HeartRateComparison.compare(a, b) == nil)
    }

    @Test func summaryStats() throws {
        let s = try #require(HeartRateComparison.summary(series([100, 150, 125])))
        #expect(s.average == 125)
        #expect(s.maximum == 150)
        #expect(s.minimum == 100)
    }
}
