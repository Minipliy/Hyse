#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
settings = File.read(File.join(root, "CalorieTrackerApp", "UserSettingsStore.swift"))
content = File.read(File.join(root, "CalorieTrackerApp", "ContentView.swift"))
widget = File.read(File.join(root, "CalorieWidget", "CalorieWidget.swift"))

def assert(condition, message)
  raise "FAILED: #{message}" unless condition
end

assert(settings.include?("func updateWidgetAvailableCalories(_ availableCalories: Double)"), "settings must expose only the resolved daily allowance to the widget")
assert(settings.include?("max(availableCalories, 0).rounded()"), "widget allowance must preserve the resolved value")
assert(!settings.include?("updateWidgetGoal(baseCalorieGoal)"), "fallback calorie goal must never overwrite the widget reference")
assert(content.scan("updateWidgetAvailableCalories(").length >= 2, "home must publish the allowance on appearance and whenever Health data changes")
assert(widget.include?("forKey: \"todayGoalKcal\""), "widget must read the shared resolved allowance")

puts "Widget available-calorie regression checks passed."
