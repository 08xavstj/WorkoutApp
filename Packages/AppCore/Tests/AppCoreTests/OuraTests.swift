import Foundation
import Testing
@testable import AppCore

struct OuraTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// A trimmed `/sleep` response in Oura's format.
    let sleepJSON = """
    {
      "data": [
        {
          "id": "a1",
          "day": "2026-11-10",
          "bedtime_start": "2026-11-09T23:00:00+00:00",
          "bedtime_end": "2026-11-10T00:00:00+00:00",
          "type": "long_sleep",
          "sleep_phase_5_min": "442211112233",
          "total_sleep_duration": 3000,
          "deep_sleep_duration": 1200,
          "light_sleep_duration": 1200,
          "rem_sleep_duration": 600,
          "awake_time": 600,
          "efficiency": 83,
          "average_hrv": 54,
          "average_heart_rate": 55.5,
          "lowest_heart_rate": 48,
          "average_breath": 14.25,
          "heart_rate": {"interval": 300, "items": [null, 50], "timestamp": "2026-11-09T23:00:00.000+00:00"},
          "readiness": {"score": 81, "temperature_deviation": -0.2, "temperature_trend_deviation": 0.1, "contributors": {"hrv_balance": 75}},
          "low_battery_alert": true
        },
        {
          "id": "a2",
          "day": "2026-11-10",
          "bedtime_start": "2026-11-10T14:00:00.000+00:00",
          "bedtime_end": "2026-11-10T14:30:00.000+00:00",
          "type": "late_nap",
          "average_hrv": null
        }
      ],
      "next_token": "abc"
    }
    """

    func page() throws -> Oura.Page<Oura.SleepPeriod> {
        try JSONDecoder().decode(Oura.Page<Oura.SleepPeriod>.self, from: Data(sleepJSON.utf8))
    }

    @Test func decodesSleepPeriods() throws {
        let page = try page()
        #expect(page.data.count == 2)
        #expect(page.nextToken == "abc")
        let night = page.data[0]
        #expect(night.bedtimeStart == Date(timeIntervalSince1970: 1_794_265_200))
        #expect(night.averageHRV == 54)
        #expect(night.lowestHeartRate == 48)
        #expect(night.isSleep)
        #expect(!page.data[1].isSleep)
    }

    @Test func hypnogramBecomesSamples() throws {
        let samples = try page().data[0].samples()
        #expect(samples.map(\.stage) == [.awake, .core, .deep, .core, .rem])
        #expect(samples.map { $0.duration / 60 } == [10, 10, 20, 10, 10])
        #expect(samples.allSatisfy { $0.tracker == .ring && $0.source == "Oura" })
        #expect(samples.last?.end == Date(timeIntervalSince1970: 1_794_268_800))
    }

    @Test func lastPhaseStopsAtBedtimeEnd() {
        let start = Date(timeIntervalSince1970: 0)
        let period = Oura.SleepPeriod(id: "x", day: "1970-01-01", bedtimeStart: start, bedtimeEnd: start.addingTimeInterval(420),
                                      sleepPhase5Min: "12")
        #expect(period.samples().last?.end == start.addingTimeInterval(420))
    }

    @Test func noHypnogramIsUnstagedSleep() {
        let start = Date(timeIntervalSince1970: 0)
        let period = Oura.SleepPeriod(id: "x", day: "1970-01-01", bedtimeStart: start, bedtimeEnd: start.addingTimeInterval(3600))
        #expect(period.samples().map(\.stage) == [.unspecified])
    }

    @Test func nightlyRMSSDUsesTheMainSleepByMorning() throws {
        let rmssd = Oura.nightlyRMSSD(try page().data, calendar: calendar)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        #expect(rmssd == [morning: 54])
    }

    @Test func nightlySleepingHeartRateAndBreathingUseTheMainSleep() throws {
        let data = try page().data
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        // The average while asleep, not the lowest: the same quantity as the watch's sleeping heart rate.
        #expect(Oura.nightlySleepingHeartRate(data, calendar: calendar) == [morning: 55.5])
        #expect(Oura.nightlyBreathingRate(data, calendar: calendar) == [morning: 14.25])
    }

    @Test func nightlyLeavesOutMissingAndZeroValues() {
        let start = Date(timeIntervalSince1970: 1_794_265_200)
        let zero = Oura.SleepPeriod(id: "z", day: "2026-11-10", bedtimeStart: start, bedtimeEnd: start.addingTimeInterval(8 * 3600),
                                    averageHRV: 0, averageHeartRate: nil)
        #expect(Oura.nightlyRMSSD([zero], calendar: calendar).isEmpty)
        #expect(Oura.nightlySleepingHeartRate([zero], calendar: calendar).isEmpty)
    }

    @Test func decodesTemperatureAndBatteryFromTheSleepPeriod() throws {
        let night = try page().data[0]
        // Only the temperature change is read from the sleep's readiness object, never its score.
        #expect(night.temperatureDeviation == -0.2)
        #expect(night.lowBatteryAlert == true)
        #expect(night.averageHeartRate == 55.5)
        #expect(try page().data[1].temperatureDeviation == nil)
    }

    @Test func samplesInAWindowSkipNaps() throws {
        let data = try page().data
        let from = Date(timeIntervalSince1970: 1_794_265_200 - 3600)
        let samples = Oura.samples(data, from: from, to: from.addingTimeInterval(24 * 3600))
        #expect(samples.count == 5)
    }

    @Test func cachedPeriodsRoundTrip() throws {
        let night = try page().data[0]
        let data = try JSONEncoder().encode(night)
        let decoded = try JSONDecoder().decode(Oura.SleepPeriod.self, from: data)
        #expect(decoded == night)
        // The cache keeps the temperature change at the top level.
        #expect(decoded.temperatureDeviation == -0.2)
    }

    @Test func aCacheFromBeforeTheScoresWereDroppedStillDecodes() throws {
        // An older cache also held `readiness` and `dailySleep` lists: they are ignored.
        struct Contents: Decodable { var periods: [Oura.SleepPeriod] }
        let night = try page().data[0]
        let periods = String(decoding: try JSONEncoder().encode([night]), as: UTF8.self)
        let old = """
        {"periods": \(periods), "readiness": [{"day": "2026-11-10", "score": 81}], "dailySleep": [{"day": "2026-11-10", "score": 77}]}
        """
        #expect(try JSONDecoder().decode(Contents.self, from: Data(old.utf8)).periods == [night])
    }

    // MARK: Sign-in

    @Test func authorizationURLCarriesTheRequest() throws {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let url = try #require(Oura.authorizationURL(clientID: "id 1", redirectURI: Oura.defaultRedirectURI, state: "s1",
                                                     codeVerifier: verifier))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(url.host() == "cloud.ouraring.com")
        #expect(value("response_type") == "code")
        #expect(value("client_id") == "id 1")
        #expect(value("redirect_uri") == "workoutapp://oura")
        #expect(value("scope") == Oura.scopes)
        #expect(value("state") == "s1")
        // PKCE: only the hash goes out with the sign-in, never the verifier.
        #expect(value("code_challenge") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(value("code_challenge_method") == "S256")
        #expect(!url.absoluteString.contains(verifier))
    }

    @Test func scopesAreOnlyWhatIsUsed() {
        #expect(Oura.scopes == "daily")
        #expect(Oura.userAgent == "Tensile/1.0")
    }

    @Test func anOldOrMissingScopeAsksToReconnectOnce() {
        // Tokens from before the scopes were trimmed: no scope recorded.
        #expect(Oura.needsReconnect(grantedScope: nil))
        // A permission the app needs is missing.
        #expect(Oura.needsReconnect(grantedScope: ""))
        #expect(Oura.needsReconnect(grantedScope: "personal heartrate"))
        #expect(!Oura.needsReconnect(grantedScope: "daily"))
        #expect(!Oura.needsReconnect(grantedScope: "DAILY "))
        // Extras Oura still reports after a fresh sign-in don't ask again.
        #expect(!Oura.needsReconnect(grantedScope: "personal daily heartrate"))
    }

    @Test func tokensRecordTheScope() throws {
        let response = try JSONDecoder().decode(Oura.TokenResponse.self, from: Data("""
        {"access_token": "a1", "refresh_token": "r1", "expires_in": 86400}
        """.utf8))
        // Oura didn't say: the scope asked for is kept.
        #expect(response.tokens(requestedScope: "daily").scope == "daily")
        // A refresh keeps the scope of the tokens it replaces.
        let old = Oura.Tokens(accessToken: "a0", refreshToken: "r0", expiresAt: nil, scope: "personal daily heartrate")
        #expect(response.tokens(keeping: old).scope == "personal daily heartrate")
        // Oura's own answer wins.
        let granted = try JSONDecoder().decode(Oura.TokenResponse.self, from: Data("""
        {"access_token": "a1", "scope": "daily"}
        """.utf8))
        #expect(granted.tokens(keeping: old).scope == "daily")
    }

    @Test func tokensSavedBeforeTheScopeWasRecordedStillDecode() throws {
        let saved = Data(#"{"accessToken": "a", "refreshToken": "r"}"#.utf8)
        let tokens = try JSONDecoder().decode(Oura.Tokens.self, from: saved)
        #expect(tokens.scope == nil)
        #expect(Oura.needsReconnect(grantedScope: tokens.scope))
    }

    @Test func callbackChecksTheState() throws {
        let good = try #require(URL(string: "workoutapp://oura?code=abc&state=s1"))
        #expect(Oura.callback(good, expectedState: "s1") == .code("abc"))
        #expect(Oura.callback(good, expectedState: "other") == .wrongState)
        let denied = try #require(URL(string: "workoutapp://oura?error=access_denied&state=s1"))
        #expect(Oura.callback(denied, expectedState: "s1") == .denied("access_denied"))
        let empty = try #require(URL(string: "workoutapp://oura?state=s1"))
        #expect(Oura.callback(empty, expectedState: "s1") == .invalid)
    }

    @Test func tokenBodyIsFormEncoded() {
        let body = String(decoding: Oura.tokenRequestBody(.code("a/b+c", redirectURI: "workoutapp://oura", codeVerifier: "v-1_2.3~4"),
                                                          clientID: "id", clientSecret: "s&t"), as: UTF8.self)
        // The verifier goes with the code; Oura still needs the client secret alongside it.
        #expect(body == "grant_type=authorization_code&code=a%2Fb%2Bc&redirect_uri=workoutapp%3A%2F%2Foura&code_verifier=v-1_2.3~4&client_id=id&client_secret=s%26t")
        let refresh = String(decoding: Oura.tokenRequestBody(.refresh("r1"), clientID: "id", clientSecret: "s"), as: UTF8.self)
        #expect(refresh == "grant_type=refresh_token&refresh_token=r1&client_id=id&client_secret=s")
    }

    @Test func tokensExpireAMinuteEarlyAndKeepTheOldRefreshToken() throws {
        let response = try JSONDecoder().decode(Oura.TokenResponse.self, from: Data("""
        {"access_token": "a2", "token_type": "bearer", "expires_in": 86400}
        """.utf8))
        let now = Date(timeIntervalSince1970: 1000)
        let previous = Oura.Tokens(accessToken: "a1", refreshToken: "r1", expiresAt: nil)
        let tokens = response.tokens(now: now, keeping: previous)
        #expect(tokens.accessToken == "a2")
        #expect(tokens.refreshToken == "r1")
        #expect(tokens.expiresAt == now.addingTimeInterval(86_340))
        #expect(!tokens.isExpired(now: now))
        #expect(tokens.isExpired(now: now.addingTimeInterval(86_400)))
    }
}

