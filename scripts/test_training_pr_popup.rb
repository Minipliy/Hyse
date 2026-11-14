#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
views = TrainingViewSources.read
store = File.read(File.join(root, "CalorieTrackerApp", "TrainingStore.swift"))
models = File.read(File.join(root, "CalorieTrackerApp", "TrainingModels.swift"))

def assert(condition, message)
  abort(message) unless condition
end

assert(models.include?("struct TrainingPersonalRecordFeedback"), "PR feedback must carry exact record values")
assert(store.include?("latestPersonalRecordFeedback = TrainingPersonalRecordFeedback("), "Completing a PR set must create record feedback")
assert(views.include?("private struct PersonalRecordBanner"), "A PR banner is required")
assert(views.include?("PersonalRecordBanner(feedback: feedback)") && views.include?(".frame(maxHeight: .infinity, alignment: .top)") && views.include?(".allowsHitTesting(false)"), "PR feedback must overlay the workout at the top without blocking it")
assert(views.include?("Task.sleep(for: .seconds(2.4))"), "The PR banner must dismiss automatically")
%w[estimated_1rm set_volume weight].each do |flag|
  assert(views.include?("training.pr.\\(flag).title") || views.include?("\"#{flag}\""), "Missing distinct PR type: #{flag}")
end
assert(!views.include?("private struct PersonalRecordPopup"), "The blocking centered PR popup must be removed")

puts "Compact training PR banner checks passed."
