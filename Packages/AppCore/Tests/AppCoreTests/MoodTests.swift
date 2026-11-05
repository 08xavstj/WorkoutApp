import Foundation
import Testing
@testable import AppCore

struct MoodTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let calendar = Calendar(identifier: .gregorian)

    @Test func scaleMapsToValence() {
        #expect(MoodScale.valence(mood: 1) == -0.8)
        #expect(MoodScale.valence(mood: 3) == 0)
        #expect(MoodScale.valence(mood: 5) == 0.8)
        #expect(MoodScale.valence(mood: 9) == 0.8)
        // Stress runs the other way: calm is pleasant.
        #expect(MoodScale.valence(stress: 1) == 0.8)
        #expect(MoodScale.valence(stress: 5) == -0.8)
        #expect(MoodScale.score(valence: -1) == 0)
        #expect(MoodScale.score(valence: 0) == 50)
        #expect(MoodScale.score(valence: 1) == 100)
        #expect(MoodScale.word(valence: -0.8) == "Low")
        #expect(MoodScale.word(valence: 0) == "OK")
        #expect(MoodScale.word(valence: 0.8) == "Great")
    }

    @Test func eveningValenceFallsBackToStress() {
        var evening = EveningCheckIn(day: start)
        #expect(evening.eveningValence == nil)
        evening.stress = 4
        #expect(evening.eveningValence == -0.4)
        evening.mood = 5
        #expect(evening.eveningValence == 0.8)
    }

    @Test func readableNames() {
        #expect(MoodScale.readable("selfCare") == "Self-care")
        #expect(MoodScale.readable("fitness") == "Training")
        #expect(MoodScale.readable("currentEvents") == "Current events")
        #expect(MoodScale.readable("happy") == "Happy")
    }

    @Test func checkInsDecodeWithoutMoodFields() throws {
        // Files written before the mood words existed have no such keys and must still load.
        var old = MorningCheckIn(day: start)
        old.mood = 4
        let json = try String(decoding: JSONEncoder().encode(old), as: UTF8.self)
        #expect(!json.contains("feelings"))
        let decoded = try JSONDecoder().decode(MorningCheckIn.self, from: Data(json.utf8))
        #expect(decoded.mood == 4)
        #expect(decoded.feelings == nil)
        #expect(decoded.associations == nil)
        var morning = MorningCheckIn(day: start)
        morning.feelings = [MoodFeeling.calm.rawValue]
        morning.associations = [MoodAssociation.work.rawValue]
        let roundTrip = try JSONDecoder().decode(MorningCheckIn.self, from: JSONEncoder().encode(morning))
        #expect(roundTrip == morning)
    }

    @Test func healthMoodsWinAndOwnEntriesAreDropped() {
        let day0 = calendar.startOfDay(for: start)
        let day1 = day0.addingTimeInterval(86_400)
        let health = [
            MoodSample(date: day0.addingTimeInterval(9 * 3600), valence: 0.5, kind: .daily, labels: ["joyful"]),
            // The app's own Health copy of its check-in: dropped, the check-in is used instead.
            MoodSample(date: day1.addingTimeInterval(8 * 3600), valence: 0.4, kind: .daily, fromThisApp: true),
        ]
        let checkIns = [
            MoodSample(date: day0.addingTimeInterval(8 * 3600), valence: -0.4, kind: .daily, fromThisApp: true),
            MoodSample(date: day1.addingTimeInterval(8 * 3600), valence: 0.4, kind: .daily, fromThisApp: true),
        ]
        let merged = MoodHistory.merge(health: health, checkIns: checkIns, calendar: calendar)
        #expect(merged.count == 2)
        #expect(merged[0].valence == 0.5)
        #expect(merged[0].labels == ["joyful"])
        #expect(merged[1].valence == 0.4)
        #expect(merged[1].fromThisApp)
    }

    @Test func dailyValencePrefersTheDailyMood() {
        let day0 = calendar.startOfDay(for: start)
        let samples = [
            MoodSample(date: day0.addingTimeInterval(8 * 3600), valence: 0.8, kind: .daily),
            MoodSample(date: day0.addingTimeInterval(20 * 3600), valence: -0.8, kind: .momentary),
            MoodSample(date: day0.addingTimeInterval(86_400 + 12 * 3600), valence: 0.2, kind: .momentary),
            MoodSample(date: day0.addingTimeInterval(86_400 + 18 * 3600), valence: 0.6, kind: .momentary),
        ]
        let days = MoodHistory.dailyValence(samples, calendar: calendar)
        #expect(days.count == 2)
        #expect(days[0].valence == 0.8)
        #expect(abs(days[1].valence - 0.4) < 1e-9)
        #expect(abs((MoodHistory.averageValence(samples, calendar: calendar) ?? 0) - 0.6) < 1e-9)
        #expect(MoodHistory.averageValence([], calendar: calendar) == nil)
    }

    private func days(with factor: (Int, inout CheckInDay) -> Void) -> [CheckInDay] {
        var result: [CheckInDay] = []
        // 8 days each way; the wobble is balanced inside each half so the means are exact.
        for index in 0..<16 {
            let wobble = index.isMultiple(of: 2) ? 0.05 : -0.05
            var day = CheckInDay(morning: start.addingTimeInterval(Double(index) * 86_400), evening: nil, checkIn: nil,
                                 hrv: nil, restingHeartRate: nil, sleepScore: nil,
                                 moodValence: (index < 8 ? 0.4 : -0.2) + wobble)
            factor(index, &day)
            result.append(day)
        }
        return result
    }

    @Test func trainingDaysLiftMood() throws {
        let insights = CheckInInsights.analyze(days { index, day in day.trainedYesterday = index < 8 })
        let mood = try #require(insights.first { $0.factor == "A training day" && $0.outcome == .mood })
        // (0.4 + 1) * 50 = 70 vs (−0.2 + 1) * 50 = 40.
        #expect(abs(mood.percentChange - 75) < 0.001)
        #expect(mood.isGood)
        #expect(mood.sentence == "Mood is 75% higher after a training day")
    }

    @Test func sleepDebtAndHardDaysAsFactors() {
        let debt = CheckInInsights.analyze(days { index, day in day.sleepDebtHours = index < 8 ? 1 : 4 })
        #expect(debt.contains { $0.factor == "3 h+ of sleep debt" && $0.outcome == .mood && !$0.isGood })
        let hard = CheckInInsights.analyze(days { index, day in
            day.strainYesterday = index < 8 ? 30 : 80
            day.usualTrainingStrain = 60
        })
        #expect(hard.contains { $0.factor == "A harder day than usual" && $0.outcome == .mood })
        // Without a usual strain the factor can't be judged, so no insight.
        let unknown = CheckInInsights.analyze(days { index, day in day.strainYesterday = index < 8 ? 30 : 80 })
        #expect(!unknown.contains { $0.factor == "A harder day than usual" })
    }

    @Test func associationsAreFactorsOnlyOnTaggedDays() throws {
        let insights = CheckInInsights.analyze(days { index, day in
            var morning = MorningCheckIn(day: day.morning)
            morning.associations = index < 8 ? [] : [MoodAssociation.work.rawValue]
            day.checkIn = morning
        })
        let work = try #require(insights.first { $0.factor == MoodAssociation.work.factorName && $0.outcome == .mood })
        #expect(!work.isGood)
        #expect(work.sentence.hasSuffix("lower after a day with work on your mind"))
        // Days with no mood answer at all are neither "with" nor "without".
        let untagged = CheckInInsights.analyze(days { _, _ in })
        #expect(!untagged.contains { $0.factor.hasSuffix("on your mind") })
    }
}
