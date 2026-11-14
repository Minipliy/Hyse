#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
store = File.read(File.join(root, "CalorieTrackerApp", "FoodStore.swift"))
add_entry = File.read(File.join(root, "CalorieTrackerApp", "AddEntryView.swift"))

def assert(condition, message)
  abort(message) unless condition
end

assert(store.include?("private static func deduplicatedByID"), "FoodStore must remove duplicate food IDs")
assert(store.include?("!personalIDs.contains(food.id)"), "A personal food must replace its global variant with the same ID")
assert(store.include?("if let index = foods.firstIndex(where: { $0.id == item.id })"), "Adding the same food ID must update instead of append")
assert(!add_entry.include?("Dictionary(uniqueKeysWithValues: foodStore.availableFoods"), "Recent food search must tolerate duplicate IDs")
assert(!add_entry.include?("Dictionary(uniqueKeysWithValues: base.map"), "Food sorting must tolerate duplicate IDs")
assert(!add_entry.include?("selectedRecipe!"), "Saving an entry must not force-unwrap a recipe selection")

puts "Add-entry duplicate food crash guards passed."
