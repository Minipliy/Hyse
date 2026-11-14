#!/usr/bin/env ruby
require_relative "training_view_sources"

hub = File.read(File.expand_path("../CalorieTrackerApp/TrainingStatisticsHub.swift", __dir__))
views = TrainingViewSources.read
body = File.read(File.expand_path("../CalorieTrackerApp/DetailedTrainingMuscleFigure.swift", __dir__))

checks = {
  "statistics hub is the profile destination" => views.include?("NavigationLink { TrainingStatisticsView(store: store) }"),
  "seven day body map exists" => hub.include?("TrainingStatisticsDayPicker") && hub.include?("TrainingMuscleBodyGraphic"),
  "overview uses all workouts from the last seven days" => hub.include?("recentWorkouts") && hub.include?("range: .sevenDays"),
  "range includes complete calendar days" => hub.include?("endExclusive") && hub.include?("date < endExclusive"),
  "statistics use the shared primary-muscle-only mapping" =>
    hub.include?("TrainingMuscleRegionMap.weightedRegions") &&
    body.include?("static func weightedRegions(") &&
    !body.include?("result[region] = 0.5") &&
    !body.include?("secondary.flatMap"),
  "historical exercises resolve against the current catalog" => hub.include?("catalogByID[log.exerciseID]"),
  "long range calculations run outside the interface" => hub.include?("Task.detached(priority: .userInitiated)"),
  "range changes show a loading indicator" => hub.include?("StatisticsLoadingIndicator") && hub.include?("training.statistics.calculating"),
  "obsolete range calculations are cancelled" => hub.include?("withTaskCancellationHandler") && hub.include?("calculation.cancel()"),
  "detailed front and back anatomy replaces capsule people" => body.include?("case front, back") && body.include?("quadriceps") && body.include?("hamstrings") && body.include?("upper_back"),
  "radar labels use the selected app language" => hub.include?("language.text(\"training.muscle.\\($0)\")"),
  "sets per muscle group has a destination" => hub.include?("MuscleSetsStatisticsView"),
  "muscle radar comparison has a destination" => hub.include?("MuscleRadarStatisticsView") && hub.include?("TrainingMuscleRadarChart"),
  "weekly body distribution has a destination" => hub.include?("MuscleBodyStatisticsView"),
  "top exercises are based on completed workouts" => hub.include?("TopExercisesStatisticsView") && hub.include?("exercise.completedSetCount > 0"),
  "record exercises inspect personal record flags" => hub.include?("RecordExercisesStatisticsView") && hub.include?("personalRecordFlags"),
  "monthly report is linked" => hub.include?("TrainingMonthlyReportView")
}

failures = checks.reject { |_, passed| passed }.keys
abort("Training statistics hub checks failed: #{failures.join(', ')}") unless failures.empty?

puts "Training statistics hub checks passed."
