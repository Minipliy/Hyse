#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
content = File.read(File.join(root, "CalorieTrackerApp", "ContentView.swift"))
design = File.read(File.join(root, "CalorieTrackerApp", "HyseDesignSystem.swift"))
detail = File.read(File.join(root, "CalorieTrackerApp", "CategoryDetailView.swift"))

checks = {
  "decorative top-right dash removed" => !design.include?(".overlay(alignment: .topTrailing)"),
  "meal card opens its overview" => content.include?("NavigationLink {") && content.include?("categoryDetailView(for: category)"),
  "whole meal card is tappable" => content.include?(".frame(maxWidth: .infinity, alignment: .leading)") && content.scan(".contentShape(Rectangle())").length >= 2,
  "meal overview owns the add action" => detail.include?("Button { showingAddEntry = true }") && detail.include?("category_detail.add_food_1"),
  "add-entry sheet uses selected meal" => content.include?("addEntryCategory ?? categoryStore.categories.first"),
  "food library removed from home header" => !content.include?("showingFoodHub") && !content.include?("homeIconAction(\"books.vertical.fill\""),
  "daily goal interpolates its resolved number" => content.include?('Text("\\(t("content.daily_goal")): \\(Int(availableCalories)) kcal")') && content.include?('Text("\\(t("content.daily_goal")) \\(Int(availableCalories)) kcal")'),
  "literal calorie expression absent" => !content.include?('daily_goal")) (Int(calorieGoal)) kcal')
}

failed = checks.reject { |_, passed| passed }
abort("Failed: #{failed.keys.join(', ')}") unless failed.empty?
puts "Home meal-entry and visual-cleanup regression tests passed."
