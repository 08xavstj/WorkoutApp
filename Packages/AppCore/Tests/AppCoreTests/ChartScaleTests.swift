import Testing
@testable import AppCore

struct ChartScaleTests {
    @Test func padsTheDataAndKeepsItOffZero() throws {
        let domain = try #require(ChartScale.domain([50, 60], minimumSpan: 4))
        #expect(domain.lowerBound == 49)
        #expect(domain.upperBound == 61)
    }

    @Test func smallChangesGetTheMinimumSpan() throws {
        // VO2 max 45.0 → 45.5: a 3-point window, not a steep climb.
        let domain = try #require(ChartScale.domain([45.0, 45.5], minimumSpan: 3))
        #expect(abs((domain.upperBound - domain.lowerBound) - 3) < 0.0001)
        #expect(domain.contains(45.0) && domain.contains(45.5))
    }

    @Test func neverBelowZeroForPositiveData() throws {
        let domain = try #require(ChartScale.domain([0.5, 1], minimumSpan: 4))
        #expect(domain.lowerBound == 0)
        #expect(domain.upperBound == 4)
    }

    @Test func emptyHasNoDomain() {
        #expect(ChartScale.domain([], minimumSpan: 4) == nil)
        #expect(ChartScale.domain([.nan], minimumSpan: 4) == nil)
        #expect(ChartScale.domain([5], minimumSpan: 0) != nil)
    }

    @Test func spansFollowTheUnit() {
        #expect(ChartScale.minimumSpan(unit: "bpm", typical: 55) == 4)
        #expect(ChartScale.minimumSpan(unit: "kg", typical: 80) == 2)
        #expect(ChartScale.minimumSpan(unit: "", typical: 8000) == 800)
    }
}
