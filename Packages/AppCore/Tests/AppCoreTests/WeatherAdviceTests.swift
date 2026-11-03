import Testing
@testable import AppCore

struct WeatherAdviceTests {
    @Test func heatAndBadAirComeFirst() {
        // 37 °C at the default humidity is "extreme" (about 37 °C WBGT).
        let tips = WeatherAdvice.tips(for: .init(feelsLikeC: 37, temperatureC: 37, uvIndexMax: 4, usAQI: 160, daylightHours: 14))
        #expect(tips.first?.level == .warning)
        #expect(tips.contains { $0.id == "heat" })
        #expect(tips.contains { $0.id == "air" })
        #expect(!tips.contains { $0.id == "daylight" })
    }

    @Test func mildDayHasNoWarnings() {
        // 15 °C at 50% is about 16 °C WBGT: below the ACSM "moderate" band.
        let tips = WeatherAdvice.tips(for: .init(feelsLikeC: 15, temperatureC: 15, humidity: 50, uvIndexMax: 2, usAQI: 30, daylightHours: 12))
        #expect(tips.isEmpty)
    }

    @Test func heatBandsFollowWBGT() {
        // 22 °C at 50% ≈ 21.6 WBGT: moderate (info). 28 °C at 60% ≈ 28.7: very high (warning).
        let moderate = WeatherAdvice.tips(for: .init(feelsLikeC: 22, temperatureC: 22, humidity: 50))
        #expect(moderate.first?.id == "heat")
        #expect(moderate.first?.level == .info)
        let veryHigh = WeatherAdvice.tips(for: .init(feelsLikeC: 28, temperatureC: 28, humidity: 60))
        #expect(veryHigh.first?.level == .warning)
        #expect(veryHigh.first?.text.contains("Very hot") == true)
        // Humidity alone moves 27 °C from "high" (caution) to "extreme" (warning).
        let dry = WeatherAdvice.tips(for: .init(temperatureC: 27, humidity: 30))
        let muggy = WeatherAdvice.tips(for: .init(temperatureC: 27, humidity: 85))
        #expect(dry.first?.level == .caution)
        #expect(muggy.first?.text.contains("Extreme heat") == true)
        // Without an air temperature, "feels like" stands in.
        #expect(WeatherAdvice.estimatedWBGT(for: .init(feelsLikeC: 30)) != nil)
        #expect(WeatherAdvice.estimatedWBGT(for: .init(uvIndexMax: 5)) == nil)
    }

    @Test func coldStillUsesFeelsLike() {
        let tips = WeatherAdvice.tips(for: .init(feelsLikeC: -12, temperatureC: -6, humidity: 70))
        #expect(tips.first?.id == "cold")
        #expect(tips.first?.level == .caution)
    }

    @Test func shortDaysSuggestMorningLight() {
        let tips = WeatherAdvice.tips(for: .init(feelsLikeC: 2, daylightHours: 8.6))
        #expect(tips.contains { $0.id == "daylight" })
    }
}
