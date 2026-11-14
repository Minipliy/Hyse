#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
views = TrainingViewSources.read

%w[share duplicate_action edit delete_action].each do |action|
  abort("missing routine action: #{action}") unless views.include?("training.routine.#{action}")
end

abort("routine ellipsis does not open the action sheet") unless views.include?("selectedRoutineActions = routine")
abort("routine duplication is not connected") unless views.include?("store.duplicateRoutine(routine)")
abort("routine editor is not connected") unless views.include?("routineForEditing = routine")
abort("routine deletion has no confirmation") unless views.include?("routinePendingDeletion = routine")

puts "routine action checks passed"
