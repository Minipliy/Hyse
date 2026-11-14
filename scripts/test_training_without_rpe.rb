#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
views = TrainingViewSources.read
models = File.read(File.join(root, "CalorieTrackerApp", "TrainingModels.swift"))

abort("RPE is still visible in the training UI") if views.match?(/Text\("RPE"\)|training\.rpe|rpeControl|draftRPE/)
abort("legacy workout decoding compatibility was removed") unless models.include?("var rpe: Double?")

puts "training RPE removal checks passed"
