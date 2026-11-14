#!/usr/bin/env ruby
require_relative "training_view_sources"

views = TrainingViewSources.read
active_source = File.read("CalorieTrackerApp/ActiveWorkoutViews.swift")
set_source = File.read("CalorieTrackerApp/TrainingSetViews.swift")

active = active_source[/struct ActiveWorkoutView: View \{[\s\S]*/]
reorder = set_source[/struct WorkoutExerciseReorderList: View \{[\s\S]*?(?=@MainActor\nenum ExerciseReorderFeedback)/]
card = set_source[/struct WorkoutExerciseCard: View \{[\s\S]*?(?=private struct WorkoutExerciseActionsSheet)/]
touch = set_source[/private struct WorkoutExerciseReorderTouchView: UIViewRepresentable \{[\s\S]*?(?=struct WorkoutExerciseCard: View)/]

abort "active workout saves before release" unless active&.match?(/private func finishExerciseReorder\(\)[\s\S]*store\.moveExercises/)
abort "active workout still uses native drag/drop" if reorder&.include?("onDrop") || card&.include?(".onDrag")
abort "dragged exercise does not stay anchored to the touch" unless reorder&.include?("current.draggedCenterY - frame.minY") && views.include?("sourceCenterY + fingerY - fingerStartY")
abort "stationary long press does not lift the exercise" unless touch&.match?(/case \.began:[\s\S]*?parent\.onBegan\(fingerY\)/) && active&.include?("onReorderBegan: { fingerY in")
abort "releasing a stationary exercise must finish the preview" unless touch&.match?(/case \.ended, \.cancelled, \.failed:[\s\S]*?parent\.onEnded\(\)/)
abort "touch location is not mapped to the preview's global coordinates" unless card&.include?("geometry.frame(in: .global).minY + localY")
abort "reorder preview touches the workout store" if reorder&.include?("store.")
abort "reorder can oscillate at a row boundary" unless reorder&.include?("rawIndex < CGFloat(source) + 0.62") && reorder&.include?("rawIndex > CGFloat(source) - 0.62")
abort "edge scrolling is missing" unless reorder&.include?("autoScroll(in: frame)")
abort "routine reorder no longer completes" unless views.match?(/private struct RoutineExerciseDropDelegate[\s\S]*performDrop[\s\S]*onDropCompleted\(\)/)

puts "Active workout reorder uses an anchored local preview and saves on release."
