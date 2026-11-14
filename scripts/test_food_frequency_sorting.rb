#!/usr/bin/env ruby

def assert(condition, message)
  abort("FAILED: #{message}") unless condition
end

frequency = File.read("CalorieTrackerApp/FrequencyStore.swift")
add_entry = File.read("CalorieTrackerApp/AddEntryView.swift")
batch_entry = File.read("CalorieTrackerApp/BatchAddEntryView.swift")
food_store = File.read("CalorieTrackerApp/FoodStore.swift")
global_service = File.read("CalorieTrackerApp/GlobalFoodService.swift")

assert(frequency.include?('sourceTotals[value.sourceKey] = value.usageCount'), "server source counts must be retained")
assert(frequency.include?('return "global_food:\\(global)"'), "global foods need a stable frequency identity")
assert(frequency.include?('max(totalCounts[food.id, default: 0], sourceTotalCounts[Self.sourceKey(for: food), default: 0])'), "food counts must prefer the stable server count")

[add_entry, batch_entry].each do |view|
  assert(view.include?("sourceUsageCounts: sourceCounts"), "food pickers must sort with source counts")
  assert(view.include?("await foodStore.hydrateGlobalFoods(recordIDs: globalIDs)"), "frequent global foods must be loaded before sorting")
  assert(view.include?("recentSearchedFoodKeys"), "recently searched foods must use stable source keys")
  assert(view.include?("accountData.recentUsage.compactMap"), "recent catalogue foods must be hydrated from usage history")
  assert(view.include?("frequencyStore.revision"), "food pickers must refresh after usage hydration")
  assert(view.include?("frequencyStore.recordUsage(food:"), "new entries must update the stable food identity")
end

assert(food_store.include?("func hydrateGlobalFoods(recordIDs: [String]) async"), "FoodStore must hydrate referenced catalogue foods")
assert(food_store.include?("enum FoodHistoryIdentity"), "food history needs stable catalogue identities")
assert(food_store.include?('if key.hasPrefix("global_food:")'), "stable history keys must resolve catalogue record IDs")
assert(global_service.include?("func fetch(recordIDs: [String], token: String) async -> [FoodItem]"), "catalogue service must support ID-based hydration")

puts "Food frequency sorting regression checks passed."
