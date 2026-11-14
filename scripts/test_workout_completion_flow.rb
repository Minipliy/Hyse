#!/usr/bin/env ruby
require_relative "training_view_sources"

views = TrainingViewSources.read
models = File.read(File.expand_path("../CalorieTrackerApp/TrainingModels.swift", __dir__))
store = File.read(File.expand_path("../CalorieTrackerApp/TrainingStore.swift", __dir__))
sync = File.read(File.expand_path("../CalorieTrackerApp/TrainingSyncService.swift", __dir__))
social = File.read(File.expand_path("../pb_hooks/training_social.pb.js", __dir__))

abort "Finishing must open the completion editor first" unless views.include?('completionDraft = store.finishActiveWorkout()')
abort "Saving must advance to the celebration" unless views.include?('completedSummary = saved')
abort "Completion media must stay locally addressable" unless models.include?('mediaLocalFilename') && store.include?('HyseWorkoutMedia')
abort "Completion edits must persist" unless store.include?('func updateCompletedWorkout')
abort "Visibility must be sent to the server" unless sync.include?('workout.visibility ?? "private"')
abort "Private workouts must stay out of the social feed" unless social.include?("visibility = 'public'")
abort "Celebration screen and confetti are required" unless views.include?('WorkoutCelebrationView') && views.include?('WorkoutConfettiView')

puts "Workout completion editor, persistence, privacy and celebration flow are connected."
