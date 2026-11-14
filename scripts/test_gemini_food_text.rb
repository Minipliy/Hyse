#!/usr/bin/env ruby

hook = File.read('pb_hooks/gemini_food_text.pb.js')
view = File.read('CalorieTrackerApp/LocalFoodAnalysisView.swift')

abort 'Text endpoint must fail closed' unless hook.include?('throw new ApiError(503')
abort 'Text endpoint must not forward to Gemini' if hook.match?(/GEMINI_API_KEY|api\.google|api\.gemini/)
abort 'Text UI must use local analysis' unless view.include?('LocalFoodAnalyzer.shared.analyzeText')
abort 'Remote Gemini service must be removed from the app' if File.exist?('CalorieTrackerApp/GeminiFoodAnalysisService.swift')
puts 'Remote text analysis remains disabled; local analysis remains available.'
