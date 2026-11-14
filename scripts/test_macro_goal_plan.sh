#!/bin/sh
set -eu

test_binary="${TMPDIR:-/tmp}/hyse-macro-goal-tests"
module_cache="${TMPDIR:-/tmp}/hyse-swift-module-cache"
xcrun swiftc \
  -module-cache-path "$module_cache" \
  Tests/MacroGoalPlanTests.swift \
  CalorieTrackerApp/MacroGoalPlan.swift \
  -o "$test_binary"
"$test_binary"
