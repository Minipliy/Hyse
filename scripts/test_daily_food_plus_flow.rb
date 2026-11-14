#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
add_entry = File.read(File.join(root, "CalorieTrackerApp", "AddEntryView.swift"))
daily_food = File.read(File.join(root, "CalorieTrackerApp", "DailyFoodAutomation.swift"))

checks = {
  "selection mode can remain in its current sheet" => add_entry.include?("dismissAfterFoodSelection: Bool = true"),
  "selection only dismisses when requested" => add_entry.include?("if dismissAfterFoodSelection { dismiss() }"),
  "daily food selection disables the intermediate dismissal" => daily_food.include?("dismissAfterFoodSelection: false"),
  "daily food editor replaces the search in one sheet" => daily_food.include?("if let selectedFoodForEditor") && daily_food.include?("} else {\n                AddEntryView("),
  "obsolete second editor sheet is removed" => !daily_food.include?("showingEditor")
}

failed = checks.reject { |_, passed| passed }
if failed.empty?
  puts "Daily food plus flow checks passed (#{checks.length})."
else
  failed.each_key { |name| warn "FAILED: #{name}" }
  exit 1
end