struct SleepSourcePickTests {
    let start = Date(timeIntervalSince1970: 0)

    func sample(_ stage: SleepStage, _ minutes: Double, _ tracker: SleepTracker?) -> SleepSample {
        SleepSample(stage: stage, start: start, end: start.addingTimeInterval(minutes * 60), tracker: tracker)
    }

    @Test func trackerFromTheHealthSource() {
        #expect(SleepSource.tracker(bundleID: "com.ouraring.oura", sourceName: "Oura", deviceModel: nil) == .ring)
        #expect(SleepSource.tracker(bundleID: "com.apple.health.ABC", sourceName: "Alex's Apple Watch", deviceModel: "Watch") == .watch)
        #expect(SleepSource.tracker(bundleID: "com.apple.health.DEF", sourceName: "iPhone", deviceModel: "iPhone") == .other)
    }

    @Test func ringFirstKeepsOnlyTheRingsNight() {
        let night = [sample(.core, 60, .watch), sample(.deep, 50, .ring), sample(.inBed, 480, .other)]
        #expect(SleepSource.pick(night, prefer: .ring).map(\.tracker) == [.ring])
        #expect(SleepSource.pick(night, prefer: .watch).map(\.tracker) == [.watch])
        #expect(SleepSource.pick(night, prefer: .combined) == night)
    }

