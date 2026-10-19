import Foundation
import Testing
@testable import AppCore

struct RestTimerTests {
    @Test func restFollowsTheGoal() {
        #expect(RestTimer.defaultSeconds(style: .strength, compound: true) == 180)
        #expect(RestTimer.defaultSeconds(style: .muscle, compound: false) == 90)
        #expect(RestTimer.defaultSeconds(style: .endurance, compound: false) == 60)
        #expect(RestTimer.defaultSeconds(style: .balanced, compound: true) == 150)
    }
}

struct TemplateTests {
    let planner = WorkoutPlanner(gym: .commercialPounds)
    let bench = "Barbell_Bench_Press_-_Medium_Grip"

    @Test func fillsMissingWeightsFromHistory() {
        let history = ExerciseHistory(bestEstimatedOneRepMax: 234, lastWeight: 185, lastReps: 8, lastRPE: 7, lastDate: .now)
        let items = [TemplateItem(exerciseID: bench, name: "Bench Press", sets: 4, reps: 6...8, rpe: 8)]
        let planned = planner.prescribe(template: items, history: [bench: history])
        #expect(planned.first?.load == 190)
        #expect(planned.first?.sets == 4)
        #expect(planned.first?.note == "45 + 25 + 2.5 lb per side")
    }

    @Test func keepsTheUsersOwnWeight() {
        let history = ExerciseHistory(bestEstimatedOneRepMax: 234, lastWeight: 185, lastReps: 8, lastRPE: 7, lastDate: .now)
        let items = [TemplateItem(exerciseID: bench, name: "Bench Press", sets: 3, reps: 5...5, weight: 200)]
        #expect(planner.prescribe(template: items, history: [bench: history]).first?.load == 200)
    }

    @Test func exercisesOutsideTheCatalogUseLastWeight() {
        let history = ExerciseHistory(bestEstimatedOneRepMax: 60, lastWeight: 40, lastReps: 12, lastRPE: nil, lastDate: .now)
        let items = [TemplateItem(exerciseID: "Some_Odd_Lift", name: "Odd lift", sets: 3, reps: 10...12)]
        #expect(planner.prescribe(template: items, history: ["Some_Odd_Lift": history]).first?.load == 40)
    }

    @Test func firstTimeGetsAHint() {
        let items = [TemplateItem(exerciseID: "Some_Cable_Lift", name: "Cable lift", sets: 3, reps: 10...12, rpe: 8, libraryLoad: .cable)]
        let planned = planner.prescribe(template: items, history: [:]).first
        #expect(planned?.load == nil)
        #expect(planned?.note?.hasPrefix("First time") == true)
    }

    @Test func libraryEquipmentMaps() {
        #expect(EquipmentKind.fromLibrary("e-z curl bar") == .ezBar)
        #expect(EquipmentKind.fromLibrary("Kettlebells") == .kettlebell)
        #expect(EquipmentKind.fromLibrary("foam roll") == nil)
    }
}

struct LiftProgressTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func marksPersonalRecords() {
        let sessions = [
            LiftProgress.LoggedSession(date: start, sets: [.init(weight: 100, reps: 5), .init(weight: 90, reps: 8)]),
            LiftProgress.LoggedSession(date: start.addingTimeInterval(86_400 * 3), sets: [.init(weight: 100, reps: 4)]),
            LiftProgress.LoggedSession(date: start.addingTimeInterval(86_400 * 7), sets: [.init(weight: 105, reps: 5)]),
        ]
        let points = LiftProgress.points(sessions)
        #expect(points.count == 3)
        #expect(points.map(\.isPR) == [false, false, true])
        #expect(points[0].volume == 100 * 5 + 90 * 8)
        // 90 x 8 (e1RM 114) beats 100 x 5 (116.7)? No: the 100 x 5 set is the best.
        #expect(points[0].bestWeight == 100)
    }

    @Test func skipsSessionsWithoutReps() {
        let sessions = [LiftProgress.LoggedSession(date: start, sets: [.init(weight: 100, reps: 0)])]
        #expect(LiftProgress.points(sessions).isEmpty)
    }
}

struct CardioFitnessTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func series(from: Double, to: Double, days: Int) -> [DayValue] {
        (0..<days).map { day in
            DayValue(date: start.addingTimeInterval(Double(day) * 86_400), value: from + (to - from) * Double(day) / Double(days - 1))
        }
    }

    @Test func flatForEightWeeksIsAPlateau() throws {
        let result = try #require(CardioFitness.assess(series(from: 45, to: 45.2, days: 80), age: 30, sex: .male))
        #expect(result.isPlateau)
        #expect(abs(result.median - Biomarkers.medianVO2Max(age: 30, sex: .male)) < 0.001)
    }

    @Test func risingIsNotAPlateau() throws {
        let result = try #require(CardioFitness.assess(series(from: 42, to: 47, days: 80), age: 30, sex: .male))
        #expect(!result.isPlateau)
        #expect((result.change ?? 0) > 2)
    }

    @Test func shortHistoryHasNoTrend() throws {
        let result = try #require(CardioFitness.assess(series(from: 45, to: 46, days: 10), age: 30, sex: .male))
        #expect(result.change == nil)
        #expect(!result.isPlateau)
    }
}

struct StrengthDaysTests {
    @Test func countsDistinctDaysThisWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2027, month: 3, day: 10, hour: 18))!
        let dates = [
            now.addingTimeInterval(-3600),             // today
            now.addingTimeInterval(-3 * 3600),         // today again
            now.addingTimeInterval(-3 * 86_400),       // 3 days ago
            now.addingTimeInterval(-9 * 86_400),       // last week
        ]
        #expect(StrengthDays.lastSevenDays(dates, now: now, calendar: calendar) == 2)
        #expect(StrengthDays.weekly(dates, weeks: 2, now: now, calendar: calendar) == [1, 2])
    }
}
