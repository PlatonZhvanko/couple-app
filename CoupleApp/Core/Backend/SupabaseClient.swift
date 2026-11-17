import Foundation

/// Адрес проекта Supabase и его публичный ключ (anon key).
/// Берутся из `BackendConfig` или вводятся один раз на экране входа.
struct SupabaseConfig: Codable, Equatable {
    var url: String = ""
    var anonKey: String = ""

    var isComplete: Bool {
        baseURL != nil && !anonKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var baseURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}

/// Вход в аккаунт Supabase (хранится в Keychain).
struct SupabaseSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?
}

enum SupabaseError: LocalizedError {
    case notConfigured
    case notSignedIn
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Не указан адрес или ключ Supabase."
        case .notSignedIn: "Нужно войти в аккаунт."
        case let .http(status, message): "Ошибка сервера (\(status)): \(message)"
        }
    }
}

/// Минимальный клиент Supabase на чистом URLSession, без сторонних библиотек.
/// Умеет входить по почте и паролю и делать запросы к базе (PostgREST).
@MainActor
final class SupabaseClient {
    let config: SupabaseConfig
    private(set) var session: SupabaseSession?
    var onSessionChange: ((SupabaseSession?) -> Void)?

    init(config: SupabaseConfig, session: SupabaseSession?) {
        self.config = config
        self.session = session
    }

    // MARK: - Вход

    func signIn(email: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let data = try await send(path: "auth/v1/token", query: "grant_type=password", method: "POST", body: body, authorized: false)
        setSession(try Self.parseSession(data))
    }

    func signOut() {
        setSession(nil)
    }

    private func validSession() async throws -> SupabaseSession {
        guard let session else { throw SupabaseError.notSignedIn }
        if session.expiresAt.timeIntervalSinceNow > 60 { return session }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": session.refreshToken])
        let data = try await send(path: "auth/v1/token", query: "grant_type=refresh_token", method: "POST", body: body, authorized: false)
        let refreshed = try Self.parseSession(data)
        setSession(refreshed)
        return refreshed
    }

    private func setSession(_ newValue: SupabaseSession?) {
        session = newValue
        onSessionChange?(newValue)
    }

    private static func parseSession(_ data: Data) throws -> SupabaseSession {
        struct Response: Decodable {
            struct User: Decodable { let id: String; let email: String? }
            let accessToken: String
            let refreshToken: String
            let expiresIn: Double
            let user: User
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)
        return SupabaseSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date.now.addingTimeInterval(response.expiresIn),
            userID: response.user.id,
            email: response.user.email
        )
    }

    // MARK: - Запросы

    /// Запрос к базе от имени вошедшего пользователя.
    /// `query` уже должен быть закодирован для URL.
    func rest(
        _ table: String,
        query: String = "",
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        _ = try await validSession()
        return try await send(path: "rest/v1/\(table)", query: query, method: method, body: body, authorized: true, headers: headers)
    }

    private func send(
        path: String,
        query: String,
        method: String,
        body: Data?,
        authorized: Bool,
        headers: [String: String] = [:]
    ) async throws -> Data {
        guard let baseURL = config.baseURL, config.isComplete else { throw SupabaseError.notConfigured }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.percentEncodedQuery = query }
        guard let url = components?.url else { throw SupabaseError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        let token = authorized ? (session?.accessToken ?? config.anonKey) : config.anonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw SupabaseError.http(status: status, message: Self.errorMessage(from: data))
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error_description", "msg", "error"] {
                if let text = json[key] as? String { return text }
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
