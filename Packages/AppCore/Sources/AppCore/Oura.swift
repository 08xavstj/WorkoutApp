import Foundation

/// Oura's cloud API (v2), for the direct link to an Oura ring: sign-in
/// URLs, the JSON it returns, and turning a night into `SleepSample`s.
/// Networking and token storage live in the app (`OuraLink`).
///
/// Sign-in is OAuth 2 with the authorization-code flow. Oura stopped issuing
/// personal access tokens in December 2025, and API access on current rings
/// needs an Oura membership. Refresh tokens are single use: every refresh
/// returns a new one that must be saved.
public enum Oura {
    public static let authorizeURL = URL(string: "https://cloud.ouraring.com/oauth/authorize")!
    public static let tokenURL = URL(string: "https://api.ouraring.com/oauth/token")!
    public static let apiBase = URL(string: "https://api.ouraring.com/v2/usercollection/")!
    /// `daily` covers sleep, readiness and activity; `heartrate` the
    /// per-minute heart rate; `personal` age and sex.
    public static let scopes = "personal daily heartrate"
    /// The app's URL scheme (project.yml) and the redirect address to give
    /// Oura's developer portal.
    public static let callbackScheme = "workoutapp"
    public static let defaultRedirectURI = "workoutapp://oura"

    // MARK: Sign-in

    /// The page that asks the user to allow access.
    public static func authorizationURL(clientID: String, redirectURI: String, state: String) -> URL? {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }

    /// What Oura sent back to the redirect address.
    public enum Callback: Equatable, Sendable {
        case code(String)
        /// The user said no, or Oura reported an error.
        case denied(String)
        /// The state didn't match the one sent: ignored (could be forged).
        case wrongState
        case invalid
    }

