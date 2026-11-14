#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
edit_entry = File.read(File.join(root, "CalorieTrackerApp", "EditEntryView.swift"))
add_entry = File.read(File.join(root, "CalorieTrackerApp", "AddEntryView.swift"))
german = File.read(File.join(root, "CalorieTrackerApp", "de.lproj", "Localizable.strings"))
english = File.read(File.join(root, "CalorieTrackerApp", "en.lproj", "Localizable.strings"))

abort "raw serving placeholder is still used in SwiftUI" if [edit_entry, add_entry].any? { |source| source.include?("ui.serving_s") }
abort "dynamic edit-entry title is not localized" unless edit_entry.include?('LabeledContent(t(amountMode == 1 ? "recipe_editor.servings" : "edit_entry.eaten_amount"))')
abort "singular/plural serving label is missing" unless edit_entry.include?("private var portionUnitLabel")
abort "German singular serving translation is missing" unless german.include?('"ui.serving" = "Portion";')
abort "English singular serving translation is missing" unless english.include?('"ui.serving" = "Serving";')

puts "Serving labels are localized for recipes and foods."
