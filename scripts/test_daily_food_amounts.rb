#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
source = File.read(File.join(root, "CalorieTrackerApp", "DailyFoodAutomation.swift"))
editor = source[/private struct DailyFoodScheduleEditor: View.*\z/m] || ""

abort("daily food editor still offers portion mode") if editor.include?("usesPortion") || editor.include?("selectedPortionID")
abort("daily food editor does not inspect actual entry history") unless editor.include?("initialAmountText(for: food, entries: calorieStore.entries)")
abort("daily food editor does not choose the newest amount") unless editor.include?(".max { $0.date < $1.date }")
abort("solid daily foods are not normalized to grams") unless editor.include?("food.unit.isVolume ? .milliliter : .gram")
abort("saved daily entries still preserve portion metadata") unless source.include?("portionName: nil") && source.include?("portionID: nil") && source.include?("portionCount: nil")
abort("legacy portion schedules are not migrated") unless source.include?("containsLegacyPortions")

puts "daily food amount checks passed"
