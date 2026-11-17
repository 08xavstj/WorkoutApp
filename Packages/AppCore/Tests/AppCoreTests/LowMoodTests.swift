import Foundation
import Testing
@testable import AppCore

struct LowMoodTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2027-02-`day` at `hour` UTC.
    func date(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: 2, day: day, hour: hour))!
    }

    /// Mood answers for days of February 2027.
    func mornings(_ moods: [Int: Int]) -> [Date: Int] {
        Dictionary(uniqueKeysWithValues: moods.map { (date($0.key), $0.value) })
    }

    func finding(_ moods: [Int: Int], health: [MoodSample] = [], on day: Int) -> LowMoodRule.Finding? {
        LowMoodRule.finding(days: LowMoodRule.days(mornings: mornings(moods), health: health, calendar: calendar),
                            on: date(day, hour: 7), calendar: calendar)
    }

    func checkShape(_ message: CoachCheckIns.Message, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(message.title.count <= CoachCheckIns.maxTitleCharacters, sourceLocation: sourceLocation)
        #expect(message.body.count <= CoachCheckIns.maxBodyCharacters, "body: \(message.body)", sourceLocation: sourceLocation)
        #expect(!message.body.hasSuffix("…"), "cut short: \(message.body)", sourceLocation: sourceLocation)
        let words = Set(CoachIntent.words(message.title + " " + message.body))
        #expect(words.isDisjoint(with: CoachCheckIns.controllingWords), "wording: \(message.body)", sourceLocation: sourceLocation)
    }

    // MARK: Counting

    @Test func twoLowMorningsInAWeekIsNotEnough() {
        #expect(finding([10: 2, 12: 1, 13: 4, 14: 3], on: 14) == nil)
    }

    @Test func threeLowMorningsInAWeekStartsTheRule() throws {
        let found = try #require(finding([9: 2, 11: 1, 14: 2, 12: 4], on: 14))
        #expect(found.lowInWeek == 3)
        #expect(found.weekApplies)
        #expect(!found.fortnightApplies)
    }

    @Test func aLowMorningEightDaysAgoIsOutsideTheWeek() {
        // Days 7 to 13 are the week ending on the 13th; the 6th is outside it.
        #expect(finding([6: 1, 12: 1, 13: 2], on: 13) == nil)
        #expect(finding([7: 1, 12: 1, 13: 2], on: 13) != nil)
    }

    @Test func moodThreeIsNotLowAndTwoIs() {
        #expect(finding([12: 3, 13: 3, 14: 3], on: 14) == nil)
        #expect(finding([12: 2, 13: 2, 14: 2], on: 14)?.lowInWeek == 3)
    }

    @Test func mostlyLowForTwoWeeksNeedsMoreThanHalfOfFourteenDays() throws {
        // Seven low days of fourteen: half, not more than half.
        let seven = try #require(finding([1: 1, 3: 2, 5: 1, 8: 2, 10: 1, 12: 2, 14: 1], on: 14))
        #expect(seven.lowInFortnight == 7)
        #expect(!seven.fortnightApplies)
        let eight = try #require(finding([1: 1, 3: 2, 5: 1, 7: 2, 8: 2, 10: 1, 12: 2, 14: 1], on: 14))
        #expect(eight.lowInFortnight == 8)
        #expect(eight.fortnightApplies)
    }

    @Test func unansweredDaysCountAsNotLow() throws {
        // Five answers in two weeks, all low: the week applies, the fortnight does not.
        let found = try #require(finding([4: 1, 9: 1, 11: 1, 12: 2, 13: 1], on: 14))
        #expect(found.answeredInFortnight == 5)
        #expect(!found.fortnightApplies)
    }

    @Test func healthFillsDaysWithoutACheckInMood() throws {
        let health = [
            // A low daily mood logged in Health in the evening counts for its day.
            MoodSample(date: date(12, hour: 21), valence: -0.6, kind: .daily),
            // Before noon, low.
            MoodSample(date: date(13, hour: 8), valence: -0.5, kind: .momentary),
            // After noon only: not a morning, and no daily mood.
            MoodSample(date: date(11, hour: 15), valence: -0.9, kind: .momentary),
            // This app's own mirror of a check-in is ignored.
            MoodSample(date: date(10, hour: 8), valence: -0.8, kind: .daily, fromThisApp: true),
        ]
        let found = try #require(finding([14: 2], health: health, on: 14))
        #expect(found.lowInWeek == 3)
    }

    @Test func theCheckInWinsOverHealthOnTheSameDay() {
        let health = [MoodSample(date: date(13, hour: 8), valence: -0.9, kind: .daily)]
        // The check-in says "Good" on the 13th, so only two days are low.
        #expect(finding([12: 1, 13: 4, 14: 1], health: health, on: 14) == nil)
    }

    @Test func raiseSentenceIsSaidOnceAWeek() {
        #expect(LowMoodRule.raiseDue(lastRaised: nil, on: date(14), calendar: calendar))
        // The same day's message keeps it when rebuilt.
        #expect(LowMoodRule.raiseDue(lastRaised: date(14, hour: 6), on: date(14, hour: 9), calendar: calendar))
        #expect(!LowMoodRule.raiseDue(lastRaised: date(14), on: date(15), calendar: calendar))
        #expect(!LowMoodRule.raiseDue(lastRaised: date(14), on: date(20), calendar: calendar))
        #expect(LowMoodRule.raiseDue(lastRaised: date(14), on: date(21), calendar: calendar))
        // Written ahead for tomorrow, read today: not due again.
        #expect(!LowMoodRule.raiseDue(lastRaised: date(15), on: date(14), calendar: calendar))
    }

    @Test func pageNoteOnlyAfterTwoWeeks() {
        #expect(LowMoodRule.pageNote(nil) == nil)
        #expect(LowMoodRule.pageNote(.init(lowInWeek: 4, lowInFortnight: 6, answeredInFortnight: 12)) == nil)
        let note = LowMoodRule.pageNote(.init(lowInWeek: 5, lowInFortnight: 9, answeredInFortnight: 13))
        #expect(note?.contains("9 of the last 14 days") == true)
        #expect(note?.contains("someone you trust or your doctor") == true)
    }

    // MARK: The morning message

    var week: LowMoodRule.Finding { .init(lowInWeek: 3, lowInFortnight: 4, answeredInFortnight: 10) }
    var fortnight: LowMoodRule.Finding { .init(lowInWeek: 5, lowInFortnight: 9, answeredInFortnight: 13) }

    func restDay(_ mood: LowMoodRule.Finding?) -> CoachCheckIns.MorningFacts {
        var f = CoachCheckIns.MorningFacts()
        f.recovery = 61
        f.restDay = true
        f.lowMood = mood
        return f
    }

    @Test func aRestDayStaysARestDayWithoutTheRule() throws {
        let message = try #require(CoachCheckIns.morning(restDay(nil)))
        #expect(message.body.contains("a walk or easy mobility is plenty on a rest day"))
        #expect(!message.body.contains("Mood"))
    }

    @Test func aRestDayOffersTheWalkOrAnEasySessionAndSaysWhy() throws {
        let message = try #require(CoachCheckIns.morning(restDay(week)))
        checkShape(message)
        #expect(message.title == "Rest day today")
        #expect(message.body == "Mood has been low on 3 of your last 7 days; moving often lifts it, so a 20-minute walk or an easy session is an option today instead of full rest.")
        #expect(CoachCheckIns.sentenceCount(message.body) == 1)
        // Quiet: no sound, Notification Centre only.
        #expect(message.priority == .low)
    }

    @Test func theOfferCarriesTheCheckInAskWhenItFits() throws {
        var f = restDay(week)
        f.checkInDone = false
        let message = try #require(CoachCheckIns.morning(f))
        checkShape(message)
        #expect(message.body.hasSuffix(CoachCheckIns.morningCheckInAsk))
    }

    @Test func lowRecoveryKeepsTheRestMessage() throws {
        var f = restDay(week)
        f.recovery = 22
        let message = try #require(CoachCheckIns.morning(f))
        #expect(!message.body.contains("Mood"))
        #expect(message.body.contains("rest day"))
        var hrv = restDay(week)
        hrv.hrvBelowNormal = true
        #expect(try #require(CoachCheckIns.morning(hrv)).body.contains("Mood") == false)
    }

    @Test func illnessKeepsTheRestMessage() throws {
        var f = restDay(fortnight)
        f.illnessFlagged = true
        f.lowMoodRaiseDue = true
        let message = try #require(CoachCheckIns.morning(f))
        #expect(!message.body.contains("Mood"))
    }

    @Test func restAfterAHardDayKeepsTheRestMessage() throws {
        var f = restDay(week)
        f.restForRecovery = true
        let message = try #require(CoachCheckIns.morning(f))
        #expect(!message.body.contains("Mood"))
    }

    @Test func restModeSaysNothingAboutMood() {
        var f = restDay(fortnight)
        f.restMode = true
        f.lowMoodRaiseDue = true
        // Rest mode with the check-in done: no message at all.
        #expect(CoachCheckIns.morning(f) == nil)
        f.checkInDone = false
        #expect(CoachCheckIns.morning(f)?.body.contains("Mood") == false)
    }

    @Test func twoWeeksAddsOneSentenceToTheOffer() throws {
        var f = restDay(fortnight)
        f.lowMoodRaiseDue = true
        let message = try #require(CoachCheckIns.morning(f))
        checkShape(message)
        #expect(CoachCheckIns.sentenceCount(message.body) == 2)
        #expect(message.body.contains("9 of your last 14 days"))
        #expect(message.body.contains("a 20-minute walk or an easy session"))
        #expect(message.body.hasSuffix("That long is worth raising with someone you trust or your doctor."))
    }

    @Test func twoWeeksWithoutTheSentenceDueIsJustTheOffer() throws {
        let message = try #require(CoachCheckIns.morning(restDay(fortnight)))
        #expect(CoachCheckIns.sentenceCount(message.body) == 1)
        #expect(!message.body.contains("raising"))
    }

    @Test func onATrainingDayOnlyTheTwoWeekSentenceIsAdded() throws {
        var f = CoachCheckIns.MorningFacts()
        f.recovery = 64
        f.session = .init(name: "Upper", minutes: 60, shortMinutes: 15)
        f.lowMood = week
        // Three low mornings on a training day: the usual message, untouched.
        let usual = try #require(CoachCheckIns.morning(f))
        #expect(!usual.body.contains("Mood"))
        f.lowMood = fortnight
        f.lowMoodRaiseDue = true
        let message = try #require(CoachCheckIns.morning(f))
        checkShape(message)
        #expect(message.title == "Today: Upper · 60 min")
        #expect(message.body.hasPrefix("Recovery is 64%"))
        #expect(message.body.hasSuffix("which is worth raising with someone you trust or your doctor."))
        #expect(!message.body.contains("walk"))
        #expect(message.priority == .normal)
    }

    @Test func theSentenceIsNeverCutShortByALongFirstLine() throws {
        var f = CoachCheckIns.MorningFacts()
        f.recovery = 58
        f.recoveryReason = "resting heart rate: 4 bpm above your normal for this time of the month"
        f.recoveryCalibrated = false
        f.session = .init(name: "Lower", minutes: 75)
        f.lowMood = fortnight
        f.lowMoodRaiseDue = true
        let message = try #require(CoachCheckIns.morning(f))
        checkShape(message)
        #expect(message.body.hasPrefix("Mood has been low on 9 of your last 14 days"))
    }

    // MARK: A realistic month

    @Test func aMonthThatSlidesAndRecovers() {
        // Week 1 fine, week 2 three low mornings, weeks 3-4 mostly low, then better.
        var moods: [Int: Int] = [:]
        for day in 1...7 { moods[day] = 4 }
        for day in 8...14 { moods[day] = [9, 11, 13].contains(day) ? 2 : 3 }
        for day in 15...24 { moods[day] = [17, 22].contains(day) ? 3 : 1 }
        for day in 25...28 { moods[day] = 4 }
        #expect(finding(moods, on: 7) == nil)
        #expect(finding(moods, on: 12) == nil) // two low so far
        #expect(finding(moods, on: 13)?.lowInWeek == 3)
        #expect(finding(moods, on: 13)?.fortnightApplies == false)
        #expect(finding(moods, on: 20)?.fortnightApplies == true) // 3 + 5 low of the last 14
        #expect(finding(moods, on: 24)?.fortnightApplies == true)
        // Two good mornings later the week still holds four low days; after four it lets go.
        #expect(finding(moods, on: 26)?.lowInWeek == 4)
        #expect(finding(moods, on: 28) == nil)
    }
}
