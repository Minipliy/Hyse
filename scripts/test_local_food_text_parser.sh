#!/bin/sh
set -eu

test_binary="${TMPDIR:-/tmp}/hyse-local-food-text-parser-tests"
module_cache="${TMPDIR:-/tmp}/hyse-local-food-text-parser-module-cache"
xcrun swiftc \
  -module-cache-path "$module_cache" \
  Tests/LocalFoodTextParserTests.swift \
  CalorieTrackerApp/LocalFoodTextParser.swift \
  -o "$test_binary"
"$test_binary"
