#!/bin/sh
set -eu

ruby scripts/test_gemini_food_photo.rb
ruby scripts/test_gemini_food_text.rb

test_binary="${TMPDIR:-/tmp}/hyse-local-food-analyzer-tests"
module_cache="${TMPDIR:-/tmp}/hyse-local-food-analyzer-module-cache"
xcrun swiftc \
  -module-cache-path "$module_cache" \
  Tests/LocalFoodAnalyzerTests.swift \
  CalorieTrackerApp/Micronutrients.swift \
  CalorieTrackerApp/FoodMetadataModels.swift \
  CalorieTrackerApp/FoodItem.swift \
  CalorieTrackerApp/LocalFoodTextParser.swift \
  CalorieTrackerApp/LocalFoodAnalyzer.swift \
  -o "$test_binary"
"$test_binary"
