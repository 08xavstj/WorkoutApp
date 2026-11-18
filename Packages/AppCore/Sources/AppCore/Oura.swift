import Foundation

/// Oura's cloud API (v2), for the direct link to an Oura ring: sign-in
/// URLs, the JSON it returns, and turning a night into `SleepSample`s.
/// Networking and token storage live in the app (`OuraLink`).
///
/// Sign-in is OAuth 2 with the authorization-code flow and PKCE (`PKCE`).
/// Oura stopped issuing personal access tokens in December 2025, and API
/// access on current rings needs an Oura membership. Refresh tokens are
/// single use: every refresh returns a new one that must be saved.
///
/// What Tensile uses from the ring, and what it leaves out and why:
/// docs/research/oura-ring-2026-11.md §6.
public enum Oura {
    public static let authorizeURL = URL(string: "https://cloud.ouraring.com/oauth/authorize")!
    public static let tokenURL = URL(string: "https://api.ouraring.com/oauth/token")!
    public static let apiBase = URL(string: "https://api.ouraring.com/v2/usercollection/")!
    /// What Tensile's own scores need: `daily` covers `/sleep` (stages,
    /// overnight HRV and heart rate, breathing rate, temperature change).
    /// `heartrate` and `personal` were requested before but never read. The
    /// "Oura's own numbers" panel, on by default, adds `spo2` and
    /// `heart_health` (`ownNumbersScopes`, `requestedScopes`); nothing in
    /// Tensile's scores reads those, and the Watch's SpO2 is the one with
    /// independent evidence (Oura API spec 1.43 scopes;
    /// docs/research/oura-ring-2026-11.md §3.2, §4.4, §6). A sign-in that
    /// lacks a permission now asked for prompts one reconnect (`needsReconnect`).
    public static let scopes = "daily"
    /// Oura asks every request to carry a User-Agent and says requests
    /// without one "may be rejected" (Oura API spec 1.43). Generic on
    /// purpose: nothing about the user or the device.
    public static let userAgent = "Tensile/1.0"
    /// The app's URL scheme (project.yml) and the redirect address to give
    /// Oura's developer portal.
    public static let callbackScheme = "workoutapp"
    public static let defaultRedirectURI = "workoutapp://oura"

    // MARK: Sign-in

    /// The page that asks the user to allow access, with the PKCE S256
    /// challenge for `codeVerifier` (`PKCE.challenge(for:)`).
    public static func authorizationURL(clientID: String, redirectURI: String, state: String, codeVerifier: String,
                                        scope: String = scopes) -> URL? {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components?.url
    }

    /// The permissions in a scope string: split on spaces, `+` or commas,
    /// lowercased, in order, without repeats.
    static func scopeList(_ text: String) -> [String] {
        var seen: Set<String> = []
        return text.lowercased().split(whereSeparator: { $0 == " " || $0 == "+" || $0 == "," })
            .map(String.init).filter { seen.insert($0).inserted }
    }

    /// The permissions in `required` that `granted` lacks, in `required`'s
    /// order. With no granted scope on record, all of them. Order and case
    /// don't matter.
    public static func missingScopes(granted: String?, required: String) -> [String] {
        let have = Set(scopeList(granted ?? ""))
        return scopeList(required).filter { !have.contains($0) }
    }

    /// True when the owner should sign in to Oura once more:
    /// - tokens saved before the app recorded the scope come from the older,
    ///   wider request (`personal daily heartrate`), so they ask once;
    /// - a sign-in that lacks a permission the app now asks for (the owner
    ///   unticked it, or the request grew) asks, since those reads would fail.
    /// Extra permissions Oura still reports after a fresh sign-in don't ask
    /// again: one more sign-in can't remove them, and nagging would never stop.
    /// A sign-in whose reply didn't say what was granted (`scopeUnreported`)
    /// doesn't ask either: another sign-in wouldn't tell us more.
    public static func needsReconnect(grantedScope: String?, required: String = scopes,
                                      scopeUnreported: Bool = false) -> Bool {
        guard let grantedScope else { return !scopeUnreported }
        return !missingScopes(granted: grantedScope, required: required).isEmpty
    }

