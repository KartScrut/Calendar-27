import Foundation
import Security

/// Where the backend lives. Values come from `SupabaseConfig.plist`.
/// Both values are public by design (the "anon" key only allows what Row
/// Level Security allows). The secret service-role key is never in the app.
struct BackendConfig {
    let url: URL
    let anonKey: String

    static func load(bundle: Bundle = .main) -> BackendConfig? {
        guard let path = bundle.url(forResource: "SupabaseConfig", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: path) as? [String: Any],
              let urlString = (dict["SUPABASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let key = (dict["SUPABASE_ANON_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty, !key.isEmpty,
              let url = URL(string: urlString), url.scheme == "https", url.host != nil else { return nil }
        return BackendConfig(url: url, anonKey: key)
    }
}

struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?
}

enum BackendError: LocalizedError, Equatable {
    case notConfigured
    case notSignedIn
    case sessionExpired
    case offline
    case server(status: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Cloud backup isn't set up in this build yet."
        case .notSignedIn: return "You're not signed in."
        case .sessionExpired: return "Your sign-in has expired. Please sign in again."
        case .offline: return "You appear to be offline. Your progress is safe on this iPhone."
        case .server(_, let message): return message
        case .invalidResponse: return "The server sent something unexpected. Please try again."
        }
    }
}

/// Session storage in the Keychain. Tokens never touch UserDefaults.
enum Keychain {
    private static let service = "com.twelve.app.session"
    private static let account = "supabase"

    static func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> AuthSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

/// Timestamps as PostgREST writes them ("2027-01-05T09:30:00.123456+00:00").
enum ServerDate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(_ date: Date) -> String { withFraction.string(from: date) }

    static func parse(_ string: String) -> Date? {
        // Trim microseconds to milliseconds; the formatter is strict about digits.
        var s = string
        if let dot = s.firstIndex(of: ".") {
            let afterDot = s.index(after: dot)
            let end = s[afterDot...].firstIndex(where: { !$0.isNumber }) ?? s.endIndex
            let digits = String(s[afterDot..<end])
            let padded = String((digits + "000").prefix(3))
            s = String(s[..<afterDot]) + padded + String(s[end...])
        }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }
}

