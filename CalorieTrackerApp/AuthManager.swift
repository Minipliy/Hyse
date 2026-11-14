import SwiftUI
import Combine
import AuthenticationServices
import UIKit

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var token: String
    @Published var isLoggedIn: Bool = false
    @Published private(set) var accountName: String = ""
    @Published private(set) var accountID: String = ""
    @Published private(set) var accountEmail: String = ""
    @Published private(set) var accountCreatedAt: String = ""
    @Published private(set) var accountAvatarFilename: String = ""
    @Published private(set) var accountAvatarLocalData: Data?
    @Published private(set) var isUploadingAvatar = false
    @Published private(set) var isRefreshingSession = false
    @Published private(set) var isDeletingAccount = false
    @Published private(set) var accountSignInMethods = AccountSignInMethods(hasPassword: true, providers: [])
    @Published private(set) var accountMethodsLoadError: String?

    // Ersetze dies durch deine Server-Domain
    private let baseURL = HyseConfiguration.serverURL
    // OAuth provider -> PocketBase HTTPS bridge. This exact value must also be
    // registered as an authorized redirect URI for the Google web client.
    private let providerOAuthRedirectURL = "\(HyseConfiguration.serverURL)/api/hyse/oauth2-callback"
    // HTTPS bridge -> ASWebAuthenticationSession. Google never receives this scheme.
    private let appCallbackScheme = "hyseapp"
    private var oauthSession: ASWebAuthenticationSession?
    private var authRevision: UInt = 0
    private var lastSessionRefreshAt: Date?

    init() {
        // Restore the last account immediately so every account-scoped store can
        // open its local cache without showing the empty guest state first. The
        // server still validates the token in the background and logs out only
        // when it explicitly rejects the session.
        let legacyToken = UserDefaults.standard.string(forKey: "authToken")
            ?? UserDefaults.standard.string(forKey: "pb_auth_token")
            ?? ""
        let secureToken = KeychainTokenStore.load()
        let restoredToken = secureToken ?? legacyToken
        let restoredAccountID = UserDefaults.standard.string(forKey: "accountID")
            ?? Self.accountID(from: restoredToken)
            ?? ""
        self.token = restoredToken
        if secureToken == nil, !legacyToken.isEmpty { try? KeychainTokenStore.save(legacyToken) }
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults.standard.removeObject(forKey: "pb_auth_token")
        self.isLoggedIn = !restoredToken.isEmpty && !restoredAccountID.isEmpty
        self.accountName = UserDefaults.standard.string(forKey: "accountDisplayName") ?? ""
        self.accountID = restoredAccountID
        self.accountEmail = UserDefaults.standard.string(forKey: "accountEmail") ?? ""
        self.accountCreatedAt = UserDefaults.standard.string(forKey: "accountCreatedAt") ?? ""
        self.accountAvatarFilename = UserDefaults.standard.string(forKey: "accountAvatarFilename") ?? ""
        self.accountAvatarLocalData = Self.loadLocalAvatar(accountID: restoredAccountID)
        self.lastSessionRefreshAt = UserDefaults.standard.object(forKey: Self.sessionRefreshKey(restoredAccountID)) as? Date
        Task { await refreshSession() }
    }

    var accountAvatarURL: URL? {
        guard !accountID.isEmpty, !accountAvatarFilename.isEmpty else { return nil }
        return URL(string: "\(baseURL)/api/files/users/\(accountID)/\(accountAvatarFilename)")
    }

    private func parsePocketBaseError(_ data: Data) -> String {
        guard let errorObj = try? JSONDecoder().decode(PocketBaseErrorResponse.self, from: data) else {
            return LanguageStore.localizedString("auth.unexpected_error")
        }

        var errorMessages: [String] = []

        if let fieldErrors = errorObj.data {
            if let emailError = fieldErrors["email"] {
                if emailError.code == "validation_invalid_email" || emailError.message.contains("already in use") {
                    errorMessages.append(LanguageStore.localizedString("auth.email_already_used"))
                } else {
                    errorMessages.append(LanguageStore.localizedString("auth.enter_valid_email"))
                }
            }

            if let usernameError = fieldErrors["username"] {
                if usernameError.code == "validation_invalid_username" || usernameError.message.contains("already in use") {
                    errorMessages.append(LanguageStore.localizedString("auth.username_already_used"))
                } else {
                    errorMessages.append(LanguageStore.localizedString("auth.invalid_username"))
                }
            }

            if fieldErrors["password"] != nil {
                errorMessages.append(LanguageStore.localizedString("auth.password_requirements"))
            }
        }

        if errorMessages.isEmpty {
            return errorObj.message.isEmpty ? LanguageStore.localizedString("auth.action_failed_check_input") : errorObj.message
        }

        return errorMessages.joined(separator: "\n")
    }

    /// Refreshes the PocketBase JWT and account record. A temporary network
    /// failure never destroys a valid local token; rejected sessions do.
    func refreshSession(force: Bool = false) async {
        guard !token.isEmpty,
              let url = URL(string: "\(baseURL)/api/collections/users/auth-refresh") else { return }
        guard !isRefreshingSession else { return }
        if !force, let lastSessionRefreshAt,
           Date().timeIntervalSince(lastSessionRefreshAt) < 900 { return }
        let expectedToken = token
        let expectedRevision = authRevision

        isRefreshingSession = true
        defer { isRefreshingSession = false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            guard authRevision == expectedRevision, token == expectedToken else { return }
            guard (200...299).contains(http.statusCode) else {
                if http.statusCode == 401 || http.statusCode == 403 { logout() }
                return
            }
            let authData = try JSONDecoder().decode(AuthResponse.self, from: data)
            guard authData.record.verified else {
                logout()
                return
            }
            try applyAuth(authData)
            let refreshedAt = Date()
            lastSessionRefreshAt = refreshedAt
            UserDefaults.standard.set(refreshedAt, forKey: Self.sessionRefreshKey(accountID))
            if UserDefaults.standard.bool(forKey: pendingAvatarKey), let accountAvatarLocalData {
                try? await uploadAvatarData(accountAvatarLocalData)
            }
        } catch {
            // Keep the existing token for offline use. The next foreground
            // transition retries the refresh.
        }
    }

    func login(email: String, password: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/collections/users/auth-with-password") else { return }
        authRevision &+= 1
        let expectedRevision = authRevision

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["identity": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            if let response = try? JSONDecoder().decode(PocketBaseErrorResponse.self, from: data) {
                let details = ([response.message] + (response.data?.values.flatMap { [$0.code, $0.message] } ?? []))
                    .joined(separator: " ").lowercased()
                if details.contains("verif") { throw AuthError.emailNotVerified(email) }
            }
            let readableError = parsePocketBaseError(data)
            let hasFieldDetails = (try? JSONDecoder().decode(PocketBaseErrorResponse.self, from: data).data)?.isEmpty == false
            throw AuthError.custom(hasFieldDetails ? readableError : LanguageStore.localizedString("auth.invalid_credentials"))
        }

        let authData = try JSONDecoder().decode(AuthResponse.self, from: data)

        guard authData.record.verified else {
            throw AuthError.emailNotVerified(email)
        }

        guard authRevision == expectedRevision else { throw CancellationError() }
        try applyAuth(authData)
    }

    func register(username: String, email: String, password: String) async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: "\(baseURL)/api/collections/users/records") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "username": cleanUsername,
            "email": cleanEmail,
            "password": password,
            "passwordConfirm": password,
            "has_local_password": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            // Rufe die Formatierungs-Funktion auf:
            let readableError = parsePocketBaseError(data)
            throw AuthError.custom(readableError)
        }

        // Erst JETZT die Verifizierungs-E-Mail anfordern
        try await resendVerification(email: cleanEmail)
    }

        /// Fordert die Verifizierungs-E-Mail für eine Adresse erneut an
    func resendVerification(email: String) async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard let url = URL(string: "\(baseURL)/api/collections/users/request-verification") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": cleanEmail]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Verifizierung fehlgeschlagen."
            throw AuthError.custom(errorMsg)
        }
    }

    func requestPasswordReset(email: String) async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanEmail.isEmpty else { throw AuthError.custom(LanguageStore.localizedString("auth.enter_email")) }
        try await sendVoid(
            path: "/api/collections/users/request-password-reset",
            body: ["email": cleanEmail],
            authenticated: false
        )
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard isLoggedIn, !token.isEmpty, !accountID.isEmpty else { throw AuthError.custom(LanguageStore.localizedString("auth.not_signed_in")) }
        guard newPassword.count >= 8 else { throw AuthError.custom(LanguageStore.localizedString("auth.new_password_minimum")) }
        try await sendVoid(
            path: "/api/collections/users/records/\(accountID)",
            method: "PATCH",
            body: ["oldPassword": currentPassword, "password": newPassword, "passwordConfirm": newPassword, "has_local_password": "true"],
            authenticated: true
        )
        await loadAccountSignInMethods()
    }

    func updateUsername(_ username: String) async throws -> String {
        guard isLoggedIn, !token.isEmpty, !accountID.isEmpty else {
            throw AuthError.custom(LanguageStore.localizedString("auth.not_signed_in"))
        }

        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) != nil else {
            throw AuthError.custom(LanguageStore.localizedString("auth.invalid_username"))
        }

        try await sendVoid(
            path: "/api/collections/users/records/\(accountID)",
            method: "PATCH",
            body: ["username": normalized],
            authenticated: true,
            timeout: 10
        )

        accountName = normalized
        UserDefaults.standard.set(normalized, forKey: "accountDisplayName")
        return normalized
    }

    func updateAvatar(_ sourceData: Data) async throws {
        guard isLoggedIn, !token.isEmpty, !accountID.isEmpty else {
            throw AuthError.custom(LanguageStore.localizedString("auth.not_signed_in"))
        }
        guard let sourceImage = UIImage(data: sourceData) else {
            throw AuthError.custom(LanguageStore.localizedString("profile.avatar_invalid_image"))
        }

        let maximumSide: CGFloat = 1024
        let scale = min(1, maximumSide / max(sourceImage.size.width, sourceImage.size.height))
        let targetSize = CGSize(width: max(1, sourceImage.size.width * scale), height: max(1, sourceImage.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let normalizedImage = renderer.image { _ in sourceImage.draw(in: CGRect(origin: .zero, size: targetSize)) }
        guard let imageData = normalizedImage.jpegData(compressionQuality: 0.82), imageData.count <= 5_242_880 else {
            throw AuthError.custom(LanguageStore.localizedString("profile.avatar_too_large"))
        }
        persistLocalAvatar(imageData)
        UserDefaults.standard.set(true, forKey: pendingAvatarKey)
        try await uploadAvatarData(imageData)
    }

    private func uploadAvatarData(_ imageData: Data) async throws {
        guard let url = URL(string: "\(baseURL)/api/collections/users/records/\(accountID)") else {
            throw AuthError.invalidServerURL
        }

        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        let boundary = "HyseAvatar-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"avatar\"; filename=\"profile.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw AuthError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidServerResponse }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { logout() }
            throw AuthError.pocketBase(parsePocketBaseError(data))
        }
        guard let record = try? JSONDecoder().decode(AuthRecord.self, from: data),
              let filename = record.avatar, !filename.isEmpty else {
            throw AuthError.invalidServerResponse
        }
        accountAvatarFilename = filename
        UserDefaults.standard.set(filename, forKey: "accountAvatarFilename")
        UserDefaults.standard.removeObject(forKey: pendingAvatarKey)
    }

    func loadAccountSignInMethods() async {
        guard isLoggedIn, !token.isEmpty, let url = URL(string: "\(baseURL)/api/hyse/account-methods") else { return }
        accountMethodsLoadError = nil
        var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AuthError.invalidServerResponse }
            guard (200...299).contains(http.statusCode) else {
                if http.statusCode == 401 { logout() }
                throw AuthError.pocketBase(parsePocketBaseError(data))
            }
            accountSignInMethods = try JSONDecoder().decode(AccountSignInMethods.self, from: data)
        } catch {
            accountMethodsLoadError = error.localizedDescription
        }
    }

    func requestEmailChange(newEmail: String, proof: EmailChangeProof) async throws {
        guard isLoggedIn, !token.isEmpty else { throw AuthError.custom(LanguageStore.localizedString("auth.not_signed_in")) }
        let cleanEmail = newEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanEmail.contains("@"), cleanEmail.contains("."), cleanEmail != accountEmail.lowercased() else {
            throw AuthError.custom(LanguageStore.localizedString("auth.enter_valid_different_email"))
        }
        let expectedAccountID = accountID
        let proofAuth: AuthResponse
        switch proof {
        case .password(let password):
            guard !password.isEmpty else { throw AuthError.custom(LanguageStore.localizedString("auth.enter_current_password")) }
            proofAuth = try await sendJSON(path: "/api/collections/users/auth-with-password", method: "POST", body: ["identity": accountEmail, "password": password])
        case .oauth(let provider):
            guard accountSignInMethods.providers.contains(provider.rawValue) else {
                throw AuthError.unsupportedProvider
            }
            // Reauthenticate independently. Sending the existing PocketBase
            // token here would allow auth-with-oauth2 to link a newly selected
            // Google identity to the current account before we can compare IDs.
            proofAuth = try await oauthAuthResponse(provider: provider.rawValue)
        }
        guard proofAuth.record.id == expectedAccountID else { throw AuthError.custom(LanguageStore.localizedString("auth.confirm_same_account")) }
        try applyAuth(proofAuth)
        try await sendVoid(path: "/api/hyse/request-email-change", body: ["newEmail": cleanEmail], authenticated: true)
    }

    func loginWithOAuth(provider: String) async throws {
        authRevision &+= 1
        let expectedRevision = authRevision
        let result = try await oauthAuthResponse(provider: provider)
        guard result.record.verified else { throw AuthError.emailNotVerified(result.record.email) }
        guard authRevision == expectedRevision else { throw CancellationError() }
        try applyAuth(result)
    }

    private func oauthAuthResponse(provider: String) async throws -> AuthResponse {
        guard ["google", "apple"].contains(provider) else { throw AuthError.unsupportedProvider }
        let methods = try await fetchAuthMethods()
        guard let configuration = methods.providers.first(where: { configuration in configuration.name == provider }) else { throw AuthError.providerNotConfigured(provider) }
        let authorizationURL = try makeAuthorizationURL(configuration: configuration, provider: provider)
        defer { oauthSession = nil }
        let callbackURL = try await runAuthenticationSession(url: authorizationURL, provider: provider)
        let callback = try validateCallback(callbackURL, expectedState: configuration.state)
        return try await sendJSON(
            path: "/api/collections/users/auth-with-oauth2",
            method: "POST",
            body: OAuthCodeExchange(provider: provider, code: callback.code, codeVerifier: configuration.codeVerifier, redirectURL: providerOAuthRedirectURL)
        )
    }

    private func fetchAuthMethods() async throws -> AuthMethodsResponse {
        try await sendJSON(path: "/api/collections/users/auth-methods", method: "GET", body: Optional<String>.none)
    }

    private func makeAuthorizationURL(configuration: OAuthProviderConfiguration, provider: String) throws -> URL {
        guard var components = URLComponents(string: configuration.authURL) else { throw AuthError.invalidAuthorizationURL }
        var items = components.queryItems ?? []
        items.removeAll {
            $0.name.caseInsensitiveCompare("redirect_uri") == .orderedSame ||
            $0.name.caseInsensitiveCompare("response_mode") == .orderedSame
        }
        // Keep response_mode ahead of redirect_uri in the final URL. More
        // importantly, never reuse PocketBase's value for Apple: requesting
        // name/email with query mode is rejected before authentication starts.
        if provider == "apple" { items.append(URLQueryItem(name: "response_mode", value: "form_post")) }
        items.append(URLQueryItem(name: "redirect_uri", value: providerOAuthRedirectURL))
        components.queryItems = items
        guard let url = components.url else { throw AuthError.invalidAuthorizationURL }
        if provider == "apple" {
            let finalItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let responseMode = finalItems.first { $0.name.caseInsensitiveCompare("response_mode") == .orderedSame }?.value
            let redirectURL = finalItems.first { $0.name.caseInsensitiveCompare("redirect_uri") == .orderedSame }?.value
            guard responseMode == "form_post", redirectURL == providerOAuthRedirectURL else {
                throw AuthError.invalidAuthorizationURL
            }
        }
        return url
    }

    private func runAuthenticationSession(url: URL, provider: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let once = OAuthContinuation(continuation)
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(appCallbackScheme)) { callbackURL, error in
                if let sessionError = error as? ASWebAuthenticationSessionError, sessionError.code == .canceledLogin {
                    once.resume(throwing: CancellationError())
                } else if let error {
                    once.resume(throwing: AuthError.authenticationSession(error.localizedDescription))
                } else if let callbackURL {
                    once.resume(returning: callbackURL)
                } else {
                    once.resume(throwing: AuthError.invalidCallbackURL)
                }
            }
            session.presentationContextProvider = OAuthPresentationContext.shared
            // Reuse the browser's Google session so signing in to Hyse does not
            // require a fresh Google account login on every attempt. Keep the
            // private browser session for Apple sign-in.
            session.prefersEphemeralWebBrowserSession = provider != "google"
            oauthSession = session
            guard session.start() else {
                once.resume(throwing: AuthError.authenticationSession(LanguageStore.localizedString("auth.sign_in_window_failed")))
                return
            }
        }
    }

    private func validateCallback(_ url: URL, expectedState: String) throws -> (code: String, state: String) {
        guard url.scheme == appCallbackScheme, url.host == "oauth-callback",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AuthError.invalidCallbackURL
        }
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let providerError = values["error"], !providerError.isEmpty {
            throw AuthError.providerRejected(values["error_description"] ?? providerError)
        }
        guard let state = values["state"], state == expectedState else { throw AuthError.stateMismatch }
        guard let code = values["code"], !code.isEmpty else { throw AuthError.missingAuthorizationCode }
        return (code, state)
    }

    private func sendJSON<Response: Decodable, Body: Encodable>(path: String, method: String, body: Body?, authenticated: Bool = false) async throws -> Response {
        guard let url = URL(string: baseURL + path) else { throw AuthError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw AuthError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidServerResponse }
        guard (200...299).contains(http.statusCode) else { throw AuthError.pocketBase(parsePocketBaseError(data)) }
        do { return try JSONDecoder().decode(Response.self, from: data) }
        catch { throw AuthError.invalidServerResponse }
    }

    private func sendVoid(
        path: String,
        method: String = "POST",
        body: [String: String],
        authenticated: Bool,
        timeout: TimeInterval = 30
    ) async throws {
        guard let url = URL(string: baseURL + path) else { throw AuthError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw AuthError.network(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidServerResponse }
        guard (200...299).contains(http.statusCode) else {
            // 403 can mean that a fresh reauthentication proof is missing; it
            // must not destroy an otherwise valid account session.
            if authenticated, http.statusCode == 401 { logout() }
            throw AuthError.pocketBase(parsePocketBaseError(data))
        }
    }

    private func applyAuth(_ authData: AuthResponse) throws {
        authRevision &+= 1
        try KeychainTokenStore.save(authData.token)
        token = authData.token
        accountID = authData.record.id
        accountAvatarLocalData = Self.loadLocalAvatar(accountID: accountID)
        accountName = authData.record.username.isEmpty ? authData.record.email : authData.record.username
        accountEmail = authData.record.email
        accountCreatedAt = authData.record.created
        accountAvatarFilename = authData.record.avatar ?? ""
        UserDefaults.standard.set(accountName, forKey: "accountDisplayName")
        UserDefaults.standard.set(accountID, forKey: "accountID")
        UserDefaults.standard.set(accountEmail, forKey: "accountEmail")
        UserDefaults.standard.set(accountCreatedAt, forKey: "accountCreatedAt")
        if accountAvatarFilename.isEmpty { UserDefaults.standard.removeObject(forKey: "accountAvatarFilename") }
        else { UserDefaults.standard.set(accountAvatarFilename, forKey: "accountAvatarFilename") }
        isLoggedIn = true
    }

    func deleteAccount() async throws {
        guard isLoggedIn, !token.isEmpty else {
            throw AuthError.custom(LanguageStore.localizedString("auth.not_signed_in"))
        }
        guard let url = URL(string: "\(baseURL)/api/hyse/account") else {
            throw AuthError.invalidServerURL
        }

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidServerResponse
        }
        guard http.statusCode == 204 else {
            throw AuthError.pocketBase(parsePocketBaseError(data))
        }

        logout()
    }

        func logout() {
            authRevision &+= 1
            oauthSession?.cancel()
            oauthSession = nil
            token = ""
            KeychainTokenStore.delete()
            isLoggedIn = false
            accountName = ""
            accountID = ""
            accountEmail = ""
            accountCreatedAt = ""
            accountAvatarFilename = ""
            accountAvatarLocalData = nil
            lastSessionRefreshAt = nil
            UserDefaults.standard.removeObject(forKey: "accountDisplayName")
            UserDefaults.standard.removeObject(forKey: "accountID")
            UserDefaults.standard.removeObject(forKey: "accountEmail")
            UserDefaults.standard.removeObject(forKey: "accountCreatedAt")
            UserDefaults.standard.removeObject(forKey: "accountAvatarFilename")
            UserDefaults.standard.removeObject(forKey: "pb_auth_token")
        }

        private var pendingAvatarKey: String { "pending_profile_avatar_\(accountID)_v1" }

        private func persistLocalAvatar(_ data: Data) {
            guard !accountID.isEmpty, let url = Self.localAvatarURL(accountID: accountID) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            accountAvatarLocalData = data
        }

        private static func loadLocalAvatar(accountID: String) -> Data? {
            guard !accountID.isEmpty, let url = localAvatarURL(accountID: accountID) else { return nil }
            return try? Data(contentsOf: url)
        }

        private static func localAvatarURL(accountID: String) -> URL? {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Hyse/ProfileAvatars", isDirectory: true)
                .appendingPathComponent("\(accountID).jpg")
        }

        private static func sessionRefreshKey(_ accountID: String) -> String {
            "account_session_refreshed_\(accountID)_v1"
        }

        private static func accountID(from token: String) -> String? {
            let parts = token.split(separator: ".")
            guard parts.count > 1 else { return nil }
            var payload = String(parts[1])
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            guard let data = Data(base64Encoded: payload),
                  let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return values["id"] as? String ?? values["sub"] as? String
        }
    }

    enum OAuthProvider: String, CaseIterable, Identifiable {
        case google, apple
        var id: String { rawValue }
    }

    enum EmailChangeProof { case password(String), oauth(OAuthProvider) }

    struct AccountSignInMethods: Codable, Equatable {
        let hasPassword: Bool
        let providers: [String]
        var hasGoogle: Bool { providers.contains("google") }
        var hasApple: Bool { providers.contains("apple") }
        var availableMethods: [String] {
            (hasPassword ? ["password"] : []) + OAuthProvider.allCases.map(\.rawValue).filter(providers.contains)
        }
    }

    struct AuthResponse: Codable {
        let token: String
        let record: AuthRecord
    }

    private final class OAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
        static let shared = OAuthPresentationContext()
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow)
                ?? scenes.flatMap(\.windows).first
                ?? ASPresentationAnchor()
        }
    }

    struct AuthRecord: Codable {
        let id: String
        let username: String
        let email: String
        let created: String
        let verified: Bool
        let avatar: String?
    }

