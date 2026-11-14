#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
store = File.read(File.join(root, "CalorieTrackerApp", "TrainingStore.swift"))
content = File.read(File.join(root, "CalorieTrackerApp", "ContentView.swift"))
views = TrainingViewSources.read

checks = {
  "store begins with an unresolved persistence scope" => store.include?("hasResolvedPersistenceScope = false"),
  "account activation resolves the scope only after account cache load" => store.match?(/load\(scope: "account_\\\(id\)"\)\s+hasResolvedPersistenceScope = true/),
  "guest activation resolves the scope only after guest cache load" => store.match?(/load\(scope: "guest"\)\s+hasResolvedPersistenceScope = true/),
  "global active workout bar waits for the resolved scope" => content.include?("if trainingStore.hasResolvedPersistenceScope, !keyboardVisible, let workout = trainingStore.activeWorkout"),
  "training home card waits for the resolved scope" => views.include?("if store.hasResolvedPersistenceScope, let active = store.activeWorkout")
}

failed = checks.reject { |_, passed| passed }
if failed.empty?
  puts "Training persistence-scope readiness checks passed."
  exit 0
end

failed.each_key { |name| warn "FAILED: #{name}" }
exit 1
