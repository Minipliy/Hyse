#!/usr/bin/env ruby

def assert(condition, message)
  abort(message) unless condition
end

edit = File.read("CalorieTrackerApp/EditEntryView.swift")
detail = File.read("CalorieTrackerApp/CategoryDetailView.swift")

assert(detail.include?("else { entryToEdit = entry }"), "Tapping any meal entry must open its editor")
assert(edit.include?("private var isQuickEntry"), "The editor must distinguish manual quick entries")
assert(edit.include?("quickNutritionField(\"quick_entry.calories\""), "Quick-entry calories must be editable")
assert(edit.include?("quickNutritionField(\"quick_entry.carbohydrates\""), "Quick-entry macros must be editable")
assert(edit.include?("updatedEntry.kcalPer100g =") && edit.include?("let factor = 100 / updatedGrams"), "Edited totals must be converted back to the persisted per-100-unit snapshot")
assert(edit.include?("calorieStore.updateEntry(updatedEntry)"), "Edited quick entries must replace their existing entry")

puts "Quick-entry editing regression tests passed."
