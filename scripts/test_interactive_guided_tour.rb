#!/usr/bin/env ruby
require_relative "training_view_sources"

def assert(value, message)
  raise message unless value
end

tour = File.read("CalorieTrackerApp/LegalAndOnboardingViews.swift")
content = File.read("CalorieTrackerApp/ContentView.swift")
login = File.read("CalorieTrackerApp/LoginView.swift")
training = TrainingViewSources.read
account = File.read("CalorieTrackerApp/AccountDataStore.swift")

assert(tour.include?("struct HyseGuidedTourOverlay"), "Tutorial must run as an overlay on the real app UI")
assert(tour.include?("struct TourDimmer"), "Tutorial must visually isolate the current control")
assert(tour.include?("struct TourArrow"), "Tutorial must point to the current control")
assert(%w[trainingFriends trainingWorkouts trainingProfile].all? { |step| tour.include?(step) }, "Tutorial must cover all three training areas")
assert(content.include?("configureTour(for:"), "Tutorial steps must navigate the real app")
assert(content.include?("selectedTrainingSection = .training"), "Tutorial must open the workout section")
assert(content.include?("selectedTrainingSection = .profile"), "Tutorial must open the training profile")
assert(content.include?("completeTourAndPresentAccountCreation()"), "Finishing the tutorial must lead to account creation")
assert(content.include?("LoginView(startsInRegistration: true)"), "Tutorial completion must open registration directly")
assert(login.include?("init(startsInRegistration: Bool = false)"), "Login must support opening directly in registration mode")
assert(training.include?("@Binding var selectedSection: TrainingRootSection"), "Training navigation must be controllable by the guided tour")
assert(account.include?("static let onboardingVersion = 2"), "Existing users must receive the redesigned tutorial once")

puts "Interactive guided-tour regression tests passed."
