import SwiftUI
import UIKit

struct LegalConsentView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var accountData: AccountDataStore
    @State private var termsAccepted = false
    @State private var privacyAcknowledged = false
    @State private var isAtLeastSixteen = false
    @State private var marketingAccepted = false
    @State private var showingCustomisation = false

    private var termsURL: URL { URL(string: language.isGerman ? "\(HyseConfiguration.serverURL)/de/agb" : "\(HyseConfiguration.serverURL)/en/terms")! }
    private var privacyURL: URL { URL(string: language.isGerman ? "\(HyseConfiguration.serverURL)/de/datenschutz" : "\(HyseConfiguration.serverURL)/en/privacy")! }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HyseSpacing.large) {
                    VStack(alignment: .leading, spacing: HyseSpacing.small) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(HyseColor.accent)
                            .accessibilityHidden(true)
                        Text(language.text("legal_consent.title"))
                            .font(.largeTitle.bold())
                        Text(language.text("legal_consent.introduction"))
                            .foregroundStyle(.secondary)
                    }

                    HyseCard {
                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            Label(language.text("legal_consent.necessary_processing"), systemImage: "lock.shield")
                                .font(.headline)
                            Text(language.text("legal_consent.necessary_processing_explanation"))
                                .font(.footnote).foregroundStyle(.secondary)
                            Divider()
                            Label(language.text("legal_consent.accept_terms"), systemImage: "doc.text.fill")
                            Link(destination: termsURL) { Label(language.text("legal_consent.open_terms"), systemImage: "arrow.up.right.square") }
                            Divider()
                            Toggle(language.text("legal_consent.minimum_age"), isOn: $isAtLeastSixteen)
                                .font(.subheadline)
                            Divider()
                            Label(language.text("legal_consent.acknowledge_privacy"), systemImage: "hand.raised.fill")
                            Link(destination: privacyURL) { Label(language.text("legal_consent.open_privacy"), systemImage: "arrow.up.right.square") }
                            Text(language.text("legal_consent.document_versions", [HyseLegalVersion.terms, HyseLegalVersion.privacy, language.language.rawValue.uppercased()]))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    VStack(spacing: HyseSpacing.small) {
                        consentChoice(language.text("legal_consent.accept_all"), prominent: true) {
                            termsAccepted = true
                            privacyAcknowledged = true
                            marketingAccepted = true
                            saveSelection()
                        }
                        .disabled(!isAtLeastSixteen)
                        consentChoice(language.text("legal_consent.use_essential_only")) {
                            termsAccepted = true
                            privacyAcknowledged = true
                            marketingAccepted = false
                            saveSelection()
                        }
                        .disabled(!isAtLeastSixteen)
                        consentChoice(language.text("legal_consent.choose_settings")) {
                            withAnimation(HyseMotion.standard) { showingCustomisation.toggle() }
                        }
                    }

                    if showingCustomisation {
                        HyseCard(accent: HyseColor.accent) {
                            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                                Text(language.text("legal_consent.customize_title")).font(.headline)
                                consentRow(isOn: $termsAccepted, title: language.text("legal_consent.accept_terms"), required: true)
                                consentRow(isOn: $privacyAcknowledged, title: language.text("legal_consent.acknowledge_privacy"), required: true)
                                Divider()
                                consentRow(isOn: $marketingAccepted, title: language.text("legal_consent.marketing"), required: false)
                                Text(language.text("legal_consent.marketing_purpose")).font(.footnote).foregroundStyle(.secondary)
                                Button(language.text("legal_consent.save_selection")) {
                                    saveSelection()
                                }
                                .buttonStyle(HysePrimaryButtonStyle())
                                .frame(maxWidth: .infinity)
                                .disabled(!isAtLeastSixteen || !termsAccepted || !privacyAcknowledged)
                            }
                        }
                    }

                    Text(language.text("legal_consent.choice_explanation"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(HyseSpacing.page)
            }
            .background(HyseBackdrop())
        }
    }

    @ViewBuilder private func consentChoice(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        if prominent {
            Button(action: action) { Text(title).frame(maxWidth: .infinity, minHeight: 48) }
                .buttonStyle(HysePrimaryButtonStyle())
        } else {
            Button(action: action) { Text(title).frame(maxWidth: .infinity, minHeight: 48) }
                .buttonStyle(HyseSecondaryButtonStyle())
        }
    }

    private func saveSelection() {
        guard isAtLeastSixteen else { return }
        accountData.acceptRequired(
            language: language.language,
            marketing: marketingAccepted
        )
    }

    private func consentRow(isOn: Binding<Bool>, title: String, required: Bool, locked: Bool = false) -> some View {
        Button { if !locked { isOn.wrappedValue.toggle() } } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: locked ? "lock.fill" : (isOn.wrappedValue ? "checkmark.square.fill" : "square"))
                    .font(.title3)
                    .foregroundStyle(isOn.wrappedValue ? HyseColor.accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Text(language.text(required ? "legal_consent.required" : "legal_consent.optional"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn.wrappedValue ? language.text("add_entry.selected") : language.text("add_entry.not_selected"))
    }
}

