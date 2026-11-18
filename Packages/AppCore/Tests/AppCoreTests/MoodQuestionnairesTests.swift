import Foundation
import Testing
@testable import AppCore

/// PHQ-9 and GAD-7: scoring, bands, the crisis line, when they are offered,
/// and how long a positive screen keeps the workout reminders plain.
struct MoodQuestionnairesTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func day(_ n: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: hour))!.addingTimeInterval(Double(n - 1) * 86_400)
    }

    /// Low on 8 of the last 14 days, 3+ in the last week: the two-week rule applies.
    let fortnight = LowMoodRule.Finding(lowInWeek: 4, lowInFortnight: 8, answeredInFortnight: 12)
    /// Three low mornings this week only.
    let week = LowMoodRule.Finding(lowInWeek: 3, lowInFortnight: 5, answeredInFortnight: 10)

    func phq9(_ answers: [Int], on date: Date? = nil) -> MoodQuestionnaires.Result {
        MoodQuestionnaires.Result(kind: .phq9, date: date ?? day(1), answers: answers)
    }

    // MARK: Forms

    @Test func formsHaveThePublishedItemCounts() {
        #expect(MoodQuestionnaires.Kind.phq9.items.count == 9)
        #expect(MoodQuestionnaires.Kind.gad7.items.count == 7)
        #expect(MoodQuestionnaires.Kind.phq9.maxScore == 27)
        #expect(MoodQuestionnaires.Kind.gad7.maxScore == 21)
        #expect(MoodQuestionnaires.answers.count == 4)
        #expect(MoodQuestionnaires.Kind.phq9.items[MoodQuestionnaires.selfHarmItem].hasPrefix("Thoughts that you would be better off dead"))
    }

    // MARK: Bands

    @Test(arguments: [(0, MoodQuestionnaires.Severity.minimal), (4, .minimal), (5, .mild), (9, .mild), (10, .moderate),
                      (14, .moderate), (15, .moderatelySevere), (19, .moderatelySevere), (20, .severe), (27, .severe)])
    func phq9BandsAtEveryCutPoint(score: Int, expected: MoodQuestionnaires.Severity) {
        #expect(MoodQuestionnaires.severity(.phq9, score: score) == expected)
    }

    @Test(arguments: [(4, MoodQuestionnaires.Severity.minimal), (5, .mild), (9, .mild), (10, .moderate), (14, .moderate),
                      (15, .severe), (21, .severe)])
    func gad7BandsAtEveryCutPoint(score: Int, expected: MoodQuestionnaires.Severity) {
        #expect(MoodQuestionnaires.severity(.gad7, score: score) == expected)
    }

    @Test func scoreIsTheSumOfAnswers() {
        let result = phq9([1, 1, 2, 1, 0, 1, 1, 0, 0])
        #expect(result.isComplete)
        #expect(result.score == 7)
        #expect(result.severity == .mild)
        #expect(result.summary == "PHQ-9: 7 of 27, mild")
        #expect(!result.suggestsDoctor)
        #expect(!result.isPositive)
        #expect(result.meaning.contains("not a diagnosis"))
    }

    @Test func incompleteOrOutOfRangeAnswersAreNotComplete() {
        #expect(!phq9([1, 1, 1]).isComplete)
        #expect(!phq9([1, 1, 1, 1, 1, 1, 1, 1, 4]).isComplete)
    }

    @Test func tenOrMoreSuggestsADoctorCalmly() {
        let nine = phq9([1, 1, 1, 1, 1, 1, 1, 2, 0])
        let ten = phq9([2, 1, 1, 1, 1, 1, 1, 2, 0])
        #expect(nine.score == 9 && !nine.suggestsDoctor)
        #expect(ten.score == 10 && ten.suggestsDoctor && ten.isPositive)
        #expect(ten.meaning.contains("doctor"))
        #expect(ten.meaning.contains("not a diagnosis"))
        let gad = MoodQuestionnaires.Result(kind: .gad7, date: day(1), answers: [2, 2, 2, 1, 1, 1, 1])
        #expect(gad.score == 10 && gad.suggestsDoctor)
    }

    @Test func anyAnswerAboveZeroOnItemNineShowsCrisisWording() {
        // A low total with item 9 at "several days" still counts.
        let result = phq9([0, 1, 0, 0, 0, 0, 0, 0, 1])
        #expect(result.score == 2)
        #expect(result.severity == .minimal)
        #expect(result.selfHarmAnswered)
        #expect(result.isPositive)
        #expect(MoodQuestionnaires.crisisText.contains("988"))
        #expect(MoodQuestionnaires.crisisText.contains("emergency services"))
        // The GAD-7 has no item 9.
        let gad = MoodQuestionnaires.Result(kind: .gad7, date: day(1), answers: [0, 0, 0, 0, 0, 0, 3])
        #expect(!gad.selfHarmAnswered)
    }

    // MARK: When it is offered

    @Test func offeredOnlyOnceTheTwoWeekRuleApplies() {
        #expect(!MoodQuestionnaires.offerDue(lowMood: nil, lastOffered: nil, lastTaken: nil, turnedOff: false, now: day(20), calendar: calendar))
        #expect(!MoodQuestionnaires.offerDue(lowMood: week, lastOffered: nil, lastTaken: nil, turnedOff: false, now: day(20), calendar: calendar))
        #expect(MoodQuestionnaires.offerDue(lowMood: fortnight, lastOffered: nil, lastTaken: nil, turnedOff: false, now: day(20), calendar: calendar))
    }

    @Test func switchedOffInSettingsNeverOffers() {
        #expect(!MoodQuestionnaires.offerDue(lowMood: fortnight, lastOffered: nil, lastTaken: nil, turnedOff: true, now: day(20), calendar: calendar))
    }

    @Test func atMostEveryFourWeeks() {
        let offered = day(1)
        // Stays up for the rest of the day it was first shown.
        #expect(MoodQuestionnaires.offerDue(lowMood: fortnight, lastOffered: offered, lastTaken: nil, turnedOff: false,
                                            now: day(1, hour: 20), calendar: calendar))
        // Gone the next day, and until 28 days have passed.
        #expect(!MoodQuestionnaires.offerDue(lowMood: fortnight, lastOffered: offered, lastTaken: nil, turnedOff: false, now: day(2), calendar: calendar))
        #expect(!MoodQuestionnaires.offerDue(lowMood: fortnight, lastOffered: offered, lastTaken: nil, turnedOff: false, now: day(28), calendar: calendar))
        #expect(MoodQuestionnaires.offerDue(lowMood: fortnight, lastOffered: offered, lastTaken: nil, turnedOff: false, now: day(29), calendar: calendar))
    }

    @Test func takenTodayHidesTheOffer() {
        #expect(!MoodQuestionnaires.offerDue(lowMood: fortnight, lastOffered: day(5), lastTaken: day(5, hour: 10), turnedOff: false,
                                             now: day(5, hour: 18), calendar: calendar))
        // Taken on its own (from the Mood page) also starts the four weeks.
        #expect(!MoodQuestionnaires.offerDue(lowMood: fortnight, lastOffered: nil, lastTaken: day(5), turnedOff: false, now: day(20), calendar: calendar))
    }

    @Test func anxietyQuestionnaireUnderSixtyFiveOnly() {
        #expect(MoodQuestionnaires.kinds(age: 30) == [.phq9, .gad7])
        #expect(MoodQuestionnaires.kinds(age: 64) == [.phq9, .gad7])
        #expect(MoodQuestionnaires.kinds(age: 65) == [.phq9])
    }

    // MARK: Plain reminders

    @Test func aPositiveScreenKeepsRemindersPlainForFourWeeks() {
        let positive = phq9([2, 2, 1, 1, 1, 1, 1, 1, 0], on: day(1))
        #expect(positive.isPositive)
        // Mornings have picked up (no low-mood finding), but the screen was positive.
        #expect(MoodCare.keepPlain(lowMood: nil, screens: [positive], now: day(10), calendar: calendar))
        #expect(MoodCare.keepPlain(lowMood: nil, screens: [positive], now: day(29), calendar: calendar))
        #expect(!MoodCare.keepPlain(lowMood: nil, screens: [positive], now: day(30), calendar: calendar))
        // A minimal screen changes nothing.
        let minimal = phq9([0, 0, 0, 0, 1, 0, 0, 0, 0], on: day(1))
        #expect(!MoodCare.keepPlain(lowMood: nil, screens: [minimal], now: day(10), calendar: calendar))
        // The week rule still keeps it plain by itself.
        #expect(MoodCare.keepPlain(lowMood: week, screens: [], now: day(10), calendar: calendar))
    }

    @Test func aRealisticMonth() {
        // Two low weeks; on day 15 the offer appears and he takes both: PHQ-9 11, GAD-7 6.
        let offerDay = day(15)
        #expect(MoodQuestionnaires.offerDue(lowMood: fortnight, lastOffered: nil, lastTaken: nil, turnedOff: false, now: offerDay, calendar: calendar))
        let phq = phq9([2, 2, 1, 2, 1, 1, 1, 1, 0], on: offerDay)
        let gad = MoodQuestionnaires.Result(kind: .gad7, date: offerDay, answers: [1, 1, 1, 1, 0, 1, 1])
        #expect(phq.score == 11 && phq.severity == .moderate && phq.suggestsDoctor)
        #expect(gad.score == 6 && gad.severity == .mild && !gad.suggestsDoctor)
        // Mornings stay low: no second offer until four weeks on (day 43).
        #expect(!MoodQuestionnaires.offerDue(lowMood: fortnight, lastOffered: offerDay, lastTaken: offerDay, turnedOff: false, now: day(30), calendar: calendar))
        #expect(MoodQuestionnaires.offerDue(lowMood: fortnight, lastOffered: offerDay, lastTaken: offerDay, turnedOff: false, now: day(43), calendar: calendar))
        // The reminders stay plain from the screen until then.
        #expect(MoodCare.keepPlain(lowMood: nil, screens: [phq, gad], now: day(42, hour: 8), calendar: calendar))
    }
}
