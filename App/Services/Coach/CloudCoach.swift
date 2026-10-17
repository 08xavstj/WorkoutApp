import Foundation

/// Coach powered by Claude, through the `coach` Supabase Edge Function in
/// `supabase/functions/coach`. The Anthropic API key lives only on the server.
///
/// The app signs in anonymously to Supabase so the function can require a
/// logged-in user (turn on "Anonymous sign-ins" in Supabase Auth settings).
final class CloudCoach {
    nonisolated struct Message: Codable, Sendable {
        let role: String // "user" or "assistant"
        let content: String
    }

    nonisolated private struct Session: Decodable {
        let access_token: String
        let refresh_token: String
    }

    nonisolated private struct RequestBody: Encodable {
        let messages: [Message]
        let snapshot: CoachSnapshot
    }

    nonisolated private struct ResponseBody: Decodable {
        let reply: String?
        let error: String?
    }

    private var auth: Session?
    private let urlSession = URLSession.shared

    func reply(history: [Message], snapshot: CoachSnapshot, settings: UserSettings) async throws -> String {
        let base = settings.supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let anonKey = settings.supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: base), !base.isEmpty, !anonKey.isEmpty else {
            throw CoachError.unavailable("Add your Supabase project URL and anon key in Settings to use Claude.")
        }

        do {
            return try await send(history: history, snapshot: snapshot, baseURL: baseURL, anonKey: anonKey)
        } catch CoachError.unauthorized {
            // Token expired: refresh (or sign in again) and retry once.
            auth = try await refreshOrSignIn(baseURL: baseURL, anonKey: anonKey)
            return try await send(history: history, snapshot: snapshot, baseURL: baseURL, anonKey: anonKey)
        }
    }

    private func send(history: [Message], snapshot: CoachSnapshot, baseURL: URL, anonKey: String) async throws -> String {
        if auth == nil {
            auth = try await refreshOrSignIn(baseURL: baseURL, anonKey: anonKey)
        }
        guard let token = auth?.access_token else { throw CoachError.unauthorized }

        var request = URLRequest(url: baseURL.appending(path: "functions/v1/coach"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(RequestBody(messages: history, snapshot: snapshot))

        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw CoachError.unauthorized }
        let body = try? JSONDecoder().decode(ResponseBody.self, from: data)
        guard (200..<300).contains(status), let reply = body?.reply else {
            throw CoachError.server(body?.error ?? "The coach server returned an error (\(status)).")
        }
        return reply
    }

    private func refreshOrSignIn(baseURL: URL, anonKey: String) async throws -> Session {
        if let refresh = auth?.refresh_token,
           let session = try? await authRequest(
               baseURL.appending(path: "auth/v1/token").appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")]),
               body: ["refresh_token": refresh],
               anonKey: anonKey
           ) {
            return session
        }
        return try await authRequest(baseURL.appending(path: "auth/v1/signup"), body: [:], anonKey: anonKey)
    }

    private func authRequest(_ url: URL, body: [String: String], anonKey: String) async throws -> Session {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CoachError.server("Couldn't sign in to Supabase. Check that anonymous sign-ins are enabled.")
        }
        return try JSONDecoder().decode(Session.self, from: data)
    }
}

enum CoachError: LocalizedError {
    case unavailable(String)
    case unauthorized
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .server(let message): message
        case .unauthorized: "Your coach session expired. Try again."
        }
    }
}

enum CoachPrompt {
    static let onDeviceInstructions = """
    You are a friendly, direct strength and recovery coach inside a fitness app.
    Always call getTodayMetrics before answering questions about today, and \
    getRecentWorkouts before answering questions about training.
    Strain is 0-21. Recovery is 0-100% (under 34 low, 34-66 moderate, 67+ high).
    getTodayMetrics also includes food logged in Cronometer and calories burned; today's food may be partial.
    For workout questions call getGymAndPlannedWorkout. The app shows the planned session as a card, \
    so explain why it fits today instead of listing every exercise. Only suggest equipment the user has.
    Keep answers under 120 words. Give one clear recommendation.
    You are not a doctor; suggest seeing one for pain, illness or injury.
    """
}