enum AuthError: LocalizedError {
    case verificationFailed
    case emailNotVerified(String)
    case custom(String)
    case unsupportedProvider, providerNotConfigured(String), invalidAuthorizationURL, invalidCallbackURL
    case missingAuthorizationCode, stateMismatch, invalidServerURL, invalidServerResponse
    case authenticationSession(String), providerRejected(String), network(String), pocketBase(String)

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return LanguageStore.localizedString("auth.verification_email_failed")
        case .emailNotVerified:
            return LanguageStore.localizedString("auth.email_not_verified")
        case .custom(let message):
            return message
        case .unsupportedProvider: return LanguageStore.localizedString("auth.unsupported_provider")
        case .providerNotConfigured(let provider): return LanguageStore.formattedString("auth.provider_not_configured", arguments: [provider.capitalized])
        case .invalidAuthorizationURL: return LanguageStore.localizedString("auth.invalid_authorization_url")
        case .invalidCallbackURL: return LanguageStore.localizedString("auth.invalid_callback_url")
        case .missingAuthorizationCode: return LanguageStore.localizedString("auth.missing_authorization_code")
        case .stateMismatch: return LanguageStore.localizedString("auth.state_mismatch")
        case .invalidServerURL: return LanguageStore.localizedString("auth.invalid_server_url")
        case .invalidServerResponse: return LanguageStore.localizedString("auth.invalid_server_response")
        case .authenticationSession(let message), .providerRejected(let message), .network(let message), .pocketBase(let message): return message
        }
    }
}

