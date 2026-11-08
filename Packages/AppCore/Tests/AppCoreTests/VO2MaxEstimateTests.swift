import Testing
@testable import AppCore

struct VO2MaxEstimateTests {
    @Test func heartRateRatioIsUthsFormula() throws {
        let result = try #require(VO2MaxEstimate.heartRateRatio(maxHeartRate: 190, restingHeartRate: 60, measuredMax: true))
        #expect(abs(result.value - 48.45) < 0.01)
        #expect(abs(result.error - 48.45 * 0.12) < 0.01)
        let predicted = try #require(VO2MaxEstimate.heartRateRatio(maxHeartRate: 190, restingHeartRate: 60, measuredMax: false))
        #expect(predicted.error > result.error)
    }

    @Test func heartRateRatioRejectsImplausibleInputs() {
        #expect(VO2MaxEstimate.heartRateRatio(maxHeartRate: 190, restingHeartRate: 20, measuredMax: true) == nil)
        #expect(VO2MaxEstimate.heartRateRatio(maxHeartRate: 90, restingHeartRate: 60, measuredMax: true) == nil)
    }

    @Test func liftingCountsAsModestActivity() {
        // Only lifting, 3 h a week, no hard heart-rate minutes: level 3.
        #expect(VO2MaxEstimate.activityRating(vigorousMinutes: 0, moderateMinutes: 0, liftingMinutes: 180) == 3)
        #expect(VO2MaxEstimate.activityRating(vigorousMinutes: 0, moderateMinutes: 0, liftingMinutes: 30) == 2)
        #expect(VO2MaxEstimate.activityRating(vigorousMinutes: 0, moderateMinutes: 0, liftingMinutes: 0) == 1)
        // Hard minutes (from any workout, lifting included) reach 4-7.
        #expect(VO2MaxEstimate.activityRating(vigorousMinutes: 20, moderateMinutes: 0, liftingMinutes: 180) == 4)
        #expect(VO2MaxEstimate.activityRating(vigorousMinutes: 45, moderateMinutes: 0, liftingMinutes: 0) == 5)
        #expect(VO2MaxEstimate.activityRating(vigorousMinutes: 90, moderateMinutes: 0, liftingMinutes: 0) == 6)
        #expect(VO2MaxEstimate.activityRating(vigorousMinutes: 200, moderateMinutes: 0, liftingMinutes: 0) == 7)
    }

    @Test func activityModelIsJackson1990() throws {
        let bmi = try #require(VO2MaxEstimate.activity(rating: 3, age: 34, sex: .male, bmi: 25.2, bodyFatPercent: nil))
        #expect(abs(bmi.value - 41.16) < 0.01)
        #expect(bmi.error == 5.35)
        let fat = try #require(VO2MaxEstimate.activity(rating: 3, age: 34, sex: .male, bmi: 25.2, bodyFatPercent: 17))
        // 50.513 + 4.767 − 9.826 − 9.384 + 5.863
        #expect(abs(fat.value - 41.933) < 0.01)
        #expect(fat.error == 5.04)
        let fitter = try #require(VO2MaxEstimate.activity(rating: 6, age: 34, sex: .male, bmi: 25.2, bodyFatPercent: nil))
        #expect(fitter.value > bmi.value)
    }

    @Test func activityModelNeedsABodyMeasure() {
        #expect(VO2MaxEstimate.activity(rating: 3, age: 34, sex: .female, bmi: nil, bodyFatPercent: nil) == nil)
    }
}
