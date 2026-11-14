#!/usr/bin/env ruby

require "tmpdir"
require "fileutils"

root = File.expand_path("..", __dir__)
source = File.read(File.join(root, "CalorieTrackerApp", "TrainingSocialService.swift"))
model = source[/nonisolated struct FriendWorkout:.*?(?=\nnonisolated struct FriendWorkoutComment)/m]
abort "FriendWorkout model not found" unless model

Dir.mktmpdir("hyse-friend-workout-date") do |directory|
  test_source = <<~SWIFT
    import Foundation
    #{model}

    @main struct FriendWorkoutDateTests {
        static func main() throws {
            let decoder = JSONDecoder()
            let cases = [
                "2026-09-29 19:10:11.123Z",
                "2026-09-29 19:10:11Z",
                "2026-09-29T19:10:11.123Z",
                "2026-09-29T19:10:11Z"
            ]
            let expected = ISO8601DateFormatter().date(from: "2026-09-29T19:10:11Z")!
            let previousWorkoutDate = ISO8601DateFormatter().date(from: "2026-09-28T19:10:11Z")!
            for completedAt in cases {
                let payload: [String: Any] = [
                    "id": "remote-workout", "client_id": "local-workout",
                    "username": "tester", "name": "Workout with photo",
                    "media_url": "/api/files/workouts/remote-workout/photo.jpg",
                    "completed_at": completedAt
                ]
                let data = try JSONSerialization.data(withJSONObject: payload)
                let workout = try decoder.decode(FriendWorkout.self, from: data)
                guard let date = workout.date, abs(date.timeIntervalSince(expected) - (completedAt.contains(".123") ? 0.123 : 0)) < 0.001 else {
                    fatalError("Incorrect friend feed date: \\(completedAt)")
                }
                guard date > previousWorkoutDate else { fatalError("Workout sorts behind older posts") }
                guard workout.mediaURL != nil else { fatalError("Photo URL was lost") }
            }
            print("Friend workout dates and photo decode correctly")
        }
    }
  SWIFT
  path = File.join(directory, "FriendWorkoutDateTests.swift")
  binary = File.join(directory, "FriendWorkoutDateTests")
  module_cache = File.join(directory, "ModuleCache")
  FileUtils.mkdir_p(module_cache)
  File.write(path, test_source)
  environment = { "CLANG_MODULE_CACHE_PATH" => module_cache, "SWIFT_MODULE_CACHE_PATH" => module_cache }
  abort "Could not compile friend workout date test" unless system(environment, "swiftc", "-parse-as-library", path, "-o", binary)
  abort "Friend workout date test failed" unless system(binary)
end
