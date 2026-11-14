#!/usr/bin/env ruby

def assert(value, message)
  raise message unless value
end

settings = File.read("CalorieTrackerApp/SettingsView.swift")
german = File.read("CalorieTrackerApp/de.lproj/Localizable.strings")
english = File.read("CalorieTrackerApp/en.lproj/Localizable.strings")

assert(!settings.include?('NavigationLink(t("settings.edit_saved_foods"))'), "Saved foods must not be managed from settings")
assert(!settings.include?('NavigationLink(t("settings.manage_recipes"))'), "Recipes must not be managed from settings")
assert(!settings.include?("Toggle(metric.title"), "Nutrition overview visibility switches must be removed")
assert(settings.include?('scheduleAutomaticSave()'), "Settings drafts must save automatically")
assert(settings.include?('settingsSavedMessage = t("settings.saved")'), "Automatic saving must provide feedback without leaving the page")
assert(!settings.include?('private func saveSettings()'), "Settings must not require a manual save action")
assert(settings.include?("private let fixedSections"), "Home layout must explain its permanent sections")
assert(settings.include?("[DashboardSection.water, .steps, .fasting]"), "Hydration, steps, and fasting must remain configurable")
assert(!settings.include?(".onMove(perform: settingsStore.moveDashboardSections)"), "The ineffective home reorder control must be removed")

%w[
  settings.home_layout_explanation
  settings.home_essentials
  settings.home_essentials_explanation
  settings.optional_sections
  settings.optional_sections_explanation
].each do |key|
  assert(german.include?(%Q{"#{key}"}), "Missing German localization: #{key}")
  assert(english.include?(%Q{"#{key}"}), "Missing English localization: #{key}")
end

puts "Settings cleanup regression tests passed."
