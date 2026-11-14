import SwiftUI

private enum AuthenticationScreen: String { case signIn, register, resetPassword }
private enum AuthenticationNoticeStyle {
    case success, information, error
    var icon: String { self == .success ? "checkmark.circle.fill" : self == .information ? "envelope.badge.fill" : "exclamationmark.triangle.fill" }
    var color: Color { self == .success ? HyseColor.success : self == .information ? HyseColor.information : HyseColor.danger }
}
private struct AuthenticationNotice { let style: AuthenticationNoticeStyle; let message: String }

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var language: LanguageStore
    @State private var screen: AuthenticationScreen
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var notice: AuthenticationNotice?
    @State private var unverifiedEmail: String?
    @State private var activeAction: String?
    @State private var confirmsMinimumAge = false

    /// Allows entry points such as the first-launch tutorial to take people
    /// directly to registration instead of making them switch modes first.
    init(startsInRegistration: Bool = false) {
        _screen = State(initialValue: startsInRegistration ? .register : .signIn)
    }

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var isBusy: Bool { activeAction != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    if screen != .resetPassword { modePicker }
                    fields
                    if let notice { noticeBox(notice) }
                    actions
                }
                .frame(maxWidth: 560).padding(HyseSpacing.xLarge).frame(maxWidth: .infinity)
            }
            .background(HyseBackdrop())
            .navigationTitle(navigationTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("login.close")) { dismiss() }.disabled(isBusy) } }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: screen == .resetPassword ? "key.fill" : "heart.text.square.fill")
                .font(.system(size: 44, weight: .semibold)).foregroundStyle(HyseColor.accent).padding(HyseSpacing.large)
                .background(HyseColor.accent.opacity(0.12), in: Circle()).accessibilityHidden(true)
            Text(headerTitle).font(.title2.bold()).multilineTextAlignment(.center)
            Text(headerSubtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(HyseSpacing.xLarge)
        .hyseGlassSurface(radius: HyseRadius.sheet)
        .padding(.top, 8)
    }

    private var modePicker: some View {
        Picker(t("login.access"), selection: $screen) {
            Text(t("app_tabs.sign_in")).tag(AuthenticationScreen.signIn)
            Text(t("login.create_account")).tag(AuthenticationScreen.register)
        }
        .pickerStyle(.segmented).disabled(isBusy)
        .onChange(of: screen) { _, _ in notice = nil; unverifiedEmail = nil }
    }

    private var fields: some View {
        VStack(spacing: 14) {
            if screen == .register {
                textField(t("login.username"), icon: "person", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            textField(t("login.email_address"), icon: "envelope", text: $email)
                .textInputAutocapitalization(.never).keyboardType(.emailAddress).textContentType(.emailAddress).autocorrectionDisabled()
            if screen != .resetPassword {
                SecureField(t("login.password"), text: $password)
                    .textContentType(screen == .register ? .newPassword : .password).hyseField().disabled(isBusy)
                if screen == .register {
                    SecureField(t("login.confirm_password"), text: $passwordConfirmation)
                        .textContentType(.newPassword).hyseField().disabled(isBusy)
                    Label(t("login.use_at_least_8_characters"), systemImage: "checkmark.shield")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if screen != .resetPassword {
                Toggle(language.isGerman ? "Ich bin mindestens 16 Jahre alt." : "I am at least 16 years old.", isOn: $confirmsMinimumAge)
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if screen == .resetPassword {
            primaryButton(t("login.send_reset_link"), action: "reset", enabled: isValidEmail, perform: requestPasswordReset)
            Button(t("login.back_sign_in"), action: switchToSignIn).disabled(isBusy)
        } else {
            if let unverifiedEmail {
                Button { resendVerification(unverifiedEmail) } label: { actionLabel(t("login.resend_verification_email"), action: "verification").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large).disabled(isBusy)
                Button(t("login.sign_in_now"), action: switchToSignIn).fontWeight(.semibold).disabled(isBusy)
            } else {
                primaryButton(screen == .register ? t("login.create_account") : t("app_tabs.sign_in"), action: "authentication", enabled: canSubmit, perform: authenticate)
            }
            if screen == .signIn && unverifiedEmail == nil {
                Button(t("login.forgot_password")) { screen = .resetPassword; notice = nil }
                    .font(.subheadline.weight(.semibold)).disabled(isBusy)
                HStack { Rectangle().frame(height: 1).foregroundStyle(.quaternary); Text(t("login.text")).font(.caption).foregroundStyle(.secondary); Rectangle().frame(height: 1).foregroundStyle(.quaternary) }
                oauthButton("google", t("login.continue_google"))
                oauthButton("apple", t("login.continue_apple"))
            }
        }
        Button(t("login.continue_without_account")) { dismiss() }
            .font(.subheadline.weight(.medium)).foregroundStyle(.secondary).disabled(isBusy)
    }

    private func oauthButton(_ provider: String, _ title: String) -> some View {
        Button { authenticateWithOAuth(provider) } label: { actionLabel(title, action: provider).frame(maxWidth: .infinity) }
            .buttonStyle(HyseSecondaryButtonStyle()).disabled(isBusy || !confirmsMinimumAge)
    }
    private func noticeBox(_ value: AuthenticationNotice) -> some View {
        HyseStatusBanner(title: nil, message: value.message, style: value.style == .success ? .success : value.style == .information ? .information : .error)
    }
    private func primaryButton(_ title: String, action: String, enabled: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { actionLabel(title, action: action).frame(maxWidth: .infinity).padding(.vertical, 5) }
            .buttonStyle(HysePrimaryButtonStyle()).disabled(!enabled || isBusy)
    }
    @ViewBuilder private func actionLabel(_ title: String, action: String) -> some View {
        if activeAction == action { ProgressView().accessibilityLabel(t("login.loading")) }
        else { Label(title, systemImage: action == "google" ? "g.circle.fill" : action == "apple" ? "apple.logo" : "arrow.right") }
    }
    private func textField(_ placeholder: String, icon: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) { Image(systemName: icon).foregroundStyle(.secondary).accessibilityHidden(true); TextField(placeholder, text: text) }
            .hyseField().disabled(isBusy)
    }

    private var isValidEmail: Bool { let value = email.trimmingCharacters(in: .whitespacesAndNewlines); return value.contains("@") && value.contains(".") }
    private var canSubmit: Bool { confirmsMinimumAge && isValidEmail && password.count >= 8 && (screen != .register || (!username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && password == passwordConfirmation)) }
    private var navigationTitle: String { screen == .signIn ? t("app_tabs.sign_in") : screen == .register ? t("login.create_account") : t("login.reset_password") }
    private var headerTitle: String { screen == .signIn ? t("login.welcome_back") : screen == .register ? t("login.hyse_account") : t("login.forgot_password_2") }
    private var headerSubtitle: String { screen == .resetPassword ? t("login.enter_email_address_we_ll_send_you") : t("login.securely_sync_foods_entries_account") }

    private func authenticate() {
        guard canSubmit else { notice = .init(style: .error, message: t("login.please_check_details")); return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        activeAction = "authentication"; notice = nil
        Task {
            defer { activeAction = nil }
            do {
                if screen == .register {
                    try await authManager.register(username: username.trimmingCharacters(in: .whitespacesAndNewlines), email: address, password: password)
                    unverifiedEmail = address; password = ""; passwordConfirmation = ""
                    notice = .init(style: .success, message: t("login.we_sent_you_confirmation_link_by_email"))
                } else { try await authManager.login(email: address, password: password); dismiss() }
            } catch let AuthError.emailNotVerified(address) {
                email = address; unverifiedEmail = address
                notice = .init(style: .information, message: t("login.email_address_has_not_been_verified_yet"))
            } catch { notice = .init(style: .error, message: localizedError(error)) }
        }
    }
    private func requestPasswordReset() {
        guard isValidEmail else { notice = .init(style: .error, message: t("login.please_enter_valid_email_address")); return }
        activeAction = "reset"; notice = nil
        Task { defer { activeAction = nil }; do { try await authManager.requestPasswordReset(email: email); notice = .init(style: .success, message: t("login.if_account_exists_email_address_password_reset")) } catch { notice = .init(style: .error, message: localizedError(error)) } }
    }
    private func resendVerification(_ address: String) {
        activeAction = "verification"; notice = nil
        Task { defer { activeAction = nil }; do { try await authManager.resendVerification(email: address); notice = .init(style: .success, message: t("login.we_sent_you_another_verification_link_by")) } catch { notice = .init(style: .error, message: localizedError(error)) } }
    }
    private func authenticateWithOAuth(_ provider: String) {
        activeAction = provider; notice = nil
        Task { defer { activeAction = nil }; do { try await authManager.loginWithOAuth(provider: provider); dismiss() } catch is CancellationError { notice = .init(style: .information, message: t("login.sign_in_was_cancelled")) } catch { notice = .init(style: .error, message: localizedError(error)) } }
    }
    private func switchToSignIn() { screen = .signIn; unverifiedEmail = nil; notice = nil; password = ""; passwordConfirmation = "" }
    private func localizedError(_ error: Error) -> String { if case AuthError.network = error { return t("login.could_not_reach_server_check_internet_connection") }; return error.localizedDescription }
}
