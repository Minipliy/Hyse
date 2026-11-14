import SwiftUI

struct PasswordManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var language: LanguageStore
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var isError = false

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var hasPassword: Bool { authManager.accountSignInMethods.hasPassword }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if hasPassword {
                        Label(t("password_management.local_password_enabled"), systemImage: "checkmark.shield.fill")
                            .foregroundStyle(HyseColor.success)
                    } else {
                        Label(t("password_management.signed_in_google"), systemImage: "g.circle.fill")
                        Text(t("password_management.account_does_not_have_local_password_yet"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if hasPassword {
                    Section(t("password_management.change_password")) {
                        SecureField(t("password_management.current_password"), text: $currentPassword)
                        SecureField(t("password_management.new_password"), text: $newPassword)
                        SecureField(t("password_management.confirm_new_password"), text: $confirmation)
                        Button(t("password_management.change_password")) { changePassword() }
                            .disabled(isWorking || currentPassword.isEmpty || newPassword.count < 8 || newPassword != confirmation)
                    }
                } else {
                    Section {
                        Button { requestSetPasswordLink() } label: {
                            HStack {
                                Label(t("password_management.set_password"), systemImage: "envelope.badge.shield.half.filled")
                                Spacer()
                                if isWorking { ProgressView() }
                            }
                        }
                        .disabled(isWorking)
                    } footer: {
                        Text(t("password_management.link_will_sent_hyse_never_asks_google").replacingOccurrences(of: "%@", with: authManager.accountEmail))
                    }
                }

                if let message {
                    Section { HyseStatusBanner(title: nil, message: message, style: isError ? .error : .success) }
                }
            }
            .hyseForm()
            .navigationTitle(t("app_tabs.password_security"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("add_entry.done")) { dismiss() } } }
            .task { await authManager.loadAccountSignInMethods() }
        }
        .hyseScreen()
    }

    private func requestSetPasswordLink() {
        isWorking = true; message = nil
        Task {
            defer { isWorking = false }
            do {
                try await authManager.requestPasswordReset(email: authManager.accountEmail)
                isError = false
                message = t("password_management.we_sent_you_secure_link_set_password")
            } catch { isError = true; message = error.localizedDescription }
        }
    }

    private func changePassword() {
        isWorking = true; message = nil
        Task {
            defer { isWorking = false }
            do {
                try await authManager.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                currentPassword = ""; newPassword = ""; confirmation = ""
                isError = false; message = t("password_management.password_has_been_changed")
            } catch { isError = true; message = error.localizedDescription }
        }
    }
}
