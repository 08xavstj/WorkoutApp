import Foundation
import Testing
@testable import AppCore

/// The reported lifting experience combined with the lifting log
/// (`TrainingStatus.resolve`; docs/research/calories.md).
struct LiftingExperienceTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Sessions over the last `days` days on the given weekdays of a `cycle`-day pattern.
    func sessions(days: Int, cycle: Int = 7, on slots: Set<Int>, skippingRecent: Int = 0) -> [Date] {
        (skippingRecent..<days).filter { slots.contains($0 % cycle) }.map { now.addingTimeInterval(-Double($0) * 86_400 - 3600) }
    }

    func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    @Test(arguments: zip(LiftingExperience.allCases, [TrainingStatus.novice, .intermediate, .advanced]))
    func eachBandMapsToAStatus(experience: LiftingExperience, status: TrainingStatus) {
        #expect(experience.status == status)
    }

    @Test func nothingReportedUsesTheLog() {
        #expect(TrainingStatus.resolve(reported: nil, sessionDates: [], now: now) == .untrained)
        let year = sessions(days: 365, on: [0, 2, 4, 6])
        #expect(TrainingStatus.resolve(reported: nil, sessionDates: year, now: now) == .intermediate)
    }

    @Test(arguments: zip(LiftingExperience.allCases, [TrainingStatus.novice, .intermediate, .advanced]))
    func noLogUsesTheReportedLevel(experience: LiftingExperience, status: TrainingStatus) {
        #expect(TrainingStatus.resolve(reported: experience, sessionDates: [], now: now) == status)
    }

    @Test func underEightWeeksOfLogUsesTheReportedLevel() {
        // A month of training reads as novice from the log alone.
        let month = sessions(days: 30, on: [0, 2, 4, 6])
        #expect(TrainingStatus.estimate(sessionDates: month, now: now) == .novice)
        #expect(TrainingStatus.resolve(reported: .twoYearsPlus, sessionDates: month, now: now) == .advanced)
        // Too short to judge even when the log looks untrained.
        let sparse = [daysAgo(3), daysAgo(20)]
        #expect(TrainingStatus.estimate(sessionDates: sparse, now: now) == .untrained)
        #expect(TrainingStatus.resolve(reported: .sixMonthsToTwoYears, sessionDates: sparse, now: now) == .intermediate)
    }

    @Test func eightWeeksOfLogTakesTheHigherLevel() {
        let year = sessions(days: 365, on: [0, 2, 4, 6])
        #expect(TrainingStatus.estimate(sessionDates: year, now: now) == .intermediate)
        // Reported higher than the log: the reported level.
        #expect(TrainingStatus.resolve(reported: .twoYearsPlus, sessionDates: year, now: now) == .advanced)
        // Log higher than the reported level: the log.
        #expect(TrainingStatus.resolve(reported: .underSixMonths, sessionDates: year, now: now) == .intermediate)
    }

    @Test func eightWeeksOfLogAndStoppedTrainingIsUntrained() {
        let stopped = sessions(days: 800, on: [0, 2, 4], skippingRecent: 60)
        #expect(TrainingStatus.estimate(sessionDates: stopped, now: now) == .untrained)
        #expect(TrainingStatus.resolve(reported: .twoYearsPlus, sessionDates: stopped, now: now) == .untrained)
    }

    @Test func theEightWeekLineCountsFromTheFirstLoggedSession() {
        // One session: 50 days ago is too short to judge, 60 days ago is not.
        #expect(TrainingStatus.resolve(reported: .twoYearsPlus, sessionDates: [daysAgo(50)], now: now) == .advanced)
        #expect(TrainingStatus.resolve(reported: .twoYearsPlus, sessionDates: [daysAgo(60)], now: now) == .untrained)
        // Planned sessions in the future don't count as history.
        #expect(TrainingStatus.resolve(reported: .twoYearsPlus, sessionDates: [now.addingTimeInterval(86_400)], now: now) == .advanced)
    }
}
