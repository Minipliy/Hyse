#!/usr/bin/env ruby
require_relative "training_view_sources"

views = TrainingViewSources.read
social_service = File.read(File.expand_path("../CalorieTrackerApp/TrainingSocialService.swift", __dir__))
content = File.read(File.expand_path("../CalorieTrackerApp/ContentView.swift", __dir__))
landing = File.read(File.expand_path("../pb_hooks/language_routes.pb.js", __dir__))
entitlements = File.read(File.expand_path("../CalorieTrackerApp/CalorieTrackerApp.entitlements", __dir__))
german = File.read(File.expand_path("../CalorieTrackerApp/de.lproj/Localizable.strings", __dir__))
english = File.read(File.expand_path("../CalorieTrackerApp/en.lproj/Localizable.strings", __dir__))

abort "Celebration must show the detailed muscle overview" unless views.include?("DetailedTrainingMuscleBody(counts: muscleCounts)")
abort "Workout share composer must be opened from celebration" unless views.include?("showingShareComposer = true") && views.include?("WorkoutShareComposer")
abort "Saved workouts must reopen the image share composer" unless views.include?("muscleCounts: WorkoutShareMuscles.counts(for: currentWorkout)")
abort "Friend workout details must share the card and canonical public link" unless views.include?("muscleCounts: WorkoutShareMuscles.counts(for: shareWorkout)") && views.include?("shareURLOverride: WorkoutShareLink.url(workoutID: current.id") && views.include?("ownerUsername: current.username")
abort "Share image must be rendered from workout data" unless views.include?("ImageRenderer(content: card)") && views.include?("WorkoutShareImage")
abort "Share sheet must include the image, caption and workout URL together" unless views.include?("WorkoutShareSheet(imageData: renderedImage.pngData, message: shareCaption)") && views.include?("activityItems: items") && views.include?("shareURL.absoluteString")
abort "All requested backgrounds must exist" unless %w[transparent light dark].all? { |value| views.include?(value) }
abort "Copied text must contain completed sets" unless views.include?("Set \\(index + 1):") && views.include?("set.completed")
abort "Copied text must contain Hyse attribution" unless views.include?("@hyseapp") && views.include?("shareURL.absoluteString")
abort "Public workouts must offer a shareable deep link" unless views.include?("training.share.share_link") && views.include?("guard workout.visibility == \"public\"")
abort "Workout links must use localized website URLs" unless social_service.include?("/en/workout/") && social_service.include?("/de/training/")
abort "Opening a workout link must present its detail in Hyse" unless content.include?("WorkoutShareLink.workoutID(from: url)") && content.include?("sharedWorkoutSocial.loadDetail") && content.include?("FriendWorkoutDetailView(")
abort "Users without Hyse need a workout download fallback" unless landing.include?("/en/workout/:id") && landing.include?("/de/training/:id") && landing.include?("Get Hyse") && landing.include?("Hyse laden")
abort "Workout pages must offer an explicit app-opening button" unless landing.include?("hyseapp://workout/") && landing.include?("In Hyse öffnen")
abort "Shared workout links must open Hyse directly when installed" unless entitlements.include?("applinks:hyse.minipliy.net") && landing.include?(%q{{ "/": "/en/workout/*" }}) && landing.include?(%q{{ "/": "/de/training/*" }})
abort "Done button must guard repeat taps and provide feedback" unless views.include?("guard !isClosing") && views.include?("UIImpactFeedbackGenerator")
abort "German share localization is incomplete" unless german.include?(%q{"training.share.background.transparent"}) && german.include?(%q{"training.share.copy_text"})
abort "English share localization is incomplete" unless english.include?(%q{"training.share.background.transparent"}) && english.include?(%q{"training.share.copy_text"})

puts "Workout muscle celebration, reliable completion and share-card flow checks passed."
