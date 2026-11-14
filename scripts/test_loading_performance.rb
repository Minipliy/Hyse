#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
global = File.read(File.join(root, "CalorieTrackerApp", "GlobalFoodService.swift"))
portions = File.read(File.join(root, "CalorieTrackerApp", "FoodPortionSyncService.swift"))
foods = File.read(File.join(root, "CalorieTrackerApp", "FoodStore.swift"))
training = File.read(File.join(root, "CalorieTrackerApp", "TrainingStore.swift"))
content = File.read(File.join(root, "CalorieTrackerApp", "ContentView.swift"))
views = TrainingViewSources.read

abort "global starter catalogue is not bounded" unless global.include?('URLQueryItem(name: "perPage", value: "250")') && global.include?('URLQueryItem(name: "skipTotal", value: "1")')
abort "personal portion sync still downloads the global catalogue" unless portions.include?('URLQueryItem(name: "filter", value: "owner = \'\\(userID)\'")')
abort "global catalogue disk decoding still runs synchronously on the UI actor" unless foods.include?("private actor GlobalFoodDiskCache")
abort "combined food results are not cached" unless foods.include?("combinedFoodsCache")
abort "food uploads are not batched" unless foods.include?("Task.sleep(for: .seconds(30))")
abort "active workout edits still rebuild completed history through didSet" if training.match?(/var workouts: \[WorkoutLog\].*didSet/m)
abort "completed workout cache has no explicit rebuild" unless training.include?("private func rebuildCompletedWorkouts()")
abort "training tab does background social work while inactive" unless content.include?("isActive: selectedTab == 1") && views.include?("guard isActive else { return }")
abort "health tab does background HealthKit work while inactive" unless content.include?("isActive: selectedTab == 3") && views.include?("if isActive { health.refreshBodyWeights() }")

puts "Loading and interaction performance contracts passed."
