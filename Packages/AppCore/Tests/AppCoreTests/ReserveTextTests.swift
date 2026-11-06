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
}
