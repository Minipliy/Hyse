#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
models = File.read(File.join(root, "CalorieTrackerApp", "TrainingModels.swift"))
guides = File.read(File.join(root, "CalorieTrackerApp", "ExerciseExecutionGuides.swift"))
views = File.read(File.join(root, "CalorieTrackerApp", "TrainingInsightsViews.swift"))

built_ins = models.scan(/\.builtIn\("([^"]+)"/).flatten.uniq
curated_imports = models.scan(/curated\("([^"]+)"/).flatten.uniq
catalog_keys = (built_ins + curated_imports).uniq
covered_keys = guides.scan(/"([a-z0-9_]+)"/).flatten.uniq
missing = catalog_keys - covered_keys

abort "Missing execution guides: #{missing.join(', ')}" unless missing.empty?
abort "Exercise detail still uses generic motion instructions" if views.include?("exercise.visualKind.instructionKey")
abort "Exercise detail does not show the specific guide" unless views.include?("exercise.executionGuide(isGerman: language.isGerman)")
abort "Execution guides need a safe fallback" unless guides.include?("default:")

puts "Exercise execution guides cover all #{catalog_keys.length} catalog exercises."
