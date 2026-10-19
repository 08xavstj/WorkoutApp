import CoreLocation
import Foundation
import AppCore

/// Today's weather, air quality and daylight where the user lives (Open-Meteo,
/// free, no account), used on Home and by the AI coach.
@Observable
final class ConditionsModel {
    private(set) var current: Conditions?
    private(set) var errorMessage: String?

    func refresh(settings: UserSettings, force: Bool = false) async {
        guard settings.hasLocation else {
            current = nil
            return
        }
        if !force, let current, Date.now.timeIntervalSince(current.fetched) < 30 * 60,
           current.latitude == settings.latitude, current.longitude == settings.longitude { return }
        do {
            current = try await WeatherClient.conditions(latitude: settings.latitude, longitude: settings.longitude)
            errorMessage = nil
            recordHotDay()
        } catch {
            errorMessage = "Couldn't load the weather."
        }
    }

    /// Today's forecast heat: the warmer of "feels like" now and the day's high.
    var forecastFeelsLikeC: Double? {
        current.map { max($0.feelsLike, $0.high ?? $0.feelsLike) }
    }

    /// Days (start of day) that reached `HeatAdvice.hotFeelsLikeC`, for heat acclimation.
    private(set) var hotDays: Set<Date> = ConditionsModel.loadHotDays()
    /// Hot days in the last 14 that had training; set by the app after a refresh.
    var heatTrainingDays = 0

    private static let hotDaysKey = "hotDays"

    private static func loadHotDays() -> Set<Date> {
        let stamps = UserDefaults.standard.array(forKey: hotDaysKey) as? [Double] ?? []
        return Set(stamps.map { Date(timeIntervalSince1970: $0) })
    }

    private func recordHotDay() {
        guard let feels = forecastFeelsLikeC, feels >= HeatAdvice.hotFeelsLikeC else { return }
        let today = Calendar.current.startOfDay(for: .now)
        let cutoff = today.addingTimeInterval(-30 * 86_400)
        guard !hotDays.contains(today) else { return }
        var days = hotDays.filter { $0 >= cutoff }
        days.insert(today)
        hotDays = days
        UserDefaults.standard.set(days.map(\.timeIntervalSince1970), forKey: Self.hotDaysKey)
    }

    var tips: [WeatherAdvice.Tip] {
        guard let current else { return [] }
        var tips = WeatherAdvice.tips(for: .init(
            feelsLikeC: current.feelsLike, humidity: current.humidity, uvIndexMax: current.uvIndexMax,
            usAQI: current.usAQI, daylightHours: current.daylightHours, precipitationChance: current.precipitationChance,
            sunrise: current.sunrise, sunset: current.sunset
        ))
        // On hot days, explain the lower strain target and acclimation instead.
        if let heat = HeatAdvice.advice(feelsLikeC: forecastFeelsLikeC, heatTrainingDays: heatTrainingDays) {
            if let index = tips.firstIndex(where: { $0.id == "heat" }) {
                tips[index].text = heat
            } else {
                tips.insert(WeatherAdvice.Tip(id: "heat", level: .caution, text: heat), at: 0)
            }
        }
        return tips
    }

    /// One line for the AI coach.
    func coachSummary(place: String) -> String? {
        guard let c = current else { return nil }
        var parts = ["\(c.summary), \(Int(c.temperature.rounded()))°C (feels \(Int(c.feelsLike.rounded()))°C)"]
        if let h = c.humidity { parts.append("humidity \(Int(h))%") }
        if let uv = c.uvIndexMax { parts.append("UV max \(Int(uv.rounded()))") }
        if let aqi = c.usAQI { parts.append("US AQI \(Int(aqi))") }
        if let rain = c.precipitationChance { parts.append("\(Int(rain))% chance of rain") }
        if let daylight = c.daylightHours { parts.append(String(format: "%.1f h daylight", daylight)) }
        if let sunrise = c.sunrise, let sunset = c.sunset {
            parts.append("sunrise \(sunrise.formatted(date: .omitted, time: .shortened)), sunset \(sunset.formatted(date: .omitted, time: .shortened))")
        }
        return "Weather in \(place) today: " + parts.joined(separator: ", ")
    }
}

nonisolated struct Conditions: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var fetched: Date
    var temperature: Double
    var feelsLike: Double
    var humidity: Double?
    var weatherCode: Int
    var isDay: Bool
    var high: Double?
    var low: Double?
    var uvIndexMax: Double?
    var precipitationChance: Double?
    var sunrise: Date?
    var sunset: Date?
    var daylightHours: Double?
    var usAQI: Double?

    /// WMO weather code → words and SF Symbol.
    var summary: String {
        switch weatherCode {
        case 0: "Clear"
        case 1, 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67, 80...82: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Thunderstorms"
        default: "Mixed"
        }
    }

    var symbol: String {
        switch weatherCode {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.sun.fill"
        }
    }
}

