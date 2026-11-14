#!/usr/bin/env ruby

content = File.read(File.expand_path("../CalorieTrackerApp/ContentView.swift", __dir__))
account = File.read(File.expand_path("../CalorieTrackerApp/AccountDataStore.swift", __dir__))
onboarding = File.read(File.expand_path("../CalorieTrackerApp/LegalAndOnboardingViews.swift", __dir__))

account_gate = content[/private var accountContent: some View \{[\s\S]*?(?=private var presentedContent: some View)/]
abort "account settings are not restored before onboarding is shown" unless account_gate&.match?(/isHydratingAccountSettings[\s\S]*trackingInterestOnboardingStatus/)
abort "restored accounts still see the tracking-interest prompt" unless account_gate&.include?('trackingInterestOnboardingStatus != "completed" && !hasRestoredSignedInProfile')
abort "restored accounts still see the calorie/profile questionnaire" unless account_gate&.include?('profileSetupOnboardingStatus != "completed" && !hasRestoredSignedInProfile')
abort "a failed restore can expose the questionnaire" unless account_gate&.match?(/accountSettingsLoadFailed[\s\S]*refreshAccountState[\s\S]*profileSetupOnboardingStatus/)
abort "cached account settings are not recognized" unless account.match?(/if let cachedSettings = loadSettingsSnapshot[\s\S]*hasRestoredAccountSettings = true/)
abort "server account settings are not recognized" unless account.match?(/if remote\.settings != nil \{ hasRestoredAccountSettings = true \}/)
abort "new accounts upload defaults before setup" unless account.include?('settings: hasRestoredAccountSettings')
abort "an already visible questionnaire can replace restored goals" unless onboarding.match?(/private func advanceOrFinish\(\)[\s\S]*?hasEstablishedAccountProfile[\s\S]*?settings\.applyOnboarding/)
abort "an already visible tracking prompt can replace the saved choice" unless onboarding.match?(/Button\(language\.text\("onboarding\.next"\)\) \{[\s\S]*?hasEstablishedAccountProfile[\s\S]*?settings\.trackingInterest = selection/)

puts "Restored account settings bypass profile onboarding without replacing saved goals."
