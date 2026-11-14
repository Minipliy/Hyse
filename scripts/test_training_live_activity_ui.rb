#!/usr/bin/env ruby

view = File.read("CalorieWidget/TrainingLiveActivity.swift")

abort "Lock-screen activity does not use the system-owned surface" unless view.include?(".activityBackgroundTint(hyseActivitySurface)")
abort "Lock-screen content does not fill the available width" unless view.include?(".frame(maxWidth: .infinity, alignment: .leading)")
abort "Lock-screen content is not protected from rounded corners" unless view.include?(".padding(.horizontal, 18)")
abort "A nested width-limited card still wastes horizontal room" if view.include?(".frame(maxWidth: 340)")
abort "Compact island timer has no width bound" unless view.include?("maxWidth: 48")
abort "Expanded island is not protected from its concave Home Screen corners" unless view.include?(".contentMargins(.horizontal, 16, for: .expanded)") && view.include?(".contentMargins(.vertical, 14, for: .expanded)")
abort "Compact island icon still draws a clipped inner background" unless view.include?("activityGlyph(for: context.state, size: 22, showsBackground: false)")
abort "Expanded island bottom region is not full-width" unless view.scan(".frame(maxWidth: .infinity, alignment: .leading)").length >= 2
abort "Workout progress does not use the rounded custom bar" unless view.scan("WorkoutActivityProgressBar(").length >= 2 && view.include?("Capsule()")
abort "Scaled progress bars can still clip against rounded corners" if view.include?(".scaleEffect(x: 1, y: 1.35")
abort "Live Activity has no visual hierarchy" unless view.include?("currentExercise") && view.include?("setDetail")

puts "Training Live Activity compact UI contracts passed."
