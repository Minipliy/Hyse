#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
auth = File.read(File.join(root, "CalorieTrackerApp", "AuthManager.swift"))
callback = File.read(File.join(root, "pb_hooks", "oauth2_callback.pb.js"))

abort("Apple OAuth must use response_mode=form_post for name/email scopes") unless auth.include?('response_mode", value: "form_post"')
abort("Apple OAuth must validate the final response mode") unless auth.include?('responseMode == "form_post"')
abort("Apple OAuth must validate the final redirect URL") unless auth.include?('redirectURL == providerOAuthRedirectURL')
abort("Apple OAuth callback must accept POST responses") unless callback.include?('routerAdd("POST", "/api/hyse/oauth2-callback"')
abort("POST callback must read the submitted form fields") unless callback.include?("$apis.requestInfo(c)")
abort("POST callback must support form-urlencoded fallback") unless callback.include?('formValue("code")')
abort("OAuth callback must forward code and state to the app") unless callback.include?('"code"') && callback.include?('"state"') && callback.include?("hyseapp://oauth-callback")
abort("PocketBase 0.22 callbacks must not depend on a module-level redirect helper") if callback.include?("function hyseOAuthAppRedirect")
abort("GET and POST callbacks must each contain their own app redirect") unless callback.scan("hyseapp://oauth-callback").length >= 2

puts "Apple OAuth callback checks passed"
