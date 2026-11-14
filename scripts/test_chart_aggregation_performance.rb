#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
exercise = File.read(File.join(root, "CalorieTrackerApp", "TrainingInsightsViews.swift"))
health = TrainingViewSources.read
german = File.read(File.join(root, "CalorieTrackerApp", "de.lproj", "Localizable.strings"))
english = File.read(File.join(root, "CalorieTrackerApp", "en.lproj", "Localizable.strings"))

checks = {
  "exercise chart uses cached points" => exercise.include?("@State private var chartPoints") && exercise.include?("return chartPoints.min"),
  "exercise chart aggregates weeks" => exercise.include?("range == .allTime ? .month : .weekOfYear"),
  "weight chart uses cached points" => health.include?("@State private var weightChartPoints") && health.include?("return weightChartPoints.min"),
  "weight chart uses monthly annual averages" => health.include?("range == .oneYear || range == .allTime") && health.include?("? .month") && health.include?(": .weekOfYear"),
  "weight chart uses a five-kilogram visible margin" => health.include?("minimum - 5") && health.include?("maximum + 5") && health.include?(".chartYScale(domain: weightChartDomain)"),
  "month view keeps individual values" => exercise.include?("guard range != .oneMonth") && health.include?("guard range != .oneMonth"),
  "aggregation is explained" => german.include?('"chart.aggregation.weekly"') && english.include?('"chart.aggregation.weekly"')
}

failed = checks.reject { |_, passed| passed }
abort("Failed: #{failed.keys.join(', ')}") unless failed.empty?
puts "Chart aggregation and selection-performance regression tests passed."