struct AccountHealthSyncConsentView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var accountData: AccountDataStore
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var userSettings: UserSettingsStore
    @State private var isAtLeastSixteen = false
    @State private var acceptsHealthSync = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HyseSpacing.large) {
                    Image(systemName: "heart.text.clipboard.fill")
                        .font(.system(size: 42)).foregroundStyle(HyseColor.accent)
                    Text(language.isGerman ? "Deine Gesundheitsdaten im Konto" : "Your health data in your account")
                        .font(.largeTitle.bold())
                    Text(language.isGerman
                         ? "Ein Hyse-Konto synchronisiert Ernährungs- und Trainingsprotokolle, Körperwerte, Ziele und Einstellungen mit dem Hyse-Server. Diese Angaben können Gesundheitsdaten enthalten. Du kannst Hyse ohne Konto lokal verwenden."
                         : "A Hyse account syncs nutrition and workout logs, body measurements, goals and settings with the Hyse server. This information may include health data. You can use Hyse locally without an account.")
                        .foregroundStyle(.secondary)
                    Link(language.text("legal_consent.open_privacy"), destination: URL(string: language.isGerman ? "\(HyseConfiguration.serverURL)/de/datenschutz" : "\(HyseConfiguration.serverURL)/en/privacy")!)
                    Toggle(language.isGerman ? "Ich bin mindestens 16 Jahre alt." : "I am at least 16 years old.", isOn: $isAtLeastSixteen)
                    if userSettings.profileAgeYears < 16 {
                        Text(language.isGerman ? "Das hinterlegte Profilalter liegt unter 16. Kontofunktionen sind dafür nicht verfügbar." : "The saved profile age is under 16. Account features are unavailable for this age.")
                            .font(.footnote).foregroundStyle(HyseColor.danger)
                    }
                    Toggle(language.isGerman
                           ? "Ich willige ausdrücklich in die Verarbeitung meiner Gesundheitsdaten zur Kontosynchronisierung ein."
                           : "I explicitly consent to the processing of my health data for account synchronisation.", isOn: $acceptsHealthSync)
                    Button(language.isGerman ? "Konto aktivieren" : "Activate account") {
                        accountData.grantHealthSyncConsent(language: language.language)
                    }
                    .buttonStyle(HysePrimaryButtonStyle())
                    .disabled(!isAtLeastSixteen || !acceptsHealthSync || userSettings.profileAgeYears < 16)
                    Button(language.text("login.continue_without_account")) { authManager.logout() }
                        .buttonStyle(HyseSecondaryButtonStyle())
                    Text(language.isGerman
                         ? "Du kannst die Einwilligung jederzeit durch Löschen deines Kontos widerrufen. Bereits erfolgte Verarbeitungen bleiben rechtmäßig."
                         : "You can withdraw consent at any time by deleting your account. Processing before withdrawal remains lawful.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(HyseSpacing.page)
            }
            .background(HyseBackdrop())
        }
    }
}

