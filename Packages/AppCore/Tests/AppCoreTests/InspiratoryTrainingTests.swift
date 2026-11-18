import Foundation
import Testing
@testable import AppCore

struct InspiratoryTrainingTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Two readings morning and evening for `days` days ending `endDaysAgo` before `now`.
    func week(systolic: Double, days: Int = 7, endDaysAgo: Int = 0, now: Date) -> [HomeBloodPressure.Reading] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).flatMap { offset -> [HomeBloodPressure.Reading] in
            let day = calendar.date(byAdding: .day, value: -(offset + endDaysAgo), to: today)!
            return [7.5, 7.55, 20.0, 20.05].map { hours in
                .init(date: day.addingTimeInterval(hours * 3600), systolic: systolic, diastolic: 78)
            }
        }
    }

    var now: Date { calendar.date(from: DateComponents(year: 2027, month: 3, day: 7, hour: 21))! }

    @Test func offeredAtOrAboveTheThreshold() {
        #expect(InspiratoryTraining.eligibility(week(systolic: 120, now: now), now: now, calendar: calendar).isOffered)
        #expect(InspiratoryTraining.eligibility(week(systolic: 131, now: now), now: now, calendar: calendar).isOffered)
    }

    @Test func neverBelowTheThreshold() {
        let result = InspiratoryTraining.eligibility(week(systolic: 119, now: now), now: now, calendar: calendar)
        #expect(!result.isOffered)
        guard case .belowThreshold(let average) = result else {
            Issue.record("expected below threshold")
            return
        }
        #expect(average.systolic == 119)
    }

    func sessions(daysAgo: [Int]) -> [InspiratoryTraining.Session] {
        let today = calendar.startOfDay(for: now)
        return daysAgo.map { .init(date: calendar.date(byAdding: .day, value: -$0, to: today)!.addingTimeInterval(8 * 3600), breaths: 30) }
    }

    @Test func someoneTrainingKeepsItWhenTheAverageDrops() {
        // Started at 128, now 116 while training: the drop may be the training.
        var readings = week(systolic: 128, endDaysAgo: 45, now: now)
        readings += week(systolic: 116, now: now)
        let training = sessions(daysAgo: Array(0..<30))
        let result = InspiratoryTraining.eligibility(readings, sessions: training, now: now, calendar: calendar)
        #expect(result.isOffered)
        #expect(result == .continuing(result.average))
        #expect(result.average?.systolic == 116)
        // Stopped three weeks ago: no longer offered below 120.
        let stopped = sessions(daysAgo: Array(21..<50))
        #expect(!InspiratoryTraining.eligibility(readings, sessions: stopped, now: now, calendar: calendar).isOffered)
        // A half session doesn't count as training.
        let half = [InspiratoryTraining.Session(date: now.addingTimeInterval(-3600), breaths: 12)]
        #expect(!InspiratoryTraining.eligibility(readings, sessions: half, now: now, calendar: calendar).isOffered)
        // Training with no recent average stays too.
        #expect(InspiratoryTraining.eligibility([], sessions: training, now: now, calendar: calendar) == .continuing(nil))
    }

    @Test func averagesOlderThanThreeMonthsDontCount() {
        #expect(InspiratoryTraining.maxAverageAgeDays == 91)
        #expect(InspiratoryTraining.eligibility(week(systolic: 128, endDaysAgo: 80, now: now), now: now, calendar: calendar).isOffered)
        #expect(InspiratoryTraining.eligibility(week(systolic: 128, endDaysAgo: 100, now: now), now: now, calendar: calendar) == .noAverage)
    }

    @Test func stageTwoAndVeryHighLeadWithTheDoctor() {
        func doctorFirst(_ systolic: Double, diastolic: Double = 78) -> Bool {
            let readings = week(systolic: systolic, now: now).map {
                HomeBloodPressure.Reading(date: $0.date, systolic: systolic, diastolic: diastolic)
            }
            return InspiratoryTraining.eligibility(readings, now: now, calendar: calendar).seeDoctorFirst
        }
        #expect(!doctorFirst(125))
        #expect(!doctorFirst(135))
        #expect(doctorFirst(142))
        #expect(doctorFirst(125, diastolic: 92))
        #expect(doctorFirst(185))
        // Below the threshold it isn't offered at all, so there's no card to lead.
        #expect(!doctorFirst(115))
    }

    @Test func neverWithoutAReliableAverage() {
        #expect(InspiratoryTraining.eligibility([], now: now, calendar: calendar) == .noAverage)
        // Two days of readings: under the 12 a home average needs.
        let short = week(systolic: 140, days: 2, now: now)
        #expect(InspiratoryTraining.eligibility(short, now: now, calendar: calendar) == .noAverage)
    }

    @Test func aWeekStillFillingDoesNotHideTheLastFullOne() {
        // A full week at 128 ending 20 days ago, then two new readings today.
        var readings = week(systolic: 128, endDaysAgo: 20, now: now)
        readings += week(systolic: 110, days: 1, now: now).prefix(2)
        let result = InspiratoryTraining.eligibility(readings, now: now, calendar: calendar)
        #expect(result.isOffered)
    }

    @Test func aNewerNormalWeekWins() {
        var readings = week(systolic: 128, endDaysAgo: 30, now: now)
        readings += week(systolic: 116, now: now)
        #expect(!InspiratoryTraining.eligibility(readings, now: now, calendar: calendar).isOffered)
    }

    @Test func averagesOverAYearOldDontCount() {
        let readings = week(systolic: 135, endDaysAgo: 400, now: now)
        #expect(InspiratoryTraining.eligibility(readings, now: now, calendar: calendar) == .noAverage)
    }

    @Test func log() {
        let today = calendar.startOfDay(for: now)
        let sessions = (0..<9).map { offset in
            InspiratoryTraining.Session(date: calendar.date(byAdding: .day, value: -offset, to: today)!.addingTimeInterval(8 * 3600),
                                        breaths: offset == 2 ? 18 : 30)
        }
        #expect(InspiratoryTraining.fullDaysThisWeek(sessions, now: now, calendar: calendar) == 6)
        #expect(InspiratoryTraining.doneToday(sessions, now: now, calendar: calendar))
        #expect(InspiratoryTraining.fullDays(sessions, calendar: calendar) == 8)
        #expect(!InspiratoryTraining.doneToday([], now: now, calendar: calendar))
    }
}
