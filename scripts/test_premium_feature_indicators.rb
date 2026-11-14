#!/usr/bin/env ruby
root = File.expand_path("..", __dir__)
access = File.read(File.join(root, "CalorieTrackerApp", "PremiumAccess.swift"))
store = File.read(File.join(root, "CalorieTrackerApp", "TrainingStore.swift"))
settings = File.read(File.join(root, "CalorieTrackerApp", "SettingsView.swift"))
project = File.read(File.join(root, "Hyse.xcodeproj", "project.pbxproj"))

abort("nutrition access is still gated") unless access.match?(/var hasNutrition: Bool \{ true \}/)
abort("training access is still gated") unless access.match?(/var hasTraining: Bool \{ true \}/)
abort("StoreKit is still linked") if project.include?("StoreKit.framework") || project.include?("com.apple.InAppPurchase")
abort("Premium purchase screen is still in settings") if settings.include?("premiumSettingsTile")
abort("routine creation is still capped") if store.match?(/guard premiumTrainingUnlocked \|\| routines\.count/)
abort("custom exercise creation is still capped") if store.match?(/guard premiumTrainingUnlocked \|\| customCount/)
puts "free-access checks passed"