    /// Why to reconnect, worded from what is actually missing; nil when
    /// nothing is (`needsReconnect`). Permissions that only "Oura's own
    /// numbers" uses (`ownNumbersScopes`) are named and said to be only for
    /// that panel.
    public static func reconnectPrompt(grantedScope: String?, required: String = scopes,
                                       scopeUnreported: Bool = false) -> String? {
        guard needsReconnect(grantedScope: grantedScope, required: required, scopeUnreported: scopeUnreported) else { return nil }
        let missing = missingScopes(granted: grantedScope, required: required)
        let extras = missing.filter { ownNumbersScopes.contains($0) }
        let core = missing.filter { !ownNumbersScopes.contains($0) }
        let extrasText = extras.isEmpty ? nil
            : "Oura's own numbers need the \(list(extras)) permission\(extras.count == 1 ? "" : "s"), used only for that panel and never for Tensile's scores."
        guard grantedScope != nil else {
            // Tokens from an earlier version: what they were granted wasn't recorded.
            return (["This Oura sign-in is from an earlier version of Tensile. Reconnect once so Tensile knows which permissions Oura granted."]
                    + [extrasText].compactMap { $0 }).joined(separator: " ")
        }
        var parts: [String] = []
        if !core.isEmpty {
            parts.append("Oura didn't grant the \(list(core)) permission\(core.count == 1 ? "" : "s") Tensile needs for your sleep, HRV and sleeping heart rate.")
        }
        if let extrasText { parts.append(extrasText) }
        parts.append("Reconnect and allow \(missing.count == 1 ? "it" : "them").")
        return parts.joined(separator: " ")
    }

    /// "a", "a and b", "a, b and c".
    static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        return items.count == 1 ? last : items.dropLast().joined(separator: ", ") + " and " + last
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

