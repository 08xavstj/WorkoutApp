import Foundation
import AppCore
import os

/// The sleep source setting, readable anywhere (Health reads run off the
/// main actor). Settings writes it with `@AppStorage(SleepSourceSetting.key)`.
nonisolated enum SleepSourceSetting {
    static let key = "sleepSourcePreference"

    static var current: SleepSourcePreference {
        UserDefaults.standard.string(forKey: key).flatMap(SleepSourcePreference.init(rawValue:)) ?? .standard
    }
}

/// The direct link to the user's Oura account (Oura API v2).
///
/// Sign-in uses the user's own Oura developer app: they create one at
/// developer.ouraring.com (free) and type its client ID and secret here, so
/// no secret ships in the app. The sign-in itself happens on Oura's page
/// (`OuraSettingsView` opens it) with PKCE (`PKCE`), and the tokens are kept
/// in the Keychain. Syncing downloads the sleep periods for recent days into
/// `OuraCache`, and, while the "Oura's own numbers" panel is on, Oura's own
/// scores into `OuraOwnNumbersStore` for display only (`OuraOwnNumbers`).
/// Nothing about the user is sent to Oura beyond the sign-in, and requests
/// carry a generic User-Agent (`Oura.userAgent`).
@Observable
final class OuraLink {
    static let shared = OuraLink()

    nonisolated enum Status: Equatable {
        /// No client ID and secret yet.
        case needsSetup
        case disconnected
        case connected
    }

    private enum Account {
        static let clientID = "oura.clientID"
        static let clientSecret = "oura.clientSecret"
        static let redirectURI = "oura.redirectURI"
        static let tokens = "oura.tokens"
        static let all = [clientID, clientSecret, redirectURI, tokens]
    }

    /// Set once this install has checked for a sign-in left over from an
    /// earlier install (`forgetKeychainAfterReinstall`).
    private static let installCheckedKey = "ouraKeychainInstallChecked"

    private(set) var status: Status = .needsSetup
    private(set) var isSyncing = false
    /// The last sync or sign-in problem, in plain words; nil once one works.
    private(set) var lastError: String?
    private(set) var syncedAt: Date?
    /// Connected, but the saved sign-in predates the recorded permissions or
    /// lacks one the app asks for (`Oura.needsReconnect`): Settings and the
    /// Oura card ask for one reconnect instead of syncs failing unexplained.
    private(set) var needsReconnect = false
    /// The permissions Oura reported for this sign-in; nil when unknown.
    private(set) var grantedScope: String?
    /// Why to reconnect, worded from what is actually missing
    /// (`Oura.reconnectPrompt`); nil when nothing is.
    private(set) var reconnectPrompt: String?
    /// The Keychain couldn't be read just now (the phone not yet unlocked
    /// since a restart, or a passing error). Not a sign-out: the sign-in is
    /// kept and read again at the next sync (`syncIfDue`).
    private(set) var keychainUnavailable = false

    var clientID: String { (try? KeychainStore.string(Account.clientID)) ?? "" }
    var redirectURI: String { (try? KeychainStore.string(Account.redirectURI)) ?? Oura.defaultRedirectURI }
    var hasCredentials: Bool { !clientID.isEmpty && (try? KeychainStore.string(Account.clientSecret))?.isEmpty == false }

    /// Days downloaded on the first sync, then on each later one.
    static let firstSyncDays = 90
    static let syncDays = 7
    /// At most one automatic sync this often (`syncIfDue`).
    static let minimumInterval: TimeInterval = 30 * 60

    @ObservationIgnored private var pendingState: String?
    /// The PKCE verifier for the sign-in in progress; only its hash leaves the phone before the token request.
    @ObservationIgnored private var pendingVerifier: String?
    /// The permissions the sign-in in progress asked for.
    @ObservationIgnored private var pendingScope: String?
    @ObservationIgnored private var refreshTask: Task<Oura.Tokens, Error>?
    /// Bumped by `disconnect()`: a sync, sign-in or token refresh that started
    /// before it checks this after each wait and drops what it got, so nothing
    /// is written back after the sign-in and its data were forgotten.
    @ObservationIgnored private var generation = 0

    private static let log = Logger(subsystem: "com.lontraindustries.workoutapp", category: "oura")
    private static let keychainMessage = "Couldn't read your Oura sign-in from this iPhone's Keychain just now. Tensile will try again shortly."

