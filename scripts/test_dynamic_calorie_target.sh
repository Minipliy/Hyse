#!/bin/sh
set -eu

test_binary="${TMPDIR:-/tmp}/hyse-calorie-target-tests"
module_cache="${TMPDIR:-/tmp}/hyse-swift-module-cache"
xcrun swiftc \
  -module-cache-path "$module_cache" \
  Tests/CalorieTargetCalculatorTests.swift \
  CalorieTrackerApp/MacroGoalPlan.swift \
  CalorieTrackerApp/CalorieTargetCalculator.swift \
  -o "$test_binary"
"$test_binary"
