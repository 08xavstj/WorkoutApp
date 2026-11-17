import Foundation
import Testing
@testable import AppCore

struct SessionFeelTests {
    let start = Date(timeIntervalSinceReferenceDate: 820_000_000)

    func day(_ offset: Double) -> Date { start.addingTimeInterval(offset * 86_400) }

    func entries(_ feels: [(Double, SessionFeel)]) -> [SessionFeelEntry] {
        feels.map { SessionFeelEntry(sessionStart: day($0.0), feel: $0.1) }
    }

    // MARK: Scale

    @Test func fiveWordsOnTheGoodBadLine() {
        #expect(SessionFeel.allCases.map(\.rawValue) == [-5, -3, 0, 3, 5])
        #expect(SessionFeel.allCases.map(\.step) == [1, 2, 3, 4, 5])
        #expect(SessionFeel(step: 4) == .good)
        #expect(SessionFeel(step: 0) == nil)
        #expect(SessionFeel(step: 6) == nil)
        #expect(SessionFeel.neutral.isBad == false && SessionFeel.neutral.isGood == false)
    }

    @Test func theQuestionAsksAboutTheSessionWhileItHappened() {
        #expect(SessionFeel.question.contains("while you were lifting"))
        // Effort has its own rating; this is not it.
        #expect(SessionFeel.hint.contains("Not how hard"))
    }

    @Test func entriesSurviveARoundTrip() throws {
        let entry = SessionFeelEntry(sessionStart: day(1), feel: .bad)
        let data = try JSONEncoder().encode([entry])
        #expect(try JSONDecoder().decode([SessionFeelEntry].self, from: data) == [entry])
    }

    // MARK: Trend

    @Test func fewerThanFourRatingsSaysNothing() {
        #expect(SessionFeelTrend.recent(entries([(1, .bad), (8, .bad), (20, .veryBad)]), now: day(21)) == nil)
    }

    @Test func badForWeeksNeedsHalfBadAcrossTwoWeeks() throws {
        let bad = entries([(1, .bad), (5, .veryBad), (9, .neutral), (16, .bad), (20, .good)])
        let summary = try #require(SessionFeelTrend.recent(bad, now: day(21)))
        #expect(summary.rated == 5)
        #expect(summary.bad == 3)
        #expect(summary.spanDays == 19)
        #expect(summary.feltBad)
        #expect(summary.text == "Felt bad in 3 of your last 5 rated sessions.")
        #expect(SessionFeelTrend.feltBadForWeeks(bad, now: day(21)))
    }

    @Test func oneBadWeekIsNotWeeks() throws {
        // Four bad sessions inside six days: bad, but not for weeks.
        let week = entries([(15, .bad), (17, .bad), (19, .veryBad), (21, .bad)])
        let summary = try #require(SessionFeelTrend.recent(week, now: day(21)))
        #expect(summary.spanDays == 6)
        #expect(!summary.feltBad)
    }

    @Test func exactlyFourteenDaysApartCounts() throws {
        let edge = entries([(7, .bad), (10, .bad), (14, .neutral), (21, .bad)])
        #expect(try #require(SessionFeelTrend.recent(edge, now: day(21))).feltBad)
        let short = entries([(8, .bad), (10, .bad), (14, .neutral), (21, .bad)])
        #expect(try #require(SessionFeelTrend.recent(short, now: day(21))).feltBad == false)
    }

    @Test func halfBadButGoodOnAverageIsMixed() throws {
        // Two bad, two very good: average +1, so not "felt bad".
        let mixed = entries([(1, .bad), (8, .veryGood), (15, .bad), (20, .veryGood)])
        let summary = try #require(SessionFeelTrend.recent(mixed, now: day(21)))
        #expect(!summary.feltBad)
        #expect(summary.text == "Felt good in 2 of your last 4 rated sessions.")
    }

    @Test func ratingsOlderThanFourWeeksDropOut() {
        let old = entries([(1, .bad), (3, .bad), (8, .bad), (12, .bad), (16, .bad)])
        #expect(SessionFeelTrend.feltBadForWeeks(old, now: day(21)))
        // Six weeks on, only nothing is left inside the window.
        #expect(SessionFeelTrend.recent(old, now: day(60)) == nil)
    }

    @Test func aGoodRunReadsGood() throws {
        let good = entries([(1, .good), (4, .veryGood), (8, .good), (11, .neutral), (15, .good), (18, .bad), (20, .good)])
        let summary = try #require(SessionFeelTrend.recent(good, now: day(21)))
        #expect(!summary.feltBad)
        #expect(summary.text == "Felt good in 5 of your last 7 rated sessions.")
    }

    @Test func chartKeepsTheNewestTwenty() {
        let many = (0..<30).map { SessionFeelEntry(sessionStart: day(Double($0)), feel: $0 % 2 == 0 ? .good : .bad) }
        let points = SessionFeelTrend.points(many.shuffled())
        #expect(points.count == 20)
        #expect(points.first?.date == day(10))
        #expect(points.last?.date == day(29))
        #expect(points.last?.value == -3)
    }

    // MARK: Coach