nonisolated struct Place: Sendable, Identifiable, Hashable {
    var name: String
    var region: String
    var latitude: Double
    var longitude: Double
    var id: String { "\(latitude),\(longitude)" }
    var label: String { region.isEmpty ? name : "\(name), \(region)" }
}

nonisolated enum WeatherClient {
    private nonisolated struct Forecast: Decodable {
        nonisolated struct Current: Decodable {
            var temperature_2m: Double
            var apparent_temperature: Double
            var relative_humidity_2m: Double?
            var weather_code: Int
            var is_day: Int
        }
        nonisolated struct Daily: Decodable {
            var sunrise: [Double]?
            var sunset: [Double]?
            var daylight_duration: [Double]?
            var uv_index_max: [Double?]?
            var precipitation_probability_max: [Double?]?
            var temperature_2m_max: [Double?]?
            var temperature_2m_min: [Double?]?
        }
        var current: Current
        var daily: Daily
    }

    private nonisolated struct AirQuality: Decodable {
        nonisolated struct Current: Decodable { var us_aqi: Double? }
        var current: Current
    }

    private nonisolated struct Geocoding: Decodable {
        nonisolated struct Result: Decodable {
            var name: String
            var latitude: Double
            var longitude: Double
            var admin1: String?
            var country: String?
        }
        var results: [Result]?
    }

    @concurrent
    static func conditions(latitude: Double, longitude: Double) async throws -> Conditions {
        var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        forecast.queryItems = [
            .init(name: "latitude", value: "\(latitude)"),
            .init(name: "longitude", value: "\(longitude)"),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day"),
            .init(name: "daily", value: "sunrise,sunset,daylight_duration,uv_index_max,precipitation_probability_max,temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "forecast_days", value: "1"),
        ]
        var air = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        air.queryItems = [
            .init(name: "latitude", value: "\(latitude)"),
            .init(name: "longitude", value: "\(longitude)"),
            .init(name: "current", value: "us_aqi"),
        ]
        async let forecastData = URLSession.shared.data(from: forecast.url!)
        async let airData = URLSession.shared.data(from: air.url!)
        let decoded = try JSONDecoder().decode(Forecast.self, from: try await forecastData.0)
        let aqi = (try? await airData).flatMap { try? JSONDecoder().decode(AirQuality.self, from: $0.0) }?.current.us_aqi
        let daily = decoded.daily
        return Conditions(
            latitude: latitude, longitude: longitude, fetched: .now,
            temperature: decoded.current.temperature_2m,
            feelsLike: decoded.current.apparent_temperature,
            humidity: decoded.current.relative_humidity_2m,
            weatherCode: decoded.current.weather_code,
            isDay: decoded.current.is_day == 1,
            high: daily.temperature_2m_max?.first ?? nil,
            low: daily.temperature_2m_min?.first ?? nil,
            uvIndexMax: daily.uv_index_max?.first ?? nil,
            precipitationChance: daily.precipitation_probability_max?.first ?? nil,
            sunrise: daily.sunrise?.first.map { Date(timeIntervalSince1970: $0) },
            sunset: daily.sunset?.first.map { Date(timeIntervalSince1970: $0) },
            daylightHours: daily.daylight_duration?.first.map { $0 / 3600 },
            usAQI: aqi
        )
    }

    /// City search for the location setting.
    @concurrent
    static func searchPlaces(_ query: String) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [.init(name: "name", value: trimmed), .init(name: "count", value: "6")]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let results = try JSONDecoder().decode(Geocoding.self, from: data).results ?? []
        return results.map { result in
            Place(name: result.name,
                  region: [result.admin1, result.country].compactMap { $0 }.joined(separator: ", "),
                  latitude: result.latitude, longitude: result.longitude)
        }
    }
}

/// One-time "use my current location".
@Observable
final class LocationFinder {
    private(set) var isLocating = false
    private(set) var problem: String?

    func locate() async -> CLLocationCoordinate2D? {
        isLocating = true
        problem = nil
        defer { isLocating = false }
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    problem = "Location is off for WorkoutApp. Turn it on in Settings → Privacy → Location Services, or search for your city."
                    return nil
                }
                if let location = update.location {
                    return location.coordinate
                }
            }
        } catch {
            problem = "Couldn't get your location. Search for your city instead."
        }
        return nil
    }
}
