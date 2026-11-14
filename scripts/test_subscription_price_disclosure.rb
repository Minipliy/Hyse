#!/usr/bin/env ruby

def assert(value, message)
  raise message unless value
end

paywall = File.read("CalorieTrackerApp/PremiumAccess.swift")
de = File.read("CalorieTrackerApp/de.lproj/Localizable.strings")
en = File.read("CalorieTrackerApp/en.lproj/Localizable.strings")

assert(paywall.include?("private var billingSummary"),
       "The purchase flow must include a persistent billing summary.")
assert(paywall.include?("selectedBillingPrice") && paywall.include?(".title2"),
       "The full billed subscription price must be the most prominent price element.")
assert(paywall.include?("premium.trial_billing_disclosure") && paywall.include?("premium.subscription_billing_disclosure"),
       "The purchase flow must distinguish trial and standard billing terms.")
assert(paywall.include?("premium.start_trial"),
       "The trial call to action must identify the trial duration.")

%w[premium.billed_after_trial premium.trial_billing_disclosure premium.subscription_billing_disclosure].each do |key|
  assert(de.include?(%Q{"#{key}"}), "Missing German disclosure: #{key}")
  assert(en.include?(%Q{"#{key}"}), "Missing English disclosure: #{key}")
end

puts "Subscription billed-price disclosure checks passed."
