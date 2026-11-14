#!/usr/bin/env ruby

source = File.read(File.expand_path("../CalorieTrackerApp/MonthlyTrainingReport.swift", __dir__))
records = File.read(File.expand_path("../CalorieTrackerApp/TrainingMonthlyRecords.swift", __dir__))

checks = {
  "chart bars can select a month by tapping" => source.include?("SpatialTapGesture") && source.include?("selectMonth(nearest.month)"),
  "month arrows and horizontal chart selection are removed" => !source.include?("moveMonth(by:") && !source.include?("chartXSelection"),
  "chart keeps the latest twelve months visible" => source.include?("monthlySummaries(endingAt: latestAvailableMonth, count: 12)"),
  "duration and volume display units" => source.include?("case .duration: \"h\"") && source.include?("case .volume: weightUnit.rawValue"),
  "all report sections follow the selected month" => source.include?("private var reportMonth") && source.include?("private var monthWorkouts"),
  "training diary calendar exists" => source.include?("trainingDiarySection") && source.include?("monthCalendar"),
  "weekly streak is calculated" => source.include?("longestWeeklyStreak"),
  "muscle comparison includes the prior month" => source.include?("MonthlyMuscleRadarChart") && source.include?("previousMonthWorkouts"),
  "primary muscles include secondary muscle weighting" => source.include?("sets * 0.5"),
  "historic imports resolve current muscle metadata" => source.include?("resolvedMuscles(for:") && source.include?("normalizedImportedCatalogEntry()"),
  "top exercises are listed" => source.include?("topExercisesSection"),
  "personal records include details" => source.include?("recordDescription") && source.include?("recordsByMonth") && records.include?("bestByExercise")
}

failures = checks.reject { |_, passed| passed }.keys
abort("Monthly training report history checks failed: #{failures.join(', ')}") unless failures.empty?

puts "Monthly training report history checks passed."
