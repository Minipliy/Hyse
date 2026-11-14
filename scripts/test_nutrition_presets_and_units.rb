#!/usr/bin/env ruby

def assert(value, message)
  raise message unless value
end

settings_store = File.read("CalorieTrackerApp/UserSettingsStore.swift")
settings_view = File.read("CalorieTrackerApp/SettingsView.swift")
food = File.read("CalorieTrackerApp/FoodItem.swift")
portions = File.read("CalorieTrackerApp/FoodMetadataModels.swift")
add_entry = File.read("CalorieTrackerApp/AddEntryView.swift")
edit_entry = File.read("CalorieTrackerApp/EditEntryView.swift")
account = File.read("CalorieTrackerApp/AccountDataStore.swift")
content = File.read("CalorieTrackerApp/ContentView.swift")
batch_entry = File.read("CalorieTrackerApp/BatchAddEntryView.swift")
quick_entry = File.read("CalorieTrackerApp/QuickEntryView.swift")

profiles = settings_store[/private func applyProfiles\(\).*?\n    }\n\n    private func saveNutritionTargets/m]
assert(profiles, "Nutrition presets must remain centralized")
assert(profiles.include?("carbs: 50, protein: 20, fat: 30"), "Standard preset must use a balanced macro split")
assert(profiles.include?("carbs: 55, protein: 25, fat: 20"), "Sport preset must retain a carbohydrate emphasis")
assert(profiles.include?("carbs: 35, protein: 35, fat: 30"), "High-protein preset must remain nutritionally balanced")
assert(profiles.include?("baseCalorieGoal * 0.05 / 4") && profiles.include?("baseCalorieGoal * 0.10 / 9"),
       "Sugar and saturated-fat guidance must scale with the calorie target")
assert(!profiles.include?("saltGoalGrams = 8") && !profiles.include?("saltGoalGrams = 10"),
       "Presets must not restore the old excessive salt guidance")
assert(profiles.scan("saltGoalGrams = 5").length == 6, "Every preset must use the 5 g salt orientation")

assert(food.include?("static let weightUnits: [FoodUnit] = [.gram, .ounce]"), "Food weight choices must be g/oz")
assert(food.include?("static let volumeUnits: [FoodUnit] = [.milliliter, .fluidOunce]"), "Liquid choices must be ml/fl oz")
assert(settings_view.include?("selection: $settingsStore.defaultLiquidUnit"), "Settings must expose a separate liquid unit")
assert(settings_view.include?("settingsStore.defaultLiquidUnit.converted(displayedWaterGoal, to: .milliliter)"),
       "Displayed water values must be stored canonically in millilitres")
assert(content.include?("settingsStore.defaultLiquidUnit") && content.include?("%.1f fl oz"),
       "The hydration tracker must display the selected liquid unit")
assert(account.include?("defaultLiquidUnit: String?") && account.include?("schemaVersion = 6"),
       "The liquid preference must sync without breaking older snapshots")
assert(add_entry.include?("food.unit.converted(100, to: displayUnit)") && add_entry.include?("recent.unit.converted(recent.amount, to: displayUnit)"),
       "Food search and recent amounts must use the selected oz/fl oz display unit")
assert(batch_entry.include?("displayUnit(for: draft.food).converted(displayedAmount, to: draft.food.unit)"),
       "Batch entry must convert displayed oz/fl oz back to the food's canonical unit")
assert(quick_entry.include?("userSettings.defaultFoodUnit.converted(enteredAmount, to: .gram)"),
       "Quick entry must convert displayed ounces back to grams")
assert(portions.include?("func baseAmount(in baseUnit: FoodUnit) -> Double?"),
       "Portion conversion must have one shared canonical implementation")
assert(add_entry.include?("portion.baseAmount(in: food.unit)"),
       "Logging a food must multiply portions by their canonical weight or volume")
assert(add_entry.include?("selection: foodAmountModeSelection") && !add_entry.include?(".onChange(of: foodAmountMode)"),
       "Programmatic default-portion selection must not be converted as if the user changed units")
assert(edit_entry.include?("entry.portionCount") && edit_entry.include?("entry.grams / count") && edit_entry.include?("matchedFoodPortion?.baseAmount(in: entry.unit)"),
       "Editing must restore the exact portion and retain a snapshot fallback")
assert(edit_entry.include?("updatedEntry.portionCount = Self.decimal(amountText)"),
       "Editing a portion count must preserve it separately from grams")

puts "Nutrition preset and split-unit regression tests passed."
