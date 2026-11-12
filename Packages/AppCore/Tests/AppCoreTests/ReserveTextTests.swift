import Testing
@testable import AppCore

struct ReserveTextTests {
    // Changed on purpose from "2 in reserve": users didn't know what "in
    // reserve" meant next to an RPE number, so the plain words lead.
    @Test func wholeHalfAndNone() {
        #expect(ReserveText.text(2) == "2 reps left")
        #expect(ReserveText.text(1) == "1 rep left")
        #expect(ReserveText.text(2.5) == "2-3 reps left")
        #expect(ReserveText.text(0) == "to failure")
        #expect(ReserveText.text(-1) == "to failure")
        #expect(ReserveText.text(0.5) == "0-1 reps left")
        // Float noise doesn't turn a whole number into a range.
        #expect(ReserveText.text(2.0000001) == "2 reps left")
        #expect(ReserveText.text(rpe: 7.5) == "2-3 reps left")
        #expect(ReserveText.text(rpe: 10) == "to failure")
    }

    @Test func theRangeTheSetsAskFor() {
        // Big lifts at RPE 7, small ones at 8: "2-3", not the session's 6.5 ("3-4").
        #expect(ReserveText.text(rpes: [7, 7, 8], fallback: 6.5) == "2-3 reps left")
        #expect(ReserveText.text(rpes: [7, 7], fallback: 6.5) == "3 reps left")
        #expect(ReserveText.text(rpes: [], fallback: 6.5) == "3-4 reps left")
        #expect(ReserveText.text(rpes: [10], fallback: 8) == "to failure")
    }

    @Test func countsShortAndSpoken() {
        #expect(ReserveText.count(3) == "3")
        #expect(ReserveText.count(2.5) == "2-3")
        #expect(ReserveText.count(0) == "0")
        #expect(ReserveText.count(rpes: [7, 8], fallback: 6) == "2-3")
        #expect(ReserveText.count(rpes: [], fallback: 7) == "3")
        #expect(ReserveText.short(rpe: 7) == "3 left")
        #expect(ReserveText.short(rpe: 8.5) == "1-2 left")
        #expect(ReserveText.short(rpe: 10) == "0 left")
        #expect(ReserveText.spoken(rpe: 9) == "1 rep left")
        #expect(ReserveText.spoken(rpe: 7.5) == "2 to 3 reps left")
        #expect(ReserveText.spoken(rpe: 10) == "no reps left")
    }

    @Test func repsLeftButtonsStoreRPE() {
        #expect(ReserveText.repsLeftChoices.map(ReserveText.choiceLabel) == ["0", "1", "2", "3", "4+"])
        // RPE = 10 − reps left (Zourdos et al. 2016); 4+ logs as 6, nothing past it.
        #expect(ReserveText.repsLeftChoices.map { ReserveText.rpe(repsLeft: $0) } == [10, 9, 8, 7, 6])
        #expect(ReserveText.rpe(repsLeft: 9) == 6)
        #expect(ReserveText.rpe(repsLeft: -2) == 10)
        // Back to the button: whole reps left, the half shown on its own.
        #expect(ReserveText.choice(rpe: 7) == 3)
        #expect(ReserveText.choice(rpe: 7.5) == 2)
        #expect(ReserveText.choice(rpe: 10) == 0)
        #expect(ReserveText.choice(rpe: 5) == 4)
        for left in ReserveText.repsLeftChoices {
            #expect(ReserveText.choice(rpe: ReserveText.rpe(repsLeft: left)) == left)
        }
    }

    @Test func explainer() {
        #expect(ReserveText.explainerTitle(3) == "What \u{201C}3 reps left\u{201D} means")
        #expect(ReserveText.explainerBody(3).hasPrefix("Pick a weight you could lift for about 3 more reps than the target, and stop the set there."))
        #expect(ReserveText.explainerBody(1).contains("about 1 more rep than"))
        #expect(ReserveText.explainerBody(2.5).contains("about 2-3 more reps"))
        #expect(ReserveText.explainerBody(0).hasPrefix("Keep going until another clean rep won't go"))
        #expect(ReserveText.explainerBody(3).hasSuffix("The app uses it to adjust your next set."))
        #expect(ReserveText.example(reps: 8, reserve: 2) == "You planned 8 reps with 2 left: pick a weight you could do 10 times, and stop at 8.")
        #expect(ReserveText.example(reps: 5, reserve: 0).contains("to failure"))
    }
}
