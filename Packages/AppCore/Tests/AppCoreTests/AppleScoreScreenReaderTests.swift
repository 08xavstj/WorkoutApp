import Foundation
import Testing
@testable import AppCore

/// Reading Apple's numbers out of screenshot text (`AppleScoreScreenReader`).
/// The line sets are invented from Apple's descriptions of the screens: nobody
/// outside Apple has their exact wording, so the tests cover several plausible
/// layouts and, above all, that clutter is never taken for a score.
@Suite struct AppleScoreScreenReaderTests {
    private typealias Reader = AppleScoreScreenReader
    private typealias Line = AppleScoreScreenReader.Line
    private typealias Box = AppleScoreScreenReader.Box

    private func read(_ texts: [String]) -> Reader.Result {
        Reader.read(texts.map { Line($0) })
    }

    /// A line at a place on the page: x, y (from the top), width, height.
    private func at(_ text: String, _ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Line {
        Line(text, box: Box(x: x, y: y, width: width, height: height))
    }

    // MARK: Readiness

    @Test func readinessScreenOnTheWatch() {
        let result = read(["9:41", "Readiness", "7", "Ready", "Activity", "Vitals", "Sleep"])
        let best = result.best(.readiness)
        #expect(best?.value == 7)
        #expect(best?.label == "Readiness")
        #expect(best?.placement == .below)
        #expect(best?.level == "ready")
        #expect(best?.confidence == .high)
        #expect(result.candidates(for: .sleepScore).isEmpty)
        #expect(result.candidates(for: .healthAge).isEmpty)
    }

    @Test func readinessWrittenOverItsScale() {
        #expect(read(["Readiness", "7/10"]).best(.readiness)?.value == 7)
        #expect(read(["Readiness", "7 / 10"]).best(.readiness)?.value == 7)
        #expect(read(["Readiness", "8 of 10", "Go For It"]).best(.readiness)?.value == 8)
        #expect(read(["Readiness Score: 3"]).best(.readiness)?.value == 3)
        #expect(read(["Your readiness is 10"]).best(.readiness)?.value == 10)
        #expect(read(["0 Readiness"]).best(.readiness)?.value == 0)
    }

    @Test func readinessWithItsWordOnTheSameLine() {
        let result = read(["Readiness", "4 Pace Yourself"])
        #expect(result.best(.readiness)?.value == 4)
        #expect(result.best(.readiness)?.level == "pace yourself")
        let inline = read(["Readiness 9 Go For It"]).best(.readiness)
        #expect(inline?.value == 9)
        #expect(inline?.placement == .sameLine)
    }

    @Test func aWordThatDoesNotFitTheNumberIsFlagged() {
        // "Ready" is 5–7 in Apple's bands; 9 beside it is probably a misread.
        let result = read(["Readiness", "9", "Ready"])
        #expect(result.best(.readiness) == nil)
        let candidate = result.candidates(for: .readiness).first
        #expect(candidate?.value == 9)
        #expect(candidate?.confidence == .low)
        #expect(candidate?.doubts.contains(.levelMismatch) == true)
    }

    @Test func readinessOutOfRangeOrWithDecimalsIsNotRead() {
        #expect(read(["Readiness", "11"]).isEmpty)
        #expect(read(["Readiness", "7.5"]).isEmpty)
        #expect(read(["Readiness 7.5"]).isEmpty)
        #expect(read(["Readiness", "72%"]).isEmpty)
    }

    @Test func sentencesAboutReadinessAreNotLabels() {
        let result = read([
            "Readiness",
            "Your readiness score is based on recent activity, vitals and sleep score.",
            "Wear your watch to sleep for at least 7 nights",
            "7",
        ])
        // The description stops the search: the lone 7 after it isn't beside the label.
        #expect(result.isEmpty)
    }

    // MARK: Sleep score

    @Test func sleepScoreScreen() {
        let result = read([
            "Sleep Score", "Last night", "82", "High",
            "Duration", "42/50", "Bedtime", "24/30", "Interruptions", "16/20",
            "Time Asleep", "7 hr 32 min",
        ])
        let best = result.best(.sleepScore)
        #expect(best?.value == 82)
        #expect(best?.level == "high")
        #expect(best?.placement == .below)
        #expect(result.candidates(for: .sleepScore).count == 1)
        #expect(result.candidates(for: .readiness).isEmpty)
    }

    @Test func sleepScoreNumberAboveItsCaption() {
        let result = read(["94", "Sleep Score", "Very High", "Mon, 16 Nov"])
        #expect(result.best(.sleepScore)?.value == 94)
        #expect(result.best(.sleepScore)?.placement == .above)
    }

    @Test func sleepScoreOverOneHundred() {
        #expect(read(["Sleep Score", "82/100"]).best(.sleepScore)?.value == 82)
        #expect(read(["Sleep Score 100 Very High"]).best(.sleepScore)?.value == 100)
        #expect(read(["Sleep Score", "82 out of 100"]).best(.sleepScore)?.value == 82)
        // A component score ("42/50") is not the sleep score.
        #expect(read(["Sleep Score", "42/50"]).isEmpty)
    }

    @Test func aBareSleepTitleIsOnlyAnOptionAndNeedsALevelWord() {
        let withLevel = read(["Sleep", "82", "High"])
        #expect(withLevel.best(.sleepScore) == nil)
        #expect(withLevel.candidates(for: .sleepScore).first?.value == 82)
        #expect(withLevel.candidates(for: .sleepScore).first?.doubts == [.weakLabel])
        // Without a level word a number under "Sleep" could be anything.
        #expect(read(["Sleep", "82"]).isEmpty)
        #expect(read(["Sleep", "7 hr 32 min"]).isEmpty)
    }

    // MARK: Health Age

    @Test func healthAgeScreen() {
        let result = read([
            "Longevity", "Health Age", "34", "years",
            "4 years younger than your age",
            "VO2 max", "46.1", "Resting Heart Rate", "52 BPM",
        ])
        let best = result.best(.healthAge)
        #expect(best?.value == 34)
        #expect(best?.label == "Health Age")
        #expect(result.candidates(for: .healthAge).count == 1)
    }

    @Test func healthAgeWithItsUnit() {
        #expect(read(["Health Age", "34 years"]).best(.healthAge)?.value == 34)
        #expect(read(["Health Age 41 yrs"]).best(.healthAge)?.value == 41)
        #expect(read(["Your Health Age is 29"]).best(.healthAge)?.value == 29)
        #expect(read(["Health Age", "52 years old"]).best(.healthAge)?.value == 52)
    }

    @Test func theGapToYourAgeIsNotAHealthAge() {
        #expect(read(["Health Age", "12 years younger"]).isEmpty)
        #expect(read(["Health Age", "12", "years younger than your age"]).isEmpty)
        #expect(read(["Health Age", "3"]).isEmpty) // under 10: not an age
    }

    @Test func healthAgeBetweenTwoNumbersIsLeftToTheOwner() {
        // No telling whether the screen puts numbers above or below their labels.
        let result = read(["34", "Health Age", "38"])
        #expect(result.best(.healthAge) == nil)
        let values = result.candidates(for: .healthAge).map(\.value).sorted()
        #expect(values == [34, 38])
        #expect(result.candidates(for: .healthAge).allSatisfy { $0.doubts.contains(.twoNumbers) })
    }

    // MARK: Several numbers

    @Test func labelsAboveTheirNumbers() {
        let result = read(["Readiness", "7", "Sleep Score", "82", "Health Age", "34"])
        #expect(result.best(.readiness)?.value == 7)
        #expect(result.best(.sleepScore)?.value == 82)
        #expect(result.best(.healthAge)?.value == 34)
        #expect(result.candidates.count == 3)
    }

    @Test func numbersAboveTheirLabels() {
        let result = read(["7", "Readiness", "82", "Sleep Score", "34", "Health Age"])
        #expect(result.best(.readiness)?.value == 7)
        #expect(result.best(.sleepScore)?.value == 82)
        #expect(result.best(.healthAge)?.value == 34)
        #expect(result.candidates.count == 3)
    }

    @Test func insightsStyleSummaryWithOtherMeasures() {
        let result = read([
            "9:41", "Insights", "Today, 17 Nov",
            "Readiness 6 Ready",
            "Sleep Score 77 OK",
            "Heart Rate", "58 BPM",
            "Steps", "8,412",
            "Move", "420/600 CAL",
            "100%",
        ])
        #expect(result.best(.readiness)?.value == 6)
        #expect(result.best(.sleepScore)?.value == 77)
        #expect(result.candidates.count == 2)
        #expect(result.dayHint == .today)
    }

    @Test func twoTilesSideBySide() {
        // Two columns: each number belongs to the label above it in its own column.
        let result = Reader.read([
            at("9:41", 0.06, 0.02, 0.10, 0.02),
            at("Readiness", 0.06, 0.20, 0.22, 0.025),
            at("Sleep Score", 0.56, 0.20, 0.26, 0.025),
            at("7", 0.06, 0.25, 0.05, 0.06),
            at("82", 0.56, 0.25, 0.10, 0.06),
            at("Ready", 0.06, 0.33, 0.12, 0.02),
            at("High", 0.56, 0.33, 0.10, 0.02),
        ])
        #expect(result.best(.readiness)?.value == 7)
        #expect(result.best(.readiness)?.level == "ready")
        #expect(result.best(.sleepScore)?.value == 82)
        #expect(result.best(.sleepScore)?.level == "high")
        #expect(result.candidates.count == 2)
    }

    @Test func listRowsWithTheNumberAtTheFarEnd() {
        let result = Reader.read([
            at("Readiness", 0.06, 0.30, 0.22, 0.022),
            at("7", 0.88, 0.30, 0.04, 0.022),
            at("Sleep Score", 0.06, 0.36, 0.26, 0.022),
            at("82", 0.86, 0.36, 0.06, 0.022),
            at("Resting Heart Rate", 0.06, 0.42, 0.40, 0.022),
            at("52", 0.80, 0.42, 0.06, 0.022),
            at("BPM", 0.87, 0.425, 0.07, 0.015),
        ])
        #expect(result.best(.readiness)?.value == 7)
        #expect(result.best(.readiness)?.placement == .sameLine)
        #expect(result.best(.sleepScore)?.value == 82)
        #expect(result.candidates.count == 2)
    }

    @Test func positionsDecideBetweenANumberAboveAndOneBelow() {
        // 34 sits right under the label; 38 is far above it.
        let result = Reader.read([
            at("38", 0.40, 0.10, 0.10, 0.04),
            at("Health Age", 0.30, 0.22, 0.30, 0.03),
            at("34", 0.40, 0.26, 0.12, 0.07),
        ])
        #expect(result.best(.healthAge)?.value == 34)
        #expect(result.candidates(for: .healthAge).count == 1)
    }

    @Test func smallPrintUnderABigTitleIsOnlyAnOption() {
        // A chart's axis label under a large title, with no hero number read.
        let result = Reader.read([
            at("Sleep Score", 0.06, 0.10, 0.50, 0.05),
            at("50", 0.06, 0.20, 0.04, 0.012),
        ])
        #expect(result.best(.sleepScore) == nil)
        #expect(result.candidates(for: .sleepScore).first?.doubts.contains(.smallPrint) == true)
    }

    // MARK: Clutter

    @Test func aScreenWithoutTheLabelsGivesNothing() {
        let result = read([
            "9:41", "100%", "Summary", "Tue, 17 Nov",
            "Heart Rate", "62", "BPM",
            "Steps", "8,412",
            "Sleep", "7 hr 32 min",
            "Exercise", "34 min",
            "Stand", "10/12 hr",
            "Cardio Fitness", "46.1", "VO2 max",
        ])
        #expect(result.isEmpty)
    }

    @Test func timesDatesPercentagesAndUnitsAreNeverScores() {
        for clutter in ["9:41", "07:30", "85%", "17 Nov", "11/17/2026", "2026", "62 BPM", "7 hr 32 min", "45 min", "1,204", "-3", "+2", "7.5", "07"] {
            #expect(read(["Readiness", clutter]).isEmpty, "\(clutter) read as readiness")
            #expect(read(["Sleep Score", clutter]).isEmpty, "\(clutter) read as a sleep score")
            #expect(read(["Health Age", clutter]).isEmpty, "\(clutter) read as a Health Age")
        }
    }

    @Test func aNumberFollowedByAUnitOnTheNextLineIsRejected() {
        #expect(read(["Sleep Score", "62", "BPM"]).isEmpty)
        #expect(read(["Readiness", "8", "hr"]).isEmpty)
    }

    @Test func aDateBetweenLabelAndNumberIsSkipped() {
        let result = read(["Sleep Score", "Mon, 16 Nov", "71", "OK"])
        #expect(result.best(.sleepScore)?.value == 71)
    }

    @Test func anotherMeasureBetweenLabelAndNumberStopsTheSearch() {
        #expect(read(["Sleep Score", "Heart Rate", "62"]).isEmpty)
        #expect(read(["Readiness", "Training Load", "5"]).isEmpty)
    }

    @Test func aNumberIsNotSharedBetweenALabelAndTheNextOne() {
        // 7 belongs to Readiness (below it), not to Sleep Score (above it).
        // It stays an option for Sleep Score, marked as doubtful and never filled in.
        let result = read(["Readiness", "7", "Sleep Score", "No data"])
        #expect(result.best(.readiness)?.value == 7)
        #expect(result.best(.sleepScore) == nil)
        #expect(result.candidates(for: .sleepScore).map(\.doubts) == [[.sharedNumber]])
    }

    @Test func aLabelWithItsOwnNumberDoesNotBorrowTheOneAboveIt() {
        let result = read(["Readiness", "7", "Sleep Score", "82", "Health Age", "No data yet"])
        #expect(result.best(.readiness)?.value == 7)
        #expect(result.best(.sleepScore)?.value == 82)
        #expect(result.candidates(for: .sleepScore).count == 1)
        #expect(result.best(.healthAge) == nil)
        #expect(result.candidates(for: .healthAge).first?.doubts == [.sharedNumber])
    }

    // MARK: Hints and bookkeeping

    @Test func dayHint() {
        #expect(read(["Yesterday", "Readiness", "5"]).dayHint == .yesterday)
        #expect(read(["Today", "Readiness", "5"]).dayHint == .today)
        #expect(read(["Readiness", "5"]).dayHint == nil)
        #expect(read(["Today", "Yesterday", "Readiness", "5"]).dayHint == nil)
    }

    @Test func theSameNumberReadTwiceIsOneCandidate() {
        let result = read(["Readiness", "7", "Ready", "Readiness 7"])
        #expect(result.candidates(for: .readiness).count == 1)
        #expect(result.best(.readiness)?.value == 7)
    }

    @Test func twoDifferentSureNumbersAreLeftToTheOwner() {
        let result = read(["Readiness 7", "Yesterday", "Readiness 4"])
        #expect(result.best(.readiness) == nil)
        #expect(result.candidates(for: .readiness).map(\.value).sorted() == [4, 7])
    }

    @Test func summarySaysWhatWasRead() {
        let candidate = read(["Sleep Score", "82"]).best(.sleepScore)
        #expect(candidate?.summary == "82, below \u{201C}Sleep Score\u{201D}")
        #expect(candidate?.valueText == "82")
    }

    @Test func emptyAndBlankInput() {
        #expect(read([]).isEmpty)
        #expect(read(["", "   "]).lineCount == 0)
    }

    @Test func caseAndPunctuationAreTolerated() {
        #expect(read(["READINESS", "7"]).best(.readiness)?.value == 7)
        #expect(read(["Readiness:", "7"]).best(.readiness)?.value == 7)
        #expect(read(["SLEEP SCORE", "82"]).best(.sleepScore)?.value == 82)
        #expect(read(["Today\u{2019}s Readiness", "7"]).best(.readiness)?.value == 7)
        #expect(read(["Readiness \u{00B7} 7 \u{00B7} Ready"]).best(.readiness)?.value == 7)
    }
}