    /// An error is read before the state: an error redirect may come back
    /// without one. An error whose state doesn't match is still ignored.
    public static func callback(_ url: URL, expectedState: String) -> Callback {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return .invalid }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            if let state = value("state"), state != expectedState { return .wrongState }
            return .denied(error)
        }
        guard value("state") == expectedState else { return .wrongState }
        guard let code = value("code"), !code.isEmpty else { return .invalid }
        return .code(code)
    }

    /// Form body for the token endpoint (`application/x-www-form-urlencoded`).
    /// Oura still needs the client secret when PKCE is used (Oura API, "Authentication").
    public static func tokenRequestBody(_ grant: Grant, clientID: String, clientSecret: String) -> Data {
        var fields: [(String, String)]
        switch grant {
        case let .code(code, redirectURI, codeVerifier):
            fields = [("grant_type", "authorization_code"), ("code", code), ("redirect_uri", redirectURI),
                      ("code_verifier", codeVerifier)]
        case let .refresh(token):
            fields = [("grant_type", "refresh_token"), ("refresh_token", token)]
        }
        fields += [("client_id", clientID), ("client_secret", clientSecret)]
        return Data(fields.map { "\(formEncode($0.0))=\(formEncode($0.1))" }.joined(separator: "&").utf8)
    }

    public enum Grant: Sendable, Equatable {
        /// The sign-in code, the redirect address sent with it, and the PKCE verifier.
        case code(String, redirectURI: String, codeVerifier: String)
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
        /// The permissions granted, when Oura says (OAuth 2, RFC 6749 §5.1).
        public var scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case scope
        }

        /// Tokens to keep, with the expiry as a date (a minute early, so a
        /// request never goes out with a token about to lapse). The scope is
        /// Oura's answer, else the previous tokens'. What was asked for is
        /// never recorded as granted (the owner can untick a permission on
        /// Oura's page): a fresh sign-in whose reply doesn't say is marked
        /// `scopeUnreported` instead, so it isn't asked to reconnect again.
        public func tokens(now: Date = .now, keeping previous: Tokens? = nil) -> Tokens {
            let granted = scope ?? previous?.scope
            let unreported = granted == nil && (previous.map { $0.scopeUnreported == true } ?? true)
            return Tokens(accessToken: accessToken,
                          refreshToken: refreshToken ?? previous?.refreshToken,
                          expiresAt: expiresIn.map { now.addingTimeInterval(max(0, $0 - 60)) },
                          scope: granted,
                          scopeUnreported: unreported ? true : nil)
        }
    }

    public struct Tokens: Codable, Sendable, Equatable {
        public var accessToken: String
        public var refreshToken: String?
        public var expiresAt: Date?
        /// The permissions this sign-in was granted; nil for tokens saved
        /// before the app recorded it, or when Oura's reply didn't say
        /// (`scopeUnreported`; `needsReconnect`).
        public var scope: String?
        /// True when this sign-in's reply didn't say what was granted; nil
        /// for tokens with a scope or saved before the app recorded one.
        public var scopeUnreported: Bool?

        public init(accessToken: String, refreshToken: String?, expiresAt: Date?, scope: String? = nil,
                    scopeUnreported: Bool? = nil) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
            self.scope = scope
            self.scopeUnreported = scopeUnreported
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
        /// Average and lowest heart rate while asleep (bpm), from 30-second
        /// samples, so they can differ a little from the Oura app (spec 1.43).
        public var averageHeartRate: Double?
        public var lowestHeartRate: Double?
        /// Breaths a minute.
        public var averageBreath: Double?
        /// °C from the user's usual skin temperature (the sleep's
        /// `readiness.temperature_deviation`; only this one field of Oura's
        /// readiness is read, never its score).
        public var temperatureDeviation: Double?
        /// Oura flagged that the ring's battery ran low during this period,
        /// so the night may be incomplete.
        public var lowBatteryAlert: Bool?

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
            /// Top level in this app's cache; inside `readiness` in Oura's answer.
            case temperatureDeviation = "temperature_deviation"
            case lowBatteryAlert = "low_battery_alert"
        }

        private enum NestedKeys: String, CodingKey {
            case readiness
        }

        private enum ReadinessKeys: String, CodingKey {
            case temperatureDeviation = "temperature_deviation"
        }

        public init(id: String, day: String, bedtimeStart: Date, bedtimeEnd: Date, type: String? = "long_sleep",
                    sleepPhase5Min: String? = nil, totalSleepDuration: Double? = nil, averageHRV: Double? = nil,
                    lowestHeartRate: Double? = nil, efficiency: Double? = nil, averageHeartRate: Double? = nil,
                    averageBreath: Double? = nil, temperatureDeviation: Double? = nil, lowBatteryAlert: Bool? = nil) {
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
            self.averageHeartRate = averageHeartRate
            self.averageBreath = averageBreath
            self.temperatureDeviation = temperatureDeviation
            self.lowBatteryAlert = lowBatteryAlert
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
            lowBatteryAlert = try c.decodeIfPresent(Bool.self, forKey: .lowBatteryAlert)
            if let cached = try c.decodeIfPresent(Double.self, forKey: .temperatureDeviation) {
                temperatureDeviation = cached
            } else {
                let nested = try decoder.container(keyedBy: NestedKeys.self)
                let readiness = try? nested.nestedContainer(keyedBy: ReadinessKeys.self, forKey: .readiness)
                temperatureDeviation = try readiness?.decodeIfPresent(Double.self, forKey: .temperatureDeviation)
            }
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

    // Oura's Readiness and Sleep scores (`/daily_readiness`, `/daily_sleep`)
    // never feed Tensile's scores: they are proprietary composites with
    // unpublished weights and no published validation against an outcome, the
    // same reason Apple's own scores were removed (docs/research/oura-ring-2026-11.md
    // §5-6, [R49]; apple-scores-2026-11.md). They are downloaded only for the
    // display-only "Oura's own numbers" panel (`OuraOwnNumbers`), on the
    // owner's request.

    // MARK: Nights

    /// The morning a sample belongs to, as the app files nights: the start
    /// of the day 6 hours after it starts (`HealthKitClient.sleepHistory`).
    public static func morning(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(6 * 3600))
    }

    /// The morning a sleep period is filed under: Oura's `day` (the local
    /// date of the morning it ended, in the time zone the ring was in) as
    /// that date in `calendar`, so a night slept in another time zone keeps
    /// its date; the morning of its bedtime start (`morning(of:)`) when `day`
    /// doesn't read as a date.
    public static func morning(of period: SleepPeriod, calendar: Calendar = .current) -> Date {
        day(period.day, calendar: calendar) ?? morning(of: period.bedtimeStart, calendar: calendar)
    }

    /// "YYYY-MM-DD" as the start of that date in `calendar`; nil when it isn't a real date.
    static func day(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// The main sleep for each morning (`morning(of:)`): the longest sleep period filed under it.
    public static func mainSleep(_ periods: [SleepPeriod], calendar: Calendar = .current) -> [Date: SleepPeriod] {
        var result: [Date: SleepPeriod] = [:]
        for period in periods where period.isSleep {
            let morning = morning(of: period, calendar: calendar)
            let length = period.bedtimeEnd.timeIntervalSince(period.bedtimeStart)
            if let current = result[morning], current.bedtimeEnd.timeIntervalSince(current.bedtimeStart) >= length { continue }
            result[morning] = period
        }
        return result
    }

    /// One value per morning from each main sleep; missing or zero values are left out.
    public static func nightly(_ periods: [SleepPeriod], _ value: (SleepPeriod) -> Double?,
                               calendar: Calendar = .current) -> [Date: Double] {
        mainSleep(periods, calendar: calendar).compactMapValues { period in
            value(period).flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        }
    }

    /// Overnight HRV (RMSSD, ms) by morning, from each main sleep. Oura Gen 4
    /// agreed with ECG at CCC 0.99, MAPE 6.0% (Dial et al., Physiol Rep 2025).
    public static func nightlyRMSSD(_ periods: [SleepPeriod], calendar: Calendar = .current) -> [Date: Double] {
        nightly(periods, { $0.averageHRV }, calendar: calendar)
    }

    /// Average sleeping heart rate (bpm) by morning, from each main sleep:
    /// the same quantity as the watch's sleeping heart rate (the mean while
    /// asleep), so the two can stand in for each other night by night but are
    /// never mixed in one baseline (`OneDeviceBaseline`). Oura Gen 4 nocturnal
    /// heart rate agreed with ECG at CCC 0.98, MAPE 1.9% (Dial et al., Physiol
    /// Rep 2025). The lowest heart rate is a different quantity (the night's
    /// minimum) and isn't used for the baseline.
    public static func nightlySleepingHeartRate(_ periods: [SleepPeriod], calendar: Calendar = .current) -> [Date: Double] {
        nightly(periods, { $0.averageHeartRate }, calendar: calendar)
    }

    /// Average breathing rate (breaths a minute) by morning. Weak evidence:
    /// only a company comparison with ECG-derived rate (0.71 breaths/min mean
    /// error), no PSG study (docs/research/oura-ring-2026-11.md §5), so it's
    /// used only as a change-from-baseline flag.
    public static func nightlyBreathingRate(_ periods: [SleepPeriod], calendar: Calendar = .current) -> [Date: Double] {
        nightly(periods, { $0.averageBreath }, calendar: calendar)
    }

    /// Sleep samples from every sleep period that starts between `start` and `end`.
    public static func samples(_ periods: [SleepPeriod], from start: Date, to end: Date) -> [SleepSample] {
        periods
            .filter { $0.isSleep && $0.bedtimeStart >= start && $0.bedtimeStart < end }
            .sorted { $0.bedtimeStart < $1.bedtimeStart }
            .flatMap { $0.samples() }
    }

    /// The cached sleep periods after a sync. A fresh period replaces a cached
    /// one with the same id. When the sync fetched every page, it is the whole
    /// truth for the days it covered (`coveredDays`, "YYYY-MM-DD", inclusive):
    /// a cached period filed on one of those days that Oura no longer returns
    /// (re-processed under a new id, or deleted) is dropped, so a night never
    /// counts twice. Pass nil when a page is missing. Deleted periods and
    /// those that ended before `cutoff` are dropped. Oldest first.
    public static func mergePeriods(cached: [SleepPeriod], fresh: [SleepPeriod],
                                    coveredDays: ClosedRange<String>?, cutoff: Date) -> [SleepPeriod] {
        let kept = coveredDays.map { days in cached.filter { !days.contains($0.day) } } ?? cached
        var byID = Dictionary(kept.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for period in fresh { byID[period.id] = period }
        return byID.values
            .filter { $0.bedtimeEnd >= cutoff && $0.type != "deleted" }
            .sorted { ($0.bedtimeStart, $0.id) < ($1.bedtimeStart, $1.id) }
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
