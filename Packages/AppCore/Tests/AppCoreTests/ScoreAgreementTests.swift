import Foundation
import Testing
@testable import AppCore

/// How two scores move together (`ScoreAgreement`): direction of day-to-day
/// change and a rank correlation, both descriptive.
@Suite struct ScoreAgreementTests {
    private typealias Pair = ScoreAgreement.Pair

    private func pairs(_ values: [(Double, Double)], startDay: Int = 100) -> [Pair] {
        values.enumerated().map { Pair(day: startDay + $0.offset, apple: $0.element.0, app: $0.element.1) }
    }

    // MARK: Direction

    @Test func countsChangesInTheSameAndOppositeDirection() {
        // Changes: (+2, +10) same, (-3, +5) opposite, (+1, -8) opposite, (+2, +20) same.
        let result = ScoreAgreement.direction(pairs([(5, 50), (7, 60), (4, 65), (5, 57), (7, 77)]))
        #expect(result.same == 2)
        #expect(result.opposite == 2)
        #expect(result.flat == 0)
        #expect(result.compared == 4)
        #expect(result.share == 0.5)
    }

    @Test func aScoreThatDidNotMoveHasNoDirection() {
        // Readiness stays at 6 while recovery moves: nothing to compare.
        let result = ScoreAgreement.direction(pairs([(6, 50), (6, 60), (7, 60), (8, 70)]))
        #expect(result.flat == 2)
        #expect(result.same == 1)
        #expect(result.opposite == 0)
        #expect(result.share == 1)
    }

    @Test func changesAcrossLongGapsAreLeftOut() {
        let far = [Pair(day: 1, apple: 5, app: 50), Pair(day: 2 + ScoreAgreement.maxGapDays, apple: 7, app: 70)]
        #expect(ScoreAgreement.direction(far).compared == 0)
        let near = [Pair(day: 1, apple: 5, app: 50), Pair(day: 1 + ScoreAgreement.maxGapDays, apple: 7, app: 70)]
        #expect(ScoreAgreement.direction(near).same == 1)
    }

    @Test func orderOfTheInputDoesNotMatter() {
        let ordered = pairs([(5, 50), (7, 60), (4, 65), (5, 57)])
        #expect(ScoreAgreement.direction(ordered.reversed()) == ScoreAgreement.direction(ordered))
    }

    @Test func nothingToCompare() {
        #expect(ScoreAgreement.direction([]).share == nil)
        #expect(ScoreAgreement.direction(pairs([(5, 50)])).share == nil)
    }

    // MARK: Ranks and correlation

    @Test func tiesShareTheAverageRank() {
        #expect(ScoreAgreement.ranks([10, 20, 20, 30]) == [1, 2.5, 2.5, 4])
        #expect(ScoreAgreement.ranks([3, 3, 3]) == [2, 2, 2])
        #expect(ScoreAgreement.ranks([]) == [])
        #expect(ScoreAgreement.ranks([5, 1, 9]) == [2, 1, 3])
    }

    @Test func noCorrelationBeforeEnoughDays() {
        let few = pairs((0..<(ScoreAgreement.minimumPairsForCorrelation - 1)).map { (Double($0 % 10), Double($0 * 3)) })
        #expect(ScoreAgreement.spearman(few) == nil)
        #expect(ScoreAgreement.summary(few).pairsUntilCorrelation == 1)
        #expect(ScoreAgreement.summary(few).correlation == nil)
    }

    @Test func perfectlyMonotonicIsOne() throws {
        // Not a straight line (squares), but always rising together: rho is 1.
        let rising = pairs((1...24).map { (Double($0), Double($0 * $0)) })
        let up = try #require(ScoreAgreement.spearman(rising))
        #expect(abs(up.rho - 1) < 1e-9)
        #expect(up.count == 24)
        let falling = pairs((1...24).map { (Double($0), Double(100 - $0)) })
        let down = try #require(ScoreAgreement.spearman(falling))
        #expect(abs(down.rho + 1) < 1e-9)
    }

    @Test func knownValueWithTies() throws {
        // Hand-checked: ranks of x = [1, 2.5, 2.5, 4, 5], of y = [1, 3, 2, 5, 4];
        // Pearson on the ranks = 8.5 / sqrt(9.5 * 10) = 0.8721.
        let sample = pairs([(1, 10), (2, 30), (2, 20), (3, 50), (4, 40)])
        let result = try #require(ScoreAgreement.spearman(sample, minimumPairs: 4))
        #expect(abs(result.rho - 0.8721) < 0.0005)
    }

    @Test func aScoreThatNeverChangedHasNoCorrelation() {
        let constant = pairs((1...25).map { (6, Double($0)) })
        #expect(ScoreAgreement.spearman(constant) == nil)
    }

    @Test func intervalIsWideAtTwentyDaysAndContainsTheEstimate() throws {
        // A noisy rising relation.
        let noisy = pairs((0..<20).map { index in
            let apple = Double(index % 10)
            let app = Double(index % 10) * 6 + Double((index * 7) % 11) * 4
            return (apple, app)
        })
        let result = try #require(ScoreAgreement.spearman(noisy))
        #expect(result.low < result.rho)
        #expect(result.high > result.rho)
        #expect(result.low >= -1)
        #expect(result.high <= 1)
        #expect(result.high - result.low > 0.3)
    }

    @Test func intervalMatchesBonettWright() throws {
        // rho = 0.5, n = 20: z = atanh(0.5) = 0.5493, se = sqrt(1.125 / 17) = 0.2572,
        // so the interval is tanh(0.5493 ± 0.5042) = 0.045 … 0.783.
        let z = atanh(0.5)
        let error = ((1 + 0.25 / 2) / 17.0).squareRoot()
        #expect(abs(tanh(z - 1.96 * error) - 0.045) < 0.001)
        #expect(abs(tanh(z + 1.96 * error) - 0.783) < 0.001)
    }

    // MARK: Difference and summary

    @Test func meanDifferenceIsAppleMinusApp() {
        #expect(ScoreAgreement.meanDifference(pairs([(82, 78), (74, 80), (90, 84)])) == 4.0 / 3.0)
        #expect(ScoreAgreement.meanDifference([]) == nil)
    }

    @Test func summaryPutsItTogether() {
        let sample = pairs((0..<22).map { (Double(60 + $0), Double(55 + $0)) })
        let summary = ScoreAgreement.summary(sample)
        #expect(summary.count == 22)
        #expect(summary.direction.same == 21)
        #expect(summary.pairsUntilCorrelation == 0)
        #expect(summary.meanDifference == 5)
        #expect(abs((summary.correlation?.rho ?? 0) - 1) < 1e-9)
    }
}
