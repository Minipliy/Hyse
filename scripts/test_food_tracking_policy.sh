#!/bin/sh
set -eu

test_binary="${TMPDIR:-/tmp}/hyse-food-tracking-policy-tests"
module_cache="${TMPDIR:-/tmp}/hyse-food-tracking-policy-module-cache"
xcrun swiftc \
  -module-cache-path "$module_cache" \
  Tests/FoodTrackingPolicyTests.swift \
  CalorieTrackerApp/FoodTrackingPolicy.swift \
  -o "$test_binary"
"$test_binary"
