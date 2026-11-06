import Foundation
import Testing
@testable import AppCore

struct LiftGoalProjectionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let week = 7 * 86_400.0

    /// Sessions 9, 6, 3 and 0 weeks ago with these e1RMs.
    func samples(_ kg: [Double]) -> [LiftGoalProjection.Sample] {
        let weeksAgo = [9.0, 6, 3, 0]
        return zip(weeksAgo, kg).map { LiftGoalProjection.Sample(date: now.addingTimeInterval(-$0 * week), kg: $1) }
    }

    func kg(_ value: Double) -> String { "\(Int(value.rounded())) kg" }
    func month(_ date: Date) -> String { "M\(Int(date.timeIntervalSince(now) / week))" }

    // MARK: Fit and band

    @Test func fitsAStraightLine() throws {
        let fit = try #require(LiftGoalProjection.fit(samples([91, 94, 97, 100]), now: now))
        #expect(abs(fit.slopePerWeek - 1) < 1e-9)
        #expect(abs(fit.intercept - 100) < 1e-9)
        #expect(fit.residualSD < 1e-9)
        #expect(fit.meanWeeks == -4.5)
        #expect(abs(fit.sumSquares - 45) < 1e-9)
        #expect(abs(fit.spanWeeks - 9) < 1e-9)
    }

    @Test func bandUsesTheResidualSpread() throws {
        // Residual SD 5.69 kg: s·√(1 + 1/4 + 4.5²/45) = 7.42 kg now.
        let fit = try #require(LiftGoalProjection.fit(samples([90, 100, 92, 102]), now: now))
        #expect(abs(fit.slopePerWeek - 0.9333) < 0.001)
        #expect(abs(fit.residualSD - 5.692) < 0.001)
        #expect(abs(fit.halfWidth(weeksAhead: 0) - 7.4216) < 0.001)
    }

    @Test func aPerfectLineStillGetsTheEstimateSpread() throws {
        // Floor of 3 kg (e1RM accuracy, B22): 3·√1.7 = 3.91 kg now, 14.05 kg at 26 weeks.
        let fit = try #require(LiftGoalProjection.fit(samples([91, 94, 97, 100]), now: now))
        #expect(abs(fit.halfWidth(weeksAhead: 0) - 3.9115) < 0.001)
        #expect(abs(fit.halfWidth(weeksAhead: 26) - 14.0464) < 0.001)
        #expect(fit.halfWidth(weeksAhead: 26) > fit.halfWidth(weeksAhead: 12))
    }

    @Test func onlySetsOfTenOrFewerCount() {
        let sessions = [
            LiftProgress.LoggedSession(date: now, sets: [.init(weight: 80, reps: 15), .init(weight: 90, reps: 5)]),
            LiftProgress.LoggedSession(date: now.addingTimeInterval(-week), sets: [.init(weight: 70, reps: 12)]),
        ]
        let series = LiftGoalProjection.series(sessions)
        #expect(series.count == 1)
        #expect(abs(series[0].kg - 90 * (1 + 5.0 / 30)) < 1e-9)
    }

    // MARK: Projection

    @Test func onTrendGivesAWindow() throws {
        let projection = LiftGoalProjection.project(samples: samples([91, 94, 97, 100]), targetKg: 110, now: now)
        #expect(projection.status == .onTrend)
        #expect(projection.reachFrom == now.addingTimeInterval(33 * 86_400))
        #expect(projection.reachBy == now.addingTimeInterval(158 * 86_400))
        let range = try #require(projection.range)
        #expect(abs(range.lowerBound - 111.95) < 0.01)
        #expect(abs(range.upperBound - 140.05) < 0.01)
        #expect(projection.progress == 100.0 / 110)
        let headline = LiftGoalProjection.headline(projection, weight: kg, month: month, now: now)
        #expect(headline == "At your last 12 weeks' rate, 110 kg falls between M4 and M22.")
        // The line itself reaches 110 kg after 10 weeks (+1 kg a week from 100).
        #expect(projection.reachLine == now.addingTimeInterval(70 * 86_400))
        // Worded as a rough 2-in-3 range: ±1 SE of a prediction, not a sure thing.
        #expect(LiftGoalProjection.rangeLine(projection, weight: kg, month: month)
                == "If the last 12 weeks continue: likely 112–140 kg by M26 (a rough 2-in-3 range).")
        #expect(LiftGoalProjection.openAlternative(projection, month: month) == nil)
    }

    @Test func advancedLiftersGetAWiderLowerEdge() throws {
        // A slow trend (+0.2 kg a week, about 5% in 6 months) under every
        // training-status ceiling, so only the band's lower edge differs.
        // (Before QA round 1 this used +1 kg a week, which advanced lifters
        // now have capped; see `slopeIsCappedByTrainingStatus`.)
        let slow = samples([97.6, 98.2, 98.8, 99.4])
        let novice = LiftGoalProjection.project(samples: slow, targetKg: 110, trainingStatus: .novice, now: now)
        let advanced = LiftGoalProjection.project(samples: slow, targetKg: 110, trainingStatus: .advanced, now: now)
        let noviceRange = try #require(novice.range)
        let advancedRange = try #require(advanced.range)
        #expect(!novice.slopeCapped && !advanced.slopeCapped)
        #expect(advancedRange.lowerBound < noviceRange.lowerBound)
        #expect(abs(advancedRange.upperBound - noviceRange.upperBound) < 1e-9)
        #expect(advanced.widenedForTrainingAge)
        #expect(!novice.widenedForTrainingAge)
        #expect(LiftGoalProjection.lowerEdgeFactor(.intermediate) == 1.5)
        let line = try #require(LiftGoalProjection.rangeLine(advanced, weight: kg, month: month))
        #expect(line.hasSuffix(" Progress usually slows, so the low end is more likely."))
    }

    @Test func slopeIsCappedByTrainingStatus() throws {
        // +1 kg a week from 100 kg is 26% in 6 months: under the untrained/novice
        // ceiling (40%, ACSM 2009), over the advanced one (10%).
        let fast = samples([91, 94, 97, 100])
        let novice = LiftGoalProjection.project(samples: fast, targetKg: 110, trainingStatus: .novice, now: now)
        let advanced = LiftGoalProjection.project(samples: fast, targetKg: 110, trainingStatus: .advanced, now: now)
        #expect(!novice.slopeCapped)
        #expect(advanced.slopeCapped)
        let fit = try #require(advanced.fit)
        #expect(abs(fit.slopePerWeek - 100 * 0.10 / 26) < 1e-9)
        // The line now reaches 110 kg only at the 6-month mark, not after 10 weeks.
        let range = try #require(advanced.range)
        #expect(range.upperBound < 125)
        #expect(LiftGoalProjection.maximumGainFraction(.intermediate) == 0.20)
        #expect(LiftGoalProjection.maximumGainFraction(nil) == 0.40)
        let line = try #require(LiftGoalProjection.rangeLine(advanced, weight: kg, month: month))
        #expect(line.contains("faster than lifters at your level usually keep up"))
        // 117 kg intermediate bench: never more than +20% (about 140 kg) on the line by 6 months.
        let bench = [9.0, 6, 3, 0].enumerated().map { LiftGoalProjection.Sample(date: now.addingTimeInterval(-$1 * week), kg: 99 + 6 * Double($0)) }
        let projected = LiftGoalProjection.project(samples: bench, targetKg: 150, trainingStatus: .intermediate, now: now)
        let benchFit = try #require(projected.fit)
        #expect(benchFit.value(weeksAhead: 26) <= benchFit.intercept + 117 * 0.20 + 1e-9)
    }

    @Test func notOnTheCurrentTrend() {
        let flat = LiftGoalProjection.project(samples: samples([100, 100, 100, 100]), targetKg: 120, now: now)
        #expect(flat.status == .notOnTrend)
        #expect(flat.reachFrom == nil)
        let headline = LiftGoalProjection.headline(flat, weight: kg, month: month, now: now)
        #expect(headline == "120 kg isn't on the current trend by M26.")
        #expect(!headline.contains("behind"))
        #expect(LiftGoalProjection.openAlternative(flat, month: month) == "Or keep it open: see how far you get by M26.")

        // A flat line isn't heading to a nearby target either, even though the band brushes it.
        let near = LiftGoalProjection.project(samples: samples([100, 100, 100, 100]), targetKg: 104, now: now)
        #expect(near.status == .notOnTrend)

        // Slow gains toward a far target.
        let slow = LiftGoalProjection.project(samples: samples([98.2, 98.4, 98.6, 98.8]), targetKg: 150, now: now)
        #expect(slow.status == .notOnTrend)
    }

    @Test func onlyTheUpperEdgeIsPossibleNotOnTrend() {
        // 8 weeks ahead the line is at 108 kg and the upper edge at about 114.5 kg:
        // 110 kg is possible, but the line doesn't reach it by then.
        let date = now.addingTimeInterval(8 * week)
        let projection = LiftGoalProjection.project(samples: samples([91, 94, 97, 100]), targetKg: 110, targetDate: date, now: now)
        #expect(projection.status == .possible)
        #expect(projection.reachFrom != nil)
        #expect(projection.reachLine == nil)
        #expect(LiftGoalProjection.headline(projection, weight: kg, month: month, now: now)
                == "At your last 12 weeks' rate, 110 kg is possible by M8, but the trend line gets there later.")
        #expect(LiftGoalProjection.openAlternative(projection, month: month) == "Or keep it open: see how far you get by M8.")
        #expect(LiftGoalProjection.rangeLine(projection, weight: kg, month: month) != nil)
    }

    @Test func targetDateShortensTheHorizon() {
        let date = now.addingTimeInterval(8 * week)
        let projection = LiftGoalProjection.project(samples: samples([91, 94, 97, 100]), targetKg: 120, targetDate: date, now: now)
        #expect(projection.horizon == date)
        #expect(projection.band.last?.date == date)
        // The upper edge reaches 120 kg only after 8 weeks.
        #expect(projection.status == .notOnTrend)
    }

    @Test func capsAtSixMonths() {
        let farDate = now.addingTimeInterval(52 * week)
        let projection = LiftGoalProjection.project(samples: samples([91, 94, 97, 100]), targetKg: 200, targetDate: farDate, now: now)
        let cap = now.addingTimeInterval(26 * week)
        #expect(projection.horizon == cap)
        #expect(projection.band.last?.date == cap)
        #expect(projection.band.allSatisfy { $0.date <= cap })
        #expect(projection.band.count == 27)
        #expect(projection.status == .notOnTrend)
    }

    @Test func tooLittleData() {
        // Three sessions.
        let three = Array(samples([91, 94, 97, 100]).suffix(3))
        let few = LiftGoalProjection.project(samples: three, targetKg: 110, now: now)
        #expect(few.status == .needsMoreData)
        #expect(few.band.isEmpty)
        #expect(LiftGoalProjection.headline(few, weight: kg, month: month, now: now) == "Log a few more sessions to see a projection.")
        #expect(LiftGoalProjection.rangeLine(few, weight: kg, month: month) == nil)

        // Four sessions inside two weeks.
        let bunched = (0..<4).map { LiftGoalProjection.Sample(date: now.addingTimeInterval(-Double($0) * 4 * 86_400), kg: 100 + Double($0)) }
        #expect(LiftGoalProjection.project(samples: bunched, targetKg: 110, now: now).status == .needsMoreData)

        // Sessions older than 12 weeks don't count.
        let old = samples([91, 94, 97, 100]).map { LiftGoalProjection.Sample(date: $0.date.addingTimeInterval(-10 * week), kg: $0.kg) }
        #expect(LiftGoalProjection.project(samples: old, targetKg: 110, now: now).status == .needsMoreData)
    }

    @Test func reachedTarget() {
        let projection = LiftGoalProjection.project(samples: samples([91, 94, 97, 100]), targetKg: 100, now: now)
        #expect(projection.status == .reached)
        #expect(projection.progress == 1)
        #expect(LiftGoalProjection.headline(projection, weight: kg, month: month, now: now).hasPrefix("You've reached it: 100 kg"))
    }

    // MARK: Goals

    @Test func bodyweightMultipleResolves() {
        let goal = LiftGoal(exerciseID: "Barbell_Squat", name: "Squat", bodyweightMultiple: 1.5)
        #expect(goal.resolvedTargetKg(bodyMassKg: 80) == 120)
        #expect(goal.resolvedTargetKg(bodyMassKg: nil) == nil)
        let fixed = LiftGoal(exerciseID: "Barbell_Squat", name: "Squat", targetKg: 140)
        #expect(fixed.resolvedTargetKg(bodyMassKg: nil) == 140)
    }

    @Test func oldGoalsDecodeWithoutLiftGoals() throws {
        let json = #"{"weight":"lose","weeklyRatePercent":0.5,"focuses":["muscle"],"targetWeightKg":80}"#
        let goals = try JSONDecoder().decode(Goals.self, from: Data(json.utf8))
        #expect(goals.weight == .lose)
        #expect(goals.targetWeightKg == 80)
        #expect(goals.liftGoals.isEmpty)

        let noTarget = #"{"weight":"maintain","weeklyRatePercent":0.5,"focuses":["strength","health"]}"#
        #expect(try JSONDecoder().decode(Goals.self, from: Data(noTarget.utf8)).targetWeightKg == nil)
    }

    @Test func liftGoalsRoundTrip() throws {
        let goal = LiftGoal(exerciseID: "Barbell_Bench_Press_-_Medium_Grip", name: "Bench press", targetKg: 100,
                            targetDate: now.addingTimeInterval(20 * week))
        let goals = Goals(weight: .gain, weeklyRatePercent: 0.25, focuses: [.strength], liftGoals: [goal])
        let decoded = try JSONDecoder().decode(Goals.self, from: JSONEncoder().encode(goals))
        #expect(decoded == goals)
    }
}
