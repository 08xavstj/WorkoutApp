import Foundation
import Testing
@testable import AppCore

struct CoachCheckInsTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2027-01-11 (a Monday) at `hour`:`minute` UTC.
    func date(day: Int = 11, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: day, hour: hour, minute: minute))!
    }

    func checkShape(_ message: CoachCheckIns.Message, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(message.title.count <= CoachCheckIns.maxTitleCharacters, "title: \(message.title)", sourceLocation: sourceLocation)
        #expect(message.body.count <= CoachCheckIns.maxBodyCharacters, "body: \(message.body)", sourceLocation: sourceLocation)
        #expect(CoachCheckIns.sentenceCount(message.body) <= 2, "body: \(message.body)", sourceLocation: sourceLocation)
        let words = Set(CoachIntent.words(message.title + " " + message.body))
        #expect(words.isDisjoint(with: CoachCheckIns.controllingWords), "wording: \(message.body)", sourceLocation: sourceLocation)
        #expect(message.link.hasPrefix("\(CoachCheckIns.scheme)://"), sourceLocation: sourceLocation)
    }

    var upper: CoachCheckIns.Session { .init(name: "Upper", minutes: 60, shortMinutes: 15) }

    // MARK: Morning

    @Test func morningWithLowRecoveryOffersTheShortVersionAsAnEqualChoice() throws {
        var f = CoachCheckIns.MorningFacts()
        f.recovery = 25
        f.recoveryReason = "resting heart rate up 5 bpm"
        f.session = upper
        let message = try #require(CoachCheckIns.morning(f))
        checkShape(message)
        #expect(message.title == "Today: easy Upper · 60 min")
        #expect(message.body.contains("Recovery is 25% (resting heart rate up 5 bpm)"))
        #expect(message.body.contains("easy day"))
        #expect(message.body.contains("or the 15-min version"))
        #expect(message.priority == .high)
        #expect(message.link == CoachCheckIns.todayLink)
    }

    @Test func morningWithGoodRecoveryAndSleepDebtGivesTheBedtimeTip() throws {
        var f = CoachCheckIns.MorningFacts()
        f.recovery = 80
        f.session = CoachCheckIns.Session(name: "Lower", minutes: 60)
        f.sleepDebtHours = 3.4
        f.bedByText = "22:00–22:30"
        let message = try #require(CoachCheckIns.morning(f))
        checkShape(message)
        #expect(message.body.contains("a good day for a harder or longer session"))
        #expect(message.body.contains("Sleep debt is 3.5 h; in bed by 22:00–22:30"))
        #expect(message.priority == .normal)
    }

    @Test func morningSaysWhenTheBaselineIsStillBuilding() throws {
        var f = CoachCheckIns.MorningFacts()
        f.recovery = 50
        f.recoveryCalibrated = false
        let message = try #require(CoachCheckIns.morning(f))
        #expect(message.body.contains("baseline still building"))
    }

    @Test func morningAfterAShortNightSuggestsTheCaffeineCutoff() throws {
        var f = CoachCheckIns.MorningFacts()
        f.recovery = 55
        f.sleepHours = 6
        f.sleepNeedHours = 8
        f.caffeineCutoffText = "2:10 pm"
        let message = try #require(CoachCheckIns.morning(f))
        checkShape(message)
        #expect(message.body.contains("last coffee by 2:10 pm"))
    }

    @Test func movedSessionWithoutRecoveryUsesTheWeeksNote() throws {
        var f = CoachCheckIns.MorningFacts()
        f.session = CoachCheckIns.Session(name: "Lower", minutes: 45, shortMinutes: 15, moved: true,
                                          note: "Lower moved to Tue: legs still sore.")
        let message = try #require(CoachCheckIns.morning(f))
        checkShape(message)
        #expect(message.body.hasPrefix("Lower moved to Tue: legs still sore."))
        #expect(message.body.contains("15-min version counts too"))
    }

    @Test func noMorningMessageWhenThereIsNothingToSay() {
        #expect(CoachCheckIns.morning(CoachCheckIns.MorningFacts()) == nil)
        var small = CoachCheckIns.MorningFacts()
        small.sleepDebtHours = 0.5 // under the 1 h worth a mention
        #expect(CoachCheckIns.morning(small) == nil)
    }

    @Test func restModeSendsNoMorningMessage() {
        var f = CoachCheckIns.MorningFacts()
        f.recovery = 20
        f.session = upper
        f.restMode = true
        #expect(CoachCheckIns.morning(f) == nil)
    }

    @Test func restDayDoesNotPushTheSession() throws {
        var f = CoachCheckIns.MorningFacts()
        f.recovery = 70
        f.restDay = true
        f.session = upper
        let message = try #require(CoachCheckIns.morning(f))
        #expect(message.title == "Rest day today")
        #expect(message.body.contains("walk or easy mobility"))
    }

    @Test func sessionFromAnAdaptiveWeekSlot() {
        let slot = AdaptiveWeek.Slot(date: date(hour: 0), session: PlannedDay(weekday: 3, time: 18 * 60, focus: .lower, minutes: 45),
                                     plannedWeekday: 2, isPlannedDay: false, note: "Lower moved to Tue.", easy: true, short: false)
        let session = CoachCheckIns.Session(slot: slot)
        #expect(session.name == "Lower")
        #expect(session.minutes == 45)
        #expect(session.shortMinutes == 15)
        #expect(session.moved)
        #expect(session.easy)
        #expect(session.note == "Lower moved to Tue.")
    }

    // MARK: After a workout

    @Test func postWorkoutLeadsWithTheNewBestAndGivesProteinForTheBodyWeight() throws {
        var f = CoachCheckIns.PostWorkoutFacts(name: "Upper A", minutes: 52, workingSets: 18)
        f.volumeText = "8,450 kg"
        f.recordExercises = ["Bench Press"]
        f.bodyMassKg = 80
        f.nextSession = CoachCheckIns.Session(name: "Lower", minutes: 60)
        f.nextDayText = "tomorrow"
        let message = try #require(CoachCheckIns.postWorkout(f))
        checkShape(message)
        #expect(message.title == "Upper A done: a new best")
        #expect(message.body.contains("18 sets in 52 min, 8,450 kg lifted, with a new best on Bench Press."))
        #expect(message.body.contains("about 25 g of protein")) // 80 kg × 0.3 = 24 → 25 g
        #expect(message.body.contains("next up: Lower tomorrow."))
        #expect(message.priority == .normal)
        #expect(message.question == CoachCheckIns.postWorkoutQuestion)
    }

    @Test func postWorkoutForEnduranceAddsCarbs() throws {
        var f = CoachCheckIns.PostWorkoutFacts(name: "Full body", minutes: 40, workingSets: 12)
        f.goals = Goals(focuses: [.endurance])
        f.progressions = ["Squat +2.5 kg"]
        let message = try #require(CoachCheckIns.postWorkout(f))
        checkShape(message)
        #expect(message.title == "Full body done: 1 lift up")
        #expect(message.body.contains("Squat +2.5 kg since last time"))
        #expect(message.body.contains("carbs and about 30 g of protein"))
    }

    @Test func postWorkoutTurnsToSleepOnceProteinIsCovered() throws {
        var f = CoachCheckIns.PostWorkoutFacts(name: "Pull", minutes: 45, workingSets: 14)
        f.proteinSoFarGrams = 150
        f.proteinTargetGrams = 140
        f.bedByText = "22:30–23:00"
        let message = try #require(CoachCheckIns.postWorkout(f))
        checkShape(message)
        #expect(message.body.contains("sleep is the next lever: in bed by 22:30–23:00"))
        #expect(message.priority == .low)
    }

    @Test func postWorkoutLongNameStillFitsTheTitle() throws {
        var f = CoachCheckIns.PostWorkoutFacts(name: "Heavy lower body with extra hamstrings and calves", minutes: 75, workingSets: 22)
        f.recordExercises = ["Squat", "Deadlift"]
        let message = try #require(CoachCheckIns.postWorkout(f))
        checkShape(message)
        #expect(message.title.hasSuffix("done: 2 new bests"))
    }

    @Test func noPostWorkoutMessageWithoutWorkingSets() {
        #expect(CoachCheckIns.postWorkout(.init(name: "Empty", minutes: 3, workingSets: 0)) == nil)
    }

    @Test func proteinGramsStayInTheTwentyToFortyRange() {
        #expect(CoachCheckIns.postWorkoutProteinGrams(bodyMassKg: nil) == 30)
        #expect(CoachCheckIns.postWorkoutProteinGrams(bodyMassKg: 50) == 20)
        #expect(CoachCheckIns.postWorkoutProteinGrams(bodyMassKg: 100) == 30)
        #expect(CoachCheckIns.postWorkoutProteinGrams(bodyMassKg: 160) == 40)
    }

    // MARK: Evening

    @Test func eveningGivesTheBedByWindowAndTomorrow() throws {
        var f = CoachCheckIns.EveningFacts()
        f.bedByText = "21:50–22:20"
        f.bedByReason = "8 h need, up at 6:30"
        f.tomorrowSession = upper
        let message = try #require(CoachCheckIns.evening(f))
        checkShape(message)
        #expect(message.title == "In bed by 21:50–22:20")
        #expect(message.body.contains("Worked back from 8 h need, up at 6:30, ready for Upper tomorrow."))
        #expect(message.body.contains("45-second check-in"))
        #expect(message.link == CoachCheckIns.eveningCheckInLink)
    }

    @Test func eveningMentionsDrinksWithoutBlame() throws {
        var f = CoachCheckIns.EveningFacts()
        f.bedByText = "22:00–22:30"
        f.drinksToday = 2
        f.checkInDone = true
        let message = try #require(CoachCheckIns.evening(f))
        checkShape(message)
        #expect(message.body.contains("With 2 drinks today"))
        #expect(message.priority == .normal)
        #expect(message.link.hasPrefix("workoutapp://coach"))
    }

    @Test func eveningMentionsLateCaffeine() throws {
        var f = CoachCheckIns.EveningFacts()
        f.tomorrowSession = upper
        f.lateCaffeine = true
        f.checkInDone = true
        let message = try #require(CoachCheckIns.evening(f))
        checkShape(message)
        #expect(message.title == "Tomorrow: Upper · 60 min")
        #expect(message.body.contains("late caffeine"))
    }

    @Test func noEveningMessageWhenNothingIsNew() {
        var f = CoachCheckIns.EveningFacts()
        f.checkInDone = true
        #expect(CoachCheckIns.evening(f) == nil)
    }

    @Test func followUpQuestionsRouteToDataAnswers() {
        for question in [CoachCheckIns.morningQuestion, CoachCheckIns.postWorkoutQuestion, CoachCheckIns.eveningQuestion] {
            #expect(CoachIntent.question(question) != nil, "\(question)")
        }
    }

    @Test func coachLinkCarriesTheQuestion() throws {
        let link = CoachCheckIns.coachLink(question: "How should I train today?")
        let components = try #require(URLComponents(string: link))
        #expect(components.scheme == "workoutapp")
        #expect(components.host == "coach")
        #expect(components.queryItems?.first { $0.name == "q" }?.value == "How should I train today?")
        #expect(CoachCheckIns.coachLink(question: nil) == "workoutapp://coach")
    }

    // MARK: Whether to send

    func sent(_ kind: CoachCheckIns.Kind, _ deliverAt: Date, opened: Bool = false, notified: Bool = true, key: String = "k") -> CoachCheckIns.Sent {
        CoachCheckIns.Sent(kind: kind, deliverAt: deliverAt, notified: notified, opened: opened, key: key)
    }

    func message(_ kind: CoachCheckIns.Kind, body: String = "Body.") -> CoachCheckIns.Message {
        CoachCheckIns.Message(kind: kind, title: "Title", body: body, link: CoachCheckIns.todayLink, question: nil, priority: .normal)
    }

    @Test func backsOffEveningThenMorningAfterUnopenedMessages() {
        let now = date(hour: 12)
        let three = (1...3).map { sent(.morning, date(day: 11 - $0, hour: 8)) }
        #expect(CoachCheckIns.unopenedStreak(three, now: now) == 3)
        #expect(CoachCheckIns.backOff(three, now: now) == .noEvening)
        #expect(CoachCheckIns.delivery(for: message(.evening), at: date(hour: 21), history: three, now: now, calendar: calendar) == .inboxOnly)
        #expect(CoachCheckIns.delivery(for: message(.morning), at: date(day: 12, hour: 8), history: three, now: now, calendar: calendar) == .notify)

        let six = (1...6).map { sent(.evening, date(day: 11 - $0, hour: 21)) }
        #expect(CoachCheckIns.backOff(six, now: now) == .noEveningOrMorning)
        #expect(CoachCheckIns.delivery(for: message(.morning), at: date(day: 12, hour: 8), history: six, now: now, calendar: calendar) == .inboxOnly)
        // A note after your own workout still notifies.
        #expect(CoachCheckIns.delivery(for: message(.postWorkout), at: date(hour: 13), history: six, now: now, calendar: calendar) == .notify)
    }

    @Test func openingOneResetsTheBackOff() {
        let now = date(hour: 12)
        var history = (1...5).map { sent(.morning, date(day: 11 - $0, hour: 8)) }
        history.append(sent(.evening, date(day: 10, hour: 21), opened: true))
        #expect(CoachCheckIns.unopenedStreak(history, now: now) == 0)
        #expect(CoachCheckIns.backOff(history, now: now) == .none)
    }

    @Test func aJustDeliveredMessageIsNotYetIgnored() {
        let now = date(hour: 9)
        let history = (0...2).map { sent(.morning, date(day: 11 - $0, hour: 8)) } // today's was an hour ago
        #expect(CoachCheckIns.unopenedStreak(history, now: now) == 2)
    }

    @Test func oncePerKindADayAndNothingRepeated() {
        let now = date(hour: 12)
        let history = [sent(.morning, date(hour: 8), key: "a")]
        #expect(CoachCheckIns.delivery(for: message(.morning), at: date(hour: 13), history: history, now: now, calendar: calendar) == .skip)
        let yesterday = [sent(.evening, date(day: 10, hour: 21), opened: true, key: message(.evening).key)]
        #expect(CoachCheckIns.delivery(for: message(.evening), at: date(hour: 21), history: yesterday, now: now, calendar: calendar) == .skip)
        #expect(CoachCheckIns.delivery(for: message(.evening, body: "New."), at: date(hour: 21), history: yesterday, now: now, calendar: calendar) == .notify)
    }

    @Test func aPendingMessageOfTheSameKindIsReplacedNotCounted() {
        let now = date(hour: 12)
        let history = [sent(.evening, date(hour: 21), key: "old")]
        #expect(CoachCheckIns.delivery(for: message(.evening), at: date(hour: 21), history: history, now: now, calendar: calendar) == .notify)
    }

    @Test func neverMoreThanThreeADay() {
        let now = date(hour: 22)
        let history = [sent(.morning, date(hour: 8), opened: true), sent(.postWorkout, date(hour: 13), opened: true),
                       sent(.evening, date(hour: 21), opened: true)]
        #expect(CoachCheckIns.delivery(for: message(.postWorkout, body: "Second."), at: date(hour: 22, minute: 20), history: history,
                                       now: now, calendar: calendar) == .skip)
    }

    @Test func aPastFireTimeGoesToTheInboxOnly() {
        let now = date(hour: 12)
        #expect(CoachCheckIns.delivery(for: message(.morning), at: date(hour: 8), history: [], now: now, calendar: calendar) == .inboxOnly)
    }

    // MARK: Timing

    @Test func morningAndEveningTimesFollowSleepOrFallBack() {
        let wake = date(day: 12, hour: 6, minute: 45)
        #expect(CoachCheckIns.morningFire(wake: wake, fallbackDay: date(hour: 0), calendar: calendar) == date(day: 12, hour: 7, minute: 15))
        #expect(CoachCheckIns.morningFire(wake: nil, fallbackDay: date(day: 12, hour: 0), calendar: calendar) == date(day: 12, hour: 7, minute: 30))
        let bed = date(hour: 22, minute: 10)
        #expect(CoachCheckIns.eveningFire(bedByStart: bed, fallbackDay: date(hour: 0), calendar: calendar) == date(hour: 21, minute: 10))
        #expect(CoachCheckIns.eveningFire(bedByStart: nil, fallbackDay: date(hour: 0), calendar: calendar) == date(hour: 21, minute: 30))
    }

    @Test func quietHoursMoveOrDropMessages() {
        let quiet = CoachCheckIns.defaultQuietHours // 22:00-07:00
        #expect(quiet.contains(23 * 60))
        #expect(quiet.contains(6 * 60 + 59))
        #expect(!quiet.contains(7 * 60))
        #expect(!quiet.contains(21 * 60))
        // Morning at 6:30 waits until 7:00.
        #expect(CoachCheckIns.outsideQuietHours(date(hour: 6, minute: 30), kind: .morning, quiet: quiet, calendar: calendar) == date(hour: 7))
        // Evening at 22:40 comes at 21:45 instead.
        #expect(CoachCheckIns.outsideQuietHours(date(hour: 22, minute: 40), kind: .evening, quiet: quiet, calendar: calendar) == date(hour: 21, minute: 45))
        // Evening after midnight: no notification.
        #expect(CoachCheckIns.outsideQuietHours(date(hour: 0, minute: 30), kind: .evening, quiet: quiet, calendar: calendar) == nil)
        // A workout note at 23:00 isn't sent; at 20:00 it is.
        #expect(CoachCheckIns.outsideQuietHours(date(hour: 23), kind: .postWorkout, quiet: quiet, calendar: calendar) == nil)
        #expect(CoachCheckIns.outsideQuietHours(date(hour: 20), kind: .postWorkout, quiet: quiet, calendar: calendar) == date(hour: 20))
        #expect(CoachCheckIns.outsideQuietHours(date(hour: 23), kind: .postWorkout, quiet: nil, calendar: calendar) == date(hour: 23))
    }

    // MARK: Rewording

    @Test func acceptsAFaithfulRewordInTheAppsWords() {
        let original = "Recovery is 72%: normal, so your usual session suits. If the day gets tight, the 15-min version counts too."
        let reworded = CoachCheckIns.acceptRephrase("\"Readiness score is 72% today, so your usual session fits, or the 15-min version if time is short.\"", of: original)
        #expect(reworded == "Recovery is 72% today, so your usual session fits, or the 15-min version if time is short.")
    }

    @Test func rejectsNewNumbersControllingWordsAndLongText() {
        let original = "Recovery is 72%: normal, so your usual session suits."
        #expect(CoachCheckIns.acceptRephrase("Recovery is 75%, a normal day.", of: original) == nil)
        #expect(CoachCheckIns.acceptRephrase("Recovery is 72%, so you should train.", of: original) == nil)
        #expect(CoachCheckIns.acceptRephrase("Okay.", of: original) == nil)
        #expect(CoachCheckIns.acceptRephrase("One. Two. Three sentences is too many here.", of: original) == nil)
        #expect(CoachCheckIns.acceptRephrase(String(repeating: "word ", count: 60), of: original) == nil)
    }
}
