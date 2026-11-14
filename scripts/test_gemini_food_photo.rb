#!/usr/bin/env ruby

hook = File.read('pb_hooks/gemini_food_photo.pb.js')
view = File.read('CalorieTrackerApp/LocalFoodAnalysisView.swift')
app_files = Dir.glob('CalorieTrackerApp/**/*.swift')

abort 'Photo endpoint must fail closed' unless hook.include?('throw new ApiError(503')
abort 'Photo endpoint must not forward to Gemini' if hook.match?(/GEMINI_API_KEY|api\.google|api\.gemini/)
abort 'Photo analysis service must be removed' if File.exist?('CalorieTrackerApp/GeminiFoodAnalysisService.swift')
abort 'Photo camera picker must be removed' if File.exist?('CalorieTrackerApp/FoodPhotoCameraPicker.swift')
abort 'Photo UI must not be shown' if view.match?(/photoCard|PhotosPicker|FoodPhotoCameraPicker|analyzePhoto/)
abort 'App must not call photo analysis endpoint' if app_files.any? { |path| File.read(path).include?('/api/hyse/ai/food-photo') }
puts 'Photo analysis is absent from the app; the old endpoint remains disabled.'
