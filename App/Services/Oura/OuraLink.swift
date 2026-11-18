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
/// `OuraCache`; Oura's Readiness and Sleep scores aren't downloaded (`Oura`).
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
    }

    private(set) var status: Status = .needsSetup
    private(set) var isSyncing = false
    /// The last sync or sign-in problem, in plain words; nil once one works.
    private(set) var lastError: String?
    private(set) var syncedAt: Date?
    /// Connected, but the saved sign-in predates the trimmed permissions or
    /// lacks one the app needs (`Oura.needsReconnect`): Settings and the Oura
    /// card ask for one reconnect instead of syncs failing unexplained.
    private(set) var needsReconnect = false

    var clientID: String { KeychainStore.string(Account.clientID) ?? "" }
    var redirectURI: String { KeychainStore.string(Account.redirectURI) ?? Oura.defaultRedirectURI }
    var hasCredentials: Bool { !clientID.isEmpty && KeychainStore.string(Account.clientSecret)?.isEmpty == false }

    /// Days downloaded on the first sync, then on each later one.
    static let firstSyncDays = 90
    static let syncDays = 7
    /// At most one automatic sync this often (`syncIfDue`).
    static let minimumInterval: TimeInterval = 30 * 60

    @ObservationIgnored private var pendingState: String?
    /// The PKCE verifier for the sign-in in progress; only its hash leaves the phone before the token request.
    @ObservationIgnored private var pendingVerifier: String?
    @ObservationIgnored private var refreshTask: Task<Oura.Tokens, Error>?

    private static let log = Logger(subsystem: "com.lontraindustries.workoutapp", category: "oura")

    init() {
        syncedAt = OuraCache.shared.contents.syncedAt
        updateStatus()
    }

    private func updateStatus() {
        if let tokens = KeychainStore.value(Oura.Tokens.self, Account.tokens) {
            status = .connected
            needsReconnect = Oura.needsReconnect(grantedScope: tokens.scope, required: OuraOwnNumbersSetting.requestedScopes)
        } else {
            status = hasCredentials ? .disconnected : .needsSetup
            needsReconnect = false
        }
    }

    // MARK: Setup

    /// Saves the developer app's details (trimmed). A changed client ID signs out.
    func saveCredentials(clientID: String, clientSecret: String, redirectURI: String) {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let redirect = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        if id != self.clientID { KeychainStore.set(Data?.none, for: Account.tokens) }
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
        pendingState = state
        pendingVerifier = verifier
        return Oura.authorizationURL(clientID: clientID, redirectURI: redirectURI, state: state, codeVerifier: verifier,
                                     scope: OuraOwnNumbersSetting.requestedScopes)
    }

    /// Finishes sign-in with the address Oura sent the browser back to, then syncs.
    func finishSignIn(callbackURL: URL) async {
        guard let state = pendingState, let verifier = pendingVerifier else { return }
        pendingState = nil
        pendingVerifier = nil
        switch Oura.callback(callbackURL, expectedState: state) {
        case let .code(code):
            do {
                let response = try await tokenRequest(.code(code, redirectURI: redirectURI, codeVerifier: verifier))
                KeychainStore.set(value: response.tokens(requestedScope: OuraOwnNumbersSetting.requestedScopes), for: Account.tokens)
                lastError = nil
                updateStatus()
                await sync(force: true)
            } catch {
                fail("Couldn't finish signing in to Oura", error)
            }
        case let .denied(reason) where reason == "invalid_scope" && !OuraOwnNumbersSetting.heartHealthRefused && OuraOwnNumbersSetting.isOn:
            // `heart_health` is newer than Oura's sign-in docs; without it,
            // cardiovascular age and VO₂ max stay empty and the rest works.
            UserDefaults.standard.set(true, forKey: OuraOwnNumbersSetting.heartHealthRefusedKey)
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
        fail("Couldn't open Oura's sign-in", error)
    }

    /// Signs out and forgets Oura's data on this phone (the developer app's details stay).
    func disconnect() {
        KeychainStore.set(Data?.none, for: Account.tokens)
        OuraCache.shared.clear()
        OuraOwnNumbersStore.shared.clear()
        syncedAt = nil
        lastError = nil
        updateStatus()
    }

    // MARK: Sync

    /// Syncs when connected and the last sync is older than `minimumInterval`.
    func syncIfDue() async {
        guard status == .connected else { return }
        if let syncedAt, Date.now.timeIntervalSince(syncedAt) < Self.minimumInterval { return }
        await sync()
    }

    /// Downloads recent sleep periods (stages, overnight HRV and heart rate,
    /// breathing rate, temperature change). Oura's Readiness and Sleep scores
    /// are left out (docs/research/oura-ring-2026-11.md §6).
    func sync(force: Bool = false) async {
        guard status == .connected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let calendar = Calendar.current
        let days = OuraCache.shared.hasData && !force ? Self.syncDays : Self.firstSyncDays
        let today = calendar.startOfDay(for: .now)
        // end_date is exclusive for sleep periods, so ask through tomorrow.
        guard let start = calendar.date(byAdding: .day, value: -days, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        do {
            let periods = try await fetch(Oura.SleepPeriod.self, "sleep", from: start, to: end)
            let now = Date.now
            OuraCache.shared.merge(periods: periods, syncedAt: now)
            if OuraOwnNumbersSetting.isOn {
                OuraOwnNumbersStore.shared.merge(await fetchOwnNumbers(from: start, to: end))
            }
            syncedAt = now
            lastError = nil
        } catch OuraError.signedOut {
            KeychainStore.set(Data?.none, for: Account.tokens)
            updateStatus()
            lastError = "Oura signed you out. Connect again to keep syncing."
        } catch {
            fail("Couldn't sync with Oura", error)
        }
    }

    /// Oura's own scores and estimates for the panel (`OuraOwnNumbersCard`).
    /// Each list on its own: one Oura refuses (a permission not granted, a
    /// ring without the feature) leaves the others, and never fails the sync.
    private func fetchOwnNumbers(from start: Date, to end: Date) async -> OuraOwnNumbers {
        var numbers = OuraOwnNumbers()
        numbers.readiness = (try? await fetch(Oura.DailyScore.self, "daily_readiness", from: start, to: end)) ?? []
        numbers.sleep = (try? await fetch(Oura.DailyScore.self, "daily_sleep", from: start, to: end)) ?? []
        numbers.stress = (try? await fetch(Oura.DailyStress.self, "daily_stress", from: start, to: end)) ?? []
        numbers.resilience = (try? await fetch(Oura.DailyResilience.self, "daily_resilience", from: start, to: end)) ?? []
        numbers.cardiovascularAge = (try? await fetch(Oura.CardiovascularAge.self, "daily_cardiovascular_age", from: start, to: end)) ?? []
        numbers.vo2Max = (try? await fetch(Oura.VO2Max.self, "vO2_max", from: start, to: end)) ?? []
        numbers.spo2 = (try? await fetch(Oura.DailySpO2.self, "daily_spo2", from: start, to: end)) ?? []
        return numbers
    }

    /// The panel was switched on or off: whether a new sign-in is needed follows.
    func ownNumbersSettingChanged() {
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

    /// Every page of one collection.
    private func fetch<Item: Decodable & Sendable>(_ type: Item.Type, _ path: String, from start: Date, to end: Date) async throws -> [Item] {
        let style = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        var items: [Item] = []
        var next: String?
        repeat {
            var components = URLComponents(url: Oura.apiBase.appending(path: path), resolvingAgainstBaseURL: false)
            var query = [URLQueryItem(name: "start_date", value: start.formatted(style)),
                         URLQueryItem(name: "end_date", value: end.formatted(style))]
            if let next { query.append(URLQueryItem(name: "next_token", value: next)) }
            components?.queryItems = query
            guard let url = components?.url else { break }
            let data = try await authorizedData(url)
            let page = try JSONDecoder().decode(Oura.Page<Item>.self, from: data)
            items += page.data
            next = page.nextToken
        } while next != nil && items.count < 2_000
        return items
    }

    /// A GET with the access token, refreshing it once if it has lapsed.
    private func authorizedData(_ url: URL) async throws -> Data {
        var tokens = try await validTokens()
        for attempt in 0..<2 {
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(Oura.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
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

    private func validTokens() async throws -> Oura.Tokens {
        guard let tokens = KeychainStore.value(Oura.Tokens.self, Account.tokens) else { throw OuraError.signedOut }
        return tokens.isExpired() ? try await refreshedTokens(after: tokens) : tokens
    }

    /// One refresh at a time: Oura's refresh tokens work once, so two at
    /// once would sign the user out.
    private func refreshedTokens(after old: Oura.Tokens) async throws -> Oura.Tokens {
        if let refreshTask { return try await refreshTask.value }
        // Another request may already have refreshed.
        if let current = KeychainStore.value(Oura.Tokens.self, Account.tokens), current.accessToken != old.accessToken {
            return current
        }
        guard let refresh = old.refreshToken else { throw OuraError.signedOut }
        let task = Task { () throws -> Oura.Tokens in
            let response = try await self.tokenRequest(.refresh(refresh))
            let tokens = response.tokens(keeping: old)
            KeychainStore.set(value: tokens, for: Account.tokens)
            return tokens
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func tokenRequest(_ grant: Oura.Grant) async throws -> Oura.TokenResponse {
        guard let secret = KeychainStore.string(Account.clientSecret) else { throw OuraError.signedOut }
        var request = URLRequest(url: Oura.tokenURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Oura.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Oura.tokenRequestBody(grant, clientID: clientID, clientSecret: secret)
        let (data, response) = try await URLSession.shared.data(for: request)
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