    /// Oura's requests skip `URLSession.shared`'s disk cache and cookie
    /// store, so neither health data nor tokens are kept in the app's caches.
    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    init() {
        Self.forgetKeychainAfterReinstall()
        syncedAt = OuraCache.shared.contents.syncedAt
        updateStatus()
    }

    /// Keychain items outlive the app, so after deleting and reinstalling it
    /// the old sign-in would come back connected. On an install's first launch
    /// (no flag in UserDefaults, which deleting the app clears) Oura's items
    /// are deleted. An update keeps its UserDefaults, and a version from before
    /// the flag is recognised by its Oura download in Application Support,
    /// which deleting the app also clears. Skipped while the Keychain can't be
    /// read (before the first unlock after a restart, when UserDefaults and the
    /// download can't be read either and would look like a fresh install).
    private static func forgetKeychainAfterReinstall() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: installCheckedKey) else { return }
        let saved: Bool
        do {
            saved = try Account.all.contains { try KeychainStore.data($0) != nil }
        } catch {
            return // Locked: check again on the next launch.
        }
        let cache = OuraCache.shared.contents
        if saved && cache.periods.isEmpty && cache.syncedAt == nil {
            for account in Account.all { KeychainStore.set(Data?.none, for: account) }
        }
        defaults.set(true, forKey: installCheckedKey)
    }

    private func updateStatus() {
        let tokens: Oura.Tokens?
        do {
            tokens = try KeychainStore.value(Oura.Tokens.self, Account.tokens)
        } catch {
            // Not a sign-out: keep the status and the tokens, and read again at the next sync.
            Self.log.error("Keychain read failed: \(error.localizedDescription, privacy: .public)")
            keychainUnavailable = true
            lastError = Self.keychainMessage
            return
        }
        if keychainUnavailable {
            keychainUnavailable = false
            if lastError == Self.keychainMessage { lastError = nil }
        }
        if let tokens {
            let required = OuraOwnNumbersSetting.requestedScopes
            let unreported = tokens.scopeUnreported == true
            status = .connected
            grantedScope = tokens.scope
            needsReconnect = Oura.needsReconnect(grantedScope: tokens.scope, required: required, scopeUnreported: unreported)
            reconnectPrompt = Oura.reconnectPrompt(grantedScope: tokens.scope, required: required, scopeUnreported: unreported)
        } else {
            status = hasCredentials ? .disconnected : .needsSetup
            grantedScope = nil
            needsReconnect = false
            reconnectPrompt = nil
        }
    }

    /// Said before sign-in opens when it will ask for more than Tensile's own
    /// scores need: which permissions, and that they are only for "Oura's own
    /// numbers". Nil when sign-in asks only for `Oura.scopes`.
    var signInPermissionsNote: String? {
        let extras = Oura.missingScopes(granted: Oura.scopes, required: OuraOwnNumbersSetting.requestedScopes)
        guard !extras.isEmpty else { return nil }
        return "Oura will ask you to allow your daily data, which Tensile's scores use, and also \(extras.joined(separator: " and ")), only for the \"Oura's own numbers\" panel: Tensile's scores never use them. Turn the panel off below to allow just your daily data."
    }

    // MARK: Setup

    /// Saves the developer app's details (trimmed). A changed client ID is
    /// another Oura app, maybe another account: it signs out and forgets the
    /// downloaded data (`disconnect()`), so two accounts never mix.
    func saveCredentials(clientID: String, clientSecret: String, redirectURI: String) {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let redirect = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        if id != self.clientID { disconnect() }
        KeychainStore.set(id, for: Account.clientID)
        if !secret.isEmpty { KeychainStore.set(secret, for: Account.clientSecret) }
        KeychainStore.set(redirect.isEmpty ? Oura.defaultRedirectURI : redirect, for: Account.redirectURI)
        lastError = nil
        updateStatus()
    }

    // MARK: Sign-in

    /// The Oura page to open for sign-in, with a fresh state value to check on
    /// return and a fresh PKCE verifier (S256 challenge in the URL).
    func authorizationURL() -> URL? {
        guard hasCredentials else { return nil }
        let state = UUID().uuidString
        let verifier = PKCE.makeVerifier()
        let scope = OuraOwnNumbersSetting.requestedScopes
        pendingState = state
        pendingVerifier = verifier
        pendingScope = scope
        return Oura.authorizationURL(clientID: clientID, redirectURI: redirectURI, state: state, codeVerifier: verifier, scope: scope)
    }

    /// Finishes sign-in with the address Oura sent the browser back to, then syncs.
    func finishSignIn(callbackURL: URL) async {
        guard let state = pendingState, let verifier = pendingVerifier else { return }
        let requested = pendingScope ?? OuraOwnNumbersSetting.requestedScopes
        pendingState = nil
        pendingVerifier = nil
        pendingScope = nil
        let askedForHeartHealth = requested.split(separator: " ").contains("heart_health")
        let generation = self.generation
        switch Oura.callback(callbackURL, expectedState: state) {
        case let .code(code):
            do {
                let response = try await tokenRequest(.code(code, redirectURI: redirectURI, codeVerifier: verifier))
                guard generation == self.generation else { return }
                let tokens = response.tokens()
                KeychainStore.set(value: tokens, for: Account.tokens)
                // Oura can leave heart_health out of the grant without an error:
                // remember it, so the next sign-in doesn't ask and the prompt doesn't nag.
                if askedForHeartHealth, let granted = tokens.scope,
                   Oura.missingScopes(granted: granted, required: requested).contains("heart_health") {
                    UserDefaults.standard.set(true, forKey: OuraOwnNumbersSetting.heartHealthRefusedKey)
                }
                lastError = nil
                updateStatus()
                await sync(force: true)
            } catch {
                guard generation == self.generation else { return }
                fail("Couldn't finish signing in to Oura", error)
            }
        case let .denied(reason) where reason == "invalid_scope" && askedForHeartHealth:
            // `heart_health` is newer than Oura's sign-in docs; without it,
            // cardiovascular age and VO₂ max stay empty and the rest works.
            UserDefaults.standard.set(true, forKey: OuraOwnNumbersSetting.heartHealthRefusedKey)
            updateStatus()
            lastError = "Oura didn't offer the heart-health permission. Tap Connect again to sign in without it."
        case let .denied(reason):
            lastError = reason == "access_denied" ? "Oura access wasn't allowed." : "Oura said: \(reason)"
        case .wrongState, .invalid:
            lastError = "The sign-in reply didn't look right. Try again."
        }
    }

    func signInFailed(_ error: Error) {
        pendingState = nil
        pendingVerifier = nil
        pendingScope = nil
        fail("Couldn't open Oura's sign-in", error)
    }

    /// Signs out and forgets Oura's data on this phone (the developer app's
    /// details stay). A sync or token refresh still running drops what it gets.
    func disconnect() {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        KeychainStore.set(Data?.none, for: Account.tokens)
        OuraCache.shared.clear()
        OuraOwnNumbersStore.shared.clear()
        UserDefaults.standard.removeObject(forKey: OuraOwnNumbersSetting.heartHealthRefusedKey)
        syncedAt = nil
        lastError = nil
        updateStatus()
    }

    // MARK: Sync

    /// Syncs when connected and the last sync is older than `minimumInterval`.
    /// Reads the sign-in again first, so a Keychain read that failed earlier is retried.
    func syncIfDue() async {
        updateStatus()
        guard status == .connected else { return }
        if let syncedAt, Date.now.timeIntervalSince(syncedAt) < Self.minimumInterval { return }
        await sync()
    }

    /// Downloads recent sleep periods (stages, overnight HRV and heart rate,
    /// breathing rate, temperature change) and, while the panel is on, Oura's
    /// own numbers for display only (docs/research/oura-ring-2026-11.md §6).
    func sync(force: Bool = false) async {
        guard status == .connected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let generation = self.generation
        let calendar = Calendar.current
        let days = OuraCache.shared.hasData && !force ? Self.syncDays : Self.firstSyncDays
        let today = calendar.startOfDay(for: .now)
        // end_date is exclusive for sleep periods, so ask through tomorrow.
        guard let start = calendar.date(byAdding: .day, value: -days, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        do {
            let sleep = try await fetch(Oura.SleepPeriod.self, "sleep", from: start, to: end)
            // Disconnected meanwhile: what came back belongs to a forgotten sign-in.
            guard generation == self.generation else { return }
            let now = Date.now
            OuraCache.shared.merge(periods: sleep.items, coveredDays: sleep.isComplete ? Self.coveredDays(from: start, through: today) : nil,
                                   syncedAt: now)
            if OuraOwnNumbersSetting.isOn {
                let numbers = await fetchOwnNumbers(from: start, to: end)
                guard generation == self.generation else { return }
                // Switched off meanwhile: its numbers were cleared and stay cleared.
                if OuraOwnNumbersSetting.isOn { OuraOwnNumbersStore.shared.merge(numbers) }
            }
            syncedAt = now
            lastError = nil
        } catch OuraError.signedOut {
            guard generation == self.generation else { return }
            KeychainStore.set(Data?.none, for: Account.tokens)
            updateStatus()
            lastError = "Oura signed you out. Connect again to keep syncing."
        } catch is KeychainStore.ReadError {
            // The tokens are kept; the next sync reads them again.
            guard generation == self.generation else { return }
            keychainUnavailable = true
            lastError = Self.keychainMessage
        } catch {
            guard generation == self.generation else { return }
            fail("Couldn't sync with Oura", error)
        }
    }

    /// The days a complete sync is the whole truth for, as Oura files periods
    /// ("YYYY-MM-DD"). The first day asked for is left out: a period filed
    /// under it may have started the evening before and not come back.
    private static func coveredDays(from start: Date, through today: Date) -> ClosedRange<String>? {
        let style = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        guard let first = Calendar.current.date(byAdding: .day, value: 1, to: start), first <= today else { return nil }
        return first.formatted(style)...today.formatted(style)
    }

    /// Oura's own scores and estimates for the panel (`OuraOwnNumbersCard`).
    /// Each list on its own: one Oura refuses (a permission not granted, a
    /// ring without the feature) leaves the others, and never fails the sync.
    private func fetchOwnNumbers(from start: Date, to end: Date) async -> OuraOwnNumbers {
        var numbers = OuraOwnNumbers()
        numbers.readiness = (try? await fetch(Oura.DailyScore.self, "daily_readiness", from: start, to: end))?.items ?? []
        numbers.sleep = (try? await fetch(Oura.DailyScore.self, "daily_sleep", from: start, to: end))?.items ?? []
        numbers.stress = (try? await fetch(Oura.DailyStress.self, "daily_stress", from: start, to: end))?.items ?? []
        numbers.resilience = (try? await fetch(Oura.DailyResilience.self, "daily_resilience", from: start, to: end))?.items ?? []
        numbers.cardiovascularAge = (try? await fetch(Oura.CardiovascularAge.self, "daily_cardiovascular_age", from: start, to: end))?.items ?? []
        numbers.vo2Max = (try? await fetch(Oura.VO2Max.self, "vO2_max", from: start, to: end))?.items ?? []
        numbers.spo2 = (try? await fetch(Oura.DailySpO2.self, "daily_spo2", from: start, to: end))?.items ?? []
        return numbers
    }

    /// The panel was switched on or off. Off deletes its downloaded numbers
    /// (`oura-own.json`); the wider permission stays with Oura until the next
    /// reconnect or disconnect. Either way a heart-health refusal is
    /// forgotten, and whether a new sign-in is needed follows.
    func ownNumbersSettingChanged() {
        UserDefaults.standard.removeObject(forKey: OuraOwnNumbersSetting.heartHealthRefusedKey)
        if !OuraOwnNumbersSetting.isOn { OuraOwnNumbersStore.shared.clear() }
        updateStatus()
    }

    // MARK: Requests

    nonisolated enum OuraError: LocalizedError {
        case signedOut
        case http(Int)
        case membership
        /// Oura refused the developer app's client ID or secret.
        case wrongCredentials
        /// Oura refused the sign-in code (used, expired, or the redirect address differs).
        case codeRefused

        var errorDescription: String? {
            switch self {
            case .signedOut: "Signed out of Oura."
            case let .http(code): "Oura answered with error \(code)."
            // Oura answers 403 for an expired membership or a missing permission (Oura API spec 1.43).
            case .membership: "Oura refused access. It needs an active membership to share data with other apps; if yours is active, reconnect Oura in Settings."
            case .wrongCredentials: "Oura didn't accept the client ID or secret. Check both against your app at developer.ouraring.com."
            case .codeRefused: "Oura didn't accept the sign-in. Check that the redirect address here matches your Oura app's, then try again."
            }
        }
    }

    /// Every page of one collection, and whether every page came back
    /// (false when it stopped at the 2,000-item cap or on a bad address).
    private func fetch<Item: Decodable & Sendable>(_ type: Item.Type, _ path: String, from start: Date,
                                                   to end: Date) async throws -> (items: [Item], isComplete: Bool) {
        let style = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        var items: [Item] = []
        var next: String?
        var complete = true
        repeat {
            var components = URLComponents(url: Oura.apiBase.appending(path: path), resolvingAgainstBaseURL: false)
            var query = [URLQueryItem(name: "start_date", value: start.formatted(style)),
                         URLQueryItem(name: "end_date", value: end.formatted(style))]
            if let next { query.append(URLQueryItem(name: "next_token", value: next)) }
            components?.queryItems = query
            guard let url = components?.url else {
                complete = false
                break
            }
            let data = try await authorizedData(url)
            let page = try JSONDecoder().decode(Oura.Page<Item>.self, from: data)
            items += page.data
            next = page.nextToken
        } while next != nil && items.count < 2_000
        return (items, complete && next == nil)
    }

    /// A GET with the access token, refreshing it once if it has lapsed.
    private func authorizedData(_ url: URL) async throws -> Data {
        var tokens = try await validTokens()
        for attempt in 0..<2 {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(Oura.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await Self.session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200..<300:
                return data
            case 401 where attempt == 0:
                tokens = try await refreshedTokens(after: tokens)
            case 401:
                throw OuraError.signedOut
            case 403:
                throw OuraError.membership
            default:
                throw OuraError.http(code)
            }
        }
        throw OuraError.signedOut
    }

    /// The saved tokens, refreshed if they have lapsed. A Keychain read error
    /// is thrown as it is (`KeychainStore.ReadError`), never as a sign-out.
    private func validTokens() async throws -> Oura.Tokens {
        guard let tokens = try KeychainStore.value(Oura.Tokens.self, Account.tokens) else { throw OuraError.signedOut }
        return tokens.isExpired() ? try await refreshedTokens(after: tokens) : tokens
    }

    /// One refresh at a time: Oura's refresh tokens work once, so two at
    /// once would sign the user out.
    private func refreshedTokens(after old: Oura.Tokens) async throws -> Oura.Tokens {
        if let refreshTask { return try await refreshTask.value }
        // Another request may already have refreshed.
        if let current = try? KeychainStore.value(Oura.Tokens.self, Account.tokens), current.accessToken != old.accessToken {
            return current
        }
        guard let refresh = old.refreshToken else { throw OuraError.signedOut }
        let generation = self.generation
        let task = Task { () throws -> Oura.Tokens in
            let response = try await self.tokenRequest(.refresh(refresh))
            // Disconnected meanwhile: never write the forgotten sign-in back.
            try Task.checkCancellation()
            guard generation == self.generation else { throw CancellationError() }
            let tokens = response.tokens(keeping: old)
            KeychainStore.set(value: tokens, for: Account.tokens)
            return tokens
        }
        refreshTask = task
        defer { if refreshTask == task { refreshTask = nil } }
        return try await task.value
    }

    private func tokenRequest(_ grant: Oura.Grant) async throws -> Oura.TokenResponse {
        guard let secret = try KeychainStore.string(Account.clientSecret) else { throw OuraError.signedOut }
        let id = try KeychainStore.string(Account.clientID) ?? ""
        var request = URLRequest(url: Oura.tokenURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Oura.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Oura.tokenRequestBody(grant, clientID: id, clientSecret: secret)
        let (data, response) = try await Self.session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 400 || code == 401 {
            // The real reason, from OAuth's error field (RFC 6749 §5.2): a wrong
            // client secret is "invalid_client", not a sign-out.
            let reason = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
            if reason == "invalid_client" || reason == "unauthorized_client" { throw OuraError.wrongCredentials }
            // A refused refresh token means signing in again; a refused sign-in code never signed in.
            if case .refresh = grant { throw OuraError.signedOut }
            throw reason == nil && code == 401 ? OuraError.wrongCredentials : OuraError.codeRefused
        }
        guard (200..<300).contains(code) else { throw OuraError.http(code) }
        return try JSONDecoder().decode(Oura.TokenResponse.self, from: data)
    }

    private func fail(_ message: String, _ error: Error) {
        Self.log.error("\(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
        lastError = "\(message): \(error.localizedDescription)"
    }
}
