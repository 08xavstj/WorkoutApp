import Foundation

/// Training tips from today's weather, air quality and daylight.
///
/// - Heat: heart rate runs higher and performance drops as it gets hot and
///   humid; ACSM advises extra fluids and easing off in the heat (Armstrong et
///   al., ACSM position stand on exertional heat illness, Med Sci Sports Exerc
///   2007). "Feels like" (apparent temperature) is used as a stand-in for heat stress.
/// - Air quality: US EPA AQI guidance: over 100, sensitive people should cut
///   long or hard outdoor exertion; over 150, everyone should.
/// - UV: WHO UV index guidance: protection from 3, avoid midday sun from 8.
/// - Daylight: morning outdoor light helps set the body clock and sleep
///   (Burns et al., J Affect Disord 2021); short winter days make it more important.
public enum WeatherAdvice {
    public struct Conditions: Sendable, Equatable {
        public var feelsLikeC: Double?
        public var humidity: Double?
        public var uvIndexMax: Double?
        public var usAQI: Double?
        public var daylightHours: Double?
        public var precipitationChance: Double?

        public init(feelsLikeC: Double? = nil, humidity: Double? = nil, uvIndexMax: Double? = nil,
                    usAQI: Double? = nil, daylightHours: Double? = nil, precipitationChance: Double? = nil) {
            self.feelsLikeC = feelsLikeC
            self.humidity = humidity
            self.uvIndexMax = uvIndexMax
            self.usAQI = usAQI
            self.daylightHours = daylightHours
            self.precipitationChance = precipitationChance
        }
    }

    public enum Level: Int, Sendable, Comparable {
        case info, caution, warning
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Tip: Sendable, Equatable, Identifiable {
        public var id: String
        public var level: Level
        public var text: String
    }

    /// Most important first.
    public static func tips(for c: Conditions) -> [Tip] {
        var tips: [Tip] = []
        if let feels = c.feelsLikeC {
            if feels >= 35 {
                tips.append(Tip(id: "heat", level: .warning, text: "Very hot (feels \(Int(feels.rounded()))°C): train indoors or early, drink before you're thirsty, and expect heart rate 10+ bpm higher."))
            } else if feels >= 28 {
                tips.append(Tip(id: "heat", level: .caution, text: "Warm (feels \(Int(feels.rounded()))°C): bring extra water and expect a higher heart rate outdoors."))
            } else if feels <= -10 {
                tips.append(Tip(id: "cold", level: .caution, text: "Very cold (feels \(Int(feels.rounded()))°C): warm up longer indoors and cover your hands, ears and face."))
            } else if feels <= 0 {
                tips.append(Tip(id: "cold", level: .info, text: "Below freezing: take a longer warm-up before hard efforts."))
            }
        }
        if let aqi = c.usAQI {
            if aqi > 150 {
                tips.append(Tip(id: "air", level: .warning, text: "Air quality is unhealthy (AQI \(Int(aqi))): move cardio indoors today."))
            } else if aqi > 100 {
                tips.append(Tip(id: "air", level: .caution, text: "Air quality is poor (AQI \(Int(aqi))): keep long or hard outdoor efforts short."))
            }
        }
        if let uv = c.uvIndexMax {
            if uv >= 8 {
                tips.append(Tip(id: "uv", level: .caution, text: "Very high UV (\(Int(uv.rounded()))): avoid outdoor training from 11 to 3 and use sunscreen."))
            } else if uv >= 3 {
                tips.append(Tip(id: "uv", level: .info, text: "UV \(Int(uv.rounded())): sunscreen for outdoor sessions."))
            }
        }
        if let rain = c.precipitationChance, rain >= 70 {
            tips.append(Tip(id: "rain", level: .info, text: "\(Int(rain))% chance of rain: have an indoor plan."))
        }
        if let daylight = c.daylightHours, daylight < 10 {
            tips.append(Tip(id: "daylight", level: .info, text: "Only \(String(format: "%.1f", daylight)) h of daylight: get 10-20 minutes outside in the morning to help your sleep."))
        }
        return tips.sorted { $0.level > $1.level }
    }
}
