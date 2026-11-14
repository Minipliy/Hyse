import SwiftUI

/// A report path available from Settings even when Hyse is used as a guest.
struct PublicContentReportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var auth: AuthManager

    @State private var location = ""
    @State private var contactEmail = ""
    @State private var reason: ContentReportReason = .illegal
    @State private var details = ""
    @State private var goodFaith = false
    @State private var isSubmitting = false
    @State private var reportID: String?
    @State private var errorMessage: String?

    private var isGerman: Bool { language.isGerman }
    private func t(_ key: String) -> String { language.text(key) }
    private var privacyURL: URL {
        URL(string: isGerman ? "\(HyseConfiguration.serverURL)/de/datenschutz" : "\(HyseConfiguration.serverURL)/en/privacy")!
    }
    private var isValid: Bool {
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLocation.count >= 8 && trimmedLocation.count <= 2048
            && trimmedEmail.contains("@") && trimmedEmail.contains(".") && trimmedEmail.count <= 254
            && (10...2000).contains(details.trimmingCharacters(in: .whitespacesAndNewlines).count)
            && goodFaith
    }

    var body: some View {
        NavigationStack {
            Form {
                if let reportID {
                    Section {
                        Label(t("content_reports.received"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(HyseColor.success)
                        Text(isGerman
                             ? "Deine Meldung wurde direkt an Hyse gesendet. Referenz: \(reportID). Wir kontaktieren dich unter der angegebenen E-Mail-Adresse zur Bearbeitung und Entscheidung."
                             : "Your report was sent directly to Hyse. Reference: \(reportID). We will contact you at the email address provided about its handling and decision.")
                            .font(.subheadline)
                    }
                } else {
                    Section {
                        Text(isGerman
                             ? "Du kannst rechtswidrige Inhalte auch ohne Hyse-Konto melden. Gib den genauen Link oder die ID des Inhalts an."
                             : "You can report illegal content without a Hyse account. Enter the exact link or ID of the content.")
                            .font(.subheadline)
                        TextField(isGerman ? "Link oder Inhalts-ID" : "Link or content ID", text: $location)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField(isGerman ? "E-Mail für Rückfragen" : "Email for follow-up", text: $contactEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Picker(t("content_reports.reason_title"), selection: $reason) {
                            ForEach(ContentReportReason.allCases) { value in
                                Text(t(value.localizationKey)).tag(value)
                            }
                        }
                    } header: {
                        Text(t("content_reports.report_title"))
                    }
                    Section {
                        TextEditor(text: $details)
                            .frame(minHeight: 130)
                        HStack {
                            Text(t("content_reports.details_hint"))
                            Spacer()
                            Text("\(details.count)/2000")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Section {
                        Toggle(t("content_reports.good_faith"), isOn: $goodFaith)
                        Link(t("settings.privacy_policy"), destination: privacyURL)
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(HyseColor.warning) }
                    }
                }
            }
            .hyseForm()
            .navigationTitle(t("content_reports.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(reportID == nil ? t("app_tabs.cancel") : t("common.ok")) { dismiss() }
                        .disabled(isSubmitting)
                }
                if reportID == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(t("content_reports.submit")) { submit() }
                            .disabled(isSubmitting || !isValid)
                    }
                }
            }
            .onAppear {
                if contactEmail.isEmpty && auth.isLoggedIn { contactEmail = auth.accountEmail }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private func submit() {
        guard !isSubmitting && isValid else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                reportID = try await ContentReportService.shared.submitPublic(
                    location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                    contactEmail: contactEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                    reason: reason,
                    details: details.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            } catch {
                errorMessage = error.localizedDescription == "content_reports.error"
                    ? t("content_reports.error") : error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
