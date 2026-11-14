#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
search = File.read(File.join(root, "CalorieTrackerApp", "NearbyGymSearch.swift"))
completion = TrainingViewSources.read
models = File.read(File.join(root, "CalorieTrackerApp", "TrainingModels.swift"))
sync = File.read(File.join(root, "CalorieTrackerApp", "TrainingSyncService.swift"))
project = File.read(File.join(root, "Hyse.xcodeproj", "project.pbxproj"))

checks = {
  "requests foreground location permission" => search.include?("requestWhenInUseAuthorization()"),
  "requests a real device location" => search.include?("requestLocation()"),
  "uses Apple Maps local search" => search.include?("MKLocalSearch(request: request).start()"),
  "filters results to real fitness centers" => search.include?(".fitnessCenter"),
  "broadens results with an unrestricted gym query" => search.include?("(\"Gym\", nil)"),
  "broadens address searches with fitness terms" => search.include?("Fitnessstudio \\(query)") && search.include?("Gym \\(query)"),
  "also searches known alternate gym names" => search.include?("gymNameAliases") && search.include?("aliasPlans"),
  "uses the canonical FittiCO name for its Berlin Street branch" => search.include?("FittiCO Dresden Mitte") && search.include?("Berliner Straße 27") && search.include?("all inclusive FITNESS"),
  "only applies an alternate name to the matching address" => search.include?("placemark.postalCode == alias.postalCode") && search.include?("normalized(street) == normalized(alias.street)") && search.include?("normalized(mapName).contains(normalized($0))"),
  "allows searching by a gym name or address" => search.include?("nearby_gyms.search_placeholder") && search.include?("findNearbyGyms(matching: gymQuery)"),
  "limits the search to the nearby map region" => search.include?("MKCoordinateRegion(") && search.include?("20_000"),
  "sorts gyms by real distance" => search.include?(".sorted { $0.distance < $1.distance }"),
  "opens the picker from workout completion" => completion.include?("showingNearbyGymPicker = true"),
  "stores the selected gym on the workout" => completion.include?("draft.gymName = gym.name"),
  "stores the exact gym address" => models.include?("var gymAddress: String?") && completion.include?("draft.gymAddress = gym.address"),
  "stores the exact gym coordinates" => models.include?("var gymLatitude: Double?") && models.include?("var gymLongitude: Double?") && completion.include?("draft.gymLatitude = gym.coordinate.latitude") && completion.include?("draft.gymLongitude = gym.coordinate.longitude"),
  "marks the exact branch as selected" => search.include?("selectedGymID == gym.id") && completion.include?("selectedGymID: draft.gymSelectionID"),
  "shows the saved branch address in workout details" => completion.include?("currentWorkout.gymAddress"),
  "syncs the saved location in the workout snapshot" => sync.include?(%q{"snapshot_json": jsonObject(workout)}),
  "declares the required location permission text" => project.scan("INFOPLIST_KEY_NSLocationWhenInUseUsageDescription").length == 2
}

failed = checks.reject { |_, passed| passed }
if failed.empty?
  puts "Nearby gym search checks passed (#{checks.length})."
else
  failed.each_key { |name| warn "FAILED: #{name}" }
  exit 1
end
