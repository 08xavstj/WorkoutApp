import Foundation
import Testing
@testable import AppCore

struct MoodScreenTests {
    let now = Date(timeIntervalSinceReferenceDate: 820_000_000)

    func days(_ count: Double) -> Date { now.addingTimeInterval(count * 86_400) }

    func answers(_ a: MoodScreen.Answer, _ b: MoodScreen.Answer, _ c: MoodScreen.Answer, _ d: MoodScreen.Answer) -> [MoodScreen.Item: MoodScreen.Answer] {
        [.littleInterest: a, .feelingDown: b, .nervous: c, .worrying: d]
    }

    // MARK: Wording (checked against phqscreeners.com on 17 Nov 2026; must not drift)

    @Test func itemsAndAnswersAreTheFormsOwnWords() {
        #expect(MoodScreen.stem == "Over the last 2 weeks, how often have you been bothered by the following problems?")
        #expect(MoodScreen.Item.allCases.map(\.text) == [
            "Little interest or pleasure in doing things",
            "Feeling down, depressed, or hopeless",
            "Feeling nervous, anxious or on edge",
            "Not being able to stop or control worrying",
        ])
        #expect(MoodScreen.Answer.allCases.map(\.title) == ["Not at all", "Several days", "More than half the days", "Nearly every day"])
        #expect(MoodScreen.Answer.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(MoodScreen.Item.allCases.map(\.scale) == [.phq2, .phq2, .gad2, .gad2])
        #expect(MoodScreen.cutoff == 3)
    }

    // MARK: Scoring

    @Test func noResultUntilAllFourAreAnswered() {
        var partial = answers(.notAtAll, .severalDays, .notAtAll, .notAtAll)
        partial[.worrying] = nil
        #expect(MoodScreen.result(answers: partial, date: now) == nil)
        #expect(MoodScreen.result(answers: [:], date: now) == nil)
    }

    @Test func eachPairIsScoredSeparately() throws {
        let result = try #require(MoodScreen.result(answers: answers(.severalDays, .moreThanHalfTheDays, .notAtAll, .severalDays), date: now))
        #expect(result.phq2 == 3)
        #expect(result.gad2 == 1)
        #expect(result.depressionPositive)
        #expect(!result.anxietyPositive)
        #expect(result.isPositive)
        #expect(result.source == .app)
    }

    @Test func twoIsBelowTheLineAndThreeIsOnIt() throws {
        let two = try #require(MoodScreen.result(answers: answers(.severalDays, .severalDays, .severalDays, .severalDays), date: now))
        #expect(two.phq2 == 2 && two.gad2 == 2)
        #expect(!two.isPositive)
        #expect(MoodScreen.line(.phq2, in: two) == "2 of 6 · below the screening line (3)")
        #expect(MoodScreen.suggestion(for: two) == nil)
        let three = try #require(MoodScreen.result(answers: answers(.notAtAll, .notAtAll, .nearlyEveryDay, .notAtAll), date: now))
        #expect(three.gad2 == 3)
        #expect(three.anxietyPositive && !three.depressionPositive)
        #expect(MoodScreen.line(.gad2, in: three) == "3 of 6 · at or above the screening line (3)")
    }

    @Test func extremes() throws {
        let none = try #require(MoodScreen.result(answers: answers(.notAtAll, .notAtAll, .notAtAll, .notAtAll), date: now))
        #expect(none.phq2 == 0 && none.gad2 == 0)
        let all = try #require(MoodScreen.result(answers: answers(.nearlyEveryDay, .nearlyEveryDay, .nearlyEveryDay, .nearlyEveryDay), date: now))
        #expect(all.phq2 == 6 && all.gad2 == 6)
        #expect(MoodScreen.suggestion(for: all)?.hasPrefix("Both pairs are") == true)
    }

    @Test func aPositiveScreenGetsOneCalmSuggestionAndNoDiagnosis() throws {
        let result = try #require(MoodScreen.result(answers: answers(.moreThanHalfTheDays, .moreThanHalfTheDays, .notAtAll, .notAtAll), date: now))
        let suggestion = try #require(MoodScreen.suggestion(for: result))
        #expect(suggestion.contains("your doctor"))
        #expect(suggestion.contains("someone you trust"))
        for word in ["depressed", "depression", "disorder", "you have", "must", "should"] {
            #expect(!suggestion.lowercased().contains(word), "suggestion says \(word)")
        }
        #expect(MoodScreen.notADiagnosis.contains("not a diagnosis"))
        #expect(MoodScreen.crisisText.contains("988"))
        #expect(MoodScreen.crisisText.contains("local emergency services"))
    }

    @Test func fullFormsFromAppleHealthUseTheirOwnLine() {
        // A PHQ-9 of 11 with low first two answers is still a positive screen.
        let phq9 = MoodScreen.Result(date: now, source: .appleHealth, phq2: 2, phq9: 11)
        #expect(phq9.depressionPositive)
        #expect(!phq9.anxietyPositive)
        let gad7 = MoodScreen.Result(date: now, source: .appleHealth, gad2: 1, gad7: 9)
        #expect(!gad7.isPositive)
        #expect(MoodScreen.line(.phq2, in: gad7) == nil)
        #expect(MoodScreen.Result(date: now, source: .appleHealth, gad2: 1, gad7: 10).anxietyPositive)
    }

    @Test func resultsSurviveARoundTrip() throws {
        let results = [MoodScreen.Result(date: now, phq2: 1, gad2: 4), MoodScreen.Result(date: days(-40), source: .appleHealth, phq2: 0, phq9: 3)]
        let data = try JSONEncoder().encode(results)
        #expect(try JSONDecoder().decode([MoodScreen.Result].self, from: data) == results)
    }

    // MARK: Monthly offer

    @Test func offeredOnceAMonth() {
        let last = [MoodScreen.Result(date: now, phq2: 0, gad2: 0)]
        #expect(MoodScreen.isDue(enabled: true, results: [], notNowUntil: nil, now: now))
        #expect(!MoodScreen.isDue(enabled: true, results: last, notNowUntil: nil, now: days(1)))
        #expect(!MoodScreen.isDue(enabled: true, results: last, notNowUntil: nil, now: days(29.9)))
        #expect(MoodScreen.isDue(enabled: true, results: last, notNowUntil: nil, now: days(30)))
    }

    @Test func switchedOffIsNeverDue() {
        #expect(!MoodScreen.isDue(enabled: false, results: [], notNowUntil: nil, now: now))
        #expect(!MoodScreen.isDue(enabled: false, results: [MoodScreen.Result(date: days(-200), phq2: 0, gad2: 0)], notNowUntil: nil, now: now))
    }

    @Test func notThisMonthPutsItOffAWeek() {
        let until = now.addingTimeInterval(Double(MoodScreen.notNowDays) * 86_400)
        #expect(!MoodScreen.isDue(enabled: true, results: [], notNowUntil: until, now: days(6.9)))
        #expect(MoodScreen.isDue(enabled: true, results: [], notNowUntil: until, now: days(7.1)))
    }

    @Test func aQuestionnaireFilledInAppleHealthCountsAsThisMonths() {
        let results = [
            MoodScreen.Result(date: days(-45), phq2: 0, gad2: 0),
            MoodScreen.Result(date: days(-3), source: .appleHealth, phq2: 1, phq9: 4),
        ]
        #expect(!MoodScreen.isDue(enabled: true, results: results, notNowUntil: nil, now: now))
        #expect(MoodScreen.latest(results)?.source == .appleHealth)
    }

    // MARK: A year of monthly screens

    @Test func aYearOfScreens() throws {
        var results: [MoodScreen.Result] = []
        var offered = 0
        // Walk a year a day at a time; answer whenever it is offered. Months 5 and 6 are rough.
        for day in 0..<365 {
            let today = days(Double(day))
            guard MoodScreen.isDue(enabled: true, results: results, notNowUntil: nil, now: today) else { continue }
            offered += 1
            let rough = (120..<190).contains(day)
            let picked = rough ? answers(.moreThanHalfTheDays, .severalDays, .severalDays, .severalDays)
                               : answers(.notAtAll, .severalDays, .notAtAll, .notAtAll)
            results.append(try #require(MoodScreen.result(answers: picked, date: today)))
        }
        // Every 30 days: day 0, 30, … 360.
        #expect(offered == 13)
        #expect(results.filter(\.isPositive).count == 3) // days 120, 150, 180
        #expect(MoodScreen.latest(results)?.isPositive == false)
    }

    // MARK: Playful tone flag

    func scratchDefaults() -> UserDefaults {
        let name = "MoodScreenTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func playfulIsAllowedByDefault() {
        #expect(PlayfulTone.isAllowed(now: now, defaults: scratchDefaults()))
    }

    @Test func aPositiveScreenPausesJokesUntilANegativeOne() {
        let defaults = scratchDefaults()
        PlayfulTone.noteScreen(MoodScreen.Result(date: now, phq2: 4, gad2: 0), defaults: defaults)
        #expect(!PlayfulTone.isAllowed(now: now, defaults: defaults))
        #expect(!PlayfulTone.isAllowed(now: days(59), defaults: defaults))
        // Runs out by itself if no later screen is taken.
        #expect(PlayfulTone.isAllowed(now: days(61), defaults: defaults))
        // A later negative screen clears it at once.
        PlayfulTone.noteScreen(MoodScreen.Result(date: days(30), phq2: 1, gad2: 2), defaults: defaults)
        #expect(PlayfulTone.isAllowed(now: days(30), defaults: defaults))
    }

    @Test func anxietyAloneAlsoPausesJokes() {
        let defaults = scratchDefaults()
        PlayfulTone.noteScreen(MoodScreen.Result(date: now, phq2: 0, gad2: 3), defaults: defaults)
        #expect(!PlayfulTone.isAllowed(now: days(1), defaults: defaults))
    }

    @Test func twoLowWeeksPauseJokesForAWeekPastTheLastLowDay() {
        let defaults = scratchDefaults()
        PlayfulTone.noteLowMood(false, now: now, defaults: defaults)
        #expect(PlayfulTone.isAllowed(now: now, defaults: defaults))
        PlayfulTone.noteLowMood(true, now: now, defaults: defaults)
        #expect(!PlayfulTone.isAllowed(now: days(6), defaults: defaults))
        // The rule stopped holding: nothing renews it, and it runs out.
        PlayfulTone.noteLowMood(false, now: days(3), defaults: defaults)
        #expect(!PlayfulTone.isAllowed(now: days(6), defaults: defaults))
        #expect(PlayfulTone.isAllowed(now: days(8), defaults: defaults))
    }

    @Test func aNegativeScreenDoesNotLiftTheLowMoodPause() {
        let defaults = scratchDefaults()
        PlayfulTone.noteLowMood(true, now: now, defaults: defaults)
        PlayfulTone.noteScreen(MoodScreen.Result(date: now, phq2: 0, gad2: 0), defaults: defaults)
        #expect(!PlayfulTone.isAllowed(now: days(1), defaults: defaults))
    }

    @Test func theCoachLineCarriesToneOnly() {
        let line = PlayfulTone.coachToneLine.lowercased()
        for word in ["screen", "phq", "gad", "depress", "anxi", "mood", "score"] {
            #expect(!line.contains(word), "tone line says \(word)")
        }
        #expect(CoachPromptVocabulary.neutral(PlayfulTone.coachToneLine) != nil)
    }
}