private struct AuthMethodsResponse: Decodable {
    let providers: [OAuthProviderConfiguration]
    private enum CodingKeys: String, CodingKey { case oauth2, authProviders }
    private struct OAuthMethods: Decodable { let enabled: Bool; let providers: [OAuthProviderConfiguration] }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let oauth2 = try container.decodeIfPresent(OAuthMethods.self, forKey: .oauth2), oauth2.enabled {
            providers = oauth2.providers
        } else {
            providers = try container.decodeIfPresent([OAuthProviderConfiguration].self, forKey: .authProviders) ?? []
        }
    }
}

private struct OAuthProviderConfiguration: Decodable {
    let name: String
    let state: String
    let authURL: String
    let codeVerifier: String
    private enum CodingKeys: String, CodingKey { case name, state, authURL, authUrl, codeVerifier }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        state = try container.decode(String.self, forKey: .state)
        authURL = try container.decodeIfPresent(String.self, forKey: .authURL)
            ?? container.decode(String.self, forKey: .authUrl)
        codeVerifier = try container.decode(String.self, forKey: .codeVerifier)
    }
}

private struct OAuthCodeExchange: Encodable {
    let provider: String
    let code: String
    let codeVerifier: String
    let redirectURL: String
    private enum CodingKeys: String, CodingKey { case provider, code, codeVerifier, redirectURL, redirectUrl }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(code, forKey: .code)
        try container.encode(codeVerifier, forKey: .codeVerifier)
        // PocketBase <= 0.22 used redirectUrl; current releases use redirectURL.
        try container.encode(redirectURL, forKey: .redirectURL)
        try container.encode(redirectURL, forKey: .redirectUrl)
    }
}

private final class OAuthContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    init(_ continuation: CheckedContinuation<URL, Error>) { self.continuation = continuation }
    func resume(returning url: URL) { take()?.resume(returning: url) }
    func resume(throwing error: Error) { take()?.resume(throwing: error) }
    private func take() -> CheckedContinuation<URL, Error>? {
        lock.lock(); defer { lock.unlock() }
        defer { continuation = nil }
        return continuation
    }
}

private struct PocketBaseErrorResponse: Decodable {
    let message: String
    let data: [String: FieldError]?

    struct FieldError: Decodable {
        let code: String
        let message: String
    }
}
