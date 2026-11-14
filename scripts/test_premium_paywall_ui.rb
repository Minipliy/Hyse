#!/usr/bin/env ruby
root = File.expand_path("..", __dir__)
access = File.read(File.join(root, "CalorieTrackerApp", "PremiumAccess.swift"))
abort("StoreKit purchase code remains in the iOS app") if access.match?(/import StoreKit|Product\.products|\.purchase\(|AppStore\.sync|presentOfferCodeRedeemSheet/)
abort("Subscription products remain in the iOS app") if access.match?(/HyseSubscription|com\.hyse\.HyseApp\.premium|hyse\.(nutrition|training|complete)\.lifetime/)
abort("Legacy navigation presents a purchase action") unless access.include?("Alle Funktionen sind kostenlos verfügbar.")
abort("StoreKit test configuration remains") if File.exist?(File.join(root, "HyseSubscriptions.storekit"))
puts "Premium purchase removal checks passed"
