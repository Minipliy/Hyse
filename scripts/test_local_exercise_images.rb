#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
visual = File.read(File.join(root, "CalorieTrackerApp/TrainingInsightsViews.swift"))

abort "Exercise visuals must use initials instead of images" unless visual.include?("exercise.initials(isGerman: isGerman)")
abort "Exercise visuals must not reference image assets" if visual.include?("ExercisePhoto") || visual.include?("UIImage")
abort "Exercise visuals must not use AsyncImage" if visual.include?("AsyncImage")
abort "Exercise visuals must not download images" if visual.include?("URLSession")

asset_names = Dir.glob(File.join(root, "CalorieTrackerApp/Assets.xcassets/ExercisePhoto*.imageset"))
abort "Unused exercise photos are still included in the app: #{asset_names.join(', ')}" unless asset_names.empty?

source_files = Dir.glob(File.join(root, "Assets/ExercisePhotosOriginal-*")) +
  Dir.glob(File.join(root, "Assets/ExercisePhotosPreview*"))
abort "Unused exercise photo source files remain: #{source_files.join(', ')}" unless source_files.empty?

puts "Exercise visuals use initials and no bundled exercise photos remain."
