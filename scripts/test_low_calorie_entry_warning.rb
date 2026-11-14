#!/usr/bin/env ruby

source = File.read(File.expand_path("../CalorieTrackerApp/AddEntryView.swift", __dir__))
settings_source = File.read(File.expand_path("../CalorieTrackerApp/SettingsView.swift", __dir__))
store_source = File.read(File.expand_path("../CalorieTrackerApp/UserSettingsStore.swift", __dir__))
german = File.read(File.expand_path("../CalorieTrackerApp/de.lproj/Localizable.strings", __dir__))
english = File.read(File.expand_path("../CalorieTrackerApp/en.lproj/Localizable.strings", __dir__))

checks = {
  "warning appears when food entry opens" => source.include?(".onAppear { showLowCalorieWarningIfNeeded() }"),
  "warning only applies to today's food logging" => source.include?("Calendar.current.isDateInToday(selectedEntryDate)"),
  "food selection-only sheets do not warn" => source.include?("guard foodSelectionHandler == nil"),
  "remaining calories use today's consumed calories" => source.include?("availableCalories - calorieStore.totalKcal(for: selectedEntryDate)"),
  "configured warning threshold is respected" => source.include?("remaining <= userSettings.lowCalorieEntryWarningThreshold"),
  "warning threshold defaults to 600 kcal" => store_source.include?("storedWarningThreshold ?? 600"),
  "warning respects the user preference" => source.include?("guard userSettings.lowCalorieEntryWarningEnabled"),
  "warning preference is shown in settings" => settings_source.include?("$settingsStore.lowCalorieEntryWarningEnabled"),
  "warning threshold is shown in settings" => settings_source.include?("$lowCalorieEntryWarningThresholdText"),
  "warning preference is persisted" => store_source.include?("lowCalorieEntryWarningEnabled_v1"),
  "warning is non-blocking" => source.include?("food_tracking.low_calorie_warning_acknowledge"),
  "German preference copy exists" => german.include?("food_tracking.low_calorie_warning_enabled"),
  "English preference copy exists" => english.include?("food_tracking.low_calorie_warning_enabled"),
  "German warning copy exists" => german.include?("food_tracking.low_calorie_warning_message"),
  "English warning copy exists" => english.include?("food_tracking.low_calorie_warning_message")
}

failures = checks.reject { |_, passed| passed }.keys
abort("Low calorie entry warning checks failed: #{failures.join(', ')}") unless failures.empty?

puts "Low calorie entry warning checks passed."