    @Test func fallsBackWhenThePreferredDeviceHasNoSleep() {
        // The ring only logged awake time (or nothing): the watch's night stands.
        let night = [sample(.core, 60, .watch), sample(.awake, 10, .ring)]
        #expect(SleepSource.pick(night, prefer: .ring) == night)
    }

    @Test func aRingFragmentDoesNotReplaceTheWatchsNight() {
        // The ring died after 2 h (or logged an evening doze); the watch has 7 h.
        let short = [sample(.core, 420, .watch), sample(.core, 120, .ring)]
        #expect(SleepSource.pick(short, prefer: .ring).map(\.tracker) == [.watch])
        // 5 h 30 of the watch's 7 h is enough (over 70%): the ring stands.
        let enough = [sample(.core, 420, .watch), sample(.core, 330, .ring)]
        #expect(SleepSource.pick(enough, prefer: .ring).map(\.tracker) == [.ring])
        // Two other trackers aren't added together: the longest one is the yardstick.
        let two = [sample(.core, 200, .watch), sample(.core, 200, .other), sample(.core, 150, .ring)]
        #expect(SleepSource.pick(two, prefer: .ring).map(\.tracker) == [.ring])
    }

    @Test func picksNightByNight() {
        let day = 86_400.0
        let first = [sample(.core, 60, .watch), sample(.core, 60, .ring)]
        let second = [SleepSample(stage: .core, start: start.addingTimeInterval(day), end: start.addingTimeInterval(day + 3600), tracker: .watch)]
        let picked = SleepSource.pick(first + second, prefer: .ring) { Calendar.current.startOfDay(for: $0.start) }
        #expect(picked.map(\.tracker) == [.ring, .watch])
    }