/// A small, dependency-free client for Supabase Auth and PostgREST.
///
/// Every request goes over HTTPS, carries the public anon key, and — once
/// signed in — the person's own access token, so the database's Row Level
/// Security decides what they may read and write.
actor SupabaseClient {
    let config: BackendConfig
    private let urlSession: URLSession
    private(set) var session: AuthSession?
    private var refreshTask: Task<AuthSession, Error>?

    init(config: BackendConfig, urlSession: URLSession? = nil) {
        self.config = config
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 20
            c.waitsForConnectivity = false
            c.httpCookieStorage = nil
            c.urlCache = nil
            self.urlSession = URLSession(configuration: c)
        }
        self.session = Keychain.load()
    }

    var currentSession: AuthSession? { session }

    // MARK: Auth

    /// Sends a six-digit code to the address. No passwords anywhere.
    func requestEmailCode(email: String) async throws {
        _ = try await send(path: "/auth/v1/otp", method: "POST",
                           body: ["email": email, "create_user": true], authorized: false)
    }

    func verifyEmailCode(email: String, code: String) async throws -> AuthSession {
        let data = try await send(path: "/auth/v1/verify", method: "POST",
                                  body: ["type": "email", "email": email, "token": code], authorized: false)
        return try store(sessionFrom: data)
    }

    /// Exchanges an Apple identity token (with its nonce) for a session.
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        let data = try await send(path: "/auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "id_token")],
                                  method: "POST", body: ["provider": "apple", "id_token": idToken, "nonce": nonce],
                                  authorized: false)
        return try store(sessionFrom: data)
    }

    func signOut() async {
        if session != nil {
            _ = try? await send(path: "/auth/v1/logout", method: "POST", body: [String: Any](), authorized: true)
        }
        session = nil
        Keychain.clear()
    }

    /// Forget the session locally without contacting the server.
    func dropSession() {
        session = nil
        Keychain.clear()
    }

    private func store(sessionFrom data: Data) throws -> AuthSession {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let userID = user["id"] as? String else { throw BackendError.invalidResponse }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        let s = AuthSession(accessToken: access, refreshToken: refresh,
                            expiresAt: Date().addingTimeInterval(expiresIn), userID: userID,
                            email: user["email"] as? String)
        session = s
        Keychain.save(s)
        return s
    }

    /// A valid access token, refreshing it first if it is about to expire.
    private func validToken() async throws -> String {
        guard let s = session else { throw BackendError.notSignedIn }
        if s.expiresAt.timeIntervalSinceNow > 60 { return s.accessToken }
        return try await refresh().accessToken
    }

    private func refresh() async throws -> AuthSession {
        if let task = refreshTask { return try await task.value }
        guard let current = session else { throw BackendError.notSignedIn }
        let task = Task<AuthSession, Error> {
            let data = try await self.send(path: "/auth/v1/token",
                                           query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                           method: "POST", body: ["refresh_token": current.refreshToken], authorized: false)
            return try self.store(sessionFrom: data)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await task.value
        } catch let error as BackendError {
            if case .server(let status, _) = error, (400...403).contains(status) {
                // The refresh token is no longer valid: the person must sign in again.
                dropSession()
                throw BackendError.sessionExpired
            }
            throw error
        }
    }

    // MARK: Database

    func select(_ table: String, query: [URLQueryItem]) async throws -> [[String: Any]] {
        let data = try await send(path: "/rest/v1/\(table)", query: query, method: "GET", body: nil, authorized: true)
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    /// Insert-or-update by primary key. Sending the same rows twice is harmless.
    func upsert(_ table: String, rows: [[String: Any]], onConflict: String) async throws {
        guard !rows.isEmpty else { return }
        _ = try await send(path: "/rest/v1/\(table)", query: [URLQueryItem(name: "on_conflict", value: onConflict)],
                           method: "POST", body: rows, authorized: true,
                           extraHeaders: ["Prefer": "resolution=merge-duplicates,return=minimal"])
    }

    func update(_ table: String, match: [URLQueryItem], values: [String: Any]) async throws {
        _ = try await send(path: "/rest/v1/\(table)", query: match, method: "PATCH", body: values, authorized: true,
                           extraHeaders: ["Prefer": "return=minimal"])
    }

    func delete(_ table: String, match: [URLQueryItem]) async throws {
        _ = try await send(path: "/rest/v1/\(table)", query: match, method: "DELETE", body: nil, authorized: true,
                           extraHeaders: ["Prefer": "return=minimal"])
    }

    func rpc(_ function: String, params: [String: Any] = [:]) async throws -> Any? {
        let data = try await send(path: "/rest/v1/rpc/\(function)", method: "POST", body: params, authorized: true)
        guard !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    // MARK: Transport

    private func send(path: String, query: [URLQueryItem] = [], method: String, body: Any?,
                      authorized: Bool, extraHeaders: [String: String] = [:], isRetry: Bool = false) async throws -> Data {
        guard var components = URLComponents(url: config.url.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw BackendError.invalidResponse
        }
        if !query.isEmpty {
            components.queryItems = query
            // "+" is legal in a query but means a space to the server; timestamps contain it.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw BackendError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let bearer: String
        if authorized { bearer = try await validToken() } else { bearer = config.anonKey }
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                throw BackendError.offline
            default:
                throw BackendError.server(status: 0, message: "Couldn't reach the server. Please try again.")
            }
        }
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        if http.statusCode == 401, authorized, !isRetry {
            // The token was rejected: refresh once and try again.
            _ = try await refresh()
            return try await send(path: path, query: query, method: method, body: body, authorized: authorized,
                                  extraHeaders: extraHeaders, isRetry: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.server(status: http.statusCode, message: Self.message(from: data, status: http.statusCode))
        }
        return data
    }

    /// A short, safe message for people. Never echoes raw server internals.
    private static func message(from data: Data, status: Int) -> String {
        if status == 429 { return "Too many attempts. Please wait a minute and try again." }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = (json?["error_code"] as? String) ?? (json?["code"] as? String) ?? ""
        switch code {
        case "otp_expired": return "That code has expired or isn't right. Request a new one and try again."
        case "over_email_send_rate_limit", "over_request_rate_limit": return "Too many attempts. Please wait a minute and try again."
        case "validation_failed", "email_address_invalid": return "That email address doesn't look right."
        case "54000": return "Too many attempts. Please wait a little and try again."
        default: break
        }
        if status >= 500 { return "The server is having trouble. Your progress is safe on this iPhone." }
        if status == 403 || status == 401 { return "That wasn't allowed. Please sign in again if this keeps happening." }
        return "Something went wrong (\(status)). Please try again."
    }
}
