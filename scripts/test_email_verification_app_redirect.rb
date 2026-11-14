#!/usr/bin/env ruby
require "json"

root = File.expand_path("..", __dir__)
migration = File.read(File.join(root, "pb_migrations", "1790200000_hyse_email_verification_app_redirect.js"))
callback = File.read(File.join(root, "pb_hooks", "email_verification_callback.pb.js"))
content = File.read(File.join(root, "CalorieTrackerApp", "ContentView.swift"))
association = JSON.parse(File.read(File.join(root, "pb_public", ".well-known", "apple-app-site-association")))
association_hook = File.read(File.join(root, "pb_hooks", "language_routes.pb.js"))
entitlements = File.read(File.join(root, "CalorieTrackerApp", "CalorieTrackerApp.entitlements"))

abort("Verification email must use Hyse's server callback") unless migration.include?("{APP_URL}/api/hyse/verify-email/{TOKEN}")
abort("Rendered verification emails must be forced to Hyse's callback") unless callback.include?("onMailerBeforeRecordVerificationSend") && callback.include?("e.meta || {}).token")
abort("Verification callback route is missing") unless callback.include?('routerAdd("GET", "/api/hyse/verify-email/:token"')
abort("Verification callback must validate PocketBase verification tokens") unless callback.include?("findAuthRecordByToken(token, $app.settings().recordVerificationToken.secret)")
abort("Verification callback must only accept Hyse user records") unless callback.include?("user.collection().name !== \"users\"")
abort("Verification callback must activate the account") unless callback.include?("user.setVerified(true)")
abort("Verification callback must not expose the token to the app") if callback.include?("hyseapp://login?token=")
abort("Verification callback must show a reliable app-opening page") unless callback.include?("c.html(200") && callback.scan("hyseapp://login?verified=1").length >= 2
abort("Hyse must open its sign-in dialog for the verification deep link") unless content.include?('url.host == "login"') && content.include?("showingLoginFromDeepLink = true")
workout_paths = [{"/" => "/en/workout/*"}, {"/" => "/de/training/*"}]
abort("Only shared workouts may open through Universal Links") unless association.dig("applinks", "details", 0, "components") == workout_paths
abort("PocketBase association route must match the static file") unless association_hook.include?('{ "/": "/en/workout/*" }') && association_hook.include?('{ "/": "/de/training/*" }')
abort("Hyse must claim shared workout links") unless entitlements.include?("applinks:hyse.minipliy.net")

puts "Email verification app-redirect checks passed"
