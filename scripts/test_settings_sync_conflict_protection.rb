#!/usr/bin/env ruby

account_data = File.read(File.expand_path("../CalorieTrackerApp/AccountDataStore.swift", __dir__))
account_hook = File.read(File.expand_path("../pb_hooks/account_state.pb.js", __dir__))
settings_view = File.read(File.expand_path("../CalorieTrackerApp/SettingsView.swift", __dir__))

abort "settings cache is not written from the same snapshot that is uploaded" unless account_data.include?("let snapshot = settingsStore.syncSnapshot")
abort "local settings are not staged before their debounced upload" unless account_data.include?("func stageSettings") && settings_view.include?("accountData.stageSettings(settingsStore, language: language)")
abort "stale remote settings can overwrite a newer cached snapshot" unless account_data.include?("shouldApplyRemoteSettings(snapshot, in: activeScope)")
abort "remote settings timestamp comparison is missing" unless account_data.include?("remote.updatedAt >= cached.updatedAt")
abort "server accepts out-of-order settings writes" unless account_hook.include?("incomingUpdatedAt < currentUpdatedAt")
abort "server does not understand Swift's encoded Date timestamps" unless account_hook.include?("Date.UTC(2001, 0, 1)")

puts "Settings sync conflict protection is present."
