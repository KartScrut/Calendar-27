import AuthenticationServices
import CryptoKit
import Foundation
import Observation

/// Sign in with Apple and email one-time codes, backed by Supabase Auth.
/// There are no passwords. If the backend isn't configured, the app still
/// works fully as a guest and says so plainly.
@MainActor
@Observable
final class AuthService {
    enum State: Equatable {
        /// No backend configured in this build: guest mode only.
        case unavailable
        case signedOut
        case signedIn(userID: String, email: String?)
    }

    private(set) var state: State = .unavailable
    /// Set when a session ended on its own, so the UI can explain why.
    var sessionExpiredNotice = false
    let client: SupabaseClient?
    private var appleNonce: String?

    init(config: BackendConfig? = BackendConfig.load()) {
        if let config {
            client = SupabaseClient(config: config)
            if let s = Keychain.load() {
                state = .signedIn(userID: s.userID, email: s.email)
            } else {
                state = .signedOut
            }
        } else {
            client = nil
            state = .unavailable
        }
    }

    var isAvailable: Bool { client != nil }

    var userID: String? {
        if case .signedIn(let id, _) = state { return id }
        return nil
    }

    var email: String? {
        if case .signedIn(_, let email) = state { return email }
        return nil
    }

    var isSignedIn: Bool { userID != nil }

    // MARK: Email code

    static func isPlausibleEmail(_ email: String) -> Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard e.count <= 254, let at = e.firstIndex(of: "@"), at != e.startIndex else { return false }
        let domain = e[e.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".") && !e.contains(" ")
    }

    func requestCode(email: String) async throws {
        guard let client else { throw BackendError.notConfigured }
        try await client.requestEmailCode(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    func verify(email: String, code: String) async throws {
        guard let client else { throw BackendError.notConfigured }
        let digits = code.filter(\.isNumber)
        let session = try await client.verifyEmailCode(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), code: digits)
        state = .signedIn(userID: session.userID, email: session.email)
        sessionExpiredNotice = false
    }

    // MARK: Apple

    /// Configure the system request. A fresh random nonce ties the Apple
    /// credential to this one sign-in attempt and prevents replay.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func handleApple(_ result: Result<ASAuthorization, Error>) async throws {
        guard let client else { throw BackendError.notConfigured }
        switch result {
        case .failure(let error):
            if let e = error as? ASAuthorizationError, e.code == .canceled { throw CancellationError() }
            throw error
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else { throw BackendError.invalidResponse }
            appleNonce = nil
            let session = try await client.signInWithApple(idToken: token, nonce: nonce)
            state = .signedIn(userID: session.userID, email: session.email)
            sessionExpiredNotice = false
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) }
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    // MARK: Leaving

    func signOut() async {
        await client?.signOut()
        if client != nil { state = .signedOut }
    }

    /// Called when the server says the session is no longer valid.
    func markExpired() {
        guard isSignedIn else { return }
        state = .signedOut
        sessionExpiredNotice = true
    }

    /// Permanently deletes the account and all its server-side data.
    func deleteAccount() async throws {
        guard let client else { throw BackendError.notConfigured }
        _ = try await client.rpc("delete_my_account")
        await client.dropSession()
        state = .signedOut
    }
}
