#!/usr/bin/env ruby

def assert(value, message)
  raise message unless value
end

content = File.read("CalorieTrackerApp/ContentView.swift")

assert(content.include?("Button(action: presentAddEntry)"),
       "The centre add action must intercept taps before the placeholder tab is selected")
assert(content.include?(".frame(width: 72, height: 56)"),
       "The centre add interception surface must stay inside the tab bar and not cover bottom text fields")
assert(!content.include?(".frame(width: 96, height: 96)"),
       "The oversized centre add interception surface must not return")
assert(content.include?(".sheet(item: $addEntryCategory)"),
       "The add-entry sheet must have populated content before presentation")
assert(content.include?("guard addEntryCategory == nil, let category = categoryStore.categories.first"),
       "The add-entry action must resolve its category before opening")
assert(!content.include?("@State private var showingAddEntry"),
       "Separate sheet visibility must not race the add-entry content")
assert(!content.include?("Color.clear\n                .tabItem { Label(t(\"ui.add_entry\")"),
       "The centre placeholder must not flash as a transparent black screen")

puts "Add-entry presentation opens populated content without a blank tab frame."
