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
        #expect(message.body == "Mood has been low on 3 of your last 7 days; moving often helps, so a 20-minute walk or an easy session is an option today instead of full rest.")
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

    @Test func theModelNeverRewordsALowMoodMessage() throws {
        #expect(CoachCheckIns.mayReword(try #require(CoachCheckIns.morning(restDay(nil)))))
        #expect(!CoachCheckIns.mayReword(try #require(CoachCheckIns.morning(restDay(week)))))
        var f = restDay(fortnight)
        f.lowMoodRaiseDue = true
        #expect(!CoachCheckIns.mayReword(try #require(CoachCheckIns.morning(f))))
        var training = CoachCheckIns.MorningFacts()
        training.recovery = 64
        training.session = .init(name: "Upper", minutes: 60)
        training.lowMood = fortnight
        training.lowMoodRaiseDue = true
        #expect(!CoachCheckIns.mayReword(try #require(CoachCheckIns.morning(training))))
    }

    // MARK: Before the morning's recovery is in

    @Test func noWalkOfferBeforeRecoveryIsIn() throws {
        // Early morning: a rest day and a low week, but no recovery yet, so neither a low
        // score nor HRV below normal can be ruled out. With sleep debt the usual message stands.
        var f = restDay(week)
        f.recovery = nil
        f.sleepDebtHours = 5
        f.bedByText = "22:00–22:30"
        let message = try #require(CoachCheckIns.morning(f))
        #expect(!message.body.contains("instead of full rest"))
        #expect(!message.body.contains("Mood"))
        #expect(message.body.contains("Sleep debt is 5 h"))
        // Without debt there is nothing to say, and nothing about mood either.
        f.sleepDebtHours = nil
        #expect(CoachCheckIns.morning(f) == nil)
        // Recovery in, HRV below normal: still no offer.
        f.recovery = 70
        f.hrvBelowNormal = true
        #expect(try #require(CoachCheckIns.morning(f)).body.contains("Mood") == false)
    }

    @Test func theTwoWeekSentenceReachesAQuietMorning() throws {
        // A message written the evening before: no recovery, no session, no debt.
        var f = CoachCheckIns.MorningFacts()
        f.lowMood = fortnight
        f.lowMoodRaiseDue = true
        let message = try #require(CoachCheckIns.morning(f))
        checkShape(message)
        #expect(message.body == "Mood has been low on 9 of your last 14 days, which is worth raising with someone you trust or your doctor.")
        #expect(CoachCheckIns.raisesLowMood(message))
        #expect(!message.body.contains("walk"))
        // The same on a rest day before recovery is in: the sentence, never the offer.
        f.restDay = true
        let rest = try #require(CoachCheckIns.morning(f))
        #expect(CoachCheckIns.raisesLowMood(rest))
        #expect(!rest.body.contains("walk"))
        // Not due: nothing to say, so no message (and the app saves no raise day).
        f.lowMoodRaiseDue = false
        #expect(CoachCheckIns.morning(f) == nil)
        #expect(!CoachCheckIns.raisesLowMood(CoachCheckIns.morning(f)))
    }

    @Test func onlyAMessageThatSaysTheSentenceCountsAsRaised() throws {
        // The offer alone doesn't use up the week; offer plus sentence does.
        #expect(!CoachCheckIns.raisesLowMood(try #require(CoachCheckIns.morning(restDay(week)))))
        var f = restDay(fortnight)
        f.lowMoodRaiseDue = true
        #expect(CoachCheckIns.raisesLowMood(try #require(CoachCheckIns.morning(f))))
        // Illness keeps it out, so it isn't counted.
        f.illnessFlagged = true
        #expect(!CoachCheckIns.raisesLowMood(try #require(CoachCheckIns.morning(f))))
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

    // MARK: Plain workout reminders while mornings run low

    func reminderFacts(lowMood: LowMoodRule.Finding?) -> WorkoutBanter.Facts {
        var facts = WorkoutBanter.Facts()
        facts.sessionName = "Upper A"
        facts.sessionMinutes = 60
        facts.shortMinutes = 25
        facts.leadMinutes = 30
        facts.sessionsDone = 2
        facts.sessionsPlanned = 4
        facts.weeksInARow = 5
        facts.hour = 18
        facts.weekday = 3
        facts.recovery = .high
        facts.keepPlain = MoodCare.keepPlain(lowMood: lowMood)
        return facts
    }

    @Test func keepPlainFollowsTheWeekRule() {
        #expect(!MoodCare.keepPlain(lowMood: nil))
        #expect(MoodCare.keepPlain(lowMood: week))
        #expect(MoodCare.keepPlain(lowMood: fortnight))
        // A finding exists only from three low mornings, but a hand-made two never counts.
        let two = LowMoodRule.Finding(lowInWeek: 2, lowInFortnight: 8, answeredInFortnight: 14)
        #expect(MoodCare.keepPlain(lowMood: two) == false)
    }

    @Test func threeLowMorningsMakeEveryReminderPlainWhateverTheTone() {
        let playful = reminderFacts(lowMood: nil)
        #expect(playful.caution == nil)
        #expect(WorkoutBanter.pick(facts: playful, tone: .playful, history: .init(), seed: 1).register != WorkoutBanter.Register.plain.rawValue)

        let facts = reminderFacts(lowMood: week)
        #expect(facts.caution == .keepPlain)
        #expect(WorkoutBanter.situations(for: facts) == [.keepPlain])
        for tone in WorkoutBanter.Tone.allCases {
            for seed in 0..<30 {
                let pick = WorkoutBanter.pick(facts: facts, tone: tone, history: .init(), seed: UInt64(seed))
                #expect(pick.register == WorkoutBanter.Register.plain.rawValue)
                #expect(pick.situation == WorkoutBanter.Situation.keepPlain.rawValue)
                #expect(WorkoutBanterGuard.problems(in: pick.text, facts: facts).isEmpty, "\(pick.text)")
            }
        }
        // The on-device model is never asked for a line then.
        let assigned = WorkoutBanter.Assigned(dayKey: "2027-02-14", fire: date(14, hour: 17),
                                              pick: WorkoutBanter.pick(facts: facts, tone: .playful, history: .init(), seed: 3),
                                              tone: .playful, ahead: false)
        #expect(!WorkoutBanter.wantsGenerated(assigned, facts: facts))
    }

    @Test func theReminderNeverSaysWhyItIsPlain() {
        for line in WorkoutBanterLibrary.all where line.situation == .keepPlain {
            let text = line.template.lowercased()
            for word in ["mood", "low", "sad", "down", "feel", "mental", "check-in", "morning"] {
                #expect(!text.contains(word), "\(line.id) says \(word)")
            }
        }
    }

    @Test func saferStatesStillWinAndTheLastCallIsStillSaid() {
        var facts = reminderFacts(lowMood: week)
        facts.recovery = .low
        #expect(facts.caution == .lowRecovery)
        facts.recovery = .normal
        facts.isRestDay = true
        #expect(facts.caution == .restDay)
        facts.isRestDay = false
        facts.lastCall = true
        // The last call keeps its own (plain) words, so reminders still say they go quiet.
        #expect(WorkoutBanter.situations(for: facts) == [.lastCall])
        let pick = WorkoutBanter.pick(facts: facts, tone: .playful, history: .init(), seed: 7)
        #expect(pick.situation == WorkoutBanter.Situation.lastCall.rawValue)
        #expect(pick.register == WorkoutBanter.Register.plain.rawValue)
    }

    @Test func aPendingPlayfulLineIsReplacedOnceMorningsRunLow() {
        let fire = date(14, hour: 17)
        let request = { (facts: WorkoutBanter.Facts) in
            [WorkoutBanter.DayRequest(dayKey: "2027-02-14", fire: fire, facts: facts, isToday: true)]
        }
        let before = WorkoutBanter.reconcile(.init(), requests: request(reminderFacts(lowMood: nil)), tone: .playful, now: date(14, hour: 7))
        #expect(before.pending.first?.pick.register != WorkoutBanter.Register.plain.rawValue)
        let after = WorkoutBanter.reconcile(before, requests: request(reminderFacts(lowMood: week)), tone: .playful, now: date(14, hour: 8))
        #expect(after.pending.first?.pick.register == WorkoutBanter.Register.plain.rawValue)
        #expect(after.pending.first?.pick.situation == WorkoutBanter.Situation.keepPlain.rawValue)
    }
}