    @Test func coachLineUsesTrainingWordsOnly() throws {
        let bad = entries([(1, .bad), (5, .veryBad), (9, .neutral), (16, .bad), (20, .good)])
        let line = try #require(SessionFeelTrend.coachLine(bad, now: day(21)))
        #expect(line.contains("bad, very bad, neutral, bad, good"))
        #expect(line.contains("short version"))
        // Nothing the on-device model would decline (`CoachPromptVocabulary`).
        #expect(CoachPromptVocabulary.neutral(line) != nil)
        let words = Set(CoachIntent.words(line))
        #expect(words.isDisjoint(with: Set(CoachPromptVocabulary.bannedWords)))
        #expect(SessionFeelTrend.coachLine(entries([(1, .good)]), now: day(21)) == nil)
    }

    @Test func coachLineWithoutABadRunAddsNoSuggestion() throws {
        let good = entries([(1, .good), (8, .good), (15, .good), (20, .good)])
        let line = try #require(SessionFeelTrend.coachLine(good, now: day(21)))
        #expect(!line.contains("short version"))
    }

    // MARK: Block report

    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func lift(_ id: String, _ name: String, stalled: Bool = false) -> BlockReport.LiftChange {
        BlockReport.LiftChange(exerciseID: id, name: name, isBodyweight: false, start: 100, end: stalled ? 100 : 105,
                               change: stalled ? 0 : 0.05, points: [], isStalled: stalled)
    }

    func report(next: [BlockReport.NextChange]) -> BlockReport.Report {
        BlockReport.Report(
            number: 2, start: day(0), end: day(35), weeksRun: 5, hadDeload: true, sessionsDone: 18, sessionsPlanned: 20,
            weeksKept: 5, weeksPlanned: 5, volumeKg: 100_000, volumeChange: nil,
            lifts: [lift("squat", "Squat"), lift("bench", "Bench Press"), lift("deadlift", "Deadlift"),
                    lift("row", "Barbell Row"), lift("curl", "Biceps Curl")],
            records: [], muscles: [], bodyWeight: nil, hrv: nil, next: next
        )
    }

    let alternatives: [String: [CatalogExercise]] = [
        "curl": [CatalogExercise(id: "curl", name: "Biceps Curl", load: nil, requires: []),
                 CatalogExercise(id: "hammer", name: "Hammer Curl", load: nil, requires: [])],
        "squat": [CatalogExercise(id: "squat", name: "Squat", load: nil, requires: []),
                  CatalogExercise(id: "front", name: "Front Squat", load: nil, requires: [])],
    ]

    let volumeUp = BlockReport.NextChange(kind: .volumeUp(sets: 1), text: "Start each muscle 1 set a week higher", why: "")

    @Test func aBlockThatFeltFineOnlyReportsTheFeel() {
        var block = report(next: [volumeUp])
        let good = entries([(1, .good), (8, .good), (15, .neutral), (22, .good), (29, .veryGood)])
        BlockReport.applyFeel(&block, entries: good, alternatives: alternatives)
        #expect(block.feel?.rated == 5)
        #expect(block.feel?.feltBad == false)
        #expect(block.next == [volumeUp])
    }

    @Test func aBlockThatFeltBadHoldsVolumeAndOffersOneAccessorySwap() throws {
        var block = report(next: [volumeUp])
        let bad = entries([(1, .bad), (8, .veryBad), (15, .neutral), (22, .bad), (29, .bad), (40, .veryGood)])
        BlockReport.applyFeel(&block, entries: bad, alternatives: alternatives)
        // The rating after the block ended is not counted.
        #expect(block.feel?.rated == 5)
        #expect(block.feel?.feltBad == true)
        #expect(block.next.count == 2)
        #expect(block.next[0].kind == .holdVolume)
        #expect(block.next[0].why.contains("Sessions felt bad in 4 of 5 rated this block."))
        #expect(block.next[0].why.contains("app's choice"))
        // The swap is for an accessory, never one of the first three lifts, and names its study.
        #expect(block.next[1].kind == .swapExercise(fromID: "curl", toID: "hammer", toName: "Hammer Curl"))
        #expect(block.next[1].why.contains("Baz-Valle 2019"))
        #expect(block.next.allSatisfy(\.isAppChoice))
    }

    @Test func aLiftAlreadyBeingChangedIsNotSwappedAgain() {
        let stalledSwap = BlockReport.NextChange(kind: .swapExercise(fromID: "curl", toID: "hammer", toName: "Hammer Curl"),
                                                 text: "Swap Biceps Curl for Hammer Curl", why: "")
        var block = report(next: [stalledSwap])
        let bad = entries([(1, .bad), (8, .veryBad), (15, .bad), (22, .bad)])
        BlockReport.applyFeel(&block, entries: bad, alternatives: ["curl": alternatives["curl"]!, "row": []])
        // Row has no alternative in this gym, curl is already swapped, and the main lifts stay.
        #expect(block.next == [stalledSwap])
    }

    @Test func tooFewRatingsLeaveTheReportAlone() {
        var block = report(next: [volumeUp])
        BlockReport.applyFeel(&block, entries: entries([(1, .bad), (8, .bad), (15, .bad)]), alternatives: alternatives)
        #expect(block.feel == nil)
        #expect(block.next == [volumeUp])
    }
}
