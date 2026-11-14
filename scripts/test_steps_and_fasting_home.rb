#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
health = File.read(File.join(root, "CalorieTrackerApp", "HealthKitManager.swift"))
content = File.read(File.join(root, "CalorieTrackerApp", "ContentView.swift"))
wellness = File.read(File.join(root, "CalorieTrackerApp", "WellnessTrackingViews.swift"))
settings = File.read(File.join(root, "CalorieTrackerApp", "SettingsView.swift"))
user_settings = File.read(File.join(root, "CalorieTrackerApp", "UserSettingsStore.swift"))
german = File.read(File.join(root, "CalorieTrackerApp", "de.lproj", "Localizable.strings"))
english = File.read(File.join(root, "CalorieTrackerApp", "en.lproj", "Localizable.strings"))

checks = {
  "Health step permission" => health.include?(".stepCount") && health.include?("stepCountType"),
  "Daily step query" => health.include?("func refreshSteps(for date: Date, force: Bool = false)") && health.include?("options: .cumulativeSum"),
  "Step cache" => health.include?("daily_health_steps_v1") && health.include?("dailySteps"),
  "Step observer" => health.include?("HKObserverQuery(sampleType: stepCountType"),
  "Persistent fasting state" => wellness.include?("fasting_tracker_state_v1") && wellness.include?("startedAt"),
  "Fasting controls" => wellness.include?("func start(at date:") && wellness.include?("func finish(at date:"),
  "Common fasting plans" => %w[12_12 14_10 16_8 18_6 20_4 omad].all? { |plan| wellness.include?(%Q{"fasting.plan.#{plan}"}) },
  "Custom fasting duration" => wellness.include?("showingCustomDuration") && wellness.include?("in: 1...48"),
  "Active fasting banner" => content.include?("ActiveFastingBanner(store: fastingStore)") && wellness.include?("struct ActiveFastingBanner"),
  "Home bottom trackers" => content.include?("wellnessHomeSection") && content.include?("StepCounterCard") && content.include?("FastingTrackerCard"),
  "Independent home visibility" => content.include?("isDashboardSectionVisible(.steps)") && content.include?("isDashboardSectionVisible(.fasting)"),
  "Home customization switches" => settings.include?("[DashboardSection.water, .steps, .fasting]") && user_settings.include?("case date, calories, training, water, nutrition, meals, steps, fasting"),
  "Steps and fasting default enabled" => user_settings.include?("wellnessDashboardVisibilityMigrated_v2") && user_settings.include?("visibleDashboardIDs.formUnion([DashboardSection.steps.rawValue, DashboardSection.fasting.rawValue])"),
  "Older cloud settings upgraded once" => File.read(File.join(root, "CalorieTrackerApp", "AccountDataStore.swift")).include?("wellnessDashboardCloudVisibilityMigrated_v2"),
  "German localization" => german.include?('"steps.title"') && german.include?('"fasting.start"'),
  "English localization" => english.include?('"steps.title"') && english.include?('"fasting.start"')
}

failed = checks.reject { |_, passed| passed }
abort("Failed: #{failed.keys.join(', ')}") unless failed.empty?
puts "Home step-counter and fasting-tracker regression tests passed."
