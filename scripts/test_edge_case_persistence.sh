#!/bin/sh
set -eu

test_binary="${TMPDIR:-/tmp}/hyse-edge-case-persistence-tests"
module_cache="${TMPDIR:-/tmp}/hyse-edge-case-persistence-module-cache"
xcrun swiftc \
  -module-cache-path "$module_cache" \
  Tests/EdgeCasePersistenceTests.swift \
  CalorieTrackerApp/Micronutrients.swift \
  CalorieTrackerApp/FoodMetadataModels.swift \
  CalorieTrackerApp/FoodItem.swift \
  CalorieTrackerApp/CalorieEntry.swift \
  CalorieTrackerApp/StrengthLogDirectory.swift \
  CalorieTrackerApp/UnilateralExerciseDirectory.swift \
  CalorieTrackerApp/TrainingModels.swift \
  -o "$test_binary"
"$test_binary"
