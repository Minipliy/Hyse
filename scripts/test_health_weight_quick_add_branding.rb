#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
health = File.read(File.join(root, "CalorieTrackerApp", "HealthKitManager.swift"))
training = TrainingViewSources.read
entry = File.read(File.join(root, "CalorieTrackerApp", "AddEntryView.swift"))
content = File.read(File.join(root, "CalorieTrackerApp", "ContentView.swift"))
design = File.read(File.join(root, "CalorieTrackerApp", "HyseDesignSystem.swift"))

checks = {
  "Health body weight query" => health.include?("func refreshBodyWeights(force: Bool = false)") && health.include?("HKObjectQueryNoLimit"),
  "Health weight local cache" => health.include?("health_body_weights_v1") && health.include?("JSONEncoder().encode(measurements)"),
  "Health weight live observer" => health.include?("HKObserverQuery(sampleType: bodyMassType"),
  "Merged Health and Hyse graph" => training.include?("health.bodyWeights") && training.include?("trainingStore.bodyMeasurements"),
  "Food plus quick add avoids the intermediate editor" => entry.include?("Button { quickAddFood(food) }") && entry.include?("withTransaction(transaction)") && !entry.include?("DispatchQueue.main.async { save() }"),
  "Home omits removed Hyse logo" => !content.include?("HyseAppIconDark1024x1024") && !content.include?("HyseAppIconLight1024x1024"),
  "Light food pattern visible" => design.include?("colorScheme == .dark ? 0.075 : 0.080")
}

failed = checks.reject { |_, passed| passed }
abort("Failed: #{failed.keys.join(', ')}") unless failed.empty?
puts "Health weight, quick-add, branding, and light-background regression tests passed."
