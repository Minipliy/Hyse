#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
migration = File.read(File.join(root, "pb_migrations", "1787751910_hyse_account_email_refresh.js"))
hook = File.read(File.join(root, "pb_hooks", "secure_email_change.pb.js"))

checks = {
  "all PocketBase account templates are refreshed" => %w[verificationTemplate resetPasswordTemplate confirmEmailChangeTemplate].all? { |name| migration.include?(name) },
  "action URL remains a button and fallback link" => migration.scan("{ACTION_URL}").length >= 2,
  "email layout is mobile responsive" => migration.include?("max-width:620px") && migration.include?("hyse-button-cell"),
  "email layout supports dark mode" => migration.include?("prefers-color-scheme:dark") && migration.include?("supported-color-schemes"),
  "design uses static Hyse colors" => migration.include?("#0e8c82") && !migration.match?(/gradient/i),
  "each email explains what happens next" => migration.scan("detailTitle:").length == 3 && migration.scan("detail:").length == 3,
  "secure email change uses shared branded layout" => hook.include?("function hyseAccountEmail") && hook.scan("html: hyseAccountEmail").length == 2,
  "secure email change matches the refreshed visual system" => hook.include?("#0e8c82") && hook.include?("Secure one-time link") && !hook.match?(/gradient/i),
  "custom email URLs are escaped" => hook.include?("const actionURL = options.actionURL ? hyseEscape(options.actionURL)")
}

failed = checks.reject { |_, passed| passed }
abort("Failed: #{failed.keys.join(', ')}") unless failed.empty?
puts "PocketBase email-design regression tests passed."