    public static func callback(_ url: URL, expectedState: String) -> Callback {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return .invalid }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == expectedState else { return .wrongState }
        if let error = value("error") { return .denied(error) }
        guard let code = value("code"), !code.isEmpty else { return .invalid }
        return .code(code)
    }

    /// Form body for the token endpoint (`application/x-www-form-urlencoded`).
    public static func tokenRequestBody(_ grant: Grant, clientID: String, clientSecret: String) -> Data {
        var fields: [(String, String)]
        switch grant {
        case let .code(code, redirectURI):
            fields = [("grant_type", "authorization_code"), ("code", code), ("redirect_uri", redirectURI)]
        case let .refresh(token):
            fields = [("grant_type", "refresh_token"), ("refresh_token", token)]
        }
        fields += [("client_id", clientID), ("client_secret", clientSecret)]
        return Data(fields.map { "\(formEncode($0.0))=\(formEncode($0.1))" }.joined(separator: "&").utf8)
    }

    public enum Grant: Sendable, Equatable {
        case code(String, redirectURI: String)
        case refresh(String)
    }

    static func formEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    /// The token endpoint's answer.
    public struct TokenResponse: Decodable, Sendable {
        public var accessToken: String
        public var refreshToken: String?
        public var expiresIn: Double?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }

        /// Tokens to keep, with the expiry as a date (a minute early, so a
        /// request never goes out with a token about to lapse).
        public func tokens(now: Date = .now, keeping previous: Tokens? = nil) -> Tokens {
            Tokens(accessToken: accessToken,
                   refreshToken: refreshToken ?? previous?.refreshToken,
                   expiresAt: expiresIn.map { now.addingTimeInterval(max(0, $0 - 60)) })
        }
    }

    public struct Tokens: Codable, Sendable, Equatable {
        public var accessToken: String
        public var refreshToken: String?
        public var expiresAt: Date?

        public init(accessToken: String, refreshToken: String?, expiresAt: Date?) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
        }

        public func isExpired(now: Date = .now) -> Bool {
            expiresAt.map { now >= $0 } ?? false
        }
    }

    // MARK: Data

    /// One page of a collection: `data` plus `next_token` for the next page.
    public struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
        public var data: [Item]
        public var nextToken: String?

        enum CodingKeys: String, CodingKey {
            case data
            case nextToken = "next_token"
        }
    }

    /// One sleep period (`/sleep`): a night, a nap or a rest.
    public struct SleepPeriod: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        /// The day Oura files it under (the morning it ended), "YYYY-MM-DD".
        public var day: String
        public var bedtimeStart: Date
        public var bedtimeEnd: Date
        /// "long_sleep" (the main sleep), "sleep", "late_nap", "rest", "deleted".
        public var type: String?
        /// One character per 5 minutes from `bedtimeStart`: 1 deep, 2 light, 3 REM, 4 awake.
        public var sleepPhase5Min: String?
        /// Seconds.
        public var totalSleepDuration: Double?
        public var deepSleepDuration: Double?
        public var lightSleepDuration: Double?
        public var remSleepDuration: Double?
        public var awakeTime: Double?
        /// Percent of time in bed asleep.
        public var efficiency: Double?
        /// Average overnight HRV, RMSSD in ms.
        public var averageHRV: Double?
        public var averageHeartRate: Double?
        public var lowestHeartRate: Double?
        /// Breaths a minute.
        public var averageBreath: Double?

        enum CodingKeys: String, CodingKey {
            case id, day, type, efficiency
            case bedtimeStart = "bedtime_start"
            case bedtimeEnd = "bedtime_end"
            case sleepPhase5Min = "sleep_phase_5_min"
            case totalSleepDuration = "total_sleep_duration"
            case deepSleepDuration = "deep_sleep_duration"
            case lightSleepDuration = "light_sleep_duration"
            case remSleepDuration = "rem_sleep_duration"
            case awakeTime = "awake_time"
            case averageHRV = "average_hrv"
            case averageHeartRate = "average_heart_rate"
            case lowestHeartRate = "lowest_heart_rate"
            case averageBreath = "average_breath"
        }

        public init(id: String, day: String, bedtimeStart: Date, bedtimeEnd: Date, type: String? = "long_sleep",
                    sleepPhase5Min: String? = nil, totalSleepDuration: Double? = nil, averageHRV: Double? = nil,
                    lowestHeartRate: Double? = nil, efficiency: Double? = nil) {
            self.id = id
            self.day = day
            self.bedtimeStart = bedtimeStart
            self.bedtimeEnd = bedtimeEnd
            self.type = type
            self.sleepPhase5Min = sleepPhase5Min
            self.totalSleepDuration = totalSleepDuration
            self.averageHRV = averageHRV
            self.lowestHeartRate = lowestHeartRate
            self.efficiency = efficiency
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            day = try c.decode(String.self, forKey: .day)
            bedtimeStart = try Oura.decodeDate(c, .bedtimeStart)
            bedtimeEnd = try Oura.decodeDate(c, .bedtimeEnd)
            type = try c.decodeIfPresent(String.self, forKey: .type)
            sleepPhase5Min = try c.decodeIfPresent(String.self, forKey: .sleepPhase5Min)
            totalSleepDuration = try c.decodeIfPresent(Double.self, forKey: .totalSleepDuration)
            deepSleepDuration = try c.decodeIfPresent(Double.self, forKey: .deepSleepDuration)
            lightSleepDuration = try c.decodeIfPresent(Double.self, forKey: .lightSleepDuration)
            remSleepDuration = try c.decodeIfPresent(Double.self, forKey: .remSleepDuration)
            awakeTime = try c.decodeIfPresent(Double.self, forKey: .awakeTime)
            efficiency = try c.decodeIfPresent(Double.self, forKey: .efficiency)
            averageHRV = try c.decodeIfPresent(Double.self, forKey: .averageHRV)
            averageHeartRate = try c.decodeIfPresent(Double.self, forKey: .averageHeartRate)
            lowestHeartRate = try c.decodeIfPresent(Double.self, forKey: .lowestHeartRate)
            averageBreath = try c.decodeIfPresent(Double.self, forKey: .averageBreath)
        }

        /// The main sleep or a shorter sleep; naps, rests and deleted periods are left out.
        public var isSleep: Bool { type == nil || type == "long_sleep" || type == "sleep" }

        /// The night as sleep samples: one per run of the same 5-minute
        /// phase, light sleep as Apple's "core", the last run ending at bedtime end.
        public func samples() -> [SleepSample] {
            func stage(_ character: Character) -> SleepStage? {
                switch character {
                case "1": .deep
                case "2": .core
                case "3": .rem
                case "4": .awake
                default: nil
                }
            }
            let phases = Array(sleepPhase5Min ?? "")
            guard !phases.isEmpty else {
                // No hypnogram: the period as unstaged sleep.
                return [SleepSample(stage: .unspecified, start: bedtimeStart, end: bedtimeEnd, source: "Oura", tracker: .ring)]
            }
            var result: [SleepSample] = []
            var index = 0
            while index < phases.count {
                var next = index + 1
                while next < phases.count, phases[next] == phases[index] { next += 1 }
                let start = bedtimeStart.addingTimeInterval(Double(index) * 300)
                let end = min(bedtimeEnd, bedtimeStart.addingTimeInterval(Double(next) * 300))
                if let stage = stage(phases[index]), end > start {
                    result.append(SleepSample(stage: stage, start: start, end: end, source: "Oura", tracker: .ring))
                }
                index = next
            }
            return result
        }
    }

    /// Oura's readiness for a day (`/daily_readiness`).
    public struct DailyReadiness: Codable, Sendable, Equatable {
        public var day: String
        /// 0-100, Oura's own score.
        public var score: Int?
        /// °C from the user's usual skin temperature.
        public var temperatureDeviation: Double?

        enum CodingKeys: String, CodingKey {
            case day, score
            case temperatureDeviation = "temperature_deviation"
        }

        public init(day: String, score: Int?, temperatureDeviation: Double?) {
            self.day = day
            self.score = score
            self.temperatureDeviation = temperatureDeviation
        }
    }

    /// Oura's sleep score for a day (`/daily_sleep`).
    public struct DailySleep: Codable, Sendable, Equatable {
        public var day: String
        public var score: Int?

        public init(day: String, score: Int?) {
            self.day = day
            self.score = score
        }
    }

    // MARK: Nights

    /// The morning a sample belongs to, as the app files nights: the start
    /// of the day 6 hours after it starts (`HealthKitClient.sleepHistory`).
    public static func morning(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(6 * 3600))
    }

    /// The main sleep for each morning: the longest sleep period starting that night.
    public static func mainSleep(_ periods: [SleepPeriod], calendar: Calendar = .current) -> [Date: SleepPeriod] {
        var result: [Date: SleepPeriod] = [:]
        for period in periods where period.isSleep {
            let morning = morning(of: period.bedtimeStart, calendar: calendar)
            let length = period.bedtimeEnd.timeIntervalSince(period.bedtimeStart)
            if let current = result[morning], current.bedtimeEnd.timeIntervalSince(current.bedtimeStart) >= length { continue }
            result[morning] = period
        }
        return result
    }

    /// Overnight HRV (RMSSD, ms) by morning, from each main sleep.
    public static func nightlyRMSSD(_ periods: [SleepPeriod], calendar: Calendar = .current) -> [Date: Double] {
        mainSleep(periods, calendar: calendar).compactMapValues { period in
            period.averageHRV.flatMap { $0 > 0 ? $0 : nil }
        }
    }

    /// Sleep samples from every sleep period that starts between `start` and `end`.
    public static func samples(_ periods: [SleepPeriod], from start: Date, to end: Date) -> [SleepSample] {
        periods
            .filter { $0.isSleep && $0.bedtimeStart >= start && $0.bedtimeStart < end }
            .sorted { $0.bedtimeStart < $1.bedtimeStart }
            .flatMap { $0.samples() }
    }

    // MARK: Dates

    /// Oura's timestamps carry an offset and sometimes fractional seconds.
    public static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    static func decodeDate<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, _ key: Key) throws -> Date {
        // A date encoded by this app (cached) is a number; Oura's is a string.
        if let seconds = try? container.decode(Double.self, forKey: key) {
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        let text = try container.decode(String.self, forKey: key)
        guard let date = parseDate(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Unreadable date \(text)")
        }
        return date
    }
}
