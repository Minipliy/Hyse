#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT
cat > "$temporary_dir/main.swift" <<'SWIFT'
import Foundation

let apple = MicronutrientProfile(valuesPer100g: ["vitaminC": 5, "iron": 0.2], source: .database, sourceName: "Open Food Facts")
precondition(apple.amount(.vitaminC, for: 250) == 12.5)
precondition(apple.amount(.iron, for: 50) == 0.1)
precondition(apple.amount(.calcium, for: 100) == nil)

let recipe = MicronutrientProfile.combined([(apple, 100), (apple, 100)], totalGrams: 200)
precondition(recipe?.valuesPer100g["vitaminC"] == 5)
let unknownRecipe = MicronutrientProfile.combined([(apple, 100), (nil, 100)], totalGrams: 200)
precondition(unknownRecipe == nil)

let encoded = try JSONEncoder().encode(apple)
let decoded = try JSONDecoder().decode(MicronutrientProfile.self, from: encoded)
let legacy = try JSONDecoder().decode(MicronutrientProfile.self, from: Data("{}".utf8))
precondition(decoded == apple)
precondition(legacy.isEmpty)

let revisedOFF = MicronutrientProfile(valuesPer100g: ["vitaminC": 8, "zinc": 0.4], source: .database, sourceName: "Open Food Facts")
let refreshed = apple.addingOpenFoodFacts(revisedOFF)
precondition(refreshed.valuesPer100g["vitaminC"] == 8)
precondition(refreshed.valuesPer100g["iron"] == 0.2)
precondition(refreshed.valuesPer100g["zinc"] == 0.4)
let manual = MicronutrientProfile(valuesPer100g: ["vitaminC": 20], source: .manual)
let withDatabase = manual.addingOpenFoodFacts(revisedOFF)
precondition(withDatabase.valuesPer100g["vitaminC"] == 20)
precondition(withDatabase.valuesPer100g["zinc"] == 0.4)
precondition(withDatabase.source == .mixed)
precondition(withDatabase.addingOpenFoodFacts(revisedOFF) == withDatabase)
print("Micronutrient scaling, unknown values, recipe aggregation, OFF merging and legacy JSON: OK")
SWIFT
swiftc "$repo_dir/CalorieTrackerApp/Micronutrients.swift" "$temporary_dir/main.swift" -o "$temporary_dir/test"
"$temporary_dir/test"
