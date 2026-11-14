#!/usr/bin/env ruby
# frozen_string_literal: true

source = File.read(File.expand_path("../CalorieTrackerApp/AddEntryView.swift", __dir__))

abort "Pending food rows must be persistable" unless source.include?("PendingFoodEntry: Identifiable, Codable")
abort "Pending food draft model is missing" unless source.include?("private struct PendingFoodEntryDraft: Codable")
abort "Pending food draft needs a stable local key" unless source.include?("pendingDraftKey = \"add_entry_pending_food_draft_v1\"")
abort "Pending food draft must be restored when opening the entry screen" unless source.include?("let pendingDraft = foodSelectionHandler == nil ? Self.loadPendingDraft() : nil")
abort "Pending food draft must be written before the app backgrounds" unless source.include?(".onChange(of: scenePhase)") && source.include?("persistPendingDraft()")
abort "Pending food draft must be cleared after committing entries" unless source.include?("pendingEntries.removeAll()") && source.include?("clearPendingDraft()")

puts "Pending food-entry drafts persist across app exits and clear after submission."
