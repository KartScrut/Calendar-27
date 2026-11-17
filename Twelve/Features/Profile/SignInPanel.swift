import AuthenticationServices
import SwiftUI
import TwelveCore

/// Continue with Apple, or an emailed one-time code. No passwords.
struct SignInPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    let onSignedIn: () -> Void

    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var working = false
    @State private var message: String?
    @FocusState private var focus: Field?

    private enum Field { case email, code }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !app.auth.isAvailable {
                InfoBanner(symbol: "icloud.slash",
                           text: "Cloud backup isn't set up in this build yet, so sign-in is unavailable. Everything works as a guest, and your progress is saved on this iPhone.",
                           tint: .limeText)
            } else if app.auth.isSignedIn {
                InfoBanner(symbol: "checkmark.icloud", text: "Signed in\(app.auth.email.map { " as \($0)" } ?? ""). Your progress is backed up.")
            } else {
                SignInWithAppleButton(.continue) { request in
                    app.auth.prepare(request)
                } onCompletion: { result in
                    run {
                        try await app.auth.handleApple(result)
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(Capsule())
                .disabled(working)

                HStack {
                    Rectangle().fill(Color.hairline).frame(height: 1)
                    Text("or").font(.caption).foregroundStyle(Color.inkSoft)
                    Rectangle().fill(Color.hairline).frame(height: 1)
                }
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.continue)
                        .onSubmit(sendCode)
                        .padding(14)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
                        .disabled(codeSent)

                    if codeSent {
                        TextField("Code from the email", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .focused($focus, equals: .code)
                            .font(.title3.monospacedDigit())
                            .padding(14)
                            .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
                            .onChange(of: code) { _, new in
                                code = String(new.filter(\.isNumber).prefix(8))
                            }
                        SecondaryButton(title: working ? "Checking…" : "Verify and continue", systemImage: "checkmark") {
                            verify()
                        }
                        .disabled(working || code.count < 6)
                        Button("Use a different email") {
                            codeSent = false
                            code = ""
                            message = nil
                        }
                        .font(.footnote)
                        .foregroundStyle(Color.accentText)
                    } else {
                        SecondaryButton(title: working ? "Sending…" : "Continue with email", systemImage: "envelope") {
                            sendCode()
                        }
                        .disabled(working || !AuthService.isPlausibleEmail(email))
                    }
                }
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.accentText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private func sendCode() {
        guard AuthService.isPlausibleEmail(email), !working else { return }
        working = true
        message = nil
        Task {
            do {
                try await app.auth.requestCode(email: email)
                codeSent = true
                focus = .code
                message = "We've sent a code to \(email.trimmingCharacters(in: .whitespaces)). It can take a minute to arrive."
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? "That didn't work. Please try again."
            }
            working = false
        }
    }

    private func verify() {
        run {
            try await app.auth.verify(email: email, code: code)
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        guard !working else { return }
        working = true
        message = nil
        Task {
            do {
                try await operation()
                if let problem = await app.didSignIn() {
                    message = problem
                } else {
                    Haptics.success()
                    onSignedIn()
                }
            } catch is CancellationError {
                // The person closed the Apple sheet. Nothing to say.
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? "Sign-in didn't complete. Please try again."
            }
            working = false
        }
    }
}

/// Sign-in presented from Profile.
struct AccountSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Back up your year")
                        .font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
                    Text("Sign in to keep your progress safe and in step across devices. What you've done as a guest comes with you. Photos always stay on this iPhone.")
                        .font(.subheadline).foregroundStyle(Color.inkSoft)
                    SignInPanel { dismiss() }
                        .padding(.top, 14)
                }
                .padding(24)
            }
            .paperScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
