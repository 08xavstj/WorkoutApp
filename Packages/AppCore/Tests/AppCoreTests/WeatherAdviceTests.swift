import Testing
@testable import AppCore

struct WeatherAdviceTests {
    @Test func heatAndBadAirComeFirst() {
        let tips = WeatherAdvice.tips(for: .init(feelsLikeC: 37, uvIndexMax: 4, usAQI: 160, daylightHours: 14))
        #expect(tips.first?.level == .warning)
        #expect(tips.contains { $0.id == "heat" })
        #expect(tips.contains { $0.id == "air" })
        #expect(!tips.contains { $0.id == "daylight" })
    }

    @Test func mildDayHasNoWarnings() {
        let tips = WeatherAdvice.tips(for: .init(feelsLikeC: 18, uvIndexMax: 2, usAQI: 30, daylightHours: 12))
        #expect(tips.isEmpty)
    }

    @Test func shortDaysSuggestMorningLight() {
        let tips = WeatherAdvice.tips(for: .init(feelsLikeC: 2, daylightHours: 8.6))
        #expect(tips.contains { $0.id == "daylight" })
    }
}