struct TrackingInterestOnboardingView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var accountData: AccountDataStore
    @ObservedObject var settings: UserSettingsStore
    let complete: () -> Void
    @State private var selection: TrackingInterest

    init(settings: UserSettingsStore, complete: @escaping () -> Void) {
        self.settings = settings
        self.complete = complete
        _selection = State(initialValue: settings.trackingInterest)
    }

    var body: some View {
        ZStack {
            HyseBackdrop()
            ScrollView {
                VStack(spacing: HyseSpacing.large) {
                    HStack {
                        Text(language.text("tracking_interest.eyebrow").uppercased())
                            .font(.caption.weight(.heavy))
                            .tracking(1.2)
                            .foregroundStyle(HyseColor.accent)
                        Spacer()
                        Text("1 / 1")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    HyseCard(accent: HyseColor.accent) {
                        VStack(spacing: HyseSpacing.medium) {
                            ZStack {
                                Circle()
                                    .fill(HyseColor.accent.opacity(0.16))
                                    .frame(width: 82, height: 82)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundStyle(HyseColor.accent)
                            }
                            Text(language.text("tracking_interest.title"))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                            Text(language.text("tracking_interest.subtitle"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        Text(language.text("tracking_interest.choose_label"))
                            .font(.headline)
                            .padding(.horizontal, 2)
                        ForEach(TrackingInterest.allCases) { value in
                            interestOption(value)
                        }
                    }

                    Button(language.text("onboarding.next")) {
                        guard accountData.activeAccountID == nil || !accountData.hasEstablishedAccountProfile else {
                            complete()
                            return
                        }
                        settings.trackingInterest = selection
                        accountData.syncSettings(settings, language: language)
                        complete()
                    }
                    .buttonStyle(HysePrimaryButtonStyle())
                    .overlay(alignment: .trailing) {
                        Image(systemName: "arrow.right")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.trailing, HyseSpacing.large)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity)

                    Text(language.text("tracking_interest.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(HyseSpacing.page)
                .padding(.top, HyseSpacing.medium)
            }
        }
    }

    private func interestOption(_ value: TrackingInterest) -> some View {
        Button {
            withAnimation(HyseMotion.quick) { selection = value }
        } label: {
            HyseCard(accent: selection == value ? HyseColor.accent : nil) {
                HStack(spacing: HyseSpacing.medium) {
                    HyseIconBadge(icon: value.iconName, color: selection == value ? HyseColor.accent : .secondary, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text(value.localizationKey))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(language.text(value.descriptionKey))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selection == value ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(selection == value ? HyseColor.accent : .secondary)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}

struct HealthConnectionOnboardingView: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var healthKitManager: HealthKitManager
    let complete: () -> Void
    @State private var isConnecting = false

    var body: some View {
        ZStack {
            HyseBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: HyseSpacing.xLarge) {
                    HyseCard(accent: HyseColor.accent) {
                        VStack(alignment: .leading, spacing: HyseSpacing.large) {
                            HyseIconBadge(icon: "heart.text.square.fill", size: 58)
                            Text(language.text("health_onboarding.title"))
                                .font(.largeTitle.bold())
                            Text(language.text("health_onboarding.introduction"))
                                .font(.body)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                                benefit("bolt.heart.fill", "health_onboarding.activity")
                                benefit("fork.knife", "health_onboarding.nutrition")
                                benefit("scalemass.fill", "health_onboarding.weight")
                            }
                        }
                    }

                    if let error = healthKitManager.authorizationError {
                        HyseStatusBanner(title: nil, message: error, style: .warning)
                    }

                    Button {
                        guard !isConnecting else { return }
                        guard healthKitManager.isHealthDataAvailable else {
                            complete()
                            return
                        }
                        isConnecting = true
                        healthKitManager.requestAuthorization { _ in
                            isConnecting = false
                            complete()
                        }
                    } label: {
                        HStack {
                            if isConnecting { ProgressView().tint(.white) }
                            Text(language.text("health_onboarding.continue"))
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(HysePrimaryButtonStyle())
                    .disabled(isConnecting)

                    Text(language.text("health_onboarding.privacy_note"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(HyseSpacing.page)
            }
        }
    }

    private func benefit(_ icon: String, _ key: String) -> some View {
        Label(language.text(key), systemImage: icon)
            .font(.subheadline.weight(.medium))
    }
}

struct ProfileSetupOnboardingView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var accountData: AccountDataStore
    @ObservedObject var settings: UserSettingsStore
    @ObservedObject var trainingStore: TrainingStore
    let allowsExistingProfileUpdate: Bool
    let complete: () -> Void

    init(settings: UserSettingsStore, trainingStore: TrainingStore, allowsExistingProfileUpdate: Bool = false, complete: @escaping () -> Void) {
        self.settings = settings
        self.trainingStore = trainingStore
        self.allowsExistingProfileUpdate = allowsExistingProfileUpdate
        self.complete = complete
        _goal = State(initialValue: settings.onboardingGoal)
        _sex = State(initialValue: settings.onboardingSex)
        _activityLevel = State(initialValue: settings.nutritionActivityLevel)
        _foodUnit = State(initialValue: settings.defaultFoodUnit)
        _liquidUnit = State(initialValue: settings.defaultLiquidUnit)
        _trainingWeightUnit = State(initialValue: settings.trainingWeightUnit)
        _distanceUnit = State(initialValue: settings.trainingDistanceUnit)
        _ageText = State(initialValue: String(settings.profileAgeYears))
        _heightText = State(initialValue: settings.profileHeightCentimeters.formatted(.number.precision(.fractionLength(0...1))))
        _weightText = State(initialValue: settings.trainingWeightUnit.display(settings.profileWeightKilograms).formatted(.number.precision(.fractionLength(0...1))))
    }

    @State private var step = 0
    @State private var goal: OnboardingGoal = .maintainWeight
    @State private var sex: OnboardingSex = .unspecified
    @State private var activityLevel: NutritionActivityLevel = .everyday
    @State private var foodUnit: FoodUnit = .gram
    @State private var liquidUnit: FoodUnit = .milliliter
    @State private var trainingWeightUnit: TrainingWeightUnit = .kilograms
    @State private var distanceUnit: TrainingDistanceUnit = .kilometers
    @State private var ageText = "30"
    @State private var heightText = "170"
    @State private var weightText = "70"
    @State private var validationMessage: String?

    private let stepCount = 4

    var body: some View {
        ZStack {
            HyseBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: HyseSpacing.large) {
                    HyseCard(accent: HyseColor.accent) {
                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            HStack {
                                HyseIconBadge(icon: "sparkles", size: 52)
                                Spacer()
                                Text(language.text("onboarding.profile.step", [step + 1, stepCount]))
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(HyseColor.accent)
                            }
                            Text(language.text("onboarding.profile.title"))
                                .font(.largeTitle.bold())
                            Text(language.text("onboarding.profile.subtitle"))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            ProgressView(value: Double(step + 1), total: Double(stepCount))
                                .tint(HyseColor.accent)
                        }
                    }

                    pageContent

                    if let validationMessage {
                        HyseStatusBanner(title: nil, message: validationMessage, style: .warning)
                    }

                    HStack(spacing: HyseSpacing.medium) {
                        if step > 0 {
                            Button(language.text("ui.back")) { step -= 1; validationMessage = nil }
                                .buttonStyle(HyseSecondaryButtonStyle())
                        }
                        Button(step == stepCount - 1 ? language.text("onboarding.profile.finish") : language.text("onboarding.next")) {
                            advanceOrFinish()
                        }
                        .buttonStyle(HysePrimaryButtonStyle())
                        .frame(maxWidth: .infinity)
                    }

                    Button(language.text("onboarding.profile.skip")) { complete() }
                        .buttonStyle(HyseSecondaryButtonStyle())
                        .frame(maxWidth: .infinity)
                        .disabled(settings.profileAgeYears < 16)
                }
                .padding(HyseSpacing.page)
            }
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch step {
        case 0:
            HyseCard {
                VStack(alignment: .leading, spacing: HyseSpacing.large) {
                    Text(language.text("onboarding.profile.goal_title")).font(.headline)
                    VStack(spacing: HyseSpacing.small) {
                        ForEach(OnboardingGoal.allCases) { value in
                            goalOption(value)
                        }
                    }
                    Text(language.text("onboarding.profile.sex_title")).font(.headline)
                    Picker(language.text("onboarding.profile.sex_title"), selection: $sex) {
                        ForEach(OnboardingSex.allCases) { value in
                            Text(language.text(value.localizationKey)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        case 1:
            HyseCard {
                VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                    Text(language.text("onboarding.profile.units_title")).font(.headline)
                    unitPicker("onboarding.profile.food_unit", selection: $foodUnit, values: FoodUnit.weightUnits)
                    unitPicker("onboarding.profile.liquid_unit", selection: $liquidUnit, values: FoodUnit.volumeUnits)
                    Picker(language.text("onboarding.profile.training_weight_unit"), selection: $trainingWeightUnit) {
                        ForEach(TrainingWeightUnit.allCases) { value in
                            Text(language.text(value.localizationKey)).tag(value)
                        }
                    }
                    Picker(language.text("onboarding.profile.distance_unit"), selection: $distanceUnit) {
                        ForEach(TrainingDistanceUnit.allCases) { value in
                            Text(language.text(value.localizationKey)).tag(value)
                        }
                    }
                }
            }
        case 2:
            HyseCard {
                VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                    Text(language.text("onboarding.profile.body_title")).font(.headline)
                    Text(language.text("onboarding.profile.body_explanation"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    profileField("onboarding.profile.age", text: $ageText, unit: language.text("onboarding.profile.years"), keyboard: .numberPad)
                    profileField("onboarding.profile.height", text: $heightText, unit: "cm", keyboard: .decimalPad)
                    profileField("onboarding.profile.weight", text: $weightText, unit: trainingWeightUnit.rawValue, keyboard: .decimalPad)
                }
            }
        default:
            HyseCard {
                VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                    Text(language.text("onboarding.profile.activity_title")).font(.headline)
                    Picker(language.text("onboarding.profile.activity_title"), selection: $activityLevel) {
                        ForEach(NutritionActivityLevel.allCases) { value in
                            Text(language.text(value.localizationKey)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(language.text(activityLevel.descriptionKey))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let previewValues {
                        VStack(alignment: .leading, spacing: HyseSpacing.small) {
                            Text(language.text("onboarding.profile.preview_title")).font(.headline)
                            LabeledContent(language.text("onboarding.profile.preview_calories"), value: "\(Int(previewValues.calories)) kcal")
                            LabeledContent(language.text("onboarding.profile.preview_water"), value: previewWaterText(previewValues.waterMilliliters))
                            LabeledContent(
                                language.text("onboarding.profile.preview_macros"),
                                value: "\(previewValues.carbsPercentage)% / \(previewValues.proteinPercentage)% / \(previewValues.fatPercentage)%"
                            )
                            Text(language.text("onboarding.profile.preview_note"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(HyseSpacing.medium)
                        .hyseGlassSurface(radius: HyseRadius.control, tint: HyseColor.accent)
                    }
                }
            }
        }
    }

    private var previewValues: OnboardingStartValues? {
        guard let inputs else { return nil }
        return OnboardingCalculator.calculate(
            goal: goal,
            sex: sex,
            ageYears: inputs.age,
            heightCentimeters: inputs.height,
            weightKilograms: inputs.weight,
            activityLevel: activityLevel
        )
    }

    private var inputs: (age: Int, height: Double, weight: Double)? {
        guard let age = Int(ageText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let height = localizedDouble(heightText),
              let displayedWeight = localizedDouble(weightText),
              (16...100).contains(age),
              (120...230).contains(height) else { return nil }
        let weight = trainingWeightUnit.kilograms(displayedWeight)
        guard weight.isFinite, (25...300).contains(weight) else { return nil }
        return (age, height, weight)
    }

    private func localizedDouble(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private func previewWaterText(_ milliliters: Double) -> String {
        let value = FoodUnit.milliliter.converted(milliliters, to: liquidUnit) ?? milliliters
        if liquidUnit == .fluidOunce {
            return "\(value.formatted(.number.precision(.fractionLength(1)))) fl oz"
        }
        return "\(Int(value.rounded())) ml"
    }

    private func advanceOrFinish() {
        // The account restore may finish while this page is still visible.
        // Never replace restored goals with the questionnaire's defaults.
        guard allowsExistingProfileUpdate || accountData.activeAccountID == nil || !accountData.hasEstablishedAccountProfile else {
            complete()
            return
        }
        validationMessage = nil
        if step < stepCount - 1 {
            step += 1
            return
        }
        guard let inputs else {
            validationMessage = language.text("onboarding.profile.validation")
            step = 2
            return
        }
        _ = settings.applyOnboarding(
            goal: goal,
            sex: sex,
            ageYears: inputs.age,
            heightCentimeters: inputs.height,
            weightKilograms: inputs.weight,
            activityLevel: activityLevel,
            foodUnit: foodUnit,
            liquidUnit: liquidUnit,
            trainingWeightUnit: trainingWeightUnit,
            distanceUnit: distanceUnit
        )
        if trainingStore.bodyMeasurements.isEmpty {
            _ = trainingStore.addBodyWeight(kilograms: inputs.weight, date: Date())
        }
        accountData.syncSettings(settings, language: language)
        complete()
    }

    private func unitPicker(_ key: String, selection: Binding<FoodUnit>, values: [FoodUnit]) -> some View {
        Picker(language.text(key), selection: selection) {
            ForEach(values, id: \.self) { value in
                Text(language.text(value.localizationKey)).tag(value)
            }
        }
    }

    private func goalOption(_ value: OnboardingGoal) -> some View {
        let isSelected = goal == value
        return Button {
            withAnimation(HyseMotion.quick) { goal = value }
        } label: {
            HStack(spacing: HyseSpacing.medium) {
                Image(systemName: value.iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : HyseColor.accent)
                    .frame(width: 38, height: 38)
                    .background(
                        isSelected ? HyseColor.accent : HyseColor.accent.opacity(0.11),
                        in: RoundedRectangle(cornerRadius: HyseRadius.small, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                    Text(language.text(value.localizationKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(language.text(value.descriptionKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: HyseSpacing.small)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? HyseColor.accent : Color.secondary.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, HyseSpacing.medium)
            .padding(.vertical, HyseSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? HyseColor.accent.opacity(0.10) : HyseColor.surface.opacity(0.72),
                in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous)
                    .stroke(isSelected ? HyseColor.accent : HyseColor.border, lineWidth: isSelected ? 1.5 : 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func profileField(_ key: String, text: Binding<String>, unit: String, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(language.text(key))
            Spacer()
            TextField(language.text(key), text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

enum HyseTourStep: Int, CaseIterable, Identifiable {
    case nutrition, meals, health, trainingFriends, trainingWorkouts, trainingProfile, trainingStart, settings

    var id: Int { rawValue }
    var icon: String {
        switch self {
        case .nutrition: "gauge.with.dots.needle.67percent"
        case .meals: "fork.knife"
        case .health: "heart.text.square.fill"
        case .trainingFriends: "person.2.fill"
        case .trainingWorkouts: "figure.strengthtraining.traditional"
        case .trainingProfile: "chart.xyaxis.line"
        case .trainingStart: "play.fill"
        case .settings: "gearshape.fill"
        }
    }
    var titleKey: String {
        switch self {
        case .nutrition: "onboarding.home.title"
        case .meals: "onboarding.meals.title"
        case .health: "onboarding.health.title"
        case .trainingFriends: "onboarding.training_friends.title"
        case .trainingWorkouts: "onboarding.training_workouts.title"
        case .trainingProfile: "onboarding.training_profile.title"
        case .trainingStart: "onboarding.training_start.title"
        case .settings: "onboarding.settings.title"
        }
    }
    var bodyKey: String {
        switch self {
        case .nutrition: "onboarding.home.body"
        case .meals: "onboarding.meals.body"
        case .health: "onboarding.health.body"
        case .trainingFriends: "onboarding.training_friends.body"
        case .trainingWorkouts: "onboarding.training_workouts.body"
        case .trainingProfile: "onboarding.training_profile.body"
        case .trainingStart: "onboarding.training_start.body"
        case .settings: "onboarding.settings.body"
        }
    }
}

struct HyseTourTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [HyseTourStep: Anchor<CGRect>] = [:]

    static func reduce(value: inout [HyseTourStep: Anchor<CGRect>], nextValue: () -> [HyseTourStep: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    func hyseTourTarget(_ step: HyseTourStep) -> some View {
        anchorPreference(key: HyseTourTargetPreferenceKey.self, value: .bounds) { [step: $0] }
    }
}

struct HyseGuidedTourOverlay: View {
    @EnvironmentObject private var language: LanguageStore
    let step: HyseTourStep
    let goBack: () -> Void
    let goForward: () -> Void
    let skip: () -> Void
    var resolvedTarget: CGRect?

    var body: some View {
        GeometryReader { proxy in
            let rawTarget = resolvedTarget ?? fallbackTargetRect(in: proxy)
            let target = fittedTarget(rawTarget, in: proxy.size)
            let bubbleY = tooltipY(for: target, in: proxy.size)
            let bubbleAboveTarget = bubbleY < target.midY

            ZStack {
                TourDimmer(target: target, circular: usesCircle)
                    .ignoresSafeArea()

                targetOutline(target)

                TourArrow(
                    from: CGPoint(x: proxy.size.width / 2, y: bubbleY + (bubbleAboveTarget ? 78 : -78)),
                    to: CGPoint(x: target.midX, y: bubbleAboveTarget ? target.minY - 8 : target.maxY + 8)
                )
                .stroke(HyseColor.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)

                targetAdvanceControl(target)

                tourCard
                    .frame(maxWidth: min(proxy.size.width - 32, 430))
                    .position(x: proxy.size.width / 2, y: bubbleY)
            }
        }
        .transition(.opacity)
        .zIndex(1000)
    }

    private var tourCard: some View {
        HyseCard(accent: HyseColor.accent) {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HStack(spacing: HyseSpacing.medium) {
                    HyseIconBadge(icon: step.icon, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%02d / %02d", step.rawValue + 1, HyseTourStep.allCases.count))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(HyseColor.accent)
                        Text(language.text(step.titleKey))
                            .font(.headline)
                    }
                    Spacer(minLength: 0)
                    Button(language.text("onboarding.skip"), action: skip)
                        .font(.caption.weight(.semibold))
                }
                Text(language.text(step.bodyKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.text(step == .trainingStart ? "onboarding.training_start.hint" : "onboarding.tap_highlight"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: HyseSpacing.medium) {
                    if step.rawValue > 0 {
                        Button(action: goBack) {
                            Label(language.text("ui.back"), systemImage: "chevron.left")
                        }
                        .buttonStyle(HyseSecondaryButtonStyle())
                    }
                    Button(action: goForward) {
                        Text(language.text(step == HyseTourStep.allCases.last ? "onboarding.finish" : "onboarding.next"))
                    }
                    .buttonStyle(HysePrimaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder private func targetOutline(_ rect: CGRect) -> some View {
        if usesCircle {
            Circle()
                .stroke(HyseColor.accent, lineWidth: 4)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HyseColor.accent, lineWidth: 4)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private func targetAdvanceControl(_ rect: CGRect) -> some View {
        if usesCircle {
            Button(action: goForward) {
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .position(x: rect.midX, y: rect.midY)
            .accessibilityLabel(language.text("onboarding.next"))
        } else {
            Button(action: goForward) {
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .position(x: rect.midX, y: rect.midY)
            .accessibilityLabel(language.text("onboarding.next"))
        }
    }

    private var usesCircle: Bool { false }

    private func fallbackTargetRect(in proxy: GeometryProxy) -> CGRect {
        let size = proxy.size
        let safeTop = proxy.safeAreaInsets.top
        // System tab-item controls sit roughly half a compact tab-bar height
        // above the bottom safe area. The full-screen overlay prevents this
        // rect from being clipped at the former content boundary.
        let tabY = size.height - max(proxy.safeAreaInsets.bottom + 28, 42)
        switch step {
        case .nutrition:
            return CGRect(x: 14, y: safeTop + 82, width: size.width - 28, height: min(285, size.height * 0.34))
        case .meals:
            return CGRect(x: 14, y: size.height * 0.43, width: size.width - 28, height: min(210, size.height * 0.26))
        case .health:
            return CGRect(x: 14, y: safeTop + 150, width: size.width - 28, height: min(340, size.height * 0.40))
        case .trainingFriends:
            return CGRect(x: 16, y: size.height - 174, width: (size.width - 44) / 3, height: 76)
        case .trainingWorkouts:
            return CGRect(x: 22 + (size.width - 44) / 3, y: size.height - 174, width: (size.width - 44) / 3, height: 76)
        case .trainingProfile:
            return CGRect(x: 28 + 2 * (size.width - 44) / 3, y: size.height - 174, width: (size.width - 44) / 3, height: 76)
        case .trainingStart:
            return CGRect(x: 16, y: safeTop + 128, width: size.width - 32, height: 92)
        case .settings:
            return CGRect(x: size.width * 0.80, y: tabY - 34, width: size.width * 0.19, height: 68)
        }
    }

    private func fittedTarget(_ rect: CGRect, in size: CGSize) -> CGRect {
        let horizontalMargin: CGFloat = 10
        let topMargin: CGFloat = 8
        let bottomMargin: CGFloat = 8
        let minX = max(horizontalMargin, rect.minX)
        let minY = max(topMargin, rect.minY)
        let maxX = min(size.width - horizontalMargin, rect.maxX)
        let maxY = min(size.height - bottomMargin, rect.maxY)
        guard maxX > minX, maxY > minY else { return fallbackTargetRect(size: size) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func fallbackTargetRect(size: CGSize) -> CGRect {
        CGRect(x: 16, y: max(90, size.height * 0.28), width: max(44, size.width - 32), height: 100)
    }

    private func tooltipY(for target: CGRect, in size: CGSize) -> CGFloat {
        if target.midY > size.height * 0.58 { return max(165, target.minY - 150) }
        return min(size.height - 180, target.maxY + 155)
    }
}

private struct TourDimmer: View {
    let target: CGRect
    let circular: Bool

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: proxy.size))
                if circular {
                    path.addEllipse(in: target.insetBy(dx: -5, dy: -5))
                } else {
                    path.addRoundedRect(in: target.insetBy(dx: -5, dy: -5), cornerSize: CGSize(width: 25, height: 25))
                }
            }
            .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
        }
    }
}

private struct TourArrow: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        let control = CGPoint(x: from.x + (to.x - from.x) * 0.25, y: from.y + (to.y - from.y) * 0.62)
        path.addQuadCurve(to: to, control: control)
        let angle = atan2(to.y - control.y, to.x - control.x)
        let length: CGFloat = 13
        path.move(to: to)
        path.addLine(to: CGPoint(x: to.x - length * cos(angle - .pi / 6), y: to.y - length * sin(angle - .pi / 6)))
        path.move(to: to)
        path.addLine(to: CGPoint(x: to.x - length * cos(angle + .pi / 6), y: to.y - length * sin(angle + .pi / 6)))
        return path
    }
}
