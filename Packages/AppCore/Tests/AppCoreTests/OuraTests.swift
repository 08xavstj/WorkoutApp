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
        // Oura didn't say: what was asked for is not recorded as granted, and
        // the sign-in is marked so it isn't asked to reconnect again and again.
        let fresh = response.tokens()
        #expect(fresh.scope == nil)
        #expect(fresh.scopeUnreported == true)
        #expect(!Oura.needsReconnect(grantedScope: fresh.scope, required: "daily spo2 heart_health",
                                     scopeUnreported: fresh.scopeUnreported == true))
        // ...and a refresh that doesn't say either keeps that mark.
        #expect(response.tokens(keeping: fresh).scopeUnreported == true)
        // A refresh keeps the scope of the tokens it replaces.
        let old = Oura.Tokens(accessToken: "a0", refreshToken: "r0", expiresAt: nil, scope: "personal daily heartrate")
        #expect(response.tokens(keeping: old).scope == "personal daily heartrate")
        #expect(response.tokens(keeping: old).scopeUnreported == nil)
        // Oura's own answer wins.
        let granted = try JSONDecoder().decode(Oura.TokenResponse.self, from: Data("""
        {"access_token": "a1", "scope": "daily"}
        """.utf8))
        #expect(granted.tokens(keeping: old).scope == "daily")
        #expect(granted.tokens(keeping: fresh).scopeUnreported == nil)
        // Tokens from before the scope was recorded still ask once, even after a silent refresh.
        let legacy = Oura.Tokens(accessToken: "a0", refreshToken: "r0", expiresAt: nil)
        let refreshed = response.tokens(keeping: legacy)
        #expect(Oura.needsReconnect(grantedScope: refreshed.scope, scopeUnreported: refreshed.scopeUnreported == true))
    }

    @Test func missingScopesAreListedInOrder() {
        #expect(Oura.missingScopes(granted: "daily", required: "daily spo2 heart_health") == ["spo2", "heart_health"])
        #expect(Oura.missingScopes(granted: "HEART_HEALTH+daily", required: "daily spo2 heart_health") == ["spo2"])
        #expect(Oura.missingScopes(granted: "personal daily spo2 heart_health", required: "daily spo2 heart_health").isEmpty)
        #expect(Oura.missingScopes(granted: nil, required: "daily spo2") == ["daily", "spo2"])
        #expect(Oura.missingScopes(granted: "daily", required: "daily").isEmpty)
    }

    @Test func theReconnectPromptNamesWhatIsMissing() throws {
        let all = Oura.requestedScopes(ownNumbers: true)
        // Nothing missing: no prompt.
        #expect(Oura.reconnectPrompt(grantedScope: "daily spo2 heart_health", required: all) == nil)
        #expect(Oura.reconnectPrompt(grantedScope: "daily", required: Oura.requestedScopes(ownNumbers: false)) == nil)
        // Only the panel's permissions missing: named, and said to be only for Oura's own numbers.
        let extras = try #require(Oura.reconnectPrompt(grantedScope: "daily", required: all))
        #expect(extras.contains("spo2 and heart_health"))
        #expect(extras.contains("only for that panel"))
        #expect(!extras.contains("Tensile needs"))
        let one = try #require(Oura.reconnectPrompt(grantedScope: "daily spo2", required: all))
        #expect(one.contains("heart_health permission,"))
        #expect(!one.contains("spo2 and"))
        // The permission Tensile's own scores need.
        let core = try #require(Oura.reconnectPrompt(grantedScope: "spo2 heart_health", required: all))
        #expect(core.contains("daily permission Tensile needs"))
        // An earlier version's tokens: what was granted is unknown.
        let legacy = try #require(Oura.reconnectPrompt(grantedScope: nil, required: all))
        #expect(legacy.contains("earlier version"))
        #expect(Oura.reconnectPrompt(grantedScope: nil, required: all, scopeUnreported: true) == nil)
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
        // A code without the right state is never used.
        let noState = try #require(URL(string: "workoutapp://oura?code=abc"))
        #expect(Oura.callback(noState, expectedState: "s1") == .wrongState)
    }

    @Test func anErrorIsReadEvenWithoutState() throws {
        // An error redirect may come back without the state.
        let bare = try #require(URL(string: "workoutapp://oura?error=invalid_scope"))
        #expect(Oura.callback(bare, expectedState: "s1") == .denied("invalid_scope"))
        // One with someone else's state is still ignored.
        let forged = try #require(URL(string: "workoutapp://oura?error=invalid_scope&state=other"))
        #expect(Oura.callback(forged, expectedState: "s1") == .wrongState)
    }

    // MARK: Cache merge

    func period(_ id: String, day: String, hour: Double = 0) -> Oura.SleepPeriod {
        let start = Date(timeIntervalSince1970: 1_794_265_200 + hour * 3600)
        return Oura.SleepPeriod(id: id, day: day, bedtimeStart: start, bedtimeEnd: start.addingTimeInterval(8 * 3600))
    }

    @Test func aCompleteSyncReplacesTheDaysItCovered() {
        let cutoff = Date(timeIntervalSince1970: 0)
        let cached = [period("old", day: "2026-11-10"), period("kept", day: "2026-11-01", hour: -200), period("same", day: "2026-11-11", hour: 24)]
        // Oura re-processed the 10th under a new id.
        let fresh = [period("new", day: "2026-11-10"), period("same", day: "2026-11-11", hour: 24)]
        let merged = Oura.mergePeriods(cached: cached, fresh: fresh, coveredDays: "2026-11-05"..."2026-11-11", cutoff: cutoff)
        #expect(merged.map(\.id) == ["kept", "new", "same"])
    }

    @Test func anIncompleteSyncOnlyAddsAndReplacesByID() {
        let cutoff = Date(timeIntervalSince1970: 0)
        let cached = [period("old", day: "2026-11-10")]
        let fresh = [period("new", day: "2026-11-10", hour: 1)]
        let merged = Oura.mergePeriods(cached: cached, fresh: fresh, coveredDays: nil, cutoff: cutoff)
        #expect(merged.map(\.id) == ["old", "new"])
    }

    @Test func mergeDropsDeletedAndOldPeriods() {
        var deleted = period("d", day: "2026-11-10")
        deleted.type = "deleted"
        let old = period("o", day: "2026-10-01", hour: -24 * 40)
        let cutoff = Date(timeIntervalSince1970: 1_794_265_200 - 24 * 3600 * 10)
        #expect(Oura.mergePeriods(cached: [old], fresh: [deleted], coveredDays: nil, cutoff: cutoff).isEmpty)
    }

    // MARK: Night dates

    @Test func nightsAreFiledByOurasDay() throws {
        // Slept in Tokyo: in bed 23:00 +09:00 (14:00 UTC), up 07:00 +09:00 on the 10th.
        let json = """
        {"data": [{"id": "t1", "day": "2026-11-10", "bedtime_start": "2026-11-09T23:00:00+09:00",
                   "bedtime_end": "2026-11-10T07:00:00+09:00", "type": "long_sleep", "average_hrv": 50}]}
        """
        let periods = try JSONDecoder().decode(Oura.Page<Oura.SleepPeriod>.self, from: Data(json.utf8)).data
        // Back home on UTC, the bedtime start alone would file it under the 9th.
        let tenth = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        let ninth = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!
        #expect(Oura.morning(of: periods[0].bedtimeStart, calendar: calendar) == ninth)
        #expect(Oura.nightlyRMSSD(periods, calendar: calendar) == [tenth: 50])
        // The same in a phone set to Los Angeles.
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let tenthLA = losAngeles.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        #expect(Oura.mainSleep(periods, calendar: losAngeles).keys.sorted() == [tenthLA])
    }

    @Test func anUnreadableDayFallsBackToTheBedtime() {
        let start = Date(timeIntervalSince1970: 1_794_265_200) // 2026-11-09 23:00 UTC
        let night = Oura.SleepPeriod(id: "x", day: "10 Nov", bedtimeStart: start, bedtimeEnd: start.addingTimeInterval(8 * 3600), averageHRV: 40)
        let impossible = Oura.SleepPeriod(id: "y", day: "2026-02-30", bedtimeStart: start, bedtimeEnd: start.addingTimeInterval(8 * 3600))
        let tenth = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        #expect(Oura.nightlyRMSSD([night], calendar: calendar) == [tenth: 40])
        #expect(Oura.morning(of: impossible, calendar: calendar) == tenth)
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

    @Test func aWatchWhoseNameContainsOuraIsNotTheRing() {
        // A name with "oura" inside a word, from a watch with its own bundle ID.
        #expect(SleepSource.tracker(bundleID: "com.apple.health.ABC", sourceName: "Ana Moura's Apple Watch", deviceModel: "Watch") == .watch)
        // With a bundle ID, the name doesn't decide, even as a whole word.
        #expect(SleepSource.tracker(bundleID: "com.apple.health.ABC", sourceName: "Oura fan's Apple Watch", deviceModel: "Watch") == .watch)
        // Without one, only "Oura" as a whole word is the ring.
        #expect(SleepSource.tracker(bundleID: nil, sourceName: "Ana Moura's Apple Watch (Health)", deviceModel: nil) == .other)
        #expect(SleepSource.tracker(bundleID: nil, sourceName: "Oura Ring (Oura)", deviceModel: nil) == .ring)
        #expect(SleepSource.tracker(bundleID: "", sourceName: "OURA", deviceModel: nil) == .ring)
        #expect(SleepSource.tracker(bundleID: "COM.OURARING.OURA", sourceName: "Ring", deviceModel: nil) == .ring)
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