    @Test func ringIsTheDefault() {
        #expect(SleepSourcePreference.standard == .ring)
    }
}

struct VO2SourceTests {
    @Test func estimateFirstByDefault() {
        #expect(VO2Source.standard == .estimate)
        let picked = VO2Source.pick(watch: 41, estimate: 47, prefer: .standard)
        #expect(picked?.value == 47)
        #expect(picked?.isEstimate == true)
    }

    @Test func eachFallsBackToTheOther() {
        #expect(VO2Source.pick(watch: nil, estimate: 47, prefer: .watch)?.isEstimate == true)
        #expect(VO2Source.pick(watch: 41, estimate: nil, prefer: .estimate)?.value == 41)
        #expect(VO2Source.pick(watch: nil, estimate: nil, prefer: .estimate) == nil)
    }

    @Test func combinedIsTheMean() throws {
        let heart = VO2MaxEstimate.Result(method: .heartRateRatio, value: 50, error: 6)
        let activity = VO2MaxEstimate.Result(method: .activity, value: 44, error: 5)
        let both = try #require(VO2MaxEstimate.combined([heart, activity]))
        #expect(both.value == 47)
        #expect(both.error == 5.5)
        #expect(both.method == .combined)
        #expect(VO2MaxEstimate.combined([heart]) == heart)
        #expect(VO2MaxEstimate.combined([]) == nil)
    }
}
