#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
unit = File.read(File.join(root, "CalorieTrackerApp", "FoodItem.swift"))
view = File.read(File.join(root, "CalorieTrackerApp", "CreateFoodView.swift"))

abort "imperial nutrition reference is not one ounce" unless unit.include?("case .ounce, .fluidOunce: 1")
abort "metric nutrition reference is not 100" unless unit.include?("case .gram, .milliliter: 100")
abort "entered values are not normalized for storage" unless view.include?("unit.per100NutrientValue(fromDisplayed:")
abort "draft values are not converted for display" unless view.include?("displayedNutrientValue(fromPer100:")
abort "unit changes do not convert existing entries" unless view.include?("convertNutrientInputs(from: oldUnit, to: newUnit)")
abort "reference amount is not shown to the user" unless view.include?("create_food.nutrition_values_reference")

puts "Create-food nutrition reference checks passed."
