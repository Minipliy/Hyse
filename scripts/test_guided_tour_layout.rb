#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
content = File.read(File.join(root, "CalorieTrackerApp", "ContentView.swift"))
onboarding = File.read(File.join(root, "CalorieTrackerApp", "LegalAndOnboardingViews.swift"))
training = TrainingViewSources.read
settings = File.read(File.join(root, "CalorieTrackerApp", "SettingsView.swift"))

checks = {
  "tour targets use anchors" => onboarding.include?("HyseTourTargetPreferenceKey") && onboarding.include?("anchorPreference"),
  "overlay resolves actual target frames" => content.include?("overlayPreferenceValue(HyseTourTargetPreferenceKey.self)") && content.include?("proxy[$0]"),
  "add-entry highlight anchors the real hit target" => content.include?(".hyseTourTarget(.addEntry)"),
  "add-entry highlight uses the actual system tab item" => onboarding.include?("addEntryTabItem(in: tabBar)") && onboarding.include?("globalCenter.x - overlayFrame.minX") && onboarding.include?("globalCenter.y - overlayFrame.minY"),
  "nutrition and meal targets are attached" => content.include?(".hyseTourTarget(.nutrition)") && content.include?(".hyseTourTarget(.meals)"),
  "training navigation targets are attached" => training.include?(".hyseTourTarget(tourStep(for: section))") && training.include?(".hyseTourTarget(.trainingStart)"),
  "health target is attached" => training.include?(".hyseTourTarget(.health)"),
  "settings target is attached" => settings.include?(".hyseTourTarget(.settings)"),
  "settings tutorial resets nested navigation" => content.include?("settingsNavigationResetID = UUID()") && content.include?(".id(settingsNavigationResetID)"),
  "tab routing is outside broad animation" => !content.match?(/withAnimation\(HyseMotion\.standard\)\s*\{\s*tourStep =/m)
}

failed = checks.reject { |_, passed| passed }
abort("Failed: #{failed.keys.join(', ')}") unless failed.empty?
puts "Guided-tour anchor and performance regression tests passed."
