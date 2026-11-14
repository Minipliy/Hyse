#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
test_file=$(mktemp /tmp/hyse-food-search-XXXXXX.swift)
trap 'rm -f "$test_file"' EXIT
cat > "$test_file" <<'SWIFT'
import Foundation

struct FoodItem {
    var name: String
    var nameDE: String? = nil
    var brand: String? = nil
    var barcode: String? = nil
    var externalSource: String? = nil
}
SWIFT
sed -n '/^enum FoodSearchRanker {/,/^}/p' CalorieTrackerApp/FoodStore.swift >> "$test_file"
cat >> "$test_file" <<'SWIFT'
let rhubarb = FoodItem(name: "Rhubarb, raw", nameDE: "Rhabarber roh")
let rhubarbDrink = FoodItem(name: "Rhabarber", brand: "ViO", externalSource: "Open Food Facts")
let rhubarbMix = FoodItem(name: "Apfel-Rhabarber-Mix", externalSource: "Open Food Facts")
precondition(FoodSearchRanker.orderedBefore(rhubarb, rhubarbDrink, query: "Rhabarber"))
precondition(FoodSearchRanker.orderedBefore(rhubarb, rhubarbMix, query: "Rhabarber"))

let doner = FoodItem(name: "Döner Kebab, Fladenbrot mit Fleisch", nameDE: "Döner Kebab, Kalb/Rind")
let dubiousDoner = FoodItem(name: "Döner", externalSource: "Open Food Facts")
let vegetarianDoner = FoodItem(name: "Döner vegetarisch", nameDE: "Döner vegetarisch, Fladenbrot")
precondition(FoodSearchRanker.orderedBefore(doner, dubiousDoner, query: "Döner"))
precondition(FoodSearchRanker.orderedBefore(doner, vegetarianDoner, query: "Döner"))
precondition(FoodSearchRanker.matches(doner, query: "Doener"))

let subway = FoodItem(name: "Chicken Teriyaki (15 cm)", brand: "Subway", externalSource: "Subway")
precondition(FoodSearchRanker.matches(subway, query: "Subway Chicken Teriyaki"))
let unverifiedSubway = FoodItem(name: "Subway Chicken Teriyaki", externalSource: "Open Food Facts")
precondition(FoodSearchRanker.orderedBefore(subway, unverifiedSubway, query: "Subway Chicken Teriyaki"))
let mcdonalds = FoodItem(name: "McRib Sweet Heat", brand: "McDonald's", externalSource: "McDonald's")
let unverifiedMcDonalds = FoodItem(name: "McRib", brand: "McDonald's", externalSource: "Open Food Facts")
precondition(FoodSearchRanker.matches(mcdonalds, query: "McDonalds McRib"))
precondition(FoodSearchRanker.matches(mcdonalds, query: "McDonalds"))
precondition(FoodSearchRanker.relevanceScore(mcdonalds, query: "McDonalds") < FoodSearchRanker.relevanceScore(unverifiedMcDonalds, query: "McDonalds"))
let usMcDonalds = FoodItem(name: "McDonalds Chicken Salad", nameDE: "McDonalds Chicken Salad")
precondition(FoodSearchRanker.orderedBefore(mcdonalds, usMcDonalds, query: "McDonalds"))
print("Food search relevance checks passed.")
SWIFT
swift "$test_file"
