import Foundation
import Testing
@testable import AppCore

struct HearingExposureTests {
    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))

    @Test func allowedHoursHalveEveryThreeDecibels() {
        // WHO-ITU H.870: 80 dB(A) for 40 h, 83 for 20 h, 86 for 10 h, 95 for about 1.25 h.
        #expect(abs(HearingExposure.allowedHours(at: 80) - 40) < 1e-9)
        #expect(abs(HearingExposure.allowedHours(at: 83) - 20) < 1e-9)
        #expect(abs(HearingExposure.allowedHours(at: 86) - 10) < 1e-9)
        #expect(abs(HearingExposure.allowedHours(at: 95) - 1.25) < 1e-9)
        // Quieter listening earns more time.
        #expect(abs(HearingExposure.allowedHours(at: 77) - 80) < 1e-9)
        // The sensitive-user budget is 5 dB stricter.
        #expect(abs(HearingExposure.allowedHours(at: 75, referenceLevel: HearingExposure.sensitiveReferenceLevel) - 40) < 1e-9)
    }

    @Test func fortyHoursAtEightyUsesTheWholeBudget() {
        let samples = (0..<5).map { HearingExposure.Sample(start: day.addingTimeInterval(Double($0) * 86_400), level: 80, hours: 8) }
        let result = HearingExposure.weekly(samples)
        #expect(abs(result.hours - 40) < 1e-9)
        #expect(abs(result.budgetFraction - 1) < 1e-9)
        #expect(result.percentOfBudget == 100)
        #expect(result.isOverBudget)
        #expect(abs((result.equivalentLevel ?? 0) - 80) < 1e-9)
        #expect(result.dailyFractions.count == 5)
        #expect(abs((result.dailyFractions[day] ?? 0) - 0.2) < 1e-9)
    }

    @Test func energyWeightedLevelFavoursTheLoudHours() {
        // 1 h at 90 dB(A) carries ten times the energy of 1 h at 80: Leq = 80 + 10·log10(5.5) ≈ 87.4.
        let samples = [
            HearingExposure.Sample(start: day, level: 90, hours: 1),
            HearingExposure.Sample(start: day, level: 80, hours: 1),
        ]
        let result = HearingExposure.weekly(samples)
        #expect(abs((result.equivalentLevel ?? 0) - 87.40) < 0.01)
        // 11 reference-hours of energy out of 40.
        #expect(abs(result.budgetFraction - 0.275) < 1e-9)
        #expect(result.percentOfBudget == 28)
        #expect(!result.isOverBudget)
    }

    @Test func quietListeningBarelyCounts() {
        // 20 h at 70 dB(A) is a tenth of the energy of 20 h at 80: 5% of the budget.
        let result = HearingExposure.weekly([HearingExposure.Sample(start: day, level: 70, hours: 20)])
        #expect(abs(result.budgetFraction - 0.05) < 1e-9)
        #expect(HearingExposure.nudge(for: result) == nil)
    }

    @Test func emptyAndInvalidSamplesGiveNoLevel() {
        let empty = HearingExposure.weekly([])
        #expect(empty.hours == 0)
        #expect(empty.equivalentLevel == nil)
        #expect(empty.budgetFraction == 0)
        #expect(HearingExposure.nudge(for: empty) == nil)
        let bad = HearingExposure.weekly([
            HearingExposure.Sample(start: day, level: .nan, hours: 2),
            HearingExposure.Sample(start: day, level: 85, hours: 0),
        ])
        #expect(bad.hours == 0)
        #expect(bad.equivalentLevel == nil)
    }

    @Test func nudgeAppearsNearAndOverTheBudget() {
        let near = HearingExposure.weekly([HearingExposure.Sample(start: day, level: 80, hours: 32)])
        #expect(HearingExposure.nudge(for: near)?.hasPrefix("Close to") == true)
        // 24 h at 83 dB(A): 10^0.3 ≈ 1.995 times the energy of 80, so 47.9 reference-hours of 40.
        let over = HearingExposure.weekly([HearingExposure.Sample(start: day, level: 83, hours: 24)])
        #expect(over.percentOfBudget == 120)
        #expect(HearingExposure.nudge(for: over)?.hasPrefix("Over") == true)
    }
}
