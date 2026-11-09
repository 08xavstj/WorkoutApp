import Foundation
import Testing
@testable import AppCore

struct PRHistoryTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 18))!
    }

    private func set(_ weight: Double, _ reps: Int, rpe: Double? = nil, warmup: Bool = false, stage: Bool = false,
                     done: Bool = true) -> WorkoutSummary.LoggedSet {
        WorkoutSummary.LoggedSet(weightKg: weight, reps: reps, rpe: rpe, isWarmup: warmup, isStage: stage,
                                 completedAt: done ? Date(timeIntervalSince1970: 0) : nil)
    }

    private func session(_ day: Date, _ id: String, _ name: String, _ sets: [WorkoutSummary.LoggedSet]) -> WorkoutSummary.LoggedSession {
        WorkoutSummary.LoggedSession(name: "Workout", start: day, end: day.addingTimeInterval(3_600),
                                     exercises: [WorkoutSummary.LoggedExercise(exerciseID: id, name: name, sets: sets)])
    }

    private let bench = "Barbell_Bench_Press_-_Medium_Grip"

    @Test func firstSessionHasNoRecordsThenHeavierSetsDo() {
        let sessions = [
            session(date(2026, 1, 5), bench, "Bench Press", [set(60, 8), set(60, 8)]),
            // A heavy warm-up, a drop stage and an unticked set don't count.
            session(date(2026, 1, 12), bench, "Bench Press", [set(90, 2, warmup: true), set(60, 8), set(80, 6, stage: true),
                                                              set(100, 1, done: false)]),
            session(date(2026, 1, 19), bench, "Bench Press", [set(65, 8), set(65, 8)]),
        ]
        let events = PRHistory.events(sessions)
        #expect(events.allSatisfy { $0.date == date(2026, 1, 19) })
        let records = events.map(\.record)
        #expect(records.contains(.estimatedOneRepMax(65 * (1 + 8.0 / 30))))
        #expect(records.contains(.heaviest(weight: 65, reps: 8)))
        #expect(records.contains(.volume(1_040)))
        #expect(records.count == 3)
    }

    @Test func bodyweightLiftsGetRepAndAddedWeightRecords() {
        let id = "Pullups"
        let sessions = [
            session(date(2026, 2, 2), id, "Pull-Ups", [set(0, 8)]),
            session(date(2026, 2, 9), id, "Pull-Ups", [set(0, 10)]),
            session(date(2026, 2, 16), id, "Pull-Ups", [set(10, 5)]),
        ]
        let traits = [id: PRHistory.Traits(isBodyweight: true)]
        let events = PRHistory.events(sessions, traits: traits)
        #expect(events.map(\.record) == [.reps(weight: 0, reps: 10), .heaviest(weight: 10, reps: 5)])
        let bests = PRHistory.bests(sessions, traits: traits, in: nil, events: events)
        #expect(bests.count == 1)
        #expect(bests[0].estimatedOneRepMax == nil)
        #expect(bests[0].volume == nil)
        #expect(bests[0].heaviest?.weightKg == 10)
        #expect(bests[0].repMaxes.map(\.reps) == [5, 10])
        #expect(bests[0].recordSessions == 2)
    }

    @Test func repMaxesKeepOnlyUnbeatenWeights() {
        let sessions = [
            session(date(2026, 3, 2), bench, "Bench Press", [set(60, 8), set(55, 7), set(50, 12)]),
            session(date(2026, 3, 9), bench, "Bench Press", [set(50, 10)]),
        ]
        let best = PRHistory.bests(sessions, in: nil, events: [])[0]
        // 55 × 7 is beaten by 60 × 8; 50 × 12 was the first time 12 was reached.
        #expect(best.repMaxes.map(\.weightKg) == [60, 50])
        #expect(best.repMaxes.map(\.reps) == [8, 12])
        #expect(best.repMaxes.last?.date == date(2026, 3, 2))
        #expect(best.volume.map { abs($0.value - 1_465) < 0.001 } == true)
        #expect(best.heaviest?.weightKg == 60)
        #expect(best.sessions == 2)
    }

    @Test func periodsFilterTheBests() {
        let sessions = [
            session(date(2025, 6, 2), bench, "Bench Press", [set(80, 5)]),
            session(date(2026, 3, 2), bench, "Bench Press", [set(70, 5)]),
        ]
        let now = date(2026, 11, 9)
        let year = PRHistory.bests(sessions, in: PRHistory.Period.thisYear.interval(now: now, calendar: Self.calendar), events: [])
        #expect(year.first?.heaviest?.weightKg == 70)
        let all = PRHistory.bests(sessions, in: PRHistory.Period.allTime.interval(now: now, calendar: Self.calendar), events: [])
        #expect(all.first?.heaviest?.weightKg == 80)
        let last12 = PRHistory.Period.last12Months.interval(now: now, calendar: Self.calendar)
        #expect(PRHistory.bests(sessions, in: last12, events: []).first?.heaviest?.weightKg == 70)
        #expect(PRHistory.periods(sessions, now: now, calendar: Self.calendar) == [.thisYear, .last12Months, .allTime, .year(2025)])
    }

    @Test func topLiftsComeFirst() {
        #expect(PRHistory.rank(exerciseID: bench, name: "Bench Press") == 0)
        #expect(PRHistory.rank(exerciseID: "Barbell_Incline_Bench_Press_-_Medium_Grip", name: "Incline Bench Press") == 1)
        #expect(PRHistory.rank(exerciseID: "Barbell_Squat", name: "Back Squat") == 2)
        #expect(PRHistory.rank(exerciseID: "Romanian_Deadlift", name: "Romanian Deadlift") == 5)
        #expect(PRHistory.rank(exerciseID: "Dumbbell_Shoulder_Press", name: "Dumbbell Shoulder Press") == 7)
        #expect(PRHistory.rank(exerciseID: "Seated_Cable_Rows", name: "Seated Cable Rows") == 9)
        #expect(PRHistory.rank(exerciseID: "Chin-Up", name: "Chin-Up") == 11)
        #expect(PRHistory.rank(exerciseID: "Barbell_Curl", name: "Barbell Curl") == 100)
        // "Arrow" isn't a row.
        #expect(PRHistory.rank(exerciseID: "x", name: "Arrow Raise") == 100)

        let curl = session(date(2026, 1, 1), "Barbell_Curl", "Barbell Curl", [set(30, 10)])
        let squat = session(date(2026, 1, 2), "Barbell_Squat", "Back Squat", [set(100, 5)])
        let benchDay = session(date(2026, 1, 3), bench, "Bench Press", [set(60, 5)])
        let order = PRHistory.bests([curl, squat, benchDay], in: nil, events: []).map(\.exerciseID)
        #expect(order == [bench, "Barbell_Squat", "Barbell_Curl"])
    }

    @Test func timelineCountsSessionsWithRecordsPerMonth() {
        let sessions = [
            session(date(2026, 1, 5), bench, "Bench Press", [set(60, 8)]),
            // Three records in one session count once.
            session(date(2026, 1, 12), bench, "Bench Press", [set(65, 8)]),
            session(date(2026, 3, 2), bench, "Bench Press", [set(70, 8)]),
        ]
        let events = PRHistory.events(sessions)
        let now = date(2026, 4, 15)
        let months = PRHistory.timeline(events, interval: PRHistory.Period.thisYear.interval(now: now, calendar: Self.calendar),
                                        now: now, calendar: Self.calendar)
        #expect(months.map(\.count) == [1, 0, 1, 0])
        let allTime = PRHistory.timeline(events, interval: nil, now: now, calendar: Self.calendar)
        #expect(allTime.count == 4)
        #expect(allTime.first?.month == Self.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        #expect(PRHistory.timeline([], interval: nil, now: now, calendar: Self.calendar).isEmpty)
    }
}
