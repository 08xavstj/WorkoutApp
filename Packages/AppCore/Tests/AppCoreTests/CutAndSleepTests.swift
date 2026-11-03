import Foundation
import Testing
@testable import AppCore

struct CutAndSleepTests {
    let highDebt = SleepDebt.compute(nightlyHours: Array(repeating: 6, count: 14), needHours: 8)
    let moderateDebt = SleepDebt.compute(nightlyHours: [6, 6, 6, 6, 10, 10], needHours: 8)

    @Test func onlyWhileCuttingWithHighDebt() {
        #expect(highDebt?.level == .high)
        #expect(moderateDebt?.level == .moderate)
        #expect(CutAndSleep.advice(goals: Goals(weight: .maintain), sleepDebt: highDebt) == nil)
        #expect(CutAndSleep.advice(goals: Goals(weight: .gain, weeklyRatePercent: 0.25), sleepDebt: highDebt) == nil)
        #expect(CutAndSleep.advice(goals: Goals(weight: .lose, weeklyRatePercent: 0.5), sleepDebt: moderateDebt) == nil)
        #expect(CutAndSleep.advice(goals: nil, sleepDebt: highDebt) == nil)
        #expect(CutAndSleep.advice(goals: Goals(weight: .lose, weeklyRatePercent: 0.5), sleepDebt: nil) == nil)
    }

    @Test func suggestsTheNextSlowerRate() throws {
        // Nedeltcheva 2010: 5.5 h vs 8.5 h in a deficit, 55% less fat lost and 60% more lean mass.
        let advice = try #require(CutAndSleep.advice(goals: Goals(weight: .lose, weeklyRatePercent: 0.75), sleepDebt: highDebt))
        #expect(advice.suggestedRatePercent == 0.5)
        #expect(advice.message.contains("Nedeltcheva 2010"))
        #expect(advice.message.contains("0.5% a week"))
        #expect(CutAndSleep.slowerRate(than: 1.0) == 0.75)
    }

    @Test func slowestRateKeepsTheTarget() throws {
        let advice = try #require(CutAndSleep.advice(goals: Goals(weight: .lose, weeklyRatePercent: 0.25), sleepDebt: highDebt))
        #expect(advice.suggestedRatePercent == nil)
        #expect(advice.message.contains("slowest rate"))
    }
}
