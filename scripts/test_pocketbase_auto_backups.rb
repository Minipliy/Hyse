#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
migration = File.read(File.join(root, "pb_migrations", "1787751900_enable_automatic_backups.js"))
compose = File.read(File.join(root, "docker-compose.production.yml"))

checks = {
  "automatic nightly backup is enabled" => migration.include?('settings.backups.cron = "15 3 * * *"'),
  "two weeks of automatic backups are retained" => migration.include?("settings.backups.cronMaxKeep = 14"),
  "backup data survives container replacement" => compose.include?("./pb_data:/pb/pb_data"),
  "backup credentials are not committed" => !migration.match?(/accessKey|secret|password/i)
}

failed = checks.reject { |_, passed| passed }
abort("Failed: #{failed.keys.join(', ')}") unless failed.empty?
puts "PocketBase automatic-backup regression tests passed."
