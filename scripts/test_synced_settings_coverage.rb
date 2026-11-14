#!/usr/bin/env ruby

account_data = File.read(File.expand_path("../CalorieTrackerApp/AccountDataStore.swift", __dir__))
settings_view = File.read(File.expand_path("../CalorieTrackerApp/SettingsView.swift", __dir__))

fields = %w[
  automatically_start_apple_watch_workout
  monthly_training_report_notifications_enabled
  visible_nutrition_metric_ids
  selected_nutrition_profile_ids
]

fields.each do |field|
  abort "#{field} is missing from the account settings snapshot" unless account_data.scan(field).length >= 3
end

abort "account settings schema was not migrated" unless account_data.include?("var schemaVersion = 21") && account_data.include?("value.schemaVersion <= 21")
abort "appearance changes do not trigger account settings sync" unless settings_view.include?("settingsStore.appTheme.rawValue")

puts "All visible UserSettings preferences are included in account sync coverage."
