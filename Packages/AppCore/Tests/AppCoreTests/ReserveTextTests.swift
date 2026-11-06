import Testing
@testable import AppCore

struct ReserveTextTests {
    @Test func wholeHalfAndNone() {
        #expect(ReserveText.text(2) == "2 in reserve")
        #expect(ReserveText.text(2.5) == "2-3 in reserve")
        #expect(ReserveText.text(0) == "to failure")
        #expect(ReserveText.text(-1) == "to failure")
        #expect(ReserveText.text(0.5) == "0-1 in reserve")
        // Float noise doesn't turn a whole number into a range.
        #expect(ReserveText.text(2.0000001) == "2 in reserve")
        #expect(ReserveText.text(rpe: 7.5) == "2-3 in reserve")
        #expect(ReserveText.text(rpe: 10) == "to failure")
    }

    @Test func theRangeTheSetsAskFor() {
        // Big lifts at RPE 7, small ones at 8: "2-3", not the session's 6.5 ("3-4").
        #expect(ReserveText.text(rpes: [7, 7, 8], fallback: 6.5) == "2-3 in reserve")
        #expect(ReserveText.text(rpes: [7, 7], fallback: 6.5) == "3 in reserve")
        #expect(ReserveText.text(rpes: [], fallback: 6.5) == "3-4 in reserve")
        #expect(ReserveText.text(rpes: [10], fallback: 8) == "to failure")
    }
}
