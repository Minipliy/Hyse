#!/usr/bin/env ruby

def assert(value, message)
  raise message unless value
end

legal = File.read("CalorieTrackerApp/LegalAndOnboardingViews.swift")
content = File.read("CalorieTrackerApp/ContentView.swift")
account = File.read("CalorieTrackerApp/AccountDataStore.swift")
settings = File.read("CalorieTrackerApp/SettingsView.swift")
hook = File.read("pb_hooks/consents_brands_portions.pb.js")
account_state_hook = File.read("pb_hooks/account_state.pb.js")

assert(legal.include?('legal_consent.accept_all'), "First launch must offer Accept all")
assert(legal.include?('legal_consent.use_essential_only'), "First launch must offer Essential only")
assert(legal.include?('legal_consent.choose_settings'), "First launch must offer custom consent choices")
assert(!legal.include?("cloudSyncAccepted = true"), "First launch must not preselect health-data sync")
assert(legal.include?("struct AccountHealthSyncConsentView"), "Health-data sync needs a separate consent screen")
assert(legal.include?("isAtLeastSixteen = false") && legal.include?("acceptsHealthSync = false"), "Age and health consent must start unchecked")
assert(account.include?("hyse_explicit_health_sync_consent_v2"), "Older implicit sync consent must not be migrated")
assert(account.include?("hasHealthSyncConsentForCurrentAccount"), "Consent must be scoped to the signed-in account")
assert(content.include?("!accountData.hasHealthSyncConsentForCurrentAccount"), "Account sync must be gated")
assert(hook.include?("cloud_sync: true"), "PocketBase consent receipts must support cloud sync")
assert(account_state_hook.include?('"terms-2026-09-4"') && account_state_hook.include?('"privacy-2026-09-3"'), "Account sync must accept current legal versions")

assert(legal.include?("struct HealthConnectionOnboardingView"), "First launch must include an Apple Health decision screen")
assert(legal.include?("healthKitManager.requestAuthorization"), "Health connection must use the system permission flow")
assert(legal.include?('health_onboarding.continue'), "The Health pre-permission action must say Continue")
assert(!legal.include?('health_onboarding.not_now') && !legal.include?('health_onboarding.connect'), "The Health pre-permission screen must not provide a skip or consent-labelled action")
assert(legal.include?('guard healthKitManager.isHealthDataAvailable else'), "Unsupported devices must be able to finish onboarding")
assert(content.include?('@AppStorage("health_onboarding_status_v1")'), "Health prompt choice must be remembered")
assert(content.include?('healthOnboardingStatus == "pending"'), "Health prompt must be part of first launch")
assert(content.include?('accountData.hasRequiredConsent ? "completed_existing_install" : "pending"'), "Existing installations must not receive a surprise first-launch prompt")
assert(account.include?('terms-2026-09-4') && account.include?('privacy-2026-09-3') && !account.include?('legacyAcceptedPairs'), "Material legal changes must require renewed acknowledgement")
assert(legal.include?('legal_consent.minimum_age') && legal.include?('guard isAtLeastSixteen else { return }'), "Guest use must require the 16+ declaration")
assert(legal.include?('(16...100).contains(age)'), "Profile onboarding must require age 16 or older")
assert(account.include?('legalConsentReceiptStorageKey') && account.include?('restoreAccountScopedConsentIfNeeded'), "Consent must survive guest/account scope switches without prompting again")

puts "First-launch consent and Apple Health regression tests passed."
